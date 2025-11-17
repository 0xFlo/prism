defmodule GscAnalytics.Analytics.SummaryStatsTest do
  use GscAnalytics.DataCase

  alias GscAnalytics.Analytics.SummaryStats
  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.PropertyDailyMetric

  @account_id 1
  @property_url "sc-domain:example.com"

  setup do
    Repo.delete_all(PropertyDailyMetric)
    Repo.delete_all("url_lifetime_stats")
    :ok
  end

  test "fetch/1 aggregates current, last month and all-time metrics" do
    today = Date.utc_today()
    current_month_start = Date.beginning_of_month(today)
    last_month_end = Date.add(current_month_start, -1)
    last_month_start = Date.beginning_of_month(last_month_end)

    insert_lifetime_stat(@account_id, "https://example.com/a", 1_000, 10_000, 3.5, 0.10,
      first_seen: Date.add(last_month_start, -30),
      last_seen: today,
      days_with_data: 200
    )

    insert_lifetime_stat(@account_id, "https://example.com/b", 500, 5_000, 4.2, 0.08,
      first_seen: Date.add(last_month_start, -60),
      last_seen: today,
      days_with_data: 150
    )

    insert_daily_metric(@account_id, current_month_start, %{
      clicks: 150,
      impressions: 1_400,
      position: 2.93,
      urls_count: 2
    })

    insert_daily_metric(@account_id, last_month_start, %{
      clicks: 120,
      impressions: 1_100,
      position: 3.41,
      urls_count: 2
    })

    # Second account noise should not affect results
    insert_daily_metric(2, current_month_start, %{
      clicks: 999,
      impressions: 9_999,
      position: 1.0,
      urls_count: 5,
      property_url: "sc-domain:othersite.com"
    })

    result =
      SummaryStats.fetch(%{
        account_id: @account_id,
        property_url: @property_url
      })

    assert result.current_month.total_clicks == 150
    assert result.current_month.total_impressions == 1_400
    assert_in_delta result.current_month.avg_position, 2.93, 0.01
    assert_in_delta result.current_month.avg_ctr, 10.71, 0.01

    assert result.last_month.total_clicks == 120
    assert result.last_month.total_impressions == 1_100
    assert_in_delta result.last_month.avg_position, 3.41, 0.01
    assert_in_delta result.last_month.avg_ctr, 10.91, 0.01
    assert result.last_month.period_label == Calendar.strftime(last_month_start, "%B %Y")

    assert result.all_time.total_clicks == 1_500
    assert result.all_time.total_impressions == 15_000
    assert_in_delta result.all_time.avg_position, 3.85, 0.01
    assert_in_delta result.all_time.avg_ctr, 9.0, 0.01
    assert result.all_time.earliest_date == Date.add(last_month_start, -60)
    assert result.all_time.latest_date == today

    assert result.month_over_month_change == 25.0
  end

  defp insert_daily_metric(account_id, date, attrs) do
    clicks = Map.fetch!(attrs, :clicks)
    impressions = Map.fetch!(attrs, :impressions)

    %PropertyDailyMetric{}
    |> PropertyDailyMetric.changeset(%{
      account_id: account_id,
      property_url: Map.get(attrs, :property_url, @property_url),
      date: date,
      clicks: clicks,
      impressions: impressions,
      ctr: ctr_from(clicks, impressions, Map.get(attrs, :ctr)),
      position: Map.get(attrs, :position, 0.0),
      urls_count: Map.get(attrs, :urls_count, 1),
      data_available: Map.get(attrs, :urls_count, 1) > 0
    })
    |> Repo.insert!()
  end

  defp ctr_from(_clicks, _impressions, ctr) when is_number(ctr) and ctr <= 1.0, do: ctr

  defp ctr_from(_clicks, impressions, _ctr) when impressions in [0, nil], do: 0.0

  defp ctr_from(clicks, impressions, _ctr), do: clicks / impressions

  defp insert_lifetime_stat(account_id, url, clicks, impressions, avg_position, avg_ctr, opts) do
    Repo.insert_all("url_lifetime_stats", [
      %{
        account_id: account_id,
        property_url: @property_url,
        url: url,
        lifetime_clicks: clicks,
        lifetime_impressions: impressions,
        avg_position: avg_position,
        avg_ctr: avg_ctr,
        first_seen_date: Keyword.fetch!(opts, :first_seen),
        last_seen_date: Keyword.fetch!(opts, :last_seen),
        days_with_data: Keyword.fetch!(opts, :days_with_data),
        refreshed_at: DateTime.utc_now()
      }
    ])
  end
end
