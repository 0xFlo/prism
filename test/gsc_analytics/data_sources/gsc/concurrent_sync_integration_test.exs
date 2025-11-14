defmodule GscAnalytics.DataSources.GSC.ConcurrentSyncIntegrationTest do
  use ExUnit.Case, async: false

  alias GscAnalytics.DataSources.GSC.Support.QueryPaginator

  @site_url "sc-domain:concurrent-test.com"

  setup do
    original_client = Application.get_env(:gsc_analytics, :gsc_client)
    Application.put_env(:gsc_analytics, :gsc_client, __MODULE__.FakeClient)
    start_supervised!({__MODULE__.RateLimiterStub, []})

    on_exit(fn ->
      Application.put_env(:gsc_analytics, :gsc_client, original_client)
    end)

    :ok
  end

  test "concurrent path completes with rate-limit retries" do
    dates = [~D[2024-01-01], ~D[2024-01-02]]

    test_pid = self()

    {:ok, results, total_calls, _http_batches} =
      QueryPaginator.fetch_all_queries(1, @site_url, dates,
        batch_size: 1,
        max_concurrency: 2,
        rate_limiter: __MODULE__.RateLimiterStub,
        on_complete: fn payload ->
          send(test_pid, {:completed, payload.date})
          :continue
        end
      )

    assert total_calls == 2
    assert __MODULE__.RateLimiterStub.invocations() >= 2

    Enum.each(dates, fn date ->
      assert_receive {:completed, ^date}
      assert results[date].row_count == 1
    end)
  end

  defmodule RateLimiterStub do
    use Agent

    def start_link(opts) do
      Agent.start_link(fn -> %{calls: 0} end, Keyword.put_new(opts, :name, __MODULE__))
    end

    def check_rate(_account_id, _site_url, _count) do
      Agent.get_and_update(__MODULE__, fn
        %{calls: 0} = state -> {{:error, :rate_limited, 1}, %{state | calls: 1}}
        state -> {:ok, %{state | calls: state.calls + 1}}
      end)
    end

    def invocations do
      Agent.get(__MODULE__, & &1.calls)
    end
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
