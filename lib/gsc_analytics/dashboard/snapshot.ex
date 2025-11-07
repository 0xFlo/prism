defmodule GscAnalytics.Dashboard.Snapshot do
  @moduledoc """
  Typed data container for the dashboard snapshot used by LiveViews.
  """

  @enforce_keys [
    :urls,
    :page,
    :total_pages,
    :total_count,
    :stats,
    :site_trends,
    :chart_label,
    :period_totals
  ]

  defstruct @enforce_keys

  @doc """
  Empty snapshot used when no property has been selected yet.
  """
  def empty do
    %__MODULE__{
      urls: [],
      page: 1,
      total_pages: 1,
      total_count: 0,
      stats: empty_stats(),
      site_trends: [],
      chart_label: "Date",
      period_totals: empty_period_totals()
    }
  end

  defp empty_stats do
    period = %{
      total_urls: 0,
      total_clicks: 0,
      total_impressions: 0,
      avg_ctr: 0.0,
      avg_position: 0.0
    }

    %{
      current_month: period,
      last_month: period,
      all_time:
        Map.merge(period, %{
          earliest_date: nil,
          latest_date: nil,
          days_with_data: 0
        }),
      month_over_month_change: 0
    }
  end

  defp empty_period_totals do
    %{
      total_clicks: 0,
      total_impressions: 0,
      avg_ctr: 0.0,
      avg_position: 0.0
    }
  end
end
