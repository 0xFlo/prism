defmodule GscAnalytics.Analytics.TimeSeriesAggregatorWoWTest do
  use GscAnalytics.DataCase

  alias GscAnalytics.Analytics.TimeSeriesAggregator
  alias GscAnalytics.Schemas.TimeSeries

  @property_url "sc-domain:example.com"

  describe "batch_calculate_wow_growth/2 with window functions" do
    setup do
      account_id = 1
      url = "https://example.com/test"

      # Insert 4 weeks of data
      weeks_data = [
        # Week 1 (baseline) - Jan 6-7 (Monday-Tuesday)
        %{date: ~D[2025-01-06], clicks: 100, impressions: 1000},
        %{date: ~D[2025-01-07], clicks: 110, impressions: 1100},
        # Week 2 (10% growth) - Jan 13-14
        %{date: ~D[2025-01-13], clicks: 110, impressions: 1100},
        %{date: ~D[2025-01-14], clicks: 121, impressions: 1210},
        # Week 3 (20% growth from week 2) - Jan 20-21
        %{date: ~D[2025-01-20], clicks: 132, impressions: 1320},
        %{date: ~D[2025-01-21], clicks: 145, impressions: 1452},
        # Week 4 (negative growth) - Jan 27-28
        %{date: ~D[2025-01-27], clicks: 100, impressions: 1000},
        %{date: ~D[2025-01-28], clicks: 110, impressions: 1100}
      ]

      Enum.each(weeks_data, fn data ->
        %TimeSeries{}
        |> TimeSeries.changeset(
          Map.merge(data, %{
            url: url,
            account_id: account_id,
            property_url: @property_url,
            ctr: data.clicks / data.impressions,
            position: 5.0
          })
        )
        |> Repo.insert!()
      end)

      %{account_id: account_id, url: url}
    end

    test "calculates WoW growth correctly", %{url: url, account_id: account_id} do
      results =
        TimeSeriesAggregator.batch_calculate_wow_growth(
          [url],
          %{
            start_date: ~D[2025-01-01],
            account_id: account_id,
            property_url: @property_url,
            weeks_back: 1
          }
        )

      # Should return 4 weeks of data
      assert length(results) == 4

      # Week 1 has no previous data (NULL growth)
      week1 = Enum.find(results, &(&1.week_start == ~D[2025-01-06]))
      assert week1.clicks == 210
      assert week1.impressions == 2100
      assert is_nil(week1.prev_clicks)
      assert is_nil(week1.wow_growth_pct)

      # Week 2: (231 - 210) / 210 * 100 = 10%
      week2 = Enum.find(results, &(&1.week_start == ~D[2025-01-13]))
      assert week2.clicks == 231
      assert week2.prev_clicks == 210
      assert_in_delta week2.wow_growth_pct, 10.0, 0.5

      # Week 3: (277 - 231) / 231 * 100 ≈ 19.9%
      week3 = Enum.find(results, &(&1.week_start == ~D[2025-01-20]))
      assert week3.clicks == 277
      assert week3.prev_clicks == 231
      assert_in_delta week3.wow_growth_pct, 19.9, 0.5

      # Week 4: Negative growth
      week4 = Enum.find(results, &(&1.week_start == ~D[2025-01-27]))
      assert week4.clicks == 210
      assert week4.prev_clicks == 277
      assert week4.wow_growth_pct < 0
      assert_in_delta week4.wow_growth_pct, -24.2, 0.5
    end

    test "handles multiple URLs independently", %{account_id: account_id, url: url} do
      url2 = "https://example.com/other"

      # Add data for second URL with different growth pattern
      # Week 1: 200 clicks
      # Week 2: 250 clicks (25% growth)
      weeks_data_url2 = [
        %{date: ~D[2025-01-06], clicks: 200, impressions: 2000},
        %{date: ~D[2025-01-13], clicks: 250, impressions: 2500}
      ]

      Enum.each(weeks_data_url2, fn data ->
        %TimeSeries{}
        |> TimeSeries.changeset(
          Map.merge(data, %{
            url: url2,
            account_id: account_id,
            property_url: @property_url,
            ctr: data.clicks / data.impressions,
            position: 3.0
          })
        )
        |> Repo.insert!()
      end)

      results =
        TimeSeriesAggregator.batch_calculate_wow_growth(
          [url, url2],
          %{start_date: ~D[2025-01-01], account_id: account_id, property_url: @property_url}
        )

      # Growth should be calculated independently per URL
      url1_results = Enum.filter(results, &(&1.url == url))
      url2_results = Enum.filter(results, &(&1.url == url2))

      assert length(url1_results) == 4
      assert length(url2_results) == 2

      # Check URL2 week 2 growth: (250 - 200) / 200 * 100 = 25%
      url2_week2 = Enum.find(url2_results, &(&1.week_start == ~D[2025-01-13]))
      assert url2_week2.clicks == 250
      assert url2_week2.prev_clicks == 200
      assert_in_delta url2_week2.wow_growth_pct, 25.0, 0.5
    end

    test "supports custom weeks_back parameter", %{url: url, account_id: account_id} do
      # Compare to 2 weeks back instead of 1 week
      results =
        TimeSeriesAggregator.batch_calculate_wow_growth(
          [url],
          %{
            start_date: ~D[2025-01-01],
            account_id: account_id,
            property_url: @property_url,
            weeks_back: 2
          }
        )

      # Week 3 should compare to Week 1, not Week 2
      week3 = Enum.find(results, &(&1.week_start == ~D[2025-01-20]))
      assert week3.clicks == 277
      assert week3.prev_clicks == 210
      # (277 - 210) / 210 * 100 ≈ 31.9%
      assert_in_delta week3.wow_growth_pct, 31.9, 0.5
    end

    test "handles division by zero (previous week has 0 clicks)", %{account_id: account_id} do
      url_zero = "https://example.com/zero-clicks"

      # Week 1: 0 clicks
      # Week 2: 100 clicks
      zero_data = [
        %{date: ~D[2025-01-06], clicks: 0, impressions: 1000},
        %{date: ~D[2025-01-13], clicks: 100, impressions: 1000}
      ]

      Enum.each(zero_data, fn data ->
        %TimeSeries{}
        |> TimeSeries.changeset(
          Map.merge(data, %{
            url: url_zero,
            account_id: account_id,
            property_url: @property_url,
            ctr: 0.0,
            position: 5.0
          })
        )
        |> Repo.insert!()
      end)

      results =
        TimeSeriesAggregator.batch_calculate_wow_growth(
          [url_zero],
          %{start_date: ~D[2025-01-01], account_id: account_id, property_url: @property_url}
        )

      # Week 2 growth should be NULL (can't divide by 0)
      week2 = Enum.find(results, &(&1.week_start == ~D[2025-01-13]))
      assert week2.clicks == 100
      assert week2.prev_clicks == 0
      assert is_nil(week2.wow_growth_pct)
    end

    test "calculates impressions growth separately from clicks growth", %{
      url: url,
      account_id: account_id
    } do
      results =
        TimeSeriesAggregator.batch_calculate_wow_growth(
          [url],
          %{start_date: ~D[2025-01-01], account_id: account_id, property_url: @property_url}
        )

      # Week 2 should have both clicks and impressions growth
      week2 = Enum.find(results, &(&1.week_start == ~D[2025-01-13]))
      assert week2.impressions == 2310
      assert week2.prev_impressions == 2100

      # Both should be ~10% growth
      assert_in_delta week2.wow_growth_pct, 10.0, 0.5
      assert_in_delta week2.wow_growth_impressions_pct, 10.0, 0.5
    end

    test "returns results ordered by URL and week_start", %{url: url, account_id: account_id} do
      url2 = "https://example.com/alpha"

      # Add one week for url2
      %TimeSeries{}
      |> TimeSeries.changeset(%{
        url: url2,
        account_id: account_id,
        property_url: @property_url,
        date: ~D[2025-01-06],
        clicks: 50,
        impressions: 500,
        ctr: 0.1,
        position: 2.0
      })
      |> Repo.insert!()

      results =
        TimeSeriesAggregator.batch_calculate_wow_growth(
          [url, url2],
          %{start_date: ~D[2025-01-01], account_id: account_id, property_url: @property_url}
        )

      # Results should be ordered: first by URL, then by week_start
      result_urls = Enum.map(results, & &1.url)

      # url2 should come before url (alphabetically: "alpha" < "test")
      assert Enum.take(result_urls, 1) == [url2]
      # Remaining results should be for url
      assert Enum.drop(result_urls, 1) == List.duplicate(url, 4)

      # Within each URL, weeks should be in ascending order
      url_weeks = results |> Enum.filter(&(&1.url == url)) |> Enum.map(& &1.week_start)

      assert url_weeks == [
               ~D[2025-01-06],
               ~D[2025-01-13],
               ~D[2025-01-20],
               ~D[2025-01-27]
             ]
    end

    test "includes weighted average position", %{url: url, account_id: account_id} do
      results =
        TimeSeriesAggregator.batch_calculate_wow_growth(
          [url],
          %{start_date: ~D[2025-01-01], account_id: account_id, property_url: @property_url}
        )

      week1 = Enum.find(results, &(&1.week_start == ~D[2025-01-06]))
      # Position should be weighted average (all days have position 5.0)
      assert_in_delta week1.position, 5.0, 0.01
    end

    test "ignores metrics from other properties when property_url is provided", %{
      url: url,
      account_id: account_id
    } do
      other_property = "https://other.example.com/"

      Enum.each(
        [
          %{date: ~D[2025-01-06], clicks: 500, impressions: 5000},
          %{date: ~D[2025-01-07], clicks: 500, impressions: 5000}
        ],
        fn data ->
          %TimeSeries{}
          |> TimeSeries.changeset(
            Map.merge(data, %{
              url: url,
              account_id: account_id,
              property_url: other_property,
              ctr: data.clicks / data.impressions,
              position: 1.0
            })
          )
          |> Repo.insert!()
        end
      )

      results =
        TimeSeriesAggregator.batch_calculate_wow_growth(
          [url],
          %{start_date: ~D[2025-01-01], account_id: account_id, property_url: @property_url}
        )

      week1 = Enum.find(results, &(&1.week_start == ~D[2025-01-06]))
      # Should only include clicks from the InsightTimer property, not the extra dataset
      assert week1.clicks == 210
    end
  end

  describe "batch_calculate_wow_growth_legacy/3" do
    setup do
      account_id = 1
      url = "https://example.com/legacy-test"

      # Insert 8 weeks of data for legacy test
      # Legacy function compares last 4 weeks vs previous 4 weeks
      weeks_data =
        for week_offset <- 0..7 do
          start_date = Date.add(~D[2025-01-06], week_offset * 7)

          [
            %{date: start_date, clicks: 100 + week_offset * 10, impressions: 1000},
            %{date: Date.add(start_date, 1), clicks: 100 + week_offset * 10, impressions: 1000}
          ]
        end
        |> List.flatten()

      Enum.each(weeks_data, fn data ->
        %TimeSeries{}
        |> TimeSeries.changeset(
          Map.merge(data, %{
            url: url,
            account_id: account_id,
            property_url: @property_url,
            ctr: data.clicks / data.impressions,
            position: 5.0
          })
        )
        |> Repo.insert!()
      end)

      %{account_id: account_id, url: url}
    end

    test "legacy function still works with old signature", %{url: url, account_id: account_id} do
      # Old signature: batch_calculate_wow_growth(urls, recent_weeks, opts)
      result =
        TimeSeriesAggregator.batch_calculate_wow_growth_legacy(
          [url],
          4,
          %{account_id: account_id, property_url: @property_url}
        )

      # Should return a map of %{url => growth_pct}
      assert is_map(result)
      assert Map.has_key?(result, url)
      assert is_float(result[url]) or is_integer(result[url])
    end

    test "legacy function calculates aggregated growth across 4 weeks", %{
      url: url,
      account_id: account_id
    } do
      result =
        TimeSeriesAggregator.batch_calculate_wow_growth_legacy(
          [url],
          4,
          %{account_id: account_id, property_url: @property_url}
        )

      # Legacy function aggregates 4 recent weeks vs 4 previous weeks
      # With increasing clicks (100, 110, 120, 130... per day over weeks 0-7),
      # recent weeks should have more clicks than previous weeks
      # The legacy function should show growth (or 0.0 if not enough data)
      assert result[url] >= 0
    end
  end
end
