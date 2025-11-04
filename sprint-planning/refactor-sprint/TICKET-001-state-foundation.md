# TICKET-001: Setup & State Foundation

**Priority:** 🔥 P1 Critical
**Estimate:** 4 hours
**Dependencies:** None
**Blocks:** All other tickets

## Objective

Create the `SyncState` struct with explicit state management and replace the Process dictionary with an Agent-based metrics store.

## Why This First?

This is the foundation for all other refactorings. The Process dictionary anti-pattern must be eliminated before we can cleanly extract phase modules.

## Implementation Steps

### 1. Create `lib/gsc_analytics/data_sources/gsc/core/sync/state.ex`

```elixir
defmodule GscAnalytics.DataSources.GSC.Core.Sync.State do
  @moduledoc """
  Sync state management with explicit structure and transitions.

  Replaces the ad-hoc state map with typed struct and provides
  Agent-based metrics storage for cross-process communication.
  """

  defstruct [
    :job_id,
    :account_id,
    :site_url,
    :dates,
    :date_steps,               # NEW: %{date => step_number}
    :metrics_agent,            # NEW: Agent PID for query counts
    :results,                  # %{date => %{url_count:, success:, row_count:}}
    :query_failures,           # NEW: MapSet of dates with query failures
    :empty_streak,
    :has_seen_data?,
    :total_urls,
    :total_queries,
    :total_query_sub_requests, # NEW: Preserve sub-request metrics
    :total_query_http_batches, # NEW: Preserve HTTP batch metrics
    :api_calls,
    :halted?,
    :halt_reason,
    :halt_error_message,       # NEW: Track formatted error
    :halted_on_date,           # NEW: Track date of failure
    :current_step,
    :total_steps,
    :opts
  ]

  @doc "Create new sync state with initialized Agent"
  def new(job_id, account_id, site_url, dates, opts) do
    {:ok, agent} = Agent.start_link(fn -> %{} end)

    # Pre-calculate step numbers
    date_steps = dates
      |> Enum.with_index(1)
      |> Map.new()

    %__MODULE__{
      job_id: job_id,
      account_id: account_id,
      site_url: site_url,
      dates: dates,
      date_steps: date_steps,
      metrics_agent: agent,
      results: %{},
      query_failures: MapSet.new(),
      empty_streak: 0,
      has_seen_data?: false,
      total_urls: 0,
      total_queries: 0,
      total_query_sub_requests: 0,
      total_query_http_batches: 0,
      api_calls: 0,
      halted?: false,
      halt_reason: nil,
      halt_error_message: nil,
      halted_on_date: nil,
      current_step: 0,
      total_steps: length(dates),
      opts: opts
    }
  end

  @doc "Get step number for a date"
  def get_step(%__MODULE__{date_steps: steps}, date) do
    Map.fetch!(steps, date)
  end

  @doc "Store query count in Agent"
  def store_query_count(%__MODULE__{metrics_agent: agent}, date, count)
      when is_integer(count) and count >= 0 do
    Agent.update(agent, fn metrics ->
      Map.put(metrics, date, count)
    end)
  end

  def store_query_count(_, _, _), do: :ok

  @doc "Retrieve and clear query counts from Agent"
  def take_query_counts(%__MODULE__{metrics_agent: agent}) do
    Agent.get_and_update(agent, fn metrics -> {metrics, %{}} end)
  end

  @doc "Clean up Agent when sync completes"
  def cleanup(%__MODULE__{metrics_agent: agent}) do
    Agent.stop(agent, :normal)
  end

  @doc "Add query failure date"
  def add_query_failure(%__MODULE__{query_failures: failures} = state, date) do
    %{state | query_failures: MapSet.put(failures, date)}
  end

  @doc "Add multiple query failure dates"
  def add_query_failures(%__MODULE__{query_failures: failures} = state, dates) do
    %{state | query_failures: MapSet.union(failures, MapSet.new(dates))}
  end
end
```

### 2. Update `sync.ex` to Use SyncState

Replace the initialization in `sync_date_range/4`:

```elixir
# OLD (lines 59-75)
state = %{
  job_id: job_id,
  account_id: account_id,
  # ... 13 more fields
}

# NEW
alias GscAnalytics.DataSources.GSC.Core.Sync.State, as: SyncState

state = SyncState.new(job_id, account_id, site_url, dates, opts)
```

