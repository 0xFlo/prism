defmodule GscAnalytics.Workers.SerpCheckWorker do
  @moduledoc """
  Oban worker for asynchronous SERP position checking via ScrapFly API.

  ## Features
  - Uses ScrapFly LLM Extraction for SERP position parsing
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
      keys: [:account_id, :property_url, :url, :keyword, :geo],
      states: [:available, :scheduled, :executing]
    ]

  alias GscAnalytics.DataSources.SERP.Core.{Client, LLMExtractor, Persistence}
  alias GscAnalytics.DataSources.SERP.Support.RateLimiter

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    account_id = args["account_id"]
    _property_url = args["property_url"]
    url = args["url"]
    keyword = args["keyword"]
    geo = args["geo"] || "us"

    Logger.info("Starting SERP check",
      account_id: account_id,
      url: url,
      keyword: keyword,
      geo: geo
    )

    with :ok <- RateLimiter.check_rate(account_id),
         extraction_prompt <- LLMExtractor.build_extraction_prompt(url),
         {:ok, scrapfly_response} <-
           Client.scrape_google(keyword,
             geo: geo,
             extraction_prompt: extraction_prompt
           ),
         parsed <- LLMExtractor.parse_llm_response(scrapfly_response, url),
         snapshot_attrs <- build_snapshot_attrs(args, parsed, scrapfly_response),
         {:ok, snapshot} <- Persistence.save_snapshot(snapshot_attrs) do
      # Track API cost
      api_cost = Decimal.to_integer(snapshot_attrs.api_cost)
      RateLimiter.track_cost(account_id, api_cost)

      Logger.info("SERP check completed",
        account_id: account_id,
        url: url,
        position: snapshot.position,
        api_cost: api_cost
      )

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

        error
    end
  end

  defp build_snapshot_attrs(args, parsed, raw_response) do
    %{
      account_id: args["account_id"],
      property_url: args["property_url"],
      url: args["url"],
      keyword: args["keyword"],
      position: parsed.position,
      competitors: parsed.competitors || [],
      serp_features: parsed.serp_features || [],
      raw_response: raw_response,
      geo: args["geo"] || "us",
      checked_at: DateTime.utc_now(),
      # ScrapFly SERP API cost: 31 (base) + 5 (LLM) = 36 credits
      api_cost: Decimal.new("36"),
      error_message: parsed[:error]
    }
  end
end
