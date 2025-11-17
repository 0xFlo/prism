defmodule GscAnalytics.DataSources.GSC.Core.Sync.Pipeline do
  @moduledoc """
  Sync pipeline orchestration.

  Handles chunking, phase coordination (URL → Query), metric aggregation,
  halt condition checks, and pause/stop commands from the progress tracker.

  ## Examples

      state =
        GscAnalytics.DataSources.GSC.Core.Sync.State.new(
          1,
          1,
          "sc-domain:example.com",
          [~D[2024-01-01]],
          []
        )

      final_state = Pipeline.execute(state)
  """

  alias GscAnalytics.DataSources.GSC.Core.Config
  alias GscAnalytics.DataSources.GSC.Core.Persistence
  alias GscAnalytics.DataSources.GSC.Core.Sync.{QueryPhase, URLPhase}
  alias GscAnalytics.DataSources.GSC.Support.SyncProgress
  alias MapSet

  require Logger

  @pause_poll_interval 500

  @doc """
  Execute the sync pipeline for all dates in the provided state.

  Processes dates in configured chunks, coordinating URL and Query phases.
  Returns the final state with metrics and halt information populated.
  """
  def execute(state) do
    chunk_size = Config.query_scheduler_chunk_size()

    final_state =
      state.dates
      |> Enum.chunk_every(chunk_size, chunk_size, [])
      |> Enum.reduce_while(state, fn chunk, acc ->
        case process_chunk(chunk, acc) do
          {:halt, new_state} -> {:halt, new_state}
          {:cont, new_state} -> {:cont, new_state}
        end
      end)

    # Batch refresh all collected URLs at the end
    refresh_all_lifetime_stats(final_state)

    final_state
  end

  defp process_chunk([], state), do: {:cont, state}

  defp process_chunk(dates, state) do
    case await_continue(state.job_id) do
      :stop ->
        {:halt, %{state | halted?: true, halt_reason: :stopped_by_user}}

      :continue ->
        execute_phases(dates, state)
    end
  end

  defp execute_phases(dates, state) do
    {url_results, url_api_calls, state_after_urls} =
      URLPhase.fetch_and_store(dates, state)

    {query_results, query_api_calls, state_after_queries} =
      QueryPhase.fetch_and_store(dates, url_results, state_after_urls)

    {merged_url_results, cleared_state} = merge_results(url_results, state_after_queries)

    metrics_state =
      update_metrics(
        cleared_state,
        merged_url_results,
        query_results,
        url_api_calls + query_api_calls
      )

    results_state =
      Map.update(metrics_state, :results, %{}, &Map.merge(&1, merged_url_results))

    new_state = check_halt_conditions(results_state, dates)

    if new_state.halted? do
      {:halt, new_state}
    else
      {:cont, new_state}
    end
  end

  defp merge_results(url_results, state) do
    failure_dates =
      state.query_failures
      |> MapSet.to_list()

    merged =
      Enum.reduce(failure_dates, url_results, fn date, acc ->
        Map.update(acc, date, %{url_count: 0, success: false}, fn entry ->
          %{entry | success: false}
        end)
      end)

    {merged, %{state | query_failures: MapSet.new()}}
  end

  defp update_metrics(state, url_results, query_results, api_calls) do
    total_urls =
      url_results
      |> Map.values()
      |> Enum.map(& &1.url_count)
      |> Enum.sum()

    total_queries =
      query_results
      |> Map.values()
      |> Enum.map(fn entry ->
        Map.get_lazy(entry, :row_count, fn ->
          entry
          |> Map.get(:rows, [])
          |> case do
            rows when is_list(rows) -> length(rows)
            _ -> 0
          end
        end)
      end)
      |> Enum.sum()

    query_sub_requests =
      query_results
      |> Map.values()
      |> Enum.map(&(&1.api_calls || 0))
      |> Enum.sum()

    query_http_batches =
      query_results
      |> Map.values()
      |> Enum.map(&(&1.http_batches || 0))
      |> Enum.sum()

    %{
      state
      | total_urls: state.total_urls + total_urls,
        total_queries: state.total_queries + total_queries,
        total_query_sub_requests: state.total_query_sub_requests + query_sub_requests,
        total_query_http_batches: state.total_query_http_batches + query_http_batches,
        api_calls: state.api_calls + api_calls,
        has_seen_data?: state.has_seen_data? or total_urls > 0
    }
  end

  defp check_halt_conditions(state, dates) do
    {new_streak, threshold_date} =
      Enum.reduce(dates, {state.empty_streak, nil}, fn date, {streak, threshold_acc} ->
        url_result = Map.get(state.results, date, %{url_count: 0})

        if url_result.url_count == 0 do
          new_streak_val = streak + 1
          empty_threshold = Keyword.get(state.opts, :empty_threshold, 0)

          new_threshold_date =
            if threshold_acc == nil and new_streak_val >= empty_threshold and empty_threshold > 0 do
              date
            else
              threshold_acc
            end

          {new_streak_val, new_threshold_date}
        else
          {0, nil}
        end
      end)

    should_halt? =
      Keyword.get(state.opts, :stop_on_empty?, false) and
        new_streak >= Keyword.get(state.opts, :empty_threshold, 0) and
        (state.has_seen_data? or
           map_size(state.results) >=
             Keyword.get(state.opts, :leading_empty_grace_days, 0))

    if should_halt? do
      %{
        state
        | empty_streak: new_streak,
          halted?: true,
          halt_reason: {:empty_threshold, threshold_date || List.last(dates)}
      }
    else
      %{state | empty_streak: new_streak}
    end
  end

  defp await_continue(job_id) do
    case SyncProgress.current_command(job_id) do
      :stop ->
        :stop

      :pause ->
        Process.sleep(@pause_poll_interval)
        await_continue(job_id)

      _ ->
        :continue
    end
  end

  defp refresh_all_lifetime_stats(state) do
    # Collect all URLs from results that have the urls field
    all_urls =
      state.results
      |> Map.values()
      |> Enum.flat_map(fn
        %{urls: urls} when is_list(urls) -> urls
        _ -> []
      end)
      |> Enum.uniq()

    if all_urls != [] do
      Logger.info("Refreshing lifetime stats for #{length(all_urls)} unique URLs")
      Persistence.refresh_lifetime_stats_incrementally(state.account_id, state.site_url, all_urls)
    end
  end
end
