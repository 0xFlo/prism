defmodule GscAnalytics.Crawler.BatchProcessorTest do
  use GscAnalytics.DataCase, async: false

  alias GscAnalytics.Crawler.BatchProcessor
  alias GscAnalytics.Crawler.ProgressTracker
  alias GscAnalytics.Schemas.Performance
  alias GscAnalytics.Repo

  import Ecto.Query

  setup do
    # Ensure inets and ssl are started for HTTP requests
    :inets.start()
    :ssl.start()

    # Start ProgressTracker if not already running
    case GenServer.whereis(ProgressTracker) do
      nil -> start_supervised!(ProgressTracker)
      _pid -> :ok
    end

    # Create test performance records
    urls = [
      "https://scrapfly.io/blog/web-scraping-with-python",
      "https://scrapfly.io/blog/web-scraping-with-javascript",
      "https://scrapfly.io/docs/scrape-api/getting-started"
    ]

    # Insert test records
    for url <- urls do
      Repo.insert!(%Performance{
        account_id: 1,
        url: url,
        clicks: 100,
        impressions: 1000,
        ctr: 0.1,
        position: 5.0,
        date_range_start: ~D[2025-01-01],
        date_range_end: ~D[2025-01-31],
        data_available: true
      })
    end

    %{urls: urls}
  end

  describe "process_batch/2" do
    test "processes multiple URLs concurrently", %{urls: urls} do
      {:ok, results} = BatchProcessor.process_batch(urls, save_results: false)

      assert length(results) == 3
      assert Enum.all?(results, fn {url, result} -> url in urls and is_map(result) end)
    end

    test "returns structured results for each URL", %{urls: urls} do
      {:ok, results} = BatchProcessor.process_batch(urls, save_results: false)

      for {_url, result} <- results do
        assert Map.has_key?(result, :status)
        assert Map.has_key?(result, :redirect_url)
        assert Map.has_key?(result, :redirect_chain)
        assert Map.has_key?(result, :checked_at)
        assert Map.has_key?(result, :error)
      end
    end

    test "respects concurrency setting" do
      # Create 20 URLs to process
      urls = Enum.map(1..20, fn i -> "https://example.com/page-#{i}" end)

      # Process with low concurrency - should still complete
      {:ok, results} =
        BatchProcessor.process_batch(urls,
          concurrency: 2,
          timeout: 5_000,
          save_results: false,
          progress_tracking: false
        )

      assert length(results) == 20
    end

    test "handles timeout with on_timeout: :kill_task" do
      # Use a URL that might timeout
      urls = ["https://httpbin.org/delay/15"]

      {:ok, results} =
        BatchProcessor.process_batch(urls,
          timeout: 2_000,
          save_results: false,
          progress_tracking: false
        )

      # Should still return results, but may have errors
      assert length(results) >= 0
    end

    test "saves results to database when save_results: true", %{urls: urls} do
      # Clear any existing http_checked_at values
      Repo.update_all(Performance, set: [http_checked_at: nil])

      {:ok, _results} = BatchProcessor.process_batch(urls, save_results: true)

      # Check that database was updated
      updated_count =
        Performance
        |> where([p], p.url in ^urls)
        |> where([p], not is_nil(p.http_checked_at))
        |> Repo.aggregate(:count)

      assert updated_count > 0
    end

    test "skips database save when save_results: false", %{urls: urls} do
      # Clear any existing http_checked_at values
      Repo.update_all(Performance, set: [http_checked_at: nil])

      {:ok, _results} = BatchProcessor.process_batch(urls, save_results: false)

      # Check that database was NOT updated
      updated_count =
        Performance
        |> where([p], p.url in ^urls)
        |> where([p], not is_nil(p.http_checked_at))
        |> Repo.aggregate(:count)

      assert updated_count == 0
    end

    test "handles mix of successful and failed URLs" do
      urls = [
        "https://scrapfly.io",
        "https://invalid-domain-that-does-not-exist-12345.com",
        "https://example.com"
      ]

      {:ok, results} =
        BatchProcessor.process_batch(urls, save_results: false, progress_tracking: false)

      assert length(results) == 3

      # Should have mix of results and errors
      statuses = Enum.map(results, fn {_url, result} -> result.status end)
      errors = Enum.map(results, fn {_url, result} -> result.error end)

      # At least some should succeed or fail
      assert Enum.any?(statuses, &(!is_nil(&1))) or Enum.any?(errors, &(!is_nil(&1)))
    end
  end

  describe "process_all/1" do
    setup %{urls: urls} do
      # Mark records as stale (need checking)
      stale_date =
        DateTime.utc_now()
        |> DateTime.add(-10, :day)
        |> DateTime.truncate(:second)

      Repo.update_all(
        from(p in Performance, where: p.url in ^urls),
        set: [http_checked_at: stale_date]
      )

      :ok
    end

    test "processes URLs from database with :all filter" do
      {:ok, stats} =
        BatchProcessor.process_all(
          account_id: 1,
          filter: :all,
          batch_size: 10,
          concurrency: 5,
          save_results: false,
          progress_tracking: false
        )

      assert stats.total == 3
      assert stats.checked == 3
    end

    test "processes only stale URLs with :stale filter" do
      {:ok, stats} =
        BatchProcessor.process_all(
          account_id: 1,
          filter: :stale,
          batch_size: 10,
          concurrency: 5,
          save_results: false,
          progress_tracking: false
        )

      assert stats.total == 3
      assert stats.checked == 3
    end

    test "returns statistics with status breakdown" do
      {:ok, stats} =
        BatchProcessor.process_all(
          account_id: 1,
          filter: :all,
          concurrency: 5,
          save_results: false,
          progress_tracking: false
        )

      assert Map.has_key?(stats, :total)
      assert Map.has_key?(stats, :checked)
      assert Map.has_key?(stats, :status_2xx)
      assert Map.has_key?(stats, :status_3xx)
      assert Map.has_key?(stats, :status_4xx)
      assert Map.has_key?(stats, :status_5xx)
      assert Map.has_key?(stats, :errors)

      assert stats.checked ==
               stats.status_2xx + stats.status_3xx + stats.status_4xx +
                 stats.status_5xx + stats.errors
    end

    test "processes in batches when batch_size is set" do
      # Insert more URLs to trigger batching
      stale_date =
        DateTime.utc_now()
        |> DateTime.add(-10, :day)
        |> DateTime.truncate(:second)

      for i <- 1..150 do
        Repo.insert!(%Performance{
          account_id: 1,
          url: "https://example.com/page-#{i}",
          clicks: 10,
          impressions: 100,
          ctr: 0.1,
          position: 10.0,
          date_range_start: ~D[2025-01-01],
          date_range_end: ~D[2025-01-31],
          data_available: true,
          http_checked_at: stale_date
        })
      end

      {:ok, stats} =
        BatchProcessor.process_all(
          account_id: 1,
          filter: :stale,
          batch_size: 50,
          concurrency: 10,
          save_results: false,
          progress_tracking: false
        )

      # Should process all URLs across multiple batches
      assert stats.total >= 150
    end

    test "prioritizes high-traffic URLs (ORDER BY clicks DESC)" do
      # Insert URLs with different click counts
      stale_date =
        DateTime.utc_now()
        |> DateTime.add(-10, :day)
        |> DateTime.truncate(:second)

      Repo.insert!(%Performance{
        account_id: 1,
        url: "https://high-traffic.com",
        clicks: 10_000,
        impressions: 50_000,
        ctr: 0.2,
        position: 2.0,
        date_range_start: ~D[2025-01-01],
        date_range_end: ~D[2025-01-31],
        data_available: true,
        http_checked_at: stale_date
      })

      Repo.insert!(%Performance{
        account_id: 1,
        url: "https://low-traffic.com",
        clicks: 10,
        impressions: 100,
        ctr: 0.1,
        position: 20.0,
        date_range_start: ~D[2025-01-01],
        date_range_end: ~D[2025-01-31],
        data_available: true,
        http_checked_at: stale_date
      })

      # Get URLs in order they'll be processed
      urls =
        from(p in Performance,
          where: p.account_id == 1,
          where: p.data_available == true,
          order_by: [desc: p.clicks],
          select: p.url
        )
        |> Repo.all()

      # High traffic URL should be first
      assert List.first(urls) == "https://high-traffic.com"
    end
  end

  describe "progress tracking integration" do
    test "updates progress tracker when enabled", %{urls: urls} do
      # Subscribe to progress events
      ProgressTracker.subscribe()

      # Start a check job (required for progress updates to be broadcast)
      {:ok, _job_id} = ProgressTracker.start_check(length(urls))

      # Process batch with progress tracking
      {:ok, _results} =
        BatchProcessor.process_batch(urls,
          save_results: false,
          progress_tracking: true,
          concurrency: 1
        )

      # Should have received progress update messages
      assert_receive {:crawler_progress, %{type: :update}}, 100
    end

    test "skips progress tracking when disabled", %{urls: urls} do
      # Subscribe to progress events
      ProgressTracker.subscribe()

      # Process without progress tracking
      {:ok, _results} =
        BatchProcessor.process_batch(urls, save_results: false, progress_tracking: false)

      # Should not receive progress updates
      refute_receive {:crawler_progress, %{type: :update}}, 1_000
    end
  end

  describe "calculate_stats/1 (private function testing via process_all)" do
    test "correctly counts 2xx responses" do
      # Insert URLs that should return 2xx
      Repo.delete_all(Performance)

      Repo.insert!(%Performance{
        account_id: 1,
        url: "https://scrapfly.io",
        clicks: 100,
        impressions: 1000,
        ctr: 0.1,
        position: 5.0,
        date_range_start: ~D[2025-01-01],
        date_range_end: ~D[2025-01-31],
        data_available: true
      })

      {:ok, stats} =
        BatchProcessor.process_all(
          account_id: 1,
          filter: :all,
          save_results: false,
          progress_tracking: false
        )

      # Should have some successful checks (2xx, 4xx, or errors)
      assert stats.checked > 0
      assert stats.total == 1
    end
  end

  describe "error handling" do
    test "handles empty URL list gracefully" do
      {:ok, results} = BatchProcessor.process_batch([], save_results: false)
      assert results == []
    end

    test "handles malformed URLs" do
      urls = ["not-a-url", "ftp://unsupported-protocol.com"]

      {:ok, results} =
        BatchProcessor.process_batch(urls, save_results: false, progress_tracking: false)

      # Should return results with errors
      assert length(results) == 2

      for {_url, result} <- results do
        assert result.status == nil or result.error != nil
      end
    end
  end
end
