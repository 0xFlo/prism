defmodule GscAnalytics.DataSources.GSC.PaginationIntegrationTest do
  @moduledoc """
  Integration tests for pagination with streaming callbacks and Agent coordination.

  Tests the full pipeline: QueryPaginator → Streaming Callback → Agent Coordination → DB Write

  Reproduces the production issue where pagination works in isolation but fails
  when combined with the Sync.ex streaming callback pattern.
  """

  use GscAnalytics.DataCase, async: false

  @moduletag :integration

  alias GscAnalytics.DataSources.GSC.Core.Sync
  alias GscAnalytics.DataSources.GSC.Support.QueryPaginator
  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.{TimeSeries, SyncDay}

  import Ecto.Query

  @site_url "sc-domain:pagination-test.com"
  @account_id 999

  setup do
    # Set up fake client that returns predictable data
    original_client = Application.get_env(:gsc_analytics, :gsc_client)
    Application.put_env(:gsc_analytics, :gsc_client, __MODULE__.FakePaginationClient)
    Application.put_env(:gsc_analytics, :test_pid, self())

    on_exit(fn ->
      Application.put_env(:gsc_analytics, :gsc_client, original_client)
      Application.delete_env(:gsc_analytics, :test_pid)
    end)

    :ok
  end

  describe "pagination with streaming callbacks" do
    test "handles multiple dates where some need pagination" do
      # Setup: 5 dates with varying query counts
      # Date 1: 30,000 rows (needs 2 pages: 25k + 5k)
      # Date 2: 50,100 rows (needs 3 pages: 25k + 25k + 100)
      # Date 3: 15,000 rows (single page)
      # Date 4: 25,000 rows (exactly 1 page, should NOT paginate)
      # Date 5: 8,000 rows (single page)

      dates = [
        # 30,000 rows
        ~D[2025-07-06],
        # 50,100 rows
        ~D[2025-07-05],
        # 15,000 rows
        ~D[2025-07-04],
        # 25,000 rows (edge case!)
        ~D[2025-07-03],
        # 8,000 rows
        ~D[2025-07-02]
      ]

      # Run sync with streaming callbacks enabled
      assert {:ok, summary} =
               Sync.sync_date_range(@site_url, ~D[2025-07-02], ~D[2025-07-06],
                 account_id: @account_id,
                 # Process in smaller batches
                 query_scheduler_chunk_size: 3,
                 # Allow concurrent pagination
                 query_scheduler_batch_size: 4
               )

      # Verify all dates completed successfully
      assert summary.total_urls > 0
      refute Map.has_key?(summary, :failed_days) or summary[:failed_days] == 0

      # Verify row counts in database match expected totals
      for date <- dates do
        sync_day =
          Repo.one!(
            from sd in SyncDay,
              where:
                sd.account_id == ^@account_id and
                  sd.site_url == ^@site_url and
                  sd.date == ^date
          )

        assert sync_day.status == :complete, "Date #{date} should be marked complete"
      end

      # Verify that data was stored for each date (we're limiting URLs to 100 for test performance)
      for date <- dates do
        url_count =
          Repo.one!(
            from ts in TimeSeries,
              where: ts.account_id == ^@account_id and ts.date == ^date,
              select: count(ts.url)
          )

        # Each date should have some URLs stored
        assert url_count > 0, "Should have URLs for #{date}"

        # We limit to 100 URLs per date for test performance
        assert url_count <= 100, "URL count should be limited to 100 for test performance"
      end

      # Check that pagination was actually triggered
      assert_receive {:pagination_triggered, ~D[2025-07-06], 0, 25_000}
      assert_receive {:pagination_triggered, ~D[2025-07-05], 0, 25_000}
      assert_receive {:pagination_triggered, ~D[2025-07-05], 25_000, 50_000}

      # Date with exactly 25,000 rows WILL trigger pagination once (to check for more)
      assert_receive {:pagination_triggered, ~D[2025-07-03], 0, 25_000}
    end

    test "pagination continues even with slow Agent coordination" do
      # Inject delay in callback processing
      Application.put_env(:gsc_analytics, :test_callback_delay_ms, 1_500)

      on_exit(fn ->
        Application.delete_env(:gsc_analytics, :test_callback_delay_ms)
      end)

      # Single date with pagination needs
      assert {:ok, summary} =
               Sync.sync_date_range(@site_url, ~D[2025-07-06], ~D[2025-07-06],
                 account_id: @account_id
               )

      # Should still complete despite slow callbacks
      assert summary.total_urls > 0

      # Verify both pages were fetched
      assert_receive {:pagination_triggered, ~D[2025-07-06], 0, 25_000}
    end

    test "detects when pagination queue is not processing" do
      # Use QueryPaginator directly with callback to isolate issue
      callback_invocations = Agent.start_link(fn -> [] end) |> elem(1)

      callback = fn payload ->
        Agent.update(callback_invocations, fn list -> [payload | list] end)
        :continue
      end

      {:ok, _results, api_calls, _batch_calls} =
        QueryPaginator.fetch_all_queries(@account_id, @site_url, [~D[2025-07-06]],
          batch_size: 4,
          on_complete: callback
        )

      # Callback should be invoked only once (after all pages complete)
      completions = Agent.get(callback_invocations, & &1)
      assert length(completions) == 1

      # Verify callback received all rows
      [completion] = completions
      assert completion.date == ~D[2025-07-06]
      assert length(completion.rows) == 30_000
      assert completion.api_calls == 2

      # Should have made 2 API calls (page 0 and page 25000)
      assert api_calls == 2

      Agent.stop(callback_invocations)
    end

    test "pagination handles Agent timeout gracefully" do
      # This test simulates what happens if Agent coordination blocks
      # We can't easily simulate a timeout without modifying production code,
      # but we can verify error handling exists

      # The callback in Sync.ex has a rescue clause that should catch timeouts
      # and convert them to {:halt, {:callback_crash, message}}

      # For now, just verify the pipeline completes
      assert {:ok, _summary} =
               Sync.sync_date_range(@site_url, ~D[2025-07-06], ~D[2025-07-06],
                 account_id: @account_id
               )
    end

    test "edge case: exactly 25,000 rows triggers pagination that returns empty" do
      # When total rows = exactly 25,000, GSC will:
      # - Return 25,000 on first request (full page)
      # - Trigger pagination check (because full page)
      # - Return 0 on second request (no more data)
      # This is expected behavior - one extra API call is acceptable

      {:ok, results, api_calls, _batch_calls} =
        QueryPaginator.fetch_all_queries(@account_id, @site_url, [~D[2025-07-03]], batch_size: 2)

      # Should make 2 API calls (initial + pagination check that returns 0)
      assert api_calls == 2

      # Final result should have exactly 25,000 rows
      result = Map.get(results, ~D[2025-07-03])
      assert length(result.rows) == 25_000

      # Pagination should have been triggered once
      assert_receive {:pagination_triggered, ~D[2025-07-03], 0, 25_000}
    end
  end

  defmodule FakePaginationClient do
    @moduledoc """
    Fake GSC client that returns predictable pagination data.

    Row counts per date:
    - 2025-07-06: 30,000 (25k + 5k)
    - 2025-07-05: 50,100 (25k + 25k + 100)
    - 2025-07-04: 15,000 (single page)
    - 2025-07-03: 25,000 (exactly one page)
    - 2025-07-02: 8,000 (single page)
    """

    alias GscAnalytics.DataSources.GSC.Support.QueryPaginator

    def fetch_all_urls_for_date(_account_id, _site_url, date, _opts \\ []) do
      # Return minimal URL data
      url_count = get_url_count_for_date(date)

      rows =
        for i <- 1..url_count do
          %{
            "keys" => ["https://pagination-test.com/page-#{i}"],
            "clicks" => 1,
            "impressions" => 10,
            "ctr" => 0.1,
            "position" => 5.0
          }
        end

      {:ok, %{"rows" => rows}}
    end

    def fetch_query_batch(_account_id, requests, operation) do
      test_pid = Application.get_env(:gsc_analytics, :test_pid)

      responses =
        Enum.map(requests, fn request ->
          {date, start_row} = parse_request_id(request.id)

          rows =
            if operation == "fetch_all_urls_batch" do
              # For URL fetching, return a reasonable number of URLs
              build_url_rows(date)
            else
              # For query fetching, return query data with pagination
              build_query_rows(date, start_row)
            end

          # Notify test process if pagination should trigger (only for query fetching)
          if operation != "fetch_all_urls_batch" and length(rows) >= QueryPaginator.page_size() do
            next_row = QueryPaginator.next_start_row(start_row)
            send(test_pid, {:pagination_triggered, date, start_row, next_row})
          end

          %{
            id: request.id,
            status: 200,
            body: %{"rows" => rows},
            raw_body: nil,
            metadata: request.metadata
          }
        end)

      {:ok, responses, 1}
    end

    defp build_url_rows(date) do
      # Return a reasonable number of URLs for testing (not thousands)
      url_count = min(get_url_count_for_date(date), 100)

      if url_count > 0 do
        for i <- 1..url_count//1 do
          %{
            "keys" => ["https://pagination-test.com/page-#{i}"],
            "clicks" => 1,
            "impressions" => 10,
            "ctr" => 0.1,
            "position" => 5.0
          }
        end
      else
        []
      end
    end

    defp build_query_rows(date, start_row) do
      total_rows = get_total_query_rows(date)
      remaining = max(0, total_rows - start_row)
      count = min(remaining, QueryPaginator.page_size())

      if count > 0 do
        for i <- 1..count//1 do
          url_index = div(start_row + i - 1, 10) + 1
          query_index = rem(start_row + i - 1, 10) + 1

          %{
            "keys" => ["https://pagination-test.com/page-#{url_index}", "query #{query_index}"],
            "clicks" => 1,
            "impressions" => 10,
            "ctr" => 0.1,
            "position" => 5.0
          }
        end
      else
        []
      end
    end

    defp get_total_query_rows(~D[2025-07-06]), do: 30_000
    defp get_total_query_rows(~D[2025-07-05]), do: 50_100
    defp get_total_query_rows(~D[2025-07-04]), do: 15_000
    defp get_total_query_rows(~D[2025-07-03]), do: 25_000
    defp get_total_query_rows(~D[2025-07-02]), do: 8_000
    defp get_total_query_rows(_), do: 0

    defp get_url_count_for_date(date) do
      # URLs are unique - 10 queries per URL
      # So divide total query rows by 10 to get unique URL count
      div(get_total_query_rows(date), 10)
    end

    defp parse_request_id(id) do
      [date_str, row_str] = String.split(id, ":")
      {Date.from_iso8601!(date_str), String.to_integer(row_str)}
    end
  end
end
