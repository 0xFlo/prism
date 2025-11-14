defmodule GscAnalytics.DataSources.GSC.Support.QueryCoordinatorTest do
  use ExUnit.Case, async: true

  alias GscAnalytics.DataSources.GSC.Support.{QueryCoordinator, QueryPaginator}

  setup do
    {:ok, coordinator} = start_coordinator()
    {:ok, coordinator: coordinator}
  end

  test "take_batch enforces in-flight limit" do
    {:ok, coordinator} = start_coordinator(max_in_flight: 1)

    assert {:ok, [job]} = QueryCoordinator.take_batch(coordinator, 1)
    assert {:backpressure, :max_in_flight} = QueryCoordinator.take_batch(coordinator, 1)

    entry = {:ok, elem(job, 0), elem(job, 1), %{body: %{"rows" => partial_rows(10_000)}}}

    assert :ok =
             QueryCoordinator.submit_results(coordinator, %{entries: [entry], http_batches: 1})

    assert {:ok, _next_job} = QueryCoordinator.take_batch(coordinator, 1)
  end

  test "submit_results paginates and finalizes with callback" do
    test_pid = self()

    {:ok, coordinator} =
      start_coordinator(
        on_complete: fn payload ->
          send(test_pid, {:completed, payload})
          :continue
        end
      )

    entries = [
      {:ok, ~D[2024-01-01], 0, %{body: %{"rows" => full_page_rows()}}},
      {:ok, ~D[2024-01-02], 0, %{body: %{"rows" => partial_rows(10_000)}}}
    ]

    assert :ok =
             QueryCoordinator.submit_results(coordinator, %{entries: entries, http_batches: 1})

    # Second page to complete first date
    entries_page_two = [
      {:ok, ~D[2024-01-01], QueryPaginator.page_size(), %{body: %{"rows" => partial_rows(5_000)}}}
    ]

    assert :ok =
             QueryCoordinator.submit_results(coordinator, %{
               entries: entries_page_two,
               http_batches: 1
             })

    assert_receive {:completed, %{date: ~D[2024-01-01], row_count: 30_000}}, 100
    assert_receive {:completed, %{date: ~D[2024-01-02], row_count: 10_000}}, 100

    assert {:ok, nil, results, total_calls, http_batches} = QueryCoordinator.finalize(coordinator)
    assert total_calls == 3
    assert http_batches == 2
    assert results[~D[2024-01-01]].row_count == 30_000
    assert results[~D[2024-01-02]].row_count == 10_000
  end

  test "halt propagates when callback requests it" do
    {:ok, coordinator} =
      start_coordinator(on_complete: fn _ -> {:halt, :stop_now} end)

    entry = {:ok, ~D[2024-01-01], 0, %{body: %{"rows" => partial_rows(10_000)}}}

    assert :ok =
             QueryCoordinator.submit_results(coordinator, %{entries: [entry], http_batches: 1})

    assert {:halted, {:halt, :stop_now}} = QueryCoordinator.take_batch(coordinator, 1)
    assert {:halt, :stop_now, _results, _calls, _batches} = QueryCoordinator.finalize(coordinator)
  end

  test "requeue_batch respects queue limits", %{coordinator: _coordinator} do
    {:ok, limited} =
      start_coordinator(dates: [~D[2024-01-01]], max_queue_size: 1, max_in_flight: 1)

    assert {:ok, [_job]} = QueryCoordinator.take_batch(limited, 1)

    assert {:error, :queue_full} =
             QueryCoordinator.requeue_batch(limited, [
               {~D[2024-01-01], 0},
               {~D[2024-01-01], QueryPaginator.page_size()}
             ])
  end

  test "error entries mark partial results and halt with {:error, reason}", %{
    coordinator: coordinator
  } do
    entry = {:error, ~D[2024-01-01], 0, :boom}

    assert :ok =
             QueryCoordinator.submit_results(coordinator, %{entries: [entry], http_batches: 0})

    assert {:error, :boom, results, total_calls, _} = QueryCoordinator.finalize(coordinator)
    assert total_calls == 1
    assert results[~D[2024-01-01]].partial?
  end

  defp full_page_rows do
    List.duplicate(%{"keys" => ["https://example.com", "query"]}, QueryPaginator.page_size())
  end

  defp partial_rows(count) do
    List.duplicate(%{"keys" => ["https://example.com", "query"]}, count)
  end

  defp start_coordinator(opts \\ []) do
    base_opts = [
      account_id: 1,
      site_url: "sc-domain:test.com",
      dates: [~D[2024-01-01], ~D[2024-01-02]],
      max_queue_size: 10,
      max_in_flight: 2,
      on_complete: nil
    ]

    QueryCoordinator.start_link(Keyword.merge(base_opts, opts))
  end
end
