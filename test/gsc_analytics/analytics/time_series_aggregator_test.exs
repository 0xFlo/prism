defmodule GscAnalytics.Analytics.TimeSeriesAggregatorTest do
  @moduledoc """
  Algorithm tests for TimeSeriesAggregator.

  Tests the mathematical calculations and aggregation logic:
  - Week-over-week (WoW) growth calculations
  - Weekly/monthly aggregation algorithms
  - CTR and position averaging
  - Date bucketing logic (week start, month start)

  Following testing guidelines:
  - Test behavior (calculations), not implementation
  - Assert on observable outcomes (aggregated numbers)
  - Tests survive refactoring
  """

  use GscAnalytics.DataCase, async: true

  @moduletag :algorithm

  alias GscAnalytics.Analytics.TimeSeriesAggregator
  alias GscAnalytics.Schemas.TimeSeries
  alias GscAnalytics.Repo

  @account_id 1
  @test_property_url "sc-domain:example.com"

  describe "week-over-week growth calculation" do
    test "calculates positive growth correctly" do
      # Business requirement: "System calculates WoW growth for trending analysis"

      url = "https://example.com/growing"

      # Previous 4 weeks: 400 total clicks (100 per week)
      # Recent 4 weeks: 600 total clicks (150 per week)
      # Expected growth: (600-400)/400 * 100 = 50%

      # Use actual Mondays: Oct 6, 13, 20, 27, Nov 3, 10, 17, 24
      populate_weekly_data(url, [
        # Previous 4 weeks
        {~D[2025-10-06], 100},
        {~D[2025-10-13], 100},
        {~D[2025-10-20], 100},
        {~D[2025-10-27], 100},
        # Recent 4 weeks
        {~D[2025-11-03], 150},
        {~D[2025-11-10], 150},
        {~D[2025-11-17], 150},
        {~D[2025-11-24], 150}
      ])

      growth =
        TimeSeriesAggregator.calculate_wow_growth(url, 4, %{
          account_id: @account_id,
          property_url: @test_property_url
        })

      # (600 - 400) / 400 * 100 = 50%
      assert growth == 50.0
    end

    test "calculates negative growth correctly" do
      # Business requirement: "System detects declining pages"

      url = "https://example.com/declining"

      # Previous 4 weeks: 800 total clicks (200 per week)
      # Recent 4 weeks: 400 total clicks (100 per week)
      # Expected growth: (400-800)/800 * 100 = -50%

      populate_weekly_data(url, [
        {~D[2025-10-06], 200},
        {~D[2025-10-13], 200},
        {~D[2025-10-20], 200},
        {~D[2025-10-27], 200},
        {~D[2025-11-03], 100},
        {~D[2025-11-10], 100},
        {~D[2025-11-17], 100},
        {~D[2025-11-24], 100}
      ])

      growth =
        TimeSeriesAggregator.calculate_wow_growth(url, 4, %{
          account_id: @account_id,
          property_url: @test_property_url
        })

      # (400 - 800) / 800 * 100 = -50%
      assert growth == -50.0
    end

    test "returns 0 when no previous data exists" do
      # Business requirement: "Handle new pages with no historical data"

      url = "https://example.com/new-page"

      # Only recent weeks, no previous weeks
      populate_weekly_data(url, [
        {~D[2025-11-17], 100},
        {~D[2025-11-24], 100}
      ])

      growth =
        TimeSeriesAggregator.calculate_wow_growth(url, 4, %{
          account_id: @account_id,
          property_url: @test_property_url
        })

      assert growth == 0.0
    end

    test "returns 0 when previous period has 0 clicks" do
      # Business requirement: "Handle division by zero gracefully"

      url = "https://example.com/zero-previous"

      populate_weekly_data(url, [
        # Previous weeks: 0 clicks
        {~D[2025-10-06], 0},
        {~D[2025-10-13], 0},
        {~D[2025-10-20], 0},
        {~D[2025-10-27], 0},
        # Recent weeks: 100 clicks each
        {~D[2025-11-03], 100},
        {~D[2025-11-10], 100},
        {~D[2025-11-17], 100},
        {~D[2025-11-24], 100}
      ])

      growth =
        TimeSeriesAggregator.calculate_wow_growth(url, 4, %{
          account_id: @account_id,
          property_url: @test_property_url
        })

      assert growth == 0.0
    end

    test "calculates growth with different week counts" do
      # Business requirement: "Support configurable comparison periods"

      url = "https://example.com/custom-weeks"

      # 2 previous weeks: 100 clicks/week = 200 total
      # 2 recent weeks: 150 clicks/week = 300 total
      # Expected: 50% growth

      populate_weekly_data(url, [
        {~D[2025-11-10], 100},
        {~D[2025-11-17], 100},
        {~D[2025-11-24], 150},
        {~D[2025-12-01], 150}
      ])

      growth =
        TimeSeriesAggregator.calculate_wow_growth(url, 2, %{
          account_id: @account_id,
          property_url: @test_property_url
        })

      assert growth == 50.0
    end
  end

  describe "batch WoW growth calculation" do
    test "calculates growth for multiple URLs in single query" do
      # Business requirement: "Efficiently calculate growth for dashboard"

      url1 = "https://example.com/page1"
      url2 = "https://example.com/page2"
      url3 = "https://example.com/page3"

      # Page 1: 50% growth (400 -> 600)
      populate_weekly_data(url1, [
        {~D[2025-10-06], 100},
        {~D[2025-10-13], 100},
        {~D[2025-10-20], 100},
        {~D[2025-10-27], 100},
        {~D[2025-11-03], 150},
        {~D[2025-11-10], 150},
        {~D[2025-11-17], 150},
        {~D[2025-11-24], 150}
      ])

      # Page 2: -25% growth (800 -> 600)
      populate_weekly_data(url2, [
        {~D[2025-10-06], 200},
        {~D[2025-10-13], 200},
        {~D[2025-10-20], 200},
        {~D[2025-10-27], 200},
        {~D[2025-11-03], 150},
        {~D[2025-11-10], 150},
        {~D[2025-11-17], 150},
        {~D[2025-11-24], 150}
      ])

      # Page 3: No data (should return 0)

      # Using legacy function for backward compatibility
      results =
        TimeSeriesAggregator.batch_calculate_wow_growth_legacy([url1, url2, url3], 4, %{
          account_id: @account_id
        })

      assert results[url1] == 50.0
      assert results[url2] == -25.0
      assert results[url3] == 0.0
    end
  end

  describe "weekly aggregation algorithm" do
    test "groups daily data into weekly buckets correctly" do
      # Business requirement: "Display weekly trends in charts"

      url = "https://example.com/weekly-test"

      # Week of Nov 10-16, 2025 (Monday to Sunday)
      # Total clicks: 7 * 10 = 70
      populate_daily_data(url, [
        {~D[2025-11-10], 10},
        # Mon
        {~D[2025-11-11], 10},
        # Tue
        {~D[2025-11-12], 10},
        # Wed
        {~D[2025-11-13], 10},
        # Thu
        {~D[2025-11-14], 10},
        # Fri
        {~D[2025-11-15], 10},
        # Sat
        {~D[2025-11-16], 10}
        # Sun
      ])

      weekly =
        TimeSeriesAggregator.aggregate_by_week(url, 2, %{
          account_id: @account_id,
          property_url: @test_property_url
        })

      assert length(weekly) == 1
      [week] = weekly

      # Week start should be Monday
      assert week.date == ~D[2025-11-10]
      # Week end should be Sunday
      assert week.period_end == ~D[2025-11-16]
      assert week.clicks == 70
      assert week.impressions == 700
    end

    test "handles partial weeks correctly" do
      # Business requirement: "Handle incomplete weeks (e.g., current week)"

      url = "https://example.com/partial-week"

      # Only Monday-Wednesday of week
      populate_daily_data(url, [
        {~D[2025-11-10], 10},
        {~D[2025-11-11], 10},
        {~D[2025-11-12], 10}
      ])

      weekly =
        TimeSeriesAggregator.aggregate_by_week(url, 2, %{
          account_id: @account_id,
          property_url: @test_property_url
        })

      [week] = weekly

      # Should still show week start/end even if partial
      assert week.date == ~D[2025-11-10]
      assert week.period_end == ~D[2025-11-16]
      assert week.clicks == 30
    end

    test "calculates average CTR for week correctly" do
      # Business requirement: "CTR reflects weekly average, not daily sum"

      url = "https://example.com/ctr-test"

      # Day 1: 10 clicks, 100 impressions = 10% CTR
      # Day 2: 20 clicks, 100 impressions = 20% CTR
      # Weekly: 30 clicks, 200 impressions = 15% CTR (weighted average)

      populate_daily_data(url, [
        {~D[2025-11-10], 10, 100},
        {~D[2025-11-11], 20, 100}
      ])

      weekly =
        TimeSeriesAggregator.aggregate_by_week(url, 2, %{
          account_id: @account_id,
          property_url: @test_property_url
        })

      [week] = weekly

      assert week.clicks == 30
      assert week.impressions == 200
      # CTR should be clicks/impressions = 30/200 = 0.15
      assert week.ctr == 0.15
    end

    test "calculates average position for week correctly" do
      # Business requirement: "Position shows average rank across week"

      url = "https://example.com/position-test"

      # 3 days with positions: 5.0, 10.0, 15.0
      # Average: 10.0

      populate_daily_data_with_position(url, [
        {~D[2025-11-10], 10, 100, 5.0},
        {~D[2025-11-11], 10, 100, 10.0},
        {~D[2025-11-12], 10, 100, 15.0}
      ])

      weekly =
        TimeSeriesAggregator.aggregate_by_week(url, 2, %{
          account_id: @account_id,
          property_url: @test_property_url
        })

      [week] = weekly

      assert week.position == 10.0
    end

    test "excludes days with position 0 from average" do
      # Business requirement: "Ignore missing position data in averages"

      url = "https://example.com/zero-position"

      populate_daily_data_with_position(url, [
        {~D[2025-11-10], 10, 100, 5.0},
        {~D[2025-11-11], 10, 100, 0.0},
        # Should be excluded
        {~D[2025-11-12], 10, 100, 15.0}
      ])

      weekly =
        TimeSeriesAggregator.aggregate_by_week(url, 2, %{
          account_id: @account_id,
          property_url: @test_property_url
        })

      [week] = weekly

      # Average should be (5.0 + 15.0) / 2 = 10.0
      assert week.position == 10.0
    end
  end

  describe "monthly aggregation algorithm" do
    test "groups daily data into monthly buckets correctly" do
      # Business requirement: "Display monthly trends"

      url = "https://example.com/monthly-test"

      # November 2025: 30 days
      populate_daily_data(url, [
        {~D[2025-11-01], 10},
        {~D[2025-11-15], 10},
        {~D[2025-11-30], 10}
      ])

      monthly =
        TimeSeriesAggregator.aggregate_by_month(url, 2, %{
          account_id: @account_id,
          property_url: @test_property_url
        })

      [month] = monthly

      # Month start should be 1st
      assert month.date == ~D[2025-11-01]
      # Month end should be last day
      assert month.period_end == ~D[2025-11-30]
      assert month.clicks == 30
    end

    test "handles months with different day counts" do
      # Business requirement: "Correctly handle February, 31-day months, etc."

      url = "https://example.com/month-days"

      # February 2025 (28 days - not leap year)
      # March 2025 (31 days)
      populate_daily_data(url, [
        {~D[2025-02-01], 10},
        {~D[2025-02-28], 10},
        {~D[2025-03-01], 10},
        {~D[2025-03-31], 10}
      ])

      # Request 12 months to ensure Feb/Mar are included (today is Oct 2025)
      monthly =
        TimeSeriesAggregator.aggregate_by_month(url, 12, %{
          account_id: @account_id,
          property_url: @test_property_url
        })

      feb = Enum.find(monthly, &(&1.date == ~D[2025-02-01]))
      mar = Enum.find(monthly, &(&1.date == ~D[2025-03-01]))

      assert feb.period_end == ~D[2025-02-28]
      assert mar.period_end == ~D[2025-03-31]
    end

    test "calculates monthly CTR correctly" do
      # Business requirement: "Monthly CTR reflects entire month"

      url = "https://example.com/monthly-ctr"

      # 3 days in month:
      # Total: 60 clicks, 300 impressions = 20% CTR

      populate_daily_data(url, [
        {~D[2025-11-01], 10, 100},
        {~D[2025-11-15], 20, 100},
        {~D[2025-11-30], 30, 100}
      ])

      monthly =
        TimeSeriesAggregator.aggregate_by_month(url, 2, %{
          account_id: @account_id,
          property_url: @test_property_url
        })

      [month] = monthly

      assert month.ctr == 0.2
    end
  end

  describe "week start date algorithm (ISO 8601)" do
    test "Monday returns itself as week start" do
      # Business requirement: "ISO 8601 week starts on Monday"

      url = "https://example.com/monday"

      # Nov 10, 2025 is a Monday
      populate_daily_data(url, [{~D[2025-11-10], 10}])

      weekly =
        TimeSeriesAggregator.aggregate_by_week(url, 2, %{
          account_id: @account_id,
          property_url: @test_property_url
        })

      [week] = weekly

      assert week.date == ~D[2025-11-10]
    end

    test "Sunday maps to previous Monday" do
      # Business requirement: "Week boundary Sunday→Monday"

      url = "https://example.com/sunday"

      # Nov 16, 2025 is a Sunday (day 7 of week Nov 10-16)
      populate_daily_data(url, [{~D[2025-11-16], 10}])

      weekly =
        TimeSeriesAggregator.aggregate_by_week(url, 2, %{
          account_id: @account_id,
          property_url: @test_property_url
        })

      [week] = weekly

      # Should map to Monday Nov 10
      assert week.date == ~D[2025-11-10]
    end

    test "mid-week day maps to correct Monday" do
      # Business requirement: "All days in week map to same Monday"

      url = "https://example.com/wednesday"

      # Nov 12, 2025 is a Wednesday (day 3 of week Nov 10-16)
      populate_daily_data(url, [{~D[2025-11-12], 10}])

      weekly =
        TimeSeriesAggregator.aggregate_by_week(url, 2, %{
          account_id: @account_id,
          property_url: @test_property_url
        })

      [week] = weekly

      # Should map to Monday Nov 10
      assert week.date == ~D[2025-11-10]
    end
  end

  describe "URL group aggregation algorithms" do
    test "aggregates metrics across multiple URLs by day" do
      # Business requirement: "Show combined metrics for URL groups"

      url1 = "https://example.com/page1"
      url2 = "https://example.com/page2"

      populate_daily_data(url1, [{~D[2025-11-15], 100, 1000}])
      populate_daily_data(url2, [{~D[2025-11-15], 50, 500}])

      daily =
        TimeSeriesAggregator.aggregate_group_by_day([url1, url2], %{
          account_id: @account_id,
          start_date: ~D[2025-11-01]
        })

      [day] = daily

      assert day.date == ~D[2025-11-15]
      assert day.clicks == 150
      assert day.impressions == 1500
      assert day.ctr == 0.1
    end

    test "calculates weighted position for URL groups" do
      # Business requirement: "Position weighted by impressions"

      url1 = "https://example.com/page1"
      url2 = "https://example.com/page2"

      # URL1: 1000 impressions at position 5.0 = 5000 weighted
      # URL2: 500 impressions at position 10.0 = 5000 weighted
      # Total: 1500 impressions, 10000 weighted = 6.67 average

      populate_daily_data_with_position(url1, [{~D[2025-11-15], 100, 1000, 5.0}])
      populate_daily_data_with_position(url2, [{~D[2025-11-15], 50, 500, 10.0}])

      daily =
        TimeSeriesAggregator.aggregate_group_by_day([url1, url2], %{
          account_id: @account_id,
          start_date: ~D[2025-11-01]
        })

      [day] = daily

      # (5.0 * 1000 + 10.0 * 500) / 1500 = 10000 / 1500 = 6.67
      assert_in_delta day.position, 6.67, 0.01
    end

    test "aggregates URL group by week" do
      # Business requirement: "Show weekly trends for URL groups"

      url1 = "https://example.com/page1"
      url2 = "https://example.com/page2"

      # Same week (Nov 10-16) - Nov 10 is Monday
      populate_daily_data(url1, [
        {~D[2025-11-10], 10},
        {~D[2025-11-11], 10}
      ])

      populate_daily_data(url2, [
        {~D[2025-11-10], 20},
        {~D[2025-11-11], 20}
      ])

      weekly =
        TimeSeriesAggregator.aggregate_group_by_week([url1, url2], %{
          account_id: @account_id,
          start_date: ~D[2025-11-01]
        })

      [week] = weekly

      assert week.date == ~D[2025-11-10]
      # 10+10+20+20 = 60
      assert week.clicks == 60
    end

    test "handles empty URL list gracefully" do
      # Business requirement: "Don't crash on edge cases"

      daily =
        TimeSeriesAggregator.aggregate_group_by_day([], %{
          account_id: @account_id,
          start_date: ~D[2025-11-01]
        })

      assert daily == []
    end

    test "handles nil URLs in list" do
      # Business requirement: "Filter out invalid URLs"

      url = "https://example.com/valid"
      populate_daily_data(url, [{~D[2025-11-15], 10}])

      daily =
        TimeSeriesAggregator.aggregate_group_by_day([url, nil, nil], %{
          account_id: @account_id,
          start_date: ~D[2025-11-01]
        })

      [day] = daily

      assert day.clicks == 10
    end
  end

  describe "edge cases and error handling" do
    test "handles missing data gracefully" do
      # Business requirement: "Don't crash when URL has no data"

      url = "https://example.com/no-data"

      weekly =
        TimeSeriesAggregator.aggregate_by_week(url, 4, %{
          account_id: @account_id,
          property_url: @test_property_url
        })

      assert weekly == []
    end

    test "handles single day of data" do
      # Business requirement: "Works with minimal data"

      url = "https://example.com/single-day"
      populate_daily_data(url, [{~D[2025-11-15], 10}])

      weekly =
        TimeSeriesAggregator.aggregate_by_week(url, 2, %{
          account_id: @account_id,
          property_url: @test_property_url
        })

      assert length(weekly) == 1
    end

    test "handles 0 impressions without division error" do
      # Business requirement: "Safe CTR calculation"

      url = "https://example.com/zero-impressions"
      populate_daily_data(url, [{~D[2025-11-15], 10, 0}])

      weekly =
        TimeSeriesAggregator.aggregate_by_week(url, 2, %{
          account_id: @account_id,
          property_url: @test_property_url
        })

      [week] = weekly

      assert week.ctr == 0.0
    end

    test "rounds decimals consistently" do
      # Business requirement: "Consistent decimal precision"

      url = "https://example.com/decimals"

      # CTR = 33/100 = 0.33, but should round to 4 decimals
      populate_daily_data(url, [{~D[2025-11-15], 33, 100}])

      weekly =
        TimeSeriesAggregator.aggregate_by_week(url, 2, %{
          account_id: @account_id,
          property_url: @test_property_url
        })

      [week] = weekly

      assert week.ctr == 0.33
    end
  end

  # Helper functions

  defp populate_weekly_data(url, weeks) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    records =
      Enum.flat_map(weeks, fn {week_start, total_clicks} ->
        # Distribute clicks evenly across 7 days
        # Use floor division to avoid floating point issues
        clicks_per_day = div(total_clicks, 7)
        remainder = rem(total_clicks, 7)

        # Create 7 days worth of data for each week
        for day_offset <- 0..6 do
          date = Date.add(week_start, day_offset)
          # First `remainder` days get one extra click to distribute the remainder
          day_clicks = if day_offset < remainder, do: clicks_per_day + 1, else: clicks_per_day

          %{
            account_id: @account_id,
            property_url: @test_property_url,
            url: url,
            date: date,
            clicks: day_clicks,
            impressions: day_clicks * 10,
            ctr: 0.1,
            position: 10.0,
            data_available: true,
            period_type: :daily,
            inserted_at: now
          }
        end
      end)

    Repo.insert_all(TimeSeries, records)
  end

  defp populate_daily_data(url, days, default_impressions \\ nil) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    records =
      Enum.map(days, fn
        {date, clicks, impressions} ->
          %{
            account_id: @account_id,
            property_url: @test_property_url,
            url: url,
            date: date,
            clicks: clicks,
            impressions: impressions,
            ctr: if(impressions > 0, do: clicks / impressions, else: 0.0),
            position: 10.0,
            data_available: true,
            period_type: :daily,
            inserted_at: now
          }

        {date, clicks} ->
          impressions = default_impressions || clicks * 10

          %{
            account_id: @account_id,
            property_url: @test_property_url,
            url: url,
            date: date,
            clicks: clicks,
            impressions: impressions,
            ctr: if(impressions > 0, do: clicks / impressions, else: 0.0),
            position: 10.0,
            data_available: true,
            period_type: :daily,
            inserted_at: now
          }
      end)

    Repo.insert_all(TimeSeries, records)
  end

  defp populate_daily_data_with_position(url, days) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    records =
      Enum.map(days, fn {date, clicks, impressions, position} ->
        %{
          account_id: @account_id,
          property_url: @test_property_url,
          url: url,
          date: date,
          clicks: clicks,
          impressions: impressions,
          ctr: if(impressions > 0, do: clicks / impressions, else: 0.0),
          position: position,
          data_available: true,
          period_type: :daily,
          inserted_at: now
        }
      end)

    Repo.insert_all(TimeSeries, records)
  end
end
