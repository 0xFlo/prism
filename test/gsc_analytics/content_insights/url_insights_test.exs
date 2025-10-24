defmodule GscAnalytics.ContentInsights.UrlInsightsTest do
  use GscAnalytics.DataCase

  alias GscAnalytics.ContentInsights
  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.{Performance, TimeSeries}

  @account_id 1

  setup do
    old_url = "https://example.com/blog/how-to-scrape"
    new_url = "https://example.com/blog/posts/how-to-scrape"

    old_attrs = %{
      account_id: @account_id,
      url: old_url,
      http_status: 301,
      redirect_url: new_url,
      http_checked_at: ~U[2025-01-15 00:00:00Z]
    }

    new_attrs = %{
      account_id: @account_id,
      url: new_url,
      http_status: 200,
      http_checked_at: ~U[2025-02-02 00:00:00Z]
    }

    [old_attrs, new_attrs]
    |> Enum.each(fn attrs ->
      %Performance{}
      |> Performance.changeset(attrs)
      |> Repo.insert!()
    end)

    insert_series(old_url, ~D[2024-12-15], %{
      clicks: 20,
      impressions: 200,
      position: 8.0,
      top_queries: [
        %{"query" => "shared query", "clicks" => 4, "impressions" => 80, "position" => 7.5}
      ]
    })

    insert_series(old_url, ~D[2024-12-16], %{
      clicks: 15,
      impressions: 150,
      position: 7.0,
      top_queries: [
        %{"query" => "legacy only", "clicks" => 5, "impressions" => 60, "position" => 6.5},
        %{"query" => "shared query", "clicks" => 3, "impressions" => 50, "position" => 6.0}
      ]
    })

    insert_series(new_url, ~D[2025-02-01], %{
      clicks: 30,
      impressions: 180,
      position: 5.0,
      top_queries: [
        %{"query" => "  Shared Query  ", "clicks" => 6, "impressions" => 90, "position" => 4.5},
        %{"query" => "new query", "clicks" => 12, "impressions" => 70, "position" => 3.5}
      ]
    })

    insert_series(new_url, ~D[2025-02-02], %{
      clicks: 25,
      impressions: 170,
      position: 4.5,
      top_queries: [
        %{"query" => "shared query", "clicks" => 5, "impressions" => 60, "position" => 4.0}
      ]
    })

    {:ok, %{old_url: old_url, new_url: new_url}}
  end

  test "aggregates metrics across redirect chain", %{old_url: old_url, new_url: new_url} do
    insights = ContentInsights.url_insights(old_url, "daily")

    assert insights.url == new_url
    assert insights.requested_url == old_url
    assert insights.performance.clicks == 90
    assert insights.performance.impressions == 700

    assert Date.compare(
             insights.performance.date_range_start,
             insights.performance.date_range_end
           ) != :gt

    dates = Enum.map(insights.time_series, & &1.date)
    assert ~D[2024-12-15] in dates
    assert ~D[2025-02-02] in dates

    assert insights.range_summary =~ "day"
    assert insights.data_coverage_summary =~ "day"
    assert insights.data_range_start == ~D[2024-12-15]
    assert insights.data_range_end == ~D[2025-02-02]

    assert Enum.any?(insights.chart_events, &(&1.date == "2025-01-15"))
  end

  test "weekly view normalizes chart events to week start", %{old_url: old_url} do
    insights = ContentInsights.url_insights(old_url, "weekly")

    assert insights.label == "Week Starting"
    assert Enum.any?(insights.chart_events, fn event -> event.date == "2025-01-13" end)
  end

  test "monthly view normalizes chart events to month start", %{old_url: old_url} do
    insights = ContentInsights.url_insights(old_url, "monthly")

    assert insights.label == "Month"
    assert Enum.any?(insights.chart_events, fn event -> event.date == "2025-01-01" end)
  end

  test "aggregates top queries across url group", %{old_url: old_url} do
    insights = ContentInsights.url_insights(old_url, "daily")

    shared = Enum.find(insights.top_queries, &(String.downcase(&1.query) == "shared query"))
    legacy = Enum.find(insights.top_queries, &(String.downcase(&1.query) == "legacy only"))
    new_query = Enum.find(insights.top_queries, &(String.downcase(&1.query) == "new query"))

    assert shared
    assert shared.query == "Shared Query"
    assert_in_delta shared.clicks, 18, 0.0001
    assert_in_delta shared.impressions, 280, 0.0001
    assert_in_delta shared.ctr, 18 / 280, 0.0001

    assert legacy
    assert new_query

    assert insights.performance.fetched_at == insights.period_end
  end

  test "selection window preserves requested span", %{old_url: old_url} do
    insights = ContentInsights.url_insights(old_url, "daily", %{period_days: 30})

    assert insights.period_end == ~D[2025-02-02]
    assert insights.period_start == ~D[2025-01-04]
    assert insights.range_summary == "30 days"
    assert insights.data_coverage_summary == "2 days"
    assert insights.data_range_start == ~D[2025-02-01]
    assert insights.data_range_end == ~D[2025-02-02]
  end

  test "period_days filters time series and query aggregation", %{old_url: old_url} do
    insights = ContentInsights.url_insights(old_url, "daily", %{period_days: 7})

    dates = Enum.map(insights.time_series, & &1.date)
    assert dates == [~D[2025-02-01], ~D[2025-02-02]]
    assert insights.range_summary == "7 days"
    assert insights.data_coverage_summary == "2 days"

    shared = Enum.find(insights.top_queries, &(String.downcase(&1.query) == "shared query"))
    refute Enum.any?(insights.top_queries, &(String.downcase(&1.query) == "legacy only"))

    assert shared
    assert shared.query == "Shared Query"
    assert_in_delta shared.clicks, 11, 0.0001
    assert_in_delta shared.impressions, 150, 0.0001
  end

  defp insert_series(url, date, overrides) do
    defaults = %{
      clicks: 10,
      impressions: 100,
      ctr: 0.1,
      position: 6.0,
      data_available: true,
      top_queries: []
    }
    attrs = Map.merge(defaults, overrides)

    %TimeSeries{
      account_id: @account_id,
      url: url,
      date: date,
      period_type: :daily,
      clicks: attrs.clicks,
      impressions: attrs.impressions,
      ctr: attrs.ctr,
      position: attrs.position,
      data_available: attrs.data_available,
      top_queries: attrs.top_queries
    }
    |> Repo.insert!()
  end
end
