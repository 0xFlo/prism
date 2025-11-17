# TICKET-005: Pipeline Coordination

**Priority:** 🟡 P2 Medium
**Estimate:** 4 hours
**Dependencies:** TICKET-003, TICKET-004
**Blocks:** TICKET-006

## Objective

Extract the orchestration logic into a `Pipeline` module that coordinates URL and Query phases, handles chunk processing, and manages halt conditions.

## Why This Matters

After extracting phase modules, the remaining orchestration logic (chunking, halting, metric updates) can be consolidated into a pipeline module, leaving sync.ex as a thin public API layer.

## Implementation Steps

### 1. Create `lib/gsc_analytics/data_sources/gsc/core/sync/pipeline.ex`

```elixir
defmodule GscAnalytics.DataSources.GSC.Core.Sync.Pipeline do
  @moduledoc """
  Sync pipeline orchestration.

  Coordinates:
  - Chunk processing (batch dates for better progress visibility)
  - Phase execution (URL → Query)
  - State updates (metrics, results)
  - Halt condition checking (empty threshold, errors)
  - Pause/resume handling
  """

  require Logger

  alias GscAnalytics.DataSources.GSC.Core.Config
  alias GscAnalytics.DataSources.GSC.Core.Sync.{State, URLPhase, QueryPhase}
  alias GscAnalytics.DataSources.GSC.Support.SyncProgress

  @pause_poll_interval 500

  @doc """
  Execute the sync pipeline for all dates in state.

  Processes dates in chunks, executing URL and Query phases for each chunk,
  and checking halt conditions between chunks.

  Returns the final state with updated metrics and halt status.
  """
  def execute(state) do
    chunk_size = Config.query_scheduler_chunk_size()

    state.dates
    |> Enum.chunk_every(chunk_size, chunk_size, [])
    |> Enum.reduce_while(state, fn chunk, acc ->
      case process_chunk(chunk, acc) do
        {:halt, new_state} -> {:halt, new_state}
        {:cont, new_state} -> {:cont, new_state}
      end
    end)
  end

  # Private functions

  defp process_chunk([], state), do: {:cont, state}

  defp process_chunk(dates, state) do
    # Check for user commands (pause/stop)
    case await_continue(state.job_id) do
      :stop ->
        {:halt, %{state | halted?: true, halt_reason: :stopped_by_user}}

      :continue ->
        execute_phases(dates, state)
    end
  end

  defp execute_phases(dates, state) do
    # Phase 1: Fetch and store URLs
    {url_results, url_api_calls, state_after_urls} =
      URLPhase.fetch_and_store(dates, state)

    # Phase 2: Fetch and store queries
    {query_results, query_api_calls, state_after_queries} =
      QueryPhase.fetch_and_store(dates, url_results, state_after_urls)

    # Merge results and update state
    merged_results = merge_results(url_results, state_after_queries.query_failures)

    new_state =
      state_after_queries
      |> update_metrics(merged_results, query_results, url_api_calls + query_api_calls)
      |> Map.update(:results, %{}, &Map.merge(&1, merged_results))
      |> check_halt_conditions(dates)

    if new_state.halted? do
      {:halt, new_state}
    else
      {:cont, new_state}
    end
  end

  defp merge_results(url_results, query_failures) do
    # Mark URLs as failed if their queries failed
    failure_dates = MapSet.to_list(query_failures)

    Enum.reduce(failure_dates, url_results, fn date, acc ->
      Map.update(acc, date, %{url_count: 0, success: false}, fn entry ->
        %{entry | success: false}
      end)
    end)
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
    # Track consecutive empty dates
    {new_streak, threshold_date} = calculate_empty_streak(state, dates)

    # Determine if we should halt
    should_halt? = should_halt_on_empty?(state, new_streak)

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

  defp calculate_empty_streak(state, dates) do
    # Dates are processed newest-first
    Enum.reduce(dates, {state.empty_streak, nil}, fn date, {streak, threshold_acc} ->
      url_result = Map.get(state.results, date, %{url_count: 0})

      if url_result.url_count == 0 do
        # Empty date: increment streak
        new_streak = streak + 1
        empty_threshold = Keyword.get(state.opts, :empty_threshold, 0)

        # Track the date where we first hit threshold
        new_threshold_date =
          if threshold_acc == nil and new_streak >= empty_threshold and empty_threshold > 0 do
            date
          else
            threshold_acc
          end

        {new_streak, new_threshold_date}
      else
        # Date with data: reset streak
        {0, nil}
      end
    end)
  end

  defp should_halt_on_empty?(state, streak) do
    Keyword.get(state.opts, :stop_on_empty?, false) and
      streak >= Keyword.get(state.opts, :empty_threshold, 0) and
      (state.has_seen_data? or
         map_size(state.results) >= Keyword.get(state.opts, :leading_empty_grace_days, 0))
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
end
```

