defmodule GscAnalytics.DataSources.SERP.Core.Config do
  @moduledoc """
  Centralized configuration for SERP data source.
  """

  @doc """
  Returns the ScrapFly API key.
  Raises if not configured (except in test environment where a placeholder is acceptable).
  """
  def api_key do
    api_key = Application.get_env(:gsc_analytics, :scrapfly_api_key)

    cond do
      is_binary(api_key) && String.length(api_key) > 0 ->
        api_key

      Mix.env() == :test ->
        "test_api_key_placeholder"

      true ->
        raise "SCRAPFLY_API_KEY not configured"
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
end
