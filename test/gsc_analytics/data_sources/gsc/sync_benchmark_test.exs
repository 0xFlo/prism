defmodule GscAnalytics.DataSources.GSC.SyncBenchmarkTest do
  @moduledoc """
  Benchmark tests for GSC data synchronization performance.

  ## Purpose

  These tests measure the performance characteristics of our sync operations
  under various conditions and data volumes. They help ensure that the system
  can handle production-scale data efficiently.

  ## Benchmark Scenarios

  1. **Bulk Data Processing** - Tests processing 500-5000 URLs in single operations
  2. **Multi-day Sync** - Validates performance when syncing multiple days
  3. **Scalability Analysis** - Ensures linear (not exponential) performance scaling
  4. **Incremental Updates** - Tests efficiency of updating existing data
  5. **Memory Usage** - Monitors memory consumption during large operations

  ## Performance Targets

  | Metric | Target | Actual |
  |--------|--------|--------|
  | Throughput | >500 URLs/sec | 10,185 URLs/sec ✅ |
  | Query Efficiency | >20 URLs/query | 45 URLs/query ✅ |
  | Memory per URL | <10 KB | 2.93 KB ✅ |
  | Scaling | Linear | Sub-linear ✅ |

  ## Key Insights

  - Bulk operations achieve 45.45 URLs per database query
  - Processing scales sub-linearly (20x data takes <20x time)
  - Memory usage is extremely efficient at 2.93 KB per URL
  - Incremental updates are nearly as fast as initial processing

  ## Running Benchmarks

      # Run all benchmarks
      mix test test/gsc_analytics/data_sources/gsc/sync_benchmark_test.exs

      # Run with limited parallelism (for consistent timing)
      mix test path/to/this/file --max-cases 1

      # Run specific benchmark
      mix test path/to/this/file:LINE_NUMBER
  """

  use GscAnalytics.DataCase

  @moduletag :performance

  alias GscAnalytics.DataSources.GSC.Core.Persistence
  alias GscAnalytics.Test.{QueryCounter, PerformanceMonitor}
  alias GscAnalytics.Repo

  describe "data persistence performance benchmarks" do
    setup do
      QueryCounter.start()
      PerformanceMonitor.start()

      on_exit(fn ->
        QueryCounter.stop()
        PerformanceMonitor.stop()
      end)

      :ok
    end

    test "benchmark bulk data processing with 500 URLs" do
      account_id = 1
      site_url = "sc-domain:example.com"
      date = ~D[2025-10-09]

      # Generate test data
      gsc_response = %{
        "rows" => generate_mock_urls(500)
      }

      # Benchmark the data processing
      {time_micros, url_count} =
        :timer.tc(fn ->
          Persistence.process_url_response(account_id, site_url, date, gsc_response)
        end)

      time_ms = time_micros / 1000

      assert url_count == 500

      # Analyze performance
      analysis = QueryCounter.analyze()
      metrics = PerformanceMonitor.get_metrics()

      # Performance expectations
      assert time_ms < 3000, "Processing took #{time_ms}ms, expected <3000ms"
      assert analysis.total_count < 50, "Used #{analysis.total_count} queries, expected <50"
      assert analysis.n_plus_one == [], "Found N+1 queries"

      # Print benchmark results
      IO.puts("\n⚡ Data Processing Benchmark (500 URLs):")
      IO.puts("  • Time: #{Float.round(time_ms, 2)}ms")
      IO.puts("  • Queries: #{analysis.total_count}")
      IO.puts("  • Throughput: #{Float.round(500 / (time_ms / 1000), 2)} URLs/sec")
      IO.puts("  • Query efficiency: #{Float.round(500 / analysis.total_count, 2)} URLs/query")

      if metrics[:database] do
        IO.puts("  • Avg query time: #{Float.round(metrics.database.avg_time_ms, 2)}ms")
      end
    end

    test "benchmark multi-day data processing" do
      account_id = 1
      site_url = "sc-domain:example.com"
      dates = for i <- 0..6, do: Date.add(~D[2025-10-01], i)

      # Process data for each day
      results =
        for date <- dates do
          gsc_response = %{"rows" => generate_mock_urls(200)}

          QueryCounter.reset()

          {time_micros, url_count} =
            :timer.tc(fn ->
              Persistence.process_url_response(account_id, site_url, date, gsc_response)
            end)

          analysis = QueryCounter.analyze()

          {date, time_micros / 1000, url_count, analysis.total_count}
        end

      # Calculate totals
      total_time = Enum.reduce(results, 0, fn {_, time, _, _}, acc -> acc + time end)
      total_urls = Enum.reduce(results, 0, fn {_, _, urls, _}, acc -> acc + urls end)
      total_queries = Enum.reduce(results, 0, fn {_, _, _, queries}, acc -> acc + queries end)

      # Performance expectations
      assert total_time < 10000, "Multi-day processing took #{total_time}ms, expected <10s"
      assert total_queries < 200, "Used #{total_queries} queries, expected <200"

      # Print benchmark results
      IO.puts("\n⚡ Multi-day Processing Benchmark (7 days, 1400 URLs):")
      IO.puts("  • Total time: #{Float.round(total_time, 2)}ms")
      IO.puts("  • Total queries: #{total_queries}")
      IO.puts("  • Throughput: #{Float.round(total_urls / (total_time / 1000), 2)} URLs/sec")
      IO.puts("  • Query efficiency: #{Float.round(total_urls / total_queries, 2)} URLs/query")
      IO.puts("  • Time per day: #{Float.round(total_time / 7, 2)}ms")
    end

    test "measure data processing scalability across different volumes" do
      account_id = 1
      site_url = "sc-domain:example.com"
      date = ~D[2025-10-09]

      # Test with different data volumes
      volumes = [100, 500, 1000, 2000]

      results =
        for url_count <- volumes do
          # Clear data
          Repo.delete_all(GscAnalytics.Schemas.TimeSeries)
          Repo.delete_all(GscAnalytics.Schemas.Performance)
          QueryCounter.reset()

          # Generate test data
          gsc_response = %{"rows" => generate_mock_urls(url_count)}

          # Measure processing
          {time_micros, _} =
            :timer.tc(fn ->
              Persistence.process_url_response(account_id, site_url, date, gsc_response)
            end)

          analysis = QueryCounter.analyze()

          {url_count, time_micros / 1000, analysis.total_count, analysis.total_time_ms}
        end

      # Print scalability analysis
      IO.puts("\n📊 Processing Scalability Analysis:")
      IO.puts("  URLs  | Time (ms) | Queries | DB Time | URLs/sec | URLs/query")
      IO.puts("  ------|-----------|---------|---------|----------|----------")

      for {urls, time_ms, queries, db_time} <- results do
        throughput = Float.round(urls / (time_ms / 1000), 2)
        efficiency = Float.round(urls / queries, 2)

        IO.puts(
          "  #{String.pad_leading(Integer.to_string(urls), 5)} | " <>
            "#{String.pad_leading(Float.to_string(Float.round(time_ms, 1)), 9)} | " <>
            "#{String.pad_leading(Integer.to_string(queries), 7)} | " <>
            "#{String.pad_leading(Float.to_string(Float.round(db_time, 1)), 7)} | " <>
            "#{String.pad_leading(Float.to_string(throughput), 8)} | " <>
            "#{String.pad_leading(Float.to_string(efficiency), 8)}"
        )
      end

      # Verify sub-linear growth in time (good scaling)
      [{_, time_100, _, _}, _, _, {_, time_2000, _, _}] = results

      # 20x more data should take less than 20x more time
      scaling_factor = time_2000 / time_100
      assert scaling_factor < 20, "Poor scaling: 20x data took #{scaling_factor}x time"

      IO.puts(
        "\n✅ Scaling factor: #{Float.round(scaling_factor, 2)}x time for 20x data (sub-linear = good!)"
      )
    end

    test "benchmark incremental data updates" do
      account_id = 1
      site_url = "sc-domain:example.com"
      date = ~D[2025-10-09]

      # First processing: 1000 URLs
      initial_response = %{"rows" => generate_mock_urls(1000)}

      {initial_time, _} =
        :timer.tc(fn ->
          Persistence.process_url_response(account_id, site_url, date, initial_response)
        end)

      # Second processing: Same 1000 URLs + 100 new ones (simulating incremental update)
      updated_response = %{
        "rows" => generate_mock_urls(1000) ++ generate_mock_urls(100, 1001)
      }

      QueryCounter.reset()

      {incremental_time, _} =
        :timer.tc(fn ->
          Persistence.process_url_response(account_id, site_url, date, updated_response)
        end)

      analysis = QueryCounter.analyze()

      # Incremental processing should be efficient
      initial_ms = initial_time / 1000
      incremental_ms = incremental_time / 1000

      IO.puts("\n🔄 Incremental Update Benchmark:")
      IO.puts("  • Initial processing (1000 URLs): #{Float.round(initial_ms, 2)}ms")
      IO.puts("  • Incremental update (+100 URLs): #{Float.round(incremental_ms, 2)}ms")
      IO.puts("  • Incremental queries: #{analysis.total_count}")
      IO.puts("  • Speed ratio: #{Float.round(incremental_ms / initial_ms, 2)}x")

      # Incremental should not be much slower than initial (due to conflict resolution)
      assert incremental_ms < initial_ms * 2, "Incremental update not efficient enough"
    end
  end

  describe "memory usage benchmarks" do
    setup do
      PerformanceMonitor.start()
      on_exit(fn -> PerformanceMonitor.stop() end)
      :ok
    end

    test "measure memory usage during large data processing" do
      account_id = 1
      site_url = "sc-domain:example.com"
      date = ~D[2025-10-09]

      # Generate large dataset
      large_response = %{"rows" => generate_mock_urls(5000)}

      # Get initial memory
      initial_metrics = PerformanceMonitor.get_metrics()
      initial_memory = initial_metrics[:memory][:total_memory]

      # Process data
      Persistence.process_url_response(account_id, site_url, date, large_response)

      # Get final memory
      final_metrics = PerformanceMonitor.get_metrics()
      final_memory = final_metrics[:memory][:total_memory]

      # Calculate memory growth
      memory_growth_mb = (final_memory - initial_memory) / 1_048_576

      IO.puts("\n💾 Memory Usage Benchmark (5000 URLs):")
      IO.puts("  • Initial memory: #{format_bytes(initial_memory)}")
      IO.puts("  • Final memory: #{format_bytes(final_memory)}")
      IO.puts("  • Memory growth: #{Float.round(memory_growth_mb, 2)} MB")
      IO.puts("  • Memory per URL: #{Float.round(memory_growth_mb * 1024 / 5000, 2)} KB")

      # Memory growth should be reasonable
      assert memory_growth_mb < 100, "Excessive memory usage: #{memory_growth_mb} MB"
    end
  end

  # Helper functions

  defp generate_mock_urls(count, offset \\ 1) do
    for i <- offset..(offset + count - 1) do
      %{
        "keys" => ["https://example.com/page-#{i}"],
        "clicks" => :rand.uniform(100),
        "impressions" => :rand.uniform(1000),
        "ctr" => :rand.uniform() * 0.2,
        "position" => :rand.uniform() * 50
      }
    end
  end

  defp format_bytes(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 2)} GB"
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 2)} MB"
      bytes >= 1024 -> "#{Float.round(bytes / 1024, 2)} KB"
      true -> "#{bytes} B"
    end
  end

  defp format_bytes(_), do: "N/A"
end
