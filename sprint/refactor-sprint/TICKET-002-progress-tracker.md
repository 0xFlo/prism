# TICKET-002: Progress Tracking Extraction

**Priority:** 🔥 P1 Critical
**Estimate:** 3 hours
**Dependencies:** TICKET-001
**Blocks:** TICKET-003, TICKET-004

## Objective

Extract progress reporting logic into a dedicated `ProgressTracker` module that wraps `SyncProgress` with consistent step number lookup and event formatting.

## Why This Matters

Progress tracking is scattered across batch functions and uses reconstructed step numbers. Centralizing this logic ensures consistent event ordering and makes it easier to verify backwards compatibility.

## Implementation Steps

### 1. Create `lib/gsc_analytics/data_sources/gsc/core/sync/progress_tracker.ex`

```elixir
defmodule GscAnalytics.DataSources.GSC.Core.Sync.ProgressTracker do
  @moduledoc """
  Centralized progress tracking for sync operations.

  Wraps SyncProgress with consistent step lookup and event formatting.
  Ensures all progress events include correct step numbers without
  runtime reconstruction.
  """

  alias GscAnalytics.DataSources.GSC.Core.Sync.State, as: SyncState
  alias GscAnalytics.DataSources.GSC.Support.SyncProgress

  @doc "Start a new sync job"
  def start_job(account_id, site_url, start_date, end_date, total_steps) do
    SyncProgress.start_job(%{
      account_id: account_id,
      site_url: site_url,
      start_date: start_date,
      end_date: end_date,
      total_steps: total_steps
    })
  end

  @doc "Report that a day's processing has started"
  def report_started(state, date) do
    step = SyncState.get_step(state, date)

    SyncProgress.day_started(state.job_id, %{
      date: date,
      step: step
    })
  end

  @doc "Report URL fetch completion"
  def report_urls_complete(state, date, url_count, api_calls) do
    step = SyncState.get_step(state, date)

    SyncProgress.day_completed(state.job_id, %{
      date: date,
      step: step,
      status: :ok,
      urls: url_count,
      rows: 0,
      query_batches: 0,
      query_sub_requests: 0,
      url_requests: api_calls,
      api_calls: api_calls
    })
  end

  @doc "Report query fetch completion"
  def report_queries_complete(state, date, query_count, api_calls, http_batches) do
    step = SyncState.get_step(state, date)

    SyncProgress.day_completed(state.job_id, %{
      date: date,
      step: step,
      status: :ok,
      urls: 0,
      rows: query_count,
      query_batches: http_batches,
      query_sub_requests: api_calls,
      url_requests: 0,
      api_calls: api_calls
    })
  end

  @doc "Report error for a day"
  def report_error(state, date, reason) do
    step = SyncState.get_step(state, date)

    SyncProgress.day_completed(state.job_id, %{
      date: date,
      step: step,
      status: :error,
      message: format_error(reason)
    })
  end

  @doc "Report that a day was skipped (already synced)"
  def report_skipped(state, date) do
    step = SyncState.get_step(state, date)

    SyncProgress.day_completed(state.job_id, %{
      date: date,
      step: step,
      status: :skipped
    })
  end

  @doc "Finish sync job with summary"
  def finish_job(state, duration_ms) do
    status = determine_status(state)
    {halt_reason, halt_on} = extract_halt_details(state.halt_reason)
    error_message = select_error_message(status, state)
    failed_on = if status == :failed, do: halt_on || state.halted_on_date, else: nil

    summary = %{
      days_processed: map_size(state.results),
      total_urls: state.total_urls,
      total_queries: state.total_queries,
      total_rows: state.total_queries,
      total_query_http_batches: state.total_query_http_batches,
      total_query_sub_requests: state.total_query_sub_requests,
      api_calls: state.api_calls,
      duration_ms: duration_ms,
      halt_reason: halt_reason,
      halt_on: halt_on || state.halted_on_date,
      failed_on: failed_on,
      error: error_message
    }

    SyncProgress.finish_job(state.job_id, %{
      status: status,
      summary: summary,
      error: error_message
    })

    summary
  end

  # Private helpers

  defp determine_status(state) do
    cond do
      state.halt_reason == :stopped_by_user -> :cancelled
      match?({:query_fetch_failed, _}, state.halt_reason) -> :failed
      state.halt_reason -> :completed_with_warnings
      true -> :completed
    end
  end

  defp extract_halt_details({:empty_threshold, date}), do: {:empty_threshold, date}
  defp extract_halt_details(other), do: {other, nil}

  defp select_error_message(:failed, state),
    do: state.halt_error_message || format_error(state.halt_reason)

  defp select_error_message(_status, state), do: state.halt_error_message

  defp format_error(reason) when is_atom(reason), do: to_string(reason)
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason) |> String.slice(0, 160)
end
```

