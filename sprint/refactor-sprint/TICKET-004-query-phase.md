# TICKET-004: Query Phase Extraction

**Priority:** 🟡 P2 Medium
**Estimate:** 5 hours
**Dependencies:** TICKET-001, TICKET-002
**Blocks:** TICKET-005

## Objective

Extract query fetching and storage logic into a dedicated `QueryPhase` module, including pagination coordination, streaming callbacks, and error handling.

## Why This Matters

The query phase is the most complex part of sync.ex (~160 lines) with callback management, pagination coordination, and multi-mode error handling. Extracting it will significantly simplify the main module.

## Implementation Steps

### 1. Create `lib/gsc_analytics/data_sources/gsc/core/sync/query_phase.ex`

```elixir
defmodule GscAnalytics.DataSources.GSC.Core.Sync.QueryPhase do
  @moduledoc """
  Query fetching and storage phase for sync operations.

  Handles:
  - Filtering dates with URLs
  - Coordinating with QueryPaginator for paginated fetching
  - Streaming callbacks for real-time processing
  - Partial result handling on errors
  - Query failure tracking
  """

  require Logger

  alias GscAnalytics.DataSources.GSC.Core.{Persistence, Config}
  alias GscAnalytics.DataSources.GSC.Support.QueryPaginator
  alias GscAnalytics.DataSources.GSC.Core.Sync.{State, ProgressTracker}

  @doc """
  Fetch and store queries for dates with URLs.

  Takes url_results from URL phase to determine which dates need query fetching.

  Returns `{query_results, api_calls, updated_state}` where:
  - query_results: %{date => %{row_count: int}}
  - api_calls: number of API calls made
  - updated_state: state with query_failures updated if errors occurred
  """
  def fetch_and_store(dates, url_results, state) do
    dates_with_urls = filter_dates_with_urls(url_results)

    if dates_with_urls == [] do
      Logger.info("No dates with URLs, skipping query fetch")
      {%{}, 0, state}
    else
      fetch_queries(dates_with_urls, state)
    end
  end

  # Private functions

  defp filter_dates_with_urls(url_results) do
    url_results
    |> Enum.filter(fn {_date, result} ->
      result.success and result.url_count > 0
    end)
    |> Enum.map(&elem(&1, 0))
  end

  defp fetch_queries(dates, state) do
    Logger.info("Fetching queries for #{length(dates)} dates with URLs")

    # Create streaming callback for real-time processing
    callback = create_callback(state)

    # Use QueryPaginator for paginated fetching
    case QueryPaginator.fetch_all_queries(
           state.account_id,
           state.site_url,
           dates,
           on_complete: callback,
           batch_size: Config.default_batch_size()
         ) do
      {:ok, results, api_calls, _batch_count} ->
        handle_success(results, api_calls, state)

      {:error, reason, partial_results, api_calls, _batch_count} ->
        handle_error(reason, dates, partial_results, api_calls, state)

      {:halt, reason, partial_results, api_calls, _batch_count} ->
        handle_halt(reason, dates, partial_results, api_calls, state)
    end
  end

  defp create_callback(state) do
    fn %{date: date, rows: rows, api_calls: api_calls} = payload ->
      http_batches = Map.get(payload, :http_batches, api_calls)

      # Process queries immediately
      query_count = Persistence.process_query_response(
        state.account_id,
        state.site_url,
        date,
        rows
      )

      # Update sync day status
      Persistence.mark_day_complete(
        state.account_id,
        state.site_url,
        date,
        query_count: query_count
      )

      # Store in Agent for later retrieval
      State.store_query_count(state, date, query_count)

      # Report progress
      ProgressTracker.report_queries_complete(
        state,
        date,
        query_count,
        api_calls,
        http_batches
      )

      :continue
    end
  end

  defp handle_success(results, api_calls, state) do
    results_with_counts = attach_query_counts(results, state)
    {results_with_counts, api_calls, state}
  end

  defp handle_error(reason, dates, partial_results, api_calls, state) do
    Logger.error("Query fetch failed: #{inspect(reason)}")

    failure_dates = identify_failed_dates(dates, partial_results)
    mark_failures(failure_dates, reason, state)

    {failure_date, error_message} = select_failure_details(failure_dates, reason)

    updated_state =
      state
      |> Map.put(:halted?, true)
      |> Map.put(:halt_reason, {:query_fetch_failed, reason})
      |> Map.put(:halt_error_message, error_message)
      |> Map.put(:halted_on_date, failure_date || state.halted_on_date)
      |> State.add_query_failures(failure_dates)

    results_with_counts = attach_query_counts(partial_results, state)
    {results_with_counts, api_calls, updated_state}
  end

  defp handle_halt(reason, dates, partial_results, api_calls, state) do
    Logger.warning("Query fetch halted: #{inspect(reason)}")

    failure_dates = identify_failed_dates(dates, partial_results)
    mark_failures(failure_dates, reason, state)

    {failure_date, error_message} = select_failure_details(failure_dates, reason)

    updated_state =
      state
      |> Map.put(:halted?, true)
      |> Map.put(:halt_reason, {:query_fetch_halted, reason})
      |> Map.put(:halt_error_message, error_message)
      |> Map.put(:halted_on_date, failure_date || state.halted_on_date)
      |> State.add_query_failures(failure_dates)

    results_with_counts = attach_query_counts(partial_results, state)
    {results_with_counts, api_calls, updated_state}
  end

  defp identify_failed_dates(dates, partial_results) when is_map(partial_results) do
    failure_dates = Enum.filter(dates, fn date ->
      case Map.get(partial_results, date) do
        nil -> true
        %{partial?: true} -> true
        _ -> false
      end
    end)

    # If no specific failures, all dates failed
    if failure_dates == [] do
      dates
    else
      failure_dates
    end
  end

  defp identify_failed_dates(dates, _), do: dates

  defp mark_failures(dates, reason, state) do
    error_message = format_error(reason)

    Enum.each(dates, fn date ->
      ProgressTracker.report_error(state, date, reason)

      Persistence.mark_day_failed(
        state.account_id,
        state.site_url,
        date,
        error_message
      )
    end)
  end

  defp attach_query_counts(results, state) do
    counts = State.take_query_counts(state)

    Enum.reduce(counts, results || %{}, fn {date, count}, acc ->
      Map.update(acc, date, %{row_count: count}, fn entry ->
        Map.put(entry, :row_count, count)
      end)
    end)
  end

  defp select_failure_details(failure_dates, reason) do
    failure_date = failure_dates |> Enum.sort() |> List.first()
    {failure_date, format_error(reason)}
  end

  defp format_error(reason) when is_atom(reason), do: to_string(reason)
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason) |> String.slice(0, 160)
end
```