### 2. Update `sync.ex` to Use Pipeline

**Replace execute_sync (line 139):**

```elixir
# OLD
defp execute_sync(state) do
  chunk_size = Config.query_scheduler_chunk_size()

  state.dates
  |> Enum.chunk_every(chunk_size, chunk_size, [])
  |> Enum.reduce_while(state, fn chunk, acc ->
    case process_date_chunk(chunk, acc) do
      {:halt, new_state} -> {:halt, new_state}
      {:cont, new_state} -> {:cont, new_state}
    end
  end)
end

# NEW
alias GscAnalytics.DataSources.GSC.Core.Sync.Pipeline

defp execute_sync(state) do
  Pipeline.execute(state)
end
```

### 3. Delete Moved Functions

Remove these functions from sync.ex (now in Pipeline):
- `process_date_chunk` (line 153)
- `update_sync_metrics` (line 472)
- `check_empty_threshold` (line 503)
- `await_continue` (line 549)

### 4. Keep Minimal Functions in sync.ex

The remaining sync.ex should have:

**Public API:**
- `sync_date_range/4` - Main entry point
- `sync_yesterday/2` - Convenience wrapper
- `sync_last_n_days/3` - Convenience wrapper
- `sync_full_history/2` - Convenience wrapper

**Private Helpers:**
- `finalize_sync/2` - Audit logging and cleanup
- `get_default_site_url/1` - Account property lookup

### 5. Simplify sync_date_range

```elixir
def sync_date_range(site_url, start_date, end_date, opts \\ []) do
  account_id = opts[:account_id] || Config.default_account_id()
  start_time = System.monotonic_time(:millisecond)

  Logger.info("Starting GSC sync for #{site_url} from #{start_date} to #{end_date}")

  # Prepare dates (newest first)
  dates = start_date
    |> Date.range(end_date)
    |> Enum.to_list()
    |> Enum.reverse()

  # Initialize state and start tracking
  job_id = ProgressTracker.start_job(account_id, site_url, start_date, end_date, length(dates))
  state = State.new(job_id, account_id, site_url, dates, opts)

  # Execute sync pipeline
  final_state = Pipeline.execute(state)

  # Finalize and cleanup
  duration_ms = System.monotonic_time(:millisecond) - start_time
  finalize_sync(final_state, duration_ms)
end
```

## Testing Checklist

- [ ] Run `mix compile` - no warnings
- [ ] Run `mix test test/gsc_analytics/data_sources/gsc/core/sync_test.exs`
- [ ] Run `mix test test/gsc_analytics/data_sources/gsc/core/sync_progress_integration_test.exs`
- [ ] Verify chunk processing works
- [ ] Verify halt conditions work (empty threshold)
- [ ] Verify pause/resume works
- [ ] Verify stop command works
- [ ] Verify metrics are calculated correctly (including sub-requests/batches/api calls)

## Success Criteria

- ✅ All tests pass
- ✅ Pipeline module < 200 lines
- ✅ sync.ex reduced to ~200 lines (from 680)
- ✅ Clear orchestration flow
- ✅ Same behavior as before

## Files Changed

- `lib/gsc_analytics/data_sources/gsc/core/sync/pipeline.ex` (NEW)
- `lib/gsc_analytics/data_sources/gsc/core/sync.ex` (MODIFIED)

## Commit Message

```
refactor(sync): Extract pipeline orchestration

- Create Sync.Pipeline for chunk and phase coordination
- Handle pause/resume/stop commands
- Manage halt condition checking (empty threshold)
- Calculate and update sync metrics
- Delete 4 orchestration functions (~150 lines)

sync.ex is now a thin API layer (~200 lines) delegating to
Pipeline for execution.

Closes TICKET-005
```