### 2. Update `sync.ex` to Use ProgressTracker

**Replace start_sync_job (line 567):**
```elixir
# OLD
defp start_sync_job(account_id, site_url, start_date, end_date, total_steps) do
  SyncProgress.start_job(%{...})
end

# NEW
alias GscAnalytics.DataSources.GSC.Core.Sync.ProgressTracker

# In sync_date_range, replace:
job_id = start_sync_job(account_id, site_url, start_date, end_date, length(dates))

# With:
job_id = ProgressTracker.start_job(account_id, site_url, start_date, end_date, length(dates))
```

**Replace report_day_started (line 577):**
```elixir
# OLD
defp report_day_started(job_id, date, step) do
  SyncProgress.day_started(job_id, %{...})
end

# NEW - Remove this function, call ProgressTracker directly
ProgressTracker.report_started(state, date)
```

**Replace report_day_progress (line 584):**
```elixir
# OLD
defp report_day_progress(job_id, date, step, type, count, api_calls, http_batches) do
  # Complex conditional logic
end

# NEW - Replace calls with specific methods:
# For URL completion (line 252):
ProgressTracker.report_urls_complete(state, date, url_count, 1)

# For query completion (line 358-366):
ProgressTracker.report_queries_complete(
  state,
  date,
  query_count,
  api_calls,
  http_batches
)
```

**Replace report_day_error (line 598):**
```elixir
# OLD
defp report_day_error(job_id, date, step, reason) do
  SyncProgress.day_completed(job_id, %{...})
end

# NEW
ProgressTracker.report_error(state, date, reason)
```

**Replace report_day_skipped (line 607):**
```elixir
# OLD
defp report_day_skipped(job_id, date, step) do
  SyncProgress.day_completed(job_id, %{...})
end

# NEW
ProgressTracker.report_skipped(state, date)
```

**Simplify finalize_sync (line 615):**
```elixir
# OLD (lines 615-663)
defp finalize_sync(state, duration_ms) do
  status = cond do ... end
  {halt_reason, halt_on} = case ... end
  summary = %{...}
  # Log audit event
  SyncProgress.finish_job(...)
  {:ok, summary}
end

# NEW
defp finalize_sync(state, duration_ms) do
  # Log audit event (keep this)
  AuditLogger.log_sync_complete(...)

  # Delegate to ProgressTracker
  summary = ProgressTracker.finish_job(state, duration_ms)

  # Cleanup state
  SyncState.cleanup(state)

  {:ok, summary}
end
```

### 3. Update Callback in create_query_callback

**Line 358-366:**
```elixir
# OLD
step = Map.get(date_to_step, date, 0)
report_day_progress(
  state.job_id,
  date,
  step,
  :queries,
  query_count,
  api_calls,
  http_batches
)

# NEW
ProgressTracker.report_queries_complete(
  state,
  date,
  query_count,
  api_calls,
  http_batches
)
```

### 4. Update batch_fetch_urls

**Lines 209-213:**
```elixir
# OLD
updated_state =
  Enum.reduce(dates, state, fn date, acc ->
    step = acc.current_step + 1
    report_day_skipped(acc.job_id, date, step)
    %{acc | current_step: step}
  end)

# NEW
updated_state =
  Enum.reduce(dates, state, fn date, acc ->
    step = acc.current_step + 1
    ProgressTracker.report_skipped(acc, date)
    %{acc | current_step: step}
  end)
```