### 2. Update `sync.ex` to Use QueryPhase

**Replace batch_fetch_queries (lines 270-337):**

```elixir
# DELETE THIS ENTIRE FUNCTION

# Replace calls with:
alias GscAnalytics.DataSources.GSC.Core.Sync.QueryPhase

# In process_date_chunk:
# OLD
{query_results, query_api_calls, state_after_queries} =
  batch_fetch_queries(dates, url_results, state_after_urls)

# NEW
{query_results, query_api_calls, state_after_queries} =
  QueryPhase.fetch_and_store(dates, url_results, state_after_urls)
```

### 3. Delete Helper Functions

Remove these functions (now in QueryPhase):
- `create_query_callback` (line 339)
- `handle_query_batch_error` (line 372)
- `handle_query_batch_halt` (line 383)
- `do_handle_query_batch_termination` (line 394)
- `append_query_failure_dates` (line 424)
- `identify_failed_query_dates` (line 435)
- `store_query_count` (line 452) - now in State module
- `attach_query_counts` (line 459) - now in QueryPhase

### 4. Simplify process_date_chunk Further

```elixir
defp process_date_chunk(dates, state) do
  case await_continue(state.job_id) do
    :stop ->
      {:halt, %{state | halted?: true, halt_reason: :stopped_by_user}}

    :continue ->
      # Phase 1: Fetch URLs
      {url_results, url_api_calls, state_after_urls} =
        URLPhase.fetch_and_store(dates, state)

      # Phase 2: Fetch queries
      {query_results, query_api_calls, state_after_queries} =
        QueryPhase.fetch_and_store(dates, url_results, state_after_urls)

      # Merge failure dates into URL results
      failure_dates = MapSet.to_list(state_after_queries.query_failures)

      url_results_with_failures =
        Enum.reduce(failure_dates, url_results, fn date, acc ->
          Map.update(acc, date, %{url_count: 0, success: false}, fn entry ->
            %{entry | success: false}
          end)
        end)

      # Update state and check halt conditions
      new_state =
        state_after_queries
        |> update_sync_metrics(
          url_results_with_failures,
          query_results,
          url_api_calls + query_api_calls
        )
        |> Map.update(:results, %{}, &Map.merge(&1, url_results_with_failures))
        |> check_empty_threshold(dates)

      if new_state.halted? do
        {:halt, new_state}
      else
        {:cont, new_state}
      end
  end
end
```

## Testing Checklist

- [ ] Run `mix compile` - no warnings
- [ ] Run `mix test test/gsc_analytics/data_sources/gsc/core/sync_test.exs`
- [ ] Run `mix test test/gsc_analytics/data_sources/gsc/core/sync_progress_integration_test.exs`
- [ ] Verify query counts are correct
- [ ] Verify partial results handling works
- [ ] Verify error propagation works
- [ ] Verify halt behavior works and populates `halt_error_message`/`halted_on_date`
- [ ] Verify query failures are tracked in state
- [ ] Verify Agent query counts are cleared between chunks

## Success Criteria

- ✅ All tests pass
- ✅ QueryPhase module < 200 lines
- ✅ sync.ex reduced by ~160 lines
- ✅ Clear separation: filter → fetch → process → report
- ✅ Same error handling behavior

## Files Changed

- `lib/gsc_analytics/data_sources/gsc/core/sync/query_phase.ex` (NEW)
- `lib/gsc_analytics/data_sources/gsc/core/sync.ex` (MODIFIED)

## Commit Message

```
refactor(sync): Extract query phase into dedicated module

- Create Sync.QueryPhase for query fetching and storage
- Handle pagination coordination with QueryPaginator
- Manage streaming callbacks and partial results
- Track query failures in state (remove Process dictionary)
- Consolidate error/halt handling
- Delete 8 helper functions (~160 lines)

Query phase now encapsulates all pagination, callback, and
error handling logic in a single module.

Closes TICKET-004
```
