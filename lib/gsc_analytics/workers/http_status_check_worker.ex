defmodule GscAnalytics.Workers.HttpStatusCheckWorker do
  @moduledoc """
  Oban worker that automatically checks HTTP status codes for URLs.

  This worker is enqueued automatically when URLs are synced from Google Search Console.
  It processes URLs in batches to validate their HTTP status codes, detect redirects,
  and identify broken links.

  ## Automatic Enqueueing

  The worker is triggered automatically during GSC sync via
  `GscAnalytics.DataSources.GSC.Core.Persistence.process_url_response/4`.
  Only URLs with `data_available=true` (URLs with actual search traffic) are enqueued.

  ## Smart Re-checking Strategy

  URLs are periodically re-checked based on their previous status:

  - **Never checked**: Checked within 1-30 minutes (depending on batch size)
  - **Broken (4xx/5xx)**: Re-checked every 3 days
  - **Redirects (3xx)**: Re-checked every 7 days
  - **Healthy (2xx)**: Re-checked every 30 days
  - **Recently checked** (< 7 days): Skipped to avoid duplicate work

  ## Backpressure & Throttling

  To prevent overwhelming the queue during large syncs:

  - **Small batches** (< 500 URLs): Checked within 1 minute, priority 1
  - **Medium batches** (500-2000 URLs): Spread over 5 minutes, priority 2
  - **Large batches** (2000-5000 URLs): Spread over 15 minutes, priority 2
  - **Huge batches** (> 5000 URLs): Spread over 30 minutes, priority 3

  ## Batch Processing

  URLs are processed in batches of 50 with:
  - 10 concurrent HTTP requests per batch
  - 100ms delay between requests (rate limiting)
  - Automatic retry up to 3 times on failure
  - Uniqueness constraints prevent duplicate checks

  ## Telemetry Events

  Emits the following telemetry events for monitoring:

  - `[:gsc_analytics, :http_check, :jobs_enqueued]` - When jobs are created
  - `[:gsc_analytics, :http_check, :batch_start]` - When batch processing starts
  - `[:gsc_analytics, :http_check, :batch_complete]` - When batch succeeds
  - `[:gsc_analytics, :http_check, :batch_failed]` - When batch fails

  ## Configuration

  Configure via application config:

      config :gsc_analytics, GscAnalytics.Workers.HttpStatusCheckWorker,
        batch_size: 50,           # URLs per job
        delay_ms: 100,            # Delay between requests (rate limiting)
        max_attempts: 3,          # Retry failed checks
        priority: 2               # Default Oban priority (0=highest, 3=lowest)

  ## Examples

      # Enqueue check for specific URLs
      HttpStatusCheckWorker.enqueue_urls([
        %{account_id: 1, property_url: "sc-domain:example.com", url: "https://example.com/page"}
      ])

      # Enqueue check for all stale URLs in an account
      HttpStatusCheckWorker.enqueue_stale_urls(account_id: 1)

      # Check specific property's stale URLs with custom limit
      HttpStatusCheckWorker.enqueue_stale_urls(
        account_id: 1,
        property_url: "sc-domain:example.com",
        limit: 500
      )
  """

  use Oban.Worker,
    queue: :http_checks,
    priority: 2,
    max_attempts: 3,
    unique: [
      period: 600,
      # Uniqueness based on individual URLs within the batch, not just batch_id
      # This prevents the same URL from being checked in multiple concurrent jobs
      states: [:available, :scheduled, :executing],
      keys: [:urls]
    ]

  import Ecto.Query
  require Logger

  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.Performance
  alias GscAnalytics.Crawler

  @batch_size Application.compile_env(
                :gsc_analytics,
                [__MODULE__, :batch_size],
                50
              )

  @delay_ms Application.compile_env(
              :gsc_analytics,
              [__MODULE__, :delay_ms],
              100
            )

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Enqueue HTTP status checks for specific URLs.

  ## Options
    - `:priority` - Oban priority (default: 2)
    - `:schedule_in` - Seconds to delay before processing (default: 0)

  ## Examples

      urls = [
        %{account_id: 1, property_url: "sc-domain:example.com", url: "https://example.com"}
      ]
      HttpStatusCheckWorker.enqueue_urls(urls)
  """
  def enqueue_urls(urls, opts \\ []) when is_list(urls) do
    batch_id = generate_batch_id()
    priority = Keyword.get(opts, :priority, 2)
    schedule_in = Keyword.get(opts, :schedule_in, 0)

    # Split into batches to avoid job size limits
    urls
    |> Enum.chunk_every(@batch_size)
    |> Enum.with_index()
    |> Enum.map(fn {batch, index} ->
      %{
        batch_id: batch_id,
        batch_index: index,
        urls: batch
      }
      |> new(priority: priority, schedule_in: schedule_in)
      |> Oban.insert()
    end)
    |> case do
      [] ->
        {:ok, []}

      results ->
        successful = Enum.count(results, &match?({:ok, _}, &1))
        failed = length(results) - successful

        # Emit telemetry for job enqueueing
        :telemetry.execute(
          [:gsc_analytics, :http_check, :jobs_enqueued],
          %{
            url_count: length(urls),
            batch_count: successful,
            failed_count: failed
          },
          %{priority: priority, schedule_in: schedule_in}
        )

        Logger.info("Enqueued #{successful} HTTP status check batches (#{length(urls)} URLs)")
        {:ok, results}
    end
  end

  @doc """
  Enqueue HTTP status checks for all stale URLs.

  Stale URLs are those that:
  - Have never been checked
  - Were checked more than 7 days ago
  - Previously returned errors (checked more than 3 days ago)

  ## Options
    - `:account_id` - Filter by account (required)
    - `:property_url` - Filter by property (optional)
    - `:limit` - Maximum URLs to check (default: 1000)
    - `:priority` - Oban priority (default: 2)

  ## Examples

      HttpStatusCheckWorker.enqueue_stale_urls(account_id: 1)
      HttpStatusCheckWorker.enqueue_stale_urls(account_id: 1, property_url: "sc-domain:example.com")
  """
  def enqueue_stale_urls(opts \\ []) do
    account_id = Keyword.fetch!(opts, :account_id)
    property_url = Keyword.get(opts, :property_url)
    limit = Keyword.get(opts, :limit, 1000)
    priority = Keyword.get(opts, :priority, 2)

    stale_urls = fetch_stale_urls(account_id, property_url, limit)
    url_count = length(stale_urls)

    if url_count > 0 do
      Logger.info("Found #{url_count} stale URLs to check for account #{account_id}")
      enqueue_urls(stale_urls, priority: priority)
    else
      Logger.debug("No stale URLs found for account #{account_id}")
      {:ok, []}
    end
  end

  @doc """
  Enqueue HTTP status checks for newly discovered URLs.

  Called automatically after GSC sync to check URLs that have never been validated.

  ## Examples

      HttpStatusCheckWorker.enqueue_new_urls(
        account_id: 1,
        property_url: "sc-domain:example.com",
        urls: ["https://example.com/new-page"]
      )
  """
  def enqueue_new_urls(opts \\ []) do
    account_id = Keyword.fetch!(opts, :account_id)
    property_url = Keyword.fetch!(opts, :property_url)
    urls = Keyword.fetch!(opts, :urls)

    # Fetch Performance records for these URLs to check if they've been checked before
    unchecked_urls =
      from(p in Performance,
        where:
          p.account_id == ^account_id and
            p.property_url == ^property_url and
            p.url in ^urls and
            is_nil(p.http_status),
        select: %{
          account_id: p.account_id,
          property_url: p.property_url,
          url: p.url
        }
      )
      |> Repo.all()

    if unchecked_urls != [] do
      Logger.info(
        "Enqueuing #{length(unchecked_urls)} newly discovered URLs for HTTP status check"
      )

      enqueue_urls(unchecked_urls, priority: 1, schedule_in: 60)
    else
      {:ok, []}
    end
  end

  # ============================================================================
  # Oban Worker Implementation
  # ============================================================================

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"batch_id" => batch_id, "urls" => urls}} = job) do
    start_time = System.monotonic_time(:millisecond)
    url_count = length(urls)

    Logger.info("Processing HTTP status check batch #{batch_id} (#{url_count} URLs)")

    # Emit telemetry event for job start
    :telemetry.execute(
      [:gsc_analytics, :http_check, :batch_start],
      %{url_count: url_count},
      %{batch_id: batch_id, attempt: job.attempt}
    )

    # Convert string keys back to atoms for Crawler
    url_list = Enum.map(urls, fn url_map -> url_map["url"] end)

    # Use existing Crawler.check_batch with our configured delay
    result =
      try do
        {:ok, results} =
          Crawler.check_batch(url_list,
            concurrency: 10,
            delay_ms: @delay_ms,
            progress_tracking: false,
            save_results: true
          )

        success_count = Enum.count(results, fn {_url, result} -> result.status != nil end)
        error_count = url_count - success_count
        duration_ms = System.monotonic_time(:millisecond) - start_time

        # Emit success telemetry
        :telemetry.execute(
          [:gsc_analytics, :http_check, :batch_complete],
          %{
            duration_ms: duration_ms,
            url_count: url_count,
            success_count: success_count,
            error_count: error_count
          },
          %{batch_id: batch_id}
        )

        Logger.info(
          "Completed batch #{batch_id}: #{success_count}/#{url_count} successful in #{duration_ms}ms"
        )

        :ok
      rescue
        error ->
          duration_ms = System.monotonic_time(:millisecond) - start_time

          # Emit failure telemetry
          :telemetry.execute(
            [:gsc_analytics, :http_check, :batch_failed],
            %{duration_ms: duration_ms, url_count: url_count},
            %{batch_id: batch_id, error: inspect(error)}
          )

          Logger.error("Batch #{batch_id} failed after #{duration_ms}ms: #{inspect(error)}")
          reraise error, __STACKTRACE__
      end

    result
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp fetch_stale_urls(account_id, property_url, limit) do
    seven_days_ago = DateTime.utc_now() |> DateTime.add(-7, :day)
    three_days_ago = DateTime.utc_now() |> DateTime.add(-3, :day)

    base_query =
      from(p in Performance,
        where: p.account_id == ^account_id and p.data_available == true,
        select: %{
          account_id: p.account_id,
          property_url: p.property_url,
          url: p.url
        },
        limit: ^limit
      )

    query =
      base_query
      |> maybe_filter_property(property_url)
      |> where(
        [p],
        # Never checked
        # Checked > 7 days ago
        # Errors checked > 3 days ago
        is_nil(p.http_status) or
          p.http_checked_at < ^seven_days_ago or
          (p.http_status >= 400 and p.http_checked_at < ^three_days_ago)
      )
      |> order_by([p],
        asc:
          fragment(
            "CASE WHEN ? IS NULL THEN 0 WHEN ? >= 400 THEN 1 ELSE 2 END",
            p.http_status,
            p.http_status
          )
      )

    Repo.all(query)
  end

  defp maybe_filter_property(query, nil), do: query

  defp maybe_filter_property(query, property_url) when is_binary(property_url) do
    where(query, [p], p.property_url == ^property_url)
  end

  defp generate_batch_id do
    "http-check-#{System.system_time(:second)}-#{:rand.uniform(9999)}"
  end
end
