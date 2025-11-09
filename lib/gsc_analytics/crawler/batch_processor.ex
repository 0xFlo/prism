defmodule GscAnalytics.Crawler.BatchProcessor do
  @moduledoc """
  Concurrent batch processing for HTTP status checking.

  This module processes multiple URLs concurrently using Task.async_stream,
  with configurable concurrency limits, timeouts, and progress tracking.

  ## Features
  - Concurrent URL processing with polite rate limiting
  - Configurable concurrency (default: 15 concurrent requests)
  - Configurable delay between requests (default: 100ms)
  - Per-URL timeout handling
  - Progress tracking integration
  - High-traffic URLs prioritized
  """

  require Logger

  alias GscAnalytics.Crawler.{HttpStatus, ProgressTracker, Persistence}
  alias GscAnalytics.Schemas.Performance
  alias GscAnalytics.Repo

  import Ecto.Query

  @default_concurrency 15
  @default_timeout 10_000
  @default_delay_ms 100

  @type batch_stats :: %{
          total: integer(),
          checked: integer(),
          status_2xx: integer(),
          status_3xx: integer(),
          status_4xx: integer(),
          status_5xx: integer(),
          errors: integer()
        }

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Process a batch of URLs concurrently.

  ## Options
    - `:concurrency` - Number of concurrent requests (default: #{@default_concurrency})
    - `:timeout` - Timeout per URL in milliseconds (default: #{@default_timeout})
    - `:delay_ms` - Delay between requests in milliseconds (default: #{@default_delay_ms})
    - `:progress_tracking` - Enable progress tracking (default: true)
    - `:save_results` - Save results to database (default: true)

  ## Returns
    - `{:ok, results}` - List of {url, result} tuples
  """
  @spec process_batch(list(String.t()), keyword()) :: {:ok, list({String.t(), map()})}
  def process_batch(urls, opts \\ []) when is_list(urls) do
    concurrency = Keyword.get(opts, :concurrency, @default_concurrency)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    delay_ms = Keyword.get(opts, :delay_ms, @default_delay_ms)
    track_progress? = Keyword.get(opts, :progress_tracking, true)
    save_results? = Keyword.get(opts, :save_results, true)

    Logger.info(
      "Starting batch check for #{length(urls)} URLs (concurrency: #{concurrency}, delay: #{delay_ms}ms)"
    )

    results =
      urls
      |> Task.async_stream(
        fn url ->
          # Add polite delay before each request to avoid overwhelming the server
          if delay_ms > 0, do: Process.sleep(delay_ms)

          result = HttpStatus.check_url(url, timeout: timeout)

          if track_progress? do
            update_progress(result)
          end

          {url, result}
        end,
        max_concurrency: concurrency,
        timeout: timeout + delay_ms + 1_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, {url, {:ok, result}}} ->
          {url, result}

        {:ok, {url, {:error, reason}}} ->
          Logger.warning("Failed to check #{url}: #{inspect(reason)}")

          {url,
           %{
             status: nil,
             redirect_url: nil,
             redirect_chain: %{},
             checked_at: DateTime.utc_now(),
             error: inspect(reason)
           }}

        {:exit, :timeout} ->
          Logger.warning("Timeout checking URL")

          {nil,
           %{
             status: nil,
             redirect_url: nil,
             redirect_chain: %{},
             checked_at: DateTime.utc_now(),
             error: "Task timeout"
           }}
      end)
      |> Enum.reject(fn {url, _result} -> is_nil(url) end)

    if save_results? do
      Persistence.save_batch(results)
    end

    {:ok, results}
  end

  @doc """
  Process all URLs for an account that need checking.

  URLs are prioritized by traffic (high-traffic URLs checked first).

  **Important**: This function is blocking and will return only when all URLs are checked.
  Progress updates are broadcast via PubSub for real-time tracking in LiveViews.

  ## Options
    - `:account_id` - Account ID (default: 1)
    - `:property_url` - Optional property URL to scope URLs
    - `:property_id` - Optional property identifier (stored as metadata)
    - `:property_label` - Optional human label for UI metadata
    - `:filter` - Filter to apply (:all, :stale, :broken, :redirected)
    - `:concurrency` - Number of concurrent requests (default: #{@default_concurrency})
    - `:delay_ms` - Delay between requests in milliseconds (default: #{@default_delay_ms})

  ## Examples

      # Blocking - waits for completion
      {:ok, stats} = Crawler.check_all(account_id: 1, filter: :stale)

      # Non-blocking - run in background task
      Task.start(fn -> Crawler.check_all(account_id: 1, filter: :all) end)

  ## Returns
    - `{:ok, stats}` - Statistics about the check operation
  """
  @spec process_all(keyword()) :: {:ok, batch_stats()}
  def process_all(opts \\ []) do
    account_id = Keyword.get(opts, :account_id, 1)
    filter = Keyword.get(opts, :filter, :stale)
    property_url = Keyword.get(opts, :property_url)
    property_id = Keyword.get(opts, :property_id)
    property_label = Keyword.get(opts, :property_label)

    # Fetch URLs to check
    urls = fetch_urls_to_check(account_id, filter, property_url)

    Logger.info("Processing #{length(urls)} URLs for account #{account_id} (filter: #{filter})")

    # Start progress tracking
    ProgressTracker.start_check(length(urls), %{
      account_id: account_id,
      property_id: property_id,
      property_url: property_url,
      property_label: property_label
    })

    # Process all URLs concurrently (Task.async_stream handles concurrency limits)
    {:ok, results} = process_batch(urls, opts)

    # Finish progress tracking
    stats = calculate_stats(results)
    ProgressTracker.finish_check(stats)

    {:ok, stats}
  end

  # ============================================================================
  # Private - URL Fetching
  # ============================================================================

  defp fetch_urls_to_check(account_id, filter, property_url) do
    # Debug: Log counts with a single optimized query
    counts =
      from(p in Performance,
        where: p.account_id == ^account_id,
        select: %{
          total: count(p.id),
          available: fragment("COUNT(*) FILTER (WHERE ? = true)", p.data_available)
        }
      )
      |> filter_by_property(property_url)
      |> Repo.one()

    Logger.debug(
      "URL check filter - account: #{account_id}, property: #{inspect(property_url)}, " <>
        "total_rows: #{counts.total}, data_available: #{counts.available}, filter: #{filter}"
    )

    base_query =
      from(p in Performance,
        where: p.account_id == ^account_id,
        where: p.data_available == true,
        order_by: [desc: p.clicks],
        select: p.url
      )
      |> filter_by_property(property_url)

    query =
      case filter do
        :all ->
          base_query

        :stale ->
          base_query |> Performance.needs_http_check(7)

        :broken ->
          base_query |> Performance.broken_links()

        :redirected ->
          base_query |> Performance.redirected_urls()

        _ ->
          base_query |> Performance.needs_http_check(7)
      end

    urls = Repo.all(query)

    Logger.debug("Fetched #{length(urls)} URLs matching filter criteria")

    urls
  end

  # ============================================================================
  # Private - Progress Tracking
  # ============================================================================

  defp update_progress({:ok, result}) do
    ProgressTracker.update_progress(result)
  end

  # ============================================================================
  # Private - Statistics
  # ============================================================================

  defp calculate_stats(results) do
    initial_stats = %{
      total: length(results),
      checked: 0,
      status_2xx: 0,
      status_3xx: 0,
      status_4xx: 0,
      status_5xx: 0,
      errors: 0
    }

    Enum.reduce(results, initial_stats, fn {_url, result}, stats ->
      stats = Map.put(stats, :checked, stats.checked + 1)

      cond do
        result.error ->
          Map.put(stats, :errors, stats.errors + 1)

        is_nil(result.status) ->
          Map.put(stats, :errors, stats.errors + 1)

        result.status >= 200 and result.status < 300 ->
          Map.put(stats, :status_2xx, stats.status_2xx + 1)

        result.status >= 300 and result.status < 400 ->
          Map.put(stats, :status_3xx, stats.status_3xx + 1)

        result.status >= 400 and result.status < 500 ->
          Map.put(stats, :status_4xx, stats.status_4xx + 1)

        result.status >= 500 ->
          Map.put(stats, :status_5xx, stats.status_5xx + 1)

        true ->
          stats
      end
    end)
  end

  defp filter_by_property(query, nil), do: query

  defp filter_by_property(query, property_url) when is_binary(property_url) do
    where(query, [p], p.property_url == ^property_url)
  end
end
