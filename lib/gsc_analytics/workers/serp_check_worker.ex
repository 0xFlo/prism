defmodule GscAnalytics.Workers.SerpCheckWorker do
  @moduledoc """
  Oban worker for asynchronous SERP position checking via ScrapFly API.

  ## Features
  - Uses HTML parsing for SERP position extraction
  - Enforces idempotency via Oban unique_periods (1 hour window)
  - Automatic retries on transient failures (max 3 attempts)
  - Rate limiting integration to prevent quota exhaustion

  ## Job Arguments
  - `account_id` (required) - Account identifier
  - `property_url` (required) - GSC property URL (e.g., "sc-domain:example.com")
  - `url` (required) - URL to check in SERP
  - `keyword` (required) - Search keyword/query
  - `geo` (optional) - Geographic location (default: "us")

  ## Unique Job Keys
  Prevents duplicate API calls for the same URL+keyword+geo within 1 hour using:
  - account_id
  - property_url
  - url
  - keyword
  - geo

  ## Example Usage
      iex> SerpCheckWorker.new(%{
      ...>   account_id: 1,
      ...>   property_url: "sc-domain:example.com",
      ...>   url: "https://example.com",
      ...>   keyword: "elixir programming"
      ...> }) |> Oban.insert()
      {:ok, %Oban.Job{}}
  """

  use Oban.Worker,
    queue: :serp_check,
    priority: 2,
    max_attempts: 3,
    unique: [
      period: 3600,
      keys: [:account_id, :property_url, :url, :keyword, :geo, :run_keyword_id],
      states: [:available, :scheduled, :executing]
    ]

  import Ecto.Changeset
  alias GscAnalytics.DataSources.SERP.Core.{Client, HTMLParser, Persistence}
  alias GscAnalytics.DataSources.SERP.Support.RateLimiter
  alias GscAnalytics.Schemas.SerpSnapshot
  alias GscAnalytics.SerpChecks

  require Logger

  @doc """
  Validates job arguments before insertion into Oban queue.

  Ensures all required fields are present and properly typed.
  Sets default value for optional `geo` parameter.
  """
  def changeset(job, params) do
    job
    |> cast(params, [:account_id, :property_url, :url, :keyword, :geo, :run_id, :run_keyword_id])
    |> validate_required([:account_id, :property_url, :url, :keyword])
    |> validate_number(:account_id, greater_than: 0)
    |> validate_format(:property_url, ~r/^(sc-domain:|https?:\/\/)/)
    |> validate_format(:url, ~r/^https?:\/\//)
    |> validate_length(:keyword, min: 1, max: 500)
    |> put_default_geo()
  end

  defp put_default_geo(changeset) do
    case get_change(changeset, :geo) do
      nil -> put_change(changeset, :geo, "us")
      _ -> changeset
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    account_id = args["account_id"]
    _property_url = args["property_url"]
    url = args["url"]
    keyword = args["keyword"]
    geo = args["geo"] || "us"
    run_keyword_id = args["run_keyword_id"]

    maybe_mark_running(run_keyword_id)

    Logger.info("Starting SERP check",
      account_id: account_id,
      url: url,
      keyword: keyword,
      geo: geo
    )

    with :ok <- RateLimiter.check_rate(account_id),
         {:ok, scrapfly_response} <-
           Client.scrape_google(keyword, geo: geo),
         # Track API cost immediately after successful API call
         # ScrapFly SERP API cost: 31 credits (base only, no LLM)
         :ok <- track_api_cost(account_id, 31),
         parsed <- HTMLParser.parse_serp_response(scrapfly_response, url),
         snapshot_attrs <-
           build_snapshot_attrs(
             args,
             parsed,
             scrapfly_response,
             content_types_present: derive_content_types(parsed),
             scrapfly_stats: SerpSnapshot.scrapfly_citation_stats(parsed[:ai_overview_citations])
           ),
         {:ok, snapshot} <- Persistence.save_snapshot(snapshot_attrs) do
      Logger.info("SERP check completed",
        account_id: account_id,
        url: url,
        position: snapshot.position,
        api_cost: 31
      )

      maybe_mark_success(run_keyword_id, snapshot)

      :ok
    else
      {:error, :rate_limited} ->
        Logger.warning("Rate limit exceeded for account", account_id: account_id)
        {:snooze, 60}

      {:error, reason} = error ->
        Logger.error("SERP check failed",
          account_id: account_id,
          url: url,
          reason: inspect(reason)
        )

        maybe_mark_failure(job, run_keyword_id, reason)

        error
    end
  end

  # Track API cost immediately after successful API call to prevent double-billing on retry
  defp track_api_cost(account_id, cost) do
    RateLimiter.track_cost(account_id, cost)
    :ok
  end

  defp derive_content_types(parsed) do
    case Map.get(parsed, :content_types_present) do
      list when is_list(list) and list != [] ->
        list

      _ ->
        parsed
        |> Map.get(:competitors, [])
        |> SerpSnapshot.content_types_from_competitors()
    end
  end

  defp build_snapshot_attrs(args, parsed, raw_response, opts \\ []) do
    content_types_present = Keyword.get(opts, :content_types_present, [])
    {scrapfly_mentioned?, scrapfly_position} =
      Keyword.get(opts, :scrapfly_stats, {false, nil})

    %{
      account_id: args["account_id"],
      property_url: args["property_url"],
      url: args["url"],
      keyword: args["keyword"],
      position: parsed.position,
      competitors: parsed.competitors,
      serp_features: parsed.serp_features,
      ai_overview_present: parsed[:ai_overview_present] || false,
      ai_overview_text: parsed[:ai_overview_text],
      ai_overview_citations: parsed[:ai_overview_citations] || [],
      content_types_present: content_types_present,
      scrapfly_mentioned_in_ao: scrapfly_mentioned?,
      scrapfly_citation_position: scrapfly_position,
      serp_check_run_id: args["run_id"],
      raw_response: raw_response,
      geo: args["geo"] || "us",
      checked_at: DateTime.utc_now(),
      # ScrapFly SERP API cost: 31 (base) + 5 (LLM) = 36 credits
      api_cost: Decimal.new("36"),
      error_message: parsed[:error]
    }
  end

  defp maybe_mark_running(nil), do: :ok
  defp maybe_mark_running(run_keyword_id), do: SerpChecks.mark_keyword_running(run_keyword_id)

  defp maybe_mark_success(nil, _snapshot), do: :ok

  defp maybe_mark_success(run_keyword_id, snapshot) do
    SerpChecks.mark_keyword_success(run_keyword_id, %{position: snapshot.position})
    :ok
  end

  defp maybe_mark_failure(_job, nil, _reason), do: :ok

  defp maybe_mark_failure(
         %Oban.Job{attempt: attempt, max_attempts: max_attempts},
         run_keyword_id,
         reason
       ) do
    if attempt >= max_attempts do
      SerpChecks.mark_keyword_failed(run_keyword_id, inspect(reason))
    end

    :ok
  end
end
