defmodule GscAnalytics.DataSources.SERP.Core.Config do
  @moduledoc """
  Centralized configuration for SERP data source.
  """

  # Compile-time environment detection to avoid runtime Mix dependency
  @is_test Application.compile_env(:gsc_analytics, :env) == :test

  @doc """
  Returns the ScrapFly API key.
  Raises if not configured (except in test environment where a placeholder is acceptable).
  """
  def api_key do
    api_key = Application.get_env(:gsc_analytics, :scrapfly_api_key)

    if is_binary(api_key) && String.length(api_key) > 0 do
      api_key
    else
      if @is_test do
        "test_api_key_placeholder"
      else
        raise "SCRAPFLY_API_KEY not configured. Set SCRAPFLY_API_KEY environment variable."
      end
    end
  end

  @doc """
  Returns the ScrapFly API base URL.
  """
  def base_url, do: "https://api.scrapfly.io"

  @doc """
  Returns the default geo location for SERP queries.
  """
  def default_geo, do: "us"

  @doc """
  Returns the default response format (JSON).
  """
  def default_format, do: "json"

  @doc """
  Returns the rate limit per minute for API calls.
  """
  def rate_limit_per_minute, do: 60

  @doc """
  Returns the unique period in hours for Oban job deduplication.
  """
  def unique_period_hours, do: 1

  @doc """
  Returns the HTTP client module to use for API requests.

  Defaults to ReqClient (production), but can be overridden via application config
  for testing (e.g., with Mox).
  """
  def http_client do
    Application.get_env(
      :gsc_analytics,
      :serp_http_client,
      GscAnalytics.DataSources.SERP.Adapters.ReqClient
    )
  end
end
