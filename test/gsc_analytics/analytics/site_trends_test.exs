defmodule GscAnalytics.Analytics.SiteTrendsTest do
  use GscAnalytics.DataCase

  alias GscAnalytics.Analytics.SiteTrends
  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.PropertyDailyMetric

  @account_id 1
  @property_url "sc-domain:example.com"

  setup do
    Repo.delete_all(PropertyDailyMetric)
    :ok
  end

  test "fetch/2 returns daily trends with axis label" do
    today = Date.utc_today()

    Enum.each(0..4, fn offset ->
      insert_daily_metric(
        @account_id,
        Date.add(today, -offset),
        10 + offset,
        100 + offset * 5,
        3.0
      )
    end)

    # Noise from another account should be ignored
    insert_daily_metric(2, today, 99, 200, 1.5, "sc-domain:othersite.com")

    {series, label} =
      SiteTrends.fetch("daily", %{account_id: @account_id, property_url: @property_url})

    assert label == "Date"
    assert length(series) == 5
    assert Enum.at(series, -1).date == today
  end

  test "weekly trends normalise dates to Mondays" do
    today = Date.utc_today()

    Enum.each(0..20, fn offset ->
      insert_daily_metric(@account_id, Date.add(today, -offset), 5, 50, 4.0)
    end)

    {series, label} =
      SiteTrends.fetch("weekly", %{account_id: @account_id, property_url: @property_url})

    assert label == "Week Starting"
    assert Enum.all?(series, fn %{date: date} -> Date.day_of_week(date) == 1 end)

    assert Enum.all?(series, fn %{period_end: period_end} -> Date.day_of_week(period_end) == 7 end)
  end

  test "monthly trends return first-of-month dates" do
    today = Date.utc_today()
    current_month = Date.beginning_of_month(today)
    previous_month = Date.beginning_of_month(Date.add(current_month, -1))

    insert_daily_metric(@account_id, current_month, 30, 300, 2.5)
    insert_daily_metric(@account_id, previous_month, 25, 250, 3.0)

    {series, label} =
      SiteTrends.fetch("monthly", %{account_id: @account_id, property_url: @property_url})

    assert label == "Month"
    refute series == []
    assert Enum.all?(series, fn %{date: date} -> date.day == 1 end)
  end

  defp insert_daily_metric(
         account_id,
         date,
         clicks,
         impressions,
         position,
         property_url \\ @property_url
       ) do
    ctr = if impressions > 0, do: clicks / impressions, else: 0.0

    %PropertyDailyMetric{}
    |> PropertyDailyMetric.changeset(%{
      account_id: account_id,
      property_url: property_url,
      date: date,
      clicks: clicks,
      impressions: impressions,
      ctr: ctr,
      position: position,
      urls_count: 1,
      data_available: true
    })
    |> Repo.insert!()
  end
end
