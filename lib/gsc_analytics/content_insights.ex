defmodule GscAnalytics.ContentInsights do
  @moduledoc """
  Public API for analytics surfaced on the Content Insights views.

  Provides a thin wrapper around specialised submodules so callers can depend on
  a stable boundary while we decompose the historic Dashboard module.
  """

  alias GscAnalytics.ContentInsights.{KeywordAggregator, UrlInsights, UrlPerformance}

  @doc """
  Fetch detailed metrics for a single URL (URL group, charts, backlinks, queries).
  """
  def url_insights(url, view_mode, opts \\ %{}) do
    UrlInsights.fetch(url, view_mode, opts)
  end

  @doc """
  List top keywords aggregated across the site.
  """
  def list_keywords(opts \\ %{}) do
    KeywordAggregator.list(opts)
  end

  @doc """
  List URLs with lifetime and period metrics.

  This temporarily delegates to the legacy Dashboard implementation until Ticket
  #007 replaces it with the new UrlPerformance module.
  """
  def list_urls(opts \\ %{}) do
    UrlPerformance.list(opts)
  end
end
