# TICKET-003: URL Phase Extraction

**Priority:** 🟡 P2 Medium
**Estimate:** 4 hours
**Dependencies:** TICKET-001, TICKET-002
**Blocks:** TICKET-005

## Objective

Extract URL fetching and storage logic into a dedicated `URLPhase` module with clear separation between fetching and storing operations.

## Why This Matters

The `batch_fetch_urls` function currently mixes concerns: filtering, fetching, storing, and reporting. Extracting this into a phase module makes the logic easier to test and understand.

## Implementation Steps

### 1. Create `lib/gsc_analytics/data_sources/gsc/core/sync/url_phase.ex`

```elixir
defmodule GscAnalytics.DataSources.GSC.Core.Sync.URLPhase do
  @moduledoc """
  URL fetching and storage phase for sync operations.

  Handles:
  - Filtering already-synced dates
  - Fetching URLs from GSC API
  - Storing URL performance data
  - Progress reporting for URL phase
  """

  require Logger

  alias GscAnalytics.DataSources.GSC.Core.{Client, Persistence}
  alias GscAnalytics.DataSources.GSC.Core.Sync.{State, ProgressTracker}

  @doc """
  Fetch and store URLs for a list of dates.

  Returns `{url_results, api_calls, updated_state}` where:
  - url_results: %{date => %{url_count: int, success: bool}}
  - api_calls: number of API calls made
  - updated_state: state with incremented current_step
  """
  def fetch_and_store(dates, state) do
    dates_to_fetch = filter_dates(dates, state)

    if dates_to_fetch == [] do
      handle_all_skipped(dates, state)
    else
      fetch_urls(dates_to_fetch, state)
    end
  end

  # Private functions

  defp filter_dates(dates, state) do
    if state.opts[:force?] do
      dates
    else
      Enum.reject(dates, fn date ->
        Persistence.day_already_synced?(state.account_id, state.site_url, date)
      end)
    end
  end

  defp handle_all_skipped(dates, state) do
    Logger.info("All dates already synced, skipping URL fetch")

    updated_state =
      Enum.reduce(dates, state, fn date, acc ->
        step = acc.current_step + 1
        ProgressTracker.report_skipped(acc, date)
        %{acc | current_step: step}
      end)

    {%{}, 0, updated_state}
  end

  defp fetch_urls(dates, state) do
    Logger.info("Fetching URLs for #{length(dates)} dates")

    client = Application.get_env(:gsc_analytics, :gsc_client, Client)

    {results, updated_state} =
      dates
      |> Enum.reduce({%{}, state}, fn date, {results_acc, state_acc} ->
        result = fetch_url_for_date(client, date, state_acc)
        new_state = %{state_acc | current_step: state_acc.current_step + 1}
        {Map.put(results_acc, elem(result, 0), elem(result, 1)), new_state}
      end)

    api_calls = length(dates)
    {results, api_calls, updated_state}
  end

  defp fetch_url_for_date(client, date, state) do
    step = state.current_step + 1

    # Report start
    ProgressTracker.report_started(state, date)

    # Fetch from API
    case client.fetch_all_urls_for_date(state.account_id, state.site_url, date) do
      {:ok, response} ->
        handle_url_success(date, response, state)

      {:error, reason} ->
        handle_url_error(date, reason, state)
    end
  end

  defp handle_url_success(date, response, state) do
    # Store in database
    url_count = Persistence.process_url_response(
      state.account_id,
      state.site_url,
      date,
      response
    )

    # Mark day complete if no URLs
    if url_count == 0 do
      Persistence.mark_day_complete(
        state.account_id,
        state.site_url,
        date,
        url_count: 0,
        query_count: 0
      )
    end

    # Report progress
    ProgressTracker.report_urls_complete(state, date, url_count, 1)

    {date, %{url_count: url_count, success: true}}
  end

  defp handle_url_error(date, reason, state) do
    Logger.error("Failed to fetch URLs for #{date}: #{inspect(reason)}")
    ProgressTracker.report_error(state, date, reason)
    {date, %{url_count: 0, success: false}}
  end
end
```

### 2. Update `sync.ex` to Use URLPhase

**Replace batch_fetch_urls (lines 198-268):**

```elixir
# DELETE THIS ENTIRE FUNCTION

# Replace calls to batch_fetch_urls with:
alias GscAnalytics.DataSources.GSC.Core.Sync.URLPhase

# In process_date_chunk (line 163):
# OLD
{url_results, url_api_calls, state_after_urls} = batch_fetch_urls(dates, state)

# NEW
{url_results, url_api_calls, state_after_urls} = URLPhase.fetch_and_store(dates, state)
```

### 3. Simplify process_date_chunk

After extraction, the function should look cleaner:

```elixir
defp process_date_chunk(dates, state) do
  # Check for user commands (pause/stop)
  case await_continue(state.job_id) do
    :stop ->
      {:halt, %{state | halted?: true, halt_reason: :stopped_by_user}}

    :continue ->
      # Phase 1: Fetch URLs
      {url_results, url_api_calls, state_after_urls} =
        URLPhase.fetch_and_store(dates, state)

      # Phase 2: Fetch queries (existing)
      {query_results, query_api_calls, state_after_queries} =
        batch_fetch_queries(dates, url_results, state_after_urls)

      # Merge failure dates into URL results
      failure_dates = state_after_queries.query_failures |> Enum.to_list()

      url_results_with_failures =
        Enum.reduce(failure_dates, url_results, fn date, acc ->
          Map.update(acc, date, %{url_count: 0, success: false}, &Map.put(&1, :success, false))
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
- [ ] Verify URL counts still correct
- [ ] Verify skip behavior works (already-synced dates)
- [ ] Verify force? option works
- [ ] Verify error handling for failed URL fetches

## Success Criteria

- ✅ All tests pass
- ✅ URLPhase module < 200 lines
- ✅ sync.ex reduced by ~70 lines
- ✅ Clear separation: fetch → store → report
- ✅ Same behavior as before

## Files Changed

- `lib/gsc_analytics/data_sources/gsc/core/sync/url_phase.ex` (NEW)
- `lib/gsc_analytics/data_sources/gsc/core/sync.ex` (MODIFIED)

## Commit Message

```
refactor(sync): Extract URL phase into dedicated module

- Create Sync.URLPhase for URL fetching and storage
- Separate filtering, fetching, storing, and reporting
- Simplify process_date_chunk by ~70 lines
- Maintain identical behavior and test compatibility

URL phase now has clear boundaries: filter dates → fetch from
API → store in DB → report progress.

Closes TICKET-003
```
