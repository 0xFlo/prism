defmodule GscAnalytics.DataSources.GSC.Support.ConcurrentBatchWorkerTest do
  use ExUnit.Case, async: true

  alias GscAnalytics.DataSources.GSC.Support.{ConcurrentBatchWorker, QueryCoordinator}

  @site_url "sc-domain:worker-test.com"

  test "workers fetch batches and stream results back to coordinator" do
    test_pid = self()

    {:ok, coordinator} =
      QueryCoordinator.start_link(
        account_id: 1,
        site_url: @site_url,
        dates: [~D[2024-01-01]],
        on_complete: fn payload ->
          send(test_pid, {:completed, payload.date})
          :continue
        end
      )

    tasks =
      ConcurrentBatchWorker.start_workers(coordinator,
        account_id: 1,
        site_url: @site_url,
        operation: "fetch_queries_batch",
        dimensions: ["page", "query"],
        batch_size: 1,
        max_concurrency: 1,
        client: __MODULE__.FakeClient,
        rate_limiter: __MODULE__.AllowAllLimiter,
        backpressure_sleep_ms: 5,
        idle_sleep_ms: 5
      )

    _ = Task.await_many(tasks, 5_000)

    assert {:ok, nil, results, total_calls, _} = QueryCoordinator.finalize(coordinator)
    assert results[~D[2024-01-01]].row_count == 1
    assert total_calls == 1
    assert_receive {:completed, ~D[2024-01-01]}
  end

  defmodule AllowAllLimiter do
    def check_rate(_account_id, _site_url, _count), do: :ok
  end

  defmodule FakeClient do
    def fetch_query_batch(_account_id, requests, _operation) do
      responses =
        Enum.map(requests, fn request ->
          %{
            id: request.id,
            status: 200,
            body: %{"rows" => [%{"keys" => ["https://example.com", "query"]}]},
            raw_body: nil
          }
        end)

      {:ok, responses, 1}
    end
  end
end
