defmodule GscAnalytics.DataSources.GSC.Support.QueryPaginatorTest do
  use ExUnit.Case, async: true

  alias GscAnalytics.DataSources.GSC.Support.QueryPaginator

  @site_url "sc-domain:test.com"

  setup do
    original_client = Application.get_env(:gsc_analytics, :gsc_client)
    original_pid = Application.get_env(:gsc_analytics, :fake_client_pid)

    Application.put_env(:gsc_analytics, :fake_client_pid, self())
    Application.put_env(:gsc_analytics, :gsc_client, __MODULE__.FakeClient)

    on_exit(fn ->
      Application.put_env(:gsc_analytics, :gsc_client, original_client)
      Application.put_env(:gsc_analytics, :fake_client_pid, original_pid)
    end)

    :ok
  end

  test "fetch_all_queries batches across dates without redundant pages" do
    newest = ~D[2024-01-02]
    older = ~D[2024-01-01]

    assert {:ok, results, total_calls, _batch_calls} =
             QueryPaginator.fetch_all_queries(1, @site_url, [newest, older],
               batch_size: 2,
               max_concurrency: 1
             )

    assert total_calls == 3

    refute Map.get(results, newest)[:partial?]
    assert Map.get(results, newest)[:api_calls] == 2
    assert length(Map.get(results, newest)[:rows]) == QueryPaginator.page_size() + 5_000

    assert Map.get(results, older)[:api_calls] == 1
    assert length(Map.get(results, older)[:rows]) == 10_000

    assert_receive {:batch, batch1}
    assert Enum.sort(batch1) == Enum.sort([{newest, 0}, {older, 0}])

    assert_receive {:batch, batch2}
    assert batch2 == [{newest, 25_000}]

    refute_receive {:batch, _}
    flush_batches()
  end

  test "fetch_all_queries emits completions via callback and frees rows" do
    newest = ~D[2024-01-02]
    older = ~D[2024-01-01]

    QueryPaginator.fetch_all_queries(1, @site_url, [newest, older],
      batch_size: 2,
      max_concurrency: 1,
      on_complete: fn payload ->
        send(self(), {:completed, payload})
        :continue
      end
    )

    assert_receive {:completed, %{date: ^newest, rows: rows_newest, api_calls: 2}}
    assert length(rows_newest) == QueryPaginator.page_size() + 5_000

    assert_receive {:completed, %{date: ^older, rows: rows_older, api_calls: 1}}
    assert length(rows_older) == 10_000

    refute_receive {:completed, _}
    flush_batches()

    {:ok, results, _, _} =
      QueryPaginator.fetch_all_queries(1, @site_url, [newest],
        batch_size: 2,
        max_concurrency: 1,
        on_complete: fn _ -> :continue end
      )

    assert Map.get(results, newest)[:rows] == []
    flush_batches()
  end

  test "fetch_all_queries halts when callback returns {:halt, reason}" do
    newest = ~D[2024-01-02]
    older = ~D[2024-01-01]

    assert {:halt, :custom_halt, results, _total_calls, _batch_calls} =
             QueryPaginator.fetch_all_queries(1, @site_url, [newest, older],
               batch_size: 2,
               max_concurrency: 1,
               on_complete: fn payload ->
                 send(self(), {:completed, payload.date})

                 # Halt after first date completes
                 if payload.date == newest do
                   {:halt, :custom_halt}
                 else
                   :continue
                 end
               end
             )

    # First date should have been completed
    assert_receive {:completed, ^newest}

    # Results should contain minimized entry for completed date
    assert Map.has_key?(results, newest)
    assert Map.get(results, newest)[:rows] == []

    flush_batches()
  end

  test "fetch_all_queries handles callback exceptions gracefully" do
    newest = ~D[2024-01-02]
    older = ~D[2024-01-01]

    assert {:halt, {:callback_error, error_msg}, _results, _total_calls, _batch_calls} =
             QueryPaginator.fetch_all_queries(1, @site_url, [newest, older],
               batch_size: 2,
               max_concurrency: 1,
               on_complete: fn payload ->
                 # Raise exception on first completion
                 if payload.date == newest do
                   raise "Simulated callback error"
                 else
                   :continue
                 end
               end
             )

    assert error_msg =~ "Simulated callback error"
    flush_batches()
  end

  defmodule FakeClient do
    alias GscAnalytics.DataSources.GSC.Support.QueryPaginator

    def fetch_query_batch(_account_id, requests, _operation) do
      send(test_pid(), {:batch, Enum.map(requests, &extract_request/1)})

      responses = Enum.map(requests, &build_response/1)
      {:ok, responses, 1}
    end

    def fetch_all_urls_for_date(_account_id, _site_url, date) do
      rows =
        case date do
          ~D[2024-01-02] -> [%{"keys" => ["https://example.com/page"], "clicks" => 1}]
          ~D[2024-01-01] -> [%{"keys" => ["https://example.com/page"], "clicks" => 1}]
          _ -> []
        end

      {:ok, %{"rows" => rows}}
    end

    def fetch_query_pages_batch(_, _, _, _), do: {:ok, []}
    def fetch_all_queries_for_date(_, _, _, _), do: {:ok, %{"rows" => []}}

    defp extract_request(request) do
      {date, start_row} = parse_id(request.id)
      {date, start_row}
    end

    defp build_response(request) do
      {date, start_row} = parse_id(request.id)

      rows =
        case {date, start_row} do
          {~D[2024-01-02], 0} -> duplicate_rows(QueryPaginator.page_size())
          {~D[2024-01-02], 25_000} -> duplicate_rows(5_000)
          {~D[2024-01-01], 0} -> duplicate_rows(10_000)
          _ -> []
        end

      %{
        id: request.id,
        status: 200,
        body: %{"rows" => rows},
        raw_body: nil,
        metadata: request.metadata
      }
    end

    defp duplicate_rows(count) do
      row = %{"keys" => ["https://example.com/page", "query"], "clicks" => 1}
      List.duplicate(row, count)
    end

    defp parse_id(id) do
      [date_iso, start_str] = String.split(id, ":")
      {Date.from_iso8601!(date_iso), String.to_integer(start_str)}
    end

    defp test_pid do
      Application.get_env(:gsc_analytics, :fake_client_pid)
    end
  end

  defp flush_batches do
    receive do
      {:batch, _} -> flush_batches()
    after
      0 -> :ok
    end
  end
end
