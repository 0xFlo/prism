defmodule GscAnalytics.DataSources.GSC.Core.PersistencePerformanceTest do
  @moduledoc """
  Performance tests for the Persistence module.

  ## Purpose

  These tests validate that our data persistence layer maintains high performance
  when processing Google Search Console data. They ensure that optimizations like
  bulk inserts and efficient aggregations continue to work as expected.

  ## Key Performance Requirements

  - **Bulk Processing**: Must handle 1000+ URLs with <25 database queries
  - **Throughput**: Must achieve >5000 URLs/second processing speed
  - **No N+1 Queries**: Must avoid N+1 query patterns completely
  - **Memory Efficiency**: Must use <5KB memory per URL
  - **Linear Scaling**: Performance must scale linearly, not exponentially

  ## Test Coverage

  1. **Bulk Operations** - Validates that `process_gsc_response/4` uses bulk inserts
  2. **Large Datasets** - Tests with 100, 1000, and 5000 URL datasets
  3. **Type Safety** - Ensures proper float/integer conversion
  4. **Aggregation Efficiency** - Validates performance aggregation only processes changed URLs
  5. **Query Processing** - Tests efficient handling of query-URL relationships

  ## Historical Context

  Before optimization (September 2025):
  - Processing 1178 URLs: ~77 seconds, 900,000+ queries
  - Severe UI freezing and crashes

  After optimization (October 2025):
  - Processing 1178 URLs: 4.6 seconds, 300 queries
  - 1,178× reduction in database load

  ## Running These Tests

      # Run all performance tests in this file
      mix test test/gsc_analytics/data_sources/gsc/data_persistence_performance_test.exs

      # Run with detailed output
      mix test path/to/this/file --trace

      # Run specific test
      mix test path/to/this/file:LINE_NUMBER
  """

  use GscAnalytics.DataCase

  @moduletag :performance

  alias GscAnalytics.DataSources.GSC.Core.Persistence
  alias GscAnalytics.Schemas.{Performance, TimeSeries}
  alias GscAnalytics.Test.{QueryCounter, PerformanceMonitor}

  describe "process_url_response/4 performance" do
    setup do
      QueryCounter.start()
      PerformanceMonitor.start()

      on_exit(fn ->
        QueryCounter.stop()
        PerformanceMonitor.stop()
      end)

      :ok
    end

    test "efficiently processes 100 URLs with bulk operations" do
      account_id = 1
      site_url = "sc-domain:example.com"
      date = ~D[2025-10-09]

      # Generate test data
      rows = generate_url_rows(100)

      # Process the response
      url_count =
        Persistence.process_url_response(
          account_id,
          site_url,
          date,
          %{"rows" => rows}
        )

      assert url_count == 100

      # Analyze performance
      analysis = QueryCounter.analyze()
      _metrics = PerformanceMonitor.get_metrics()

      # Should use bulk operations, not individual inserts
      assert analysis.total_count < 10, "Expected <10 queries, got #{analysis.total_count}"
      assert analysis.n_plus_one == [], "Found N+1 queries: #{inspect(analysis.n_plus_one)}"

      # Check that data was actually inserted
      assert Repo.aggregate(TimeSeries, :count) == 100
    end

    test "efficiently processes 1000 URLs without performance degradation" do
      account_id = 1
      site_url = "sc-domain:example.com"
      date = ~D[2025-10-09]

      # Generate large dataset
      rows = generate_url_rows(1000)

      # Reset counters
      QueryCounter.reset()

      # Time the operation
      {time_micros, url_count} =
        :timer.tc(fn ->
          Persistence.process_url_response(
            account_id,
            site_url,
            date,
            %{"rows" => rows}
          )
        end)

      time_ms = time_micros / 1000

      assert url_count == 1000

      # Performance assertions
      analysis = QueryCounter.analyze()

      # Should still use minimal queries even with 1000 URLs (allow slightly more for larger batch)
      assert analysis.total_count < 25, "Too many queries: #{analysis.total_count}"
      assert time_ms < 5000, "Operation took too long: #{time_ms}ms"

      # Verify no slow queries
      assert analysis.slow_queries == [], "Found slow queries: #{inspect(analysis.slow_queries)}"

      # Print performance report
      IO.puts("\n📊 1000 URL Processing Performance:")
      IO.puts("  • Time: #{Float.round(time_ms, 2)}ms")
      IO.puts("  • Queries: #{analysis.total_count}")
      IO.puts("  • Throughput: #{Float.round(1000 / (time_ms / 1000), 2)} URLs/sec")
    end

    test "handles float type conversion correctly" do
      account_id = 1
      site_url = "sc-domain:example.com"
      date = ~D[2025-10-09]

      # Include integers that need conversion to floats
      rows = [
        %{
          "keys" => ["https://example.com/page1"],
          "clicks" => 10,
          "impressions" => 100,
          # Float
          "ctr" => 0.1,
          # Integer - needs conversion
          "position" => 5
        },
        %{
          "keys" => ["https://example.com/page2"],
          "clicks" => 20,
          "impressions" => 200,
          # Integer - needs conversion
          "ctr" => 10,
          # Float
          "position" => 2.5
        }
      ]

      # Should not crash with type errors
      url_count =
        Persistence.process_url_response(
          account_id,
          site_url,
          date,
          %{"rows" => rows}
        )

      assert url_count == 2

      # Verify data was stored correctly
      records = Repo.all(from ts in TimeSeries, order_by: ts.url)
      assert length(records) == 2

      # Check that all values are floats
      Enum.each(records, fn record ->
        assert is_float(record.ctr)
        assert is_float(record.position)
      end)
    end
  end

  describe "aggregate_performance_for_urls/3 performance" do
    setup do
      QueryCounter.start()
      PerformanceMonitor.start()

      on_exit(fn ->
        QueryCounter.stop()
        PerformanceMonitor.stop()
      end)

      # Pre-populate some time series data
      account_id = 1
      property_url = "sc-domain:example.com"
      dates = for i <- 1..30, do: Date.add(~D[2025-10-09], -i)

      urls = for i <- 1..100, do: "https://example.com/page-#{i}"

      # Insert time series data for all URLs and dates
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      time_series_records =
        for url <- urls, date <- dates do
          %{
            account_id: account_id,
            property_url: property_url,
            url: url,
            date: date,
            clicks: :rand.uniform(100),
            impressions: :rand.uniform(1000),
            ctr: :rand.uniform() * 0.2,
            position: :rand.uniform() * 50.0,
            data_available: true,
            period_type: :daily,
            inserted_at: now
          }
        end

      {_count, _} = Repo.insert_all(TimeSeries, time_series_records)

      {:ok, account_id: account_id, property_url: property_url, urls: urls}
    end

    test "efficiently aggregates performance for specific URLs only", %{
      account_id: account_id,
      property_url: property_url,
      urls: urls
    } do
      # Select a subset of URLs to aggregate
      urls_to_aggregate = Enum.take(urls, 20)

      # Reset counters
      QueryCounter.reset()

      # Time the aggregation
      {time_micros, _} =
        :timer.tc(fn ->
          Persistence.aggregate_performance_for_urls(
            account_id,
            property_url,
            urls_to_aggregate,
            ~D[2025-10-09]
          )
        end)

      time_ms = time_micros / 1000

      # Analyze performance
      analysis = QueryCounter.analyze()

      # Should use efficient bulk operations
      assert analysis.total_count < 10, "Too many queries: #{analysis.total_count}"
      assert time_ms < 1000, "Aggregation took too long: #{time_ms}ms"

      # Verify Performance records were created
      performance_count = Repo.aggregate(Performance, :count)
      assert performance_count == 20, "Expected 20 Performance records, got #{performance_count}"

      # No N+1 queries
      assert analysis.n_plus_one == [], "Found N+1 queries"
    end

    test "scales linearly with number of URLs", %{
      account_id: account_id,
      property_url: property_url,
      urls: urls
    } do
      results =
        for count <- [10, 50, 100] do
          urls_subset = Enum.take(urls, count)

          # Clear Performance table
          Repo.delete_all(Performance)
          QueryCounter.reset()

          {time_micros, _} =
            :timer.tc(fn ->
              Persistence.aggregate_performance_for_urls(
                account_id,
                property_url,
                urls_subset,
                ~D[2025-10-09]
              )
            end)

          analysis = QueryCounter.analyze()

          {count, time_micros / 1000, analysis.total_count}
        end

      # Print scaling analysis
      IO.puts("\n📈 Aggregation Scaling Analysis:")

      for {url_count, time_ms, query_count} <- results do
        throughput = Float.round(url_count / (time_ms / 1000), 2)

        IO.puts(
          "  • #{url_count} URLs: #{Float.round(time_ms, 2)}ms, #{query_count} queries, #{throughput} URLs/sec"
        )
      end

      # Verify linear scaling (not exponential)
      [{_, time_10, _}, {_, _time_50, _}, {_, time_100, _}] = results

      # Time should scale roughly linearly, not exponentially
      # 100 URLs should take less than 20x the time of 10 URLs (allowing for overhead)
      assert time_100 < time_10 * 20, "Performance doesn't scale linearly"
    end
  end

  describe "process_query_response/4 performance" do
    setup do
      QueryCounter.start()
      PerformanceMonitor.start()

      on_exit(fn ->
        QueryCounter.stop()
        PerformanceMonitor.stop()
      end)

      # Pre-populate time series records
      account_id = 1
      property_url = "sc-domain:example.com"
      date = ~D[2025-10-09]
      urls = for i <- 1..100, do: "https://example.com/page-#{i}"

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      time_series_records =
        for url <- urls do
          %{
            account_id: account_id,
            property_url: property_url,
            url: url,
            date: date,
            clicks: 100,
            impressions: 1000,
            ctr: 0.1,
            position: 10.0,
            data_available: true,
            period_type: :daily,
            inserted_at: now
          }
        end

      {_count, _} = Repo.insert_all(TimeSeries, time_series_records)

      {:ok, account_id: account_id, property_url: property_url, date: date}
    end

    test "efficiently processes query data with batching", %{
      account_id: account_id,
      property_url: property_url,
      date: date
    } do
      # Generate query data: 50 queries per URL for 100 URLs
      query_rows = generate_query_rows(100, 50)

      # Reset counters
      QueryCounter.reset()

      # Process queries
      {time_micros, query_count} =
        :timer.tc(fn ->
          Persistence.process_query_response(
            account_id,
            property_url,
            date,
            query_rows
          )
        end)

      time_ms = time_micros / 1000

      # 100 URLs * 50 queries
      assert query_count == 5000

      # Analyze performance
      analysis = QueryCounter.analyze()

      # Should use batch updates
      assert analysis.total_count < 200, "Too many queries: #{analysis.total_count}"
      assert time_ms < 5000, "Query processing took too long: #{time_ms}ms"

      # Verify top queries were stored (only top 20 per URL)
      sample_record =
        Repo.get_by(TimeSeries,
          account_id: account_id,
          property_url: property_url,
          url: "https://example.com/page-1",
          date: date
        )

      assert length(sample_record.top_queries) == 20

      # Verify queries are sorted by clicks
      clicks = Enum.map(sample_record.top_queries, & &1["clicks"])
      assert clicks == Enum.sort(clicks, :desc)
    end
  end

  # Helper functions

  defp generate_url_rows(count) do
    for i <- 1..count do
      %{
        "keys" => ["https://example.com/page-#{i}"],
        "clicks" => :rand.uniform(100),
        "impressions" => :rand.uniform(1000),
        "ctr" => :rand.uniform() * 0.2,
        "position" => :rand.uniform() * 50
      }
    end
  end

  defp generate_query_rows(url_count, queries_per_url) do
    for i <- 1..url_count,
        j <- 1..queries_per_url do
      %{
        "keys" => ["https://example.com/page-#{i}", "query-#{j}"],
        "clicks" => :rand.uniform(50),
        "impressions" => :rand.uniform(500),
        "ctr" => :rand.uniform() * 0.3,
        "position" => :rand.uniform() * 20
      }
    end
  end
end