**Lines 226-252:**
```elixir
# OLD
step = state_acc.current_step + 1
report_day_started(state_acc.job_id, date, step)
# ... fetch logic ...
report_day_progress(state_acc.job_id, date, step, :urls, url_count, 1, 0)

# NEW
step = state_acc.current_step + 1
ProgressTracker.report_started(state_acc, date)
# ... fetch logic ...
ProgressTracker.report_urls_complete(state_acc, date, url_count, 1)
```

### 5. Remove date_to_step Mapping Logic

**Delete lines 284-296** (no longer needed):
```elixir
# DELETE THIS - step numbers now pre-calculated in SyncState
date_to_step =
  dates_with_urls
  |> Enum.reduce(%{}, fn date, acc ->
    step = Enum.find_index(state.dates, &(&1 == date)) |> ...
    Map.put(acc, date, step)
  end)
```

**Update create_query_callback call (line 299):**
```elixir
# OLD
callback = create_query_callback(state, date_to_step)

# NEW
callback = create_query_callback(state)
```

**Update create_query_callback signature (line 339):**
```elixir
# OLD
defp create_query_callback(state, date_to_step) do

# NEW
defp create_query_callback(state) do
```

**Update handle_query_batch_* calls:**
```elixir
# OLD (lines 314, 324, remove date_to_step parameter)
handle_query_batch_error(state, reason, dates_with_urls, date_to_step, partial_results)

# NEW
handle_query_batch_error(state, reason, dates_with_urls, partial_results)
```

**Update function signatures (lines 372, 383, 394):**
```elixir
# OLD
defp handle_query_batch_error(state, reason, dates, date_to_step, partial_results)

# NEW
defp handle_query_batch_error(state, reason, dates, partial_results)
```

**Update error reporting in do_handle_query_batch_termination (line 406):**
```elixir
# OLD
step = Map.get(date_to_step, date, state.current_step)
report_day_error(state.job_id, date, step, reason)

# NEW
ProgressTracker.report_error(state, date, reason)
```

### 6. Remove Old Progress Helper Functions

Delete these functions (now in ProgressTracker):
- `start_sync_job` (line 567)
- `report_day_started` (line 577)
- `report_day_progress` (line 584)
- `report_day_error` (line 598)
- `report_day_skipped` (line 607)

## Testing Checklist

- [ ] Run `mix compile` - no warnings
- [ ] Run `mix test test/gsc_analytics/data_sources/gsc/core/sync_test.exs`
- [ ] Run `mix test test/gsc_analytics/data_sources/gsc/core/sync_progress_integration_test.exs`
- [ ] Verify step numbers are correct (integration tests check this)
- [ ] Verify skipped days report correct steps
- [ ] Verify error reporting includes correct steps and messages
- [ ] Verify final summary still contains rows/sub-request/batch totals

## Success Criteria

- ✅ All tests pass (especially sync_progress_integration_test.exs)
- ✅ No step number reconstruction (no Enum.find_index)
- ✅ All progress events have correct step numbers
- ✅ Same event sequence as before
- ✅ sync.ex reduced by ~100 lines

## Files Changed

- `lib/gsc_analytics/data_sources/gsc/core/sync/progress_tracker.ex` (NEW)
- `lib/gsc_analytics/data_sources/gsc/core/sync.ex` (MODIFIED)

## Commit Message

```
refactor(sync): Extract progress tracking into ProgressTracker

- Create Sync.ProgressTracker module for centralized reporting
- Remove step number reconstruction (use pre-calculated map)
- Simplify progress reporting with explicit methods
- Remove date_to_step mapping logic (now in SyncState)
- Delete 5 private helper functions (~100 lines)

Progress events now use pre-calculated step numbers and have
consistent formatting through dedicated methods.

Closes TICKET-002
```