### 3. Replace Process Dictionary Calls

Update these functions:

**store_query_count (line 452):**
```elixir
# OLD
defp store_query_count(job_id, date, count) do
  key = {@query_count_store, job_id}
  Process.put(key, Map.put(Process.get(key, %{}), date, count))
end

# NEW
defp store_query_count(state, date, count) do
  SyncState.store_query_count(state, date, count)
end
```

**attach_query_counts (line 459):**
```elixir
# OLD
defp attach_query_counts(results, job_id) do
  key = {@query_count_store, job_id}
  counts = Process.get(key, %{})
  Process.delete(key)
  # ...
end

# NEW
defp attach_query_counts(results, state) do
  counts = SyncState.take_query_counts(state)
  # ... rest stays the same
end
```

**Update callback in create_query_callback (line 354):**
```elixir
# OLD
store_query_count(state.job_id, date, query_count)

# NEW
SyncState.store_query_count(state, date, query_count)
```

**Update batch_fetch_queries calls (lines 278, 310, 322, 334):**
```elixir
# OLD
{attach_query_counts(results, state.job_id), api_calls, state}

# NEW
{attach_query_counts(results, state), api_calls, state}
```

### 4. Add Cleanup in finalize_sync

```elixir
defp finalize_sync(state, duration_ms) do
  # ... existing finalization logic

  # NEW: Clean up Agent
  SyncState.cleanup(state)

  {:ok, summary}
end
```

### 5. Preserve Additional Metrics

When replacing the anonymous state map, ensure you continue to track:
- `total_query_sub_requests`
- `total_query_http_batches`
- `halt_error_message`
- `halted_on_date`

Update any call sites that previously updated these keys to use the struct fields so telemetry and summaries remain unchanged.

### 5. Update query_failure_dates Handling

**In process_date_chunk (line 169):**
```elixir
# OLD
{failure_dates_set, state_after_queries} =
  Map.pop(state_after_queries, :query_failure_dates, MapSet.new())

failure_dates = failure_dates_set |> Enum.to_list()

# NEW
failure_dates = state_after_queries.query_failures |> Enum.to_list()
```

**In append_query_failure_dates (line 424):**
```elixir
# OLD
defp append_query_failure_dates(state, dates) do
  combined =
    state
    |> Map.get(:query_failure_dates, MapSet.new())
    |> MapSet.union(MapSet.new(dates))
  Map.put(state, :query_failure_dates, combined)
end

# NEW
defp append_query_failure_dates(state, []), do: state

defp append_query_failure_dates(state, dates) do
  SyncState.add_query_failures(state, dates)
end
```

## Testing Checklist

- [ ] Run `mix compile` - no warnings
- [ ] Run `mix test test/gsc_analytics/data_sources/gsc/core/sync_test.exs`
- [ ] Run `mix test test/gsc_analytics/data_sources/gsc/core/sync_progress_integration_test.exs`
- [ ] Verify query counts still work (check test assertions)
- [ ] Verify Agent cleanup doesn't leak processes

## Success Criteria

- ✅ All tests pass
- ✅ No Process dictionary usage
- ✅ Agent properly cleaned up (no process leaks)
- ✅ Query counts still reported correctly
- ✅ Step numbers pre-calculated (no Enum.find_index)

## Rollback

If issues arise:
```bash
git checkout lib/gsc_analytics/data_sources/gsc/core/sync.ex
rm lib/gsc_analytics/data_sources/gsc/core/sync/state.ex
```

## Files Changed

- `lib/gsc_analytics/data_sources/gsc/core/sync/state.ex` (NEW)
- `lib/gsc_analytics/data_sources/gsc/core/sync.ex` (MODIFIED)

## Commit Message

```
refactor(sync): Replace Process dictionary with SyncState struct

- Create Sync.State module with explicit struct
- Add Agent-based metrics storage for query counts
- Pre-calculate date-to-step mapping
- Replace ad-hoc map with typed state
- Add proper cleanup for Agent processes

This eliminates the Process dictionary anti-pattern and provides
a foundation for extracting phase modules.

Closes TICKET-001
```
