defmodule GscAnalytics.ContentInsights.UrlPerformance.Enrichment do
  @moduledoc """
  Enriches URL performance data with WoW growth calculations and content tagging.

  This module handles post-query enrichment including:
  - Week-over-week (WoW) growth calculation using window functions
  - Selected metrics computation (period vs lifetime)
  - Update status tagging (needs update, priority, reason)
  - CTR percentage formatting

  ## WoW Growth Calculation

  Uses `TimeSeriesAggregator.batch_calculate_wow_growth/2` which leverages PostgreSQL
  window functions for 20x performance improvement over naive batch queries.

  Fetches the last 8 weeks of data (4 recent + 4 prior) to compute growth percentages
  for the most recent week.

  ## Tagging Logic

  URLs are tagged as "needs update" if:
  - WoW growth drops below -20%
  - Average position is worse than 10
  - Content is categorized as "Stale" (future enhancement)

  Priority is assigned based on traffic volume:
  - High: >1,000 clicks
  - Medium: >100 clicks
  - Low: ≤100 clicks
  """

  alias GscAnalytics.Analytics.TimeSeriesAggregator

  @doc """
  Enrich URLs with WoW growth, selected metrics, and update tags.

  ## Parameters

  - `urls` - List of URL data maps from the query
  - `account_id` - Account ID for filtering time series data
  - `property_url` - GSC property URL
  - `period_days` - Determines whether to use period or lifetime metrics

  ## Returns

  List of enriched URL maps with additional fields:
  - `wow_growth_last4w` - Week-over-week growth percentage
  - `selected_clicks` - Period or lifetime clicks based on mode
  - `selected_impressions` - Period or lifetime impressions
  - `selected_ctr` - Period or lifetime CTR
  - `selected_ctr_pct` - CTR as percentage (0-100)
  - `selected_position` - Period or lifetime position
  - `selected_metrics_source` - `:period` or `:lifetime`
  - `lifetime_ctr_pct` - Lifetime CTR as percentage
  - `period_ctr_pct` - Period CTR as percentage
  - `needs_update` - Boolean flag for update recommendation
  - `update_reason` - Human-readable reason for update
  - `update_priority` - "High", "Medium", or "Low"
  - `type` - Content type (placeholder for future metadata)
  - `content_category` - Content category (placeholder)
  """
  @spec enrich_urls([map()], integer(), String.t(), integer()) :: [map()]
  def enrich_urls(urls, account_id, property_url, period_days) do
    url_list = Enum.map(urls, & &1.url)

    # Use window function implementation for 20x performance improvement
    # Fetches last 8 weeks (4 weeks recent + 4 weeks prior for comparison)
    start_date = Date.add(Date.utc_today(), -8 * 7)

    wow_growth_results =
      TimeSeriesAggregator.batch_calculate_wow_growth(
        url_list,
        %{
          start_date: start_date,
          account_id: account_id,
          property_url: property_url,
          weeks_back: 1
        }
      )

    # Convert list of weekly results to map of url => latest WoW growth
    # We take the most recent week's growth for each URL
    wow_growth_map = build_wow_growth_map(wow_growth_results)

    use_lifetime = lifetime_window?(period_days)

    Enum.map(urls, fn url_data ->
      wow_growth = Map.get(wow_growth_map, url_data.url, 0.0)

      url_data
      |> add_selected_metrics(use_lifetime)
      |> add_ctr_percentages()
      |> add_wow_growth(wow_growth)
      |> add_content_metadata()
      |> tag_update_status(wow_growth)
    end)
  end

  # ============================================================================
  # PRIVATE HELPERS
  # ============================================================================

  # Build a map of url => wow_growth from batch results
  defp build_wow_growth_map(wow_growth_results) do
    wow_growth_results
    |> Enum.group_by(& &1.url)
    |> Enum.map(fn {url, weeks} ->
      # Get the most recent week that has growth data
      latest_growth =
        weeks
        |> Enum.reject(&is_nil(&1.wow_growth_pct))
        |> Enum.max_by(& &1.week_start, Date, fn -> nil end)

      growth_value = if latest_growth, do: latest_growth.wow_growth_pct, else: 0.0
      {url, growth_value}
    end)
    |> Map.new()
  end

  # Add selected metrics based on period vs lifetime mode
  defp add_selected_metrics(url_data, use_lifetime) do
    selected_clicks =
      if use_lifetime do
        url_data.lifetime_clicks || 0
      else
        url_data.period_clicks || url_data.lifetime_clicks || 0
      end

    selected_impressions =
      if use_lifetime do
        url_data.lifetime_impressions || 0
      else
        url_data.period_impressions || url_data.lifetime_impressions || 0
      end

    selected_ctr =
      if use_lifetime do
        url_data.lifetime_avg_ctr
      else
        url_data.period_ctr || url_data.lifetime_avg_ctr
      end

    selected_position =
      if use_lifetime do
        url_data.lifetime_avg_position
      else
        url_data.period_position || url_data.lifetime_avg_position
      end

    Map.merge(url_data, %{
      selected_clicks: selected_clicks,
      selected_impressions: selected_impressions,
      selected_ctr: selected_ctr,
      selected_position: selected_position,
      selected_metrics_source: if(use_lifetime, do: :lifetime, else: :period)
    })
  end

  # Add CTR percentages (0-100 scale)
  defp add_ctr_percentages(url_data) do
    selected_ctr_pct = Float.round((url_data.selected_ctr || 0.0) * 100, 2)
    lifetime_ctr_pct = Float.round((url_data.lifetime_avg_ctr || 0.0) * 100, 2)
    period_ctr_pct = Float.round((url_data.period_ctr || 0.0) * 100, 2)

    Map.merge(url_data, %{
      selected_ctr_pct: selected_ctr_pct,
      lifetime_ctr_pct: lifetime_ctr_pct,
      period_ctr_pct: period_ctr_pct
    })
  end

  # Add WoW growth metric
  defp add_wow_growth(url_data, wow_growth) do
    Map.put(url_data, :wow_growth_last4w, wow_growth)
  end

  # Add content metadata (placeholders for future enhancement)
  defp add_content_metadata(url_data) do
    Map.merge(url_data, %{
      type: nil,
      content_category: nil
    })
  end

  # Tag URL with update status, reason, and priority
  defp tag_update_status(url_data, wow_growth) do
    position =
      Map.get(url_data, :selected_position) ||
        Map.get(url_data, :period_position) ||
        Map.get(url_data, :lifetime_avg_position)

    clicks =
      Map.get(url_data, :selected_clicks) ||
        Map.get(url_data, :period_clicks) ||
        Map.get(url_data, :lifetime_clicks, 0)

    needs_update =
      cond do
        wow_growth < -20 -> true
        position && position > 10 -> true
        url_data[:content_category] == "Stale" -> true
        true -> false
      end

    Map.merge(url_data, %{
      needs_update: needs_update,
      update_reason:
        if needs_update do
          cond do
            wow_growth < -20 -> "Traffic drop #{wow_growth}%"
            position && position > 10 -> "Low ranking (position #{Float.round(position, 1)})"
            url_data[:content_category] == "Stale" -> "Content is stale"
            true -> "Review needed"
          end
        end,
      update_priority:
        if needs_update do
          cond do
            clicks > 1_000 -> "High"
            clicks > 100 -> "Medium"
            true -> "Low"
          end
        end
    })
  end

  defp lifetime_window?(period_days) when is_integer(period_days) and period_days >= 10_000,
    do: true

  defp lifetime_window?(_), do: false
end
