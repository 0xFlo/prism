# Ticket 019 — Unified Aggregation Pipeline Refactor

**Status**: 📋 Pending
**Estimate**: 4h
**Actual**: TBD
**Priority**: 🔥 Critical
**Dependencies**: #018 (TimeSeriesData domain type)

## Problem

Our `TimeSeriesAggregator` module has significant code duplication:

1. **Repeated aggregation logic**: Daily, weekly, and monthly aggregations follow identical patterns but duplicate the code
2. **Scattered sorting**: Even after #018, we still have 8 calls to `Enum.sort_by` across different functions
3. **No abstraction**: The pattern of "group by period → aggregate metrics → sort" is repeated 6+ times
4. **Hard to maintain**: Bug fixes or enhancements require updating multiple nearly-identical functions
5. **Testing burden**: Each function needs separate tests despite sharing logic

### Current Duplication

All of these follow the same pattern:
- `aggregate_group_by_day/2`
- `aggregate_group_by_week/2`
- `aggregate_group_by_month/2`
- `fetch_site_aggregate_by_week/2`
- `fetch_site_aggregate_by_month/2`
- `aggregate_by_week/3` (legacy single-URL)
- `aggregate_by_month/3` (legacy single-URL)

## Proposed Approach

Create a **single aggregation pipeline** that handles all time periods through parameterization.

### 1. Core Pipeline Function

```elixir
@doc """
Single aggregation pipeline for all time period groupings.
Eliminates code duplication across daily/weekly/monthly aggregations.

## Parameters
  - daily_data: Raw daily time series data
  - grouping_fn: Function to determine period bucket (day/week/month)
  - period_end_fn: Function to calculate period end date (nil for daily)

## Returns
  List of TimeSeriesData structs, sorted chronologically
"""
defp aggregate_pipeline(daily_data, grouping_fn, period_end_fn) do
  daily_data
  |> Enum.group_by(grouping_fn)
  |> Enum.map(fn {period_start, entries} ->
    metrics = aggregate_entries(entries)

    %TimeSeriesData{
      date: period_start,
      period_end: period_end_fn.(period_start),
      clicks: metrics.clicks,
      impressions: metrics.impressions,
      ctr: metrics.ctr,
      position: metrics.position
    }
  end)
  |> TimeSeriesData.sort_chronologically()  # Single place for sorting!
end
```

### 2. Refactored Public Functions

```elixir
def aggregate_group_by_day(urls, opts) when is_list(urls) do
  fetch_daily_data_for_urls(urls, opts[:start_date], opts)
  |> aggregate_pipeline(
    & &1.date,              # Group by exact date
    fn _ -> nil end         # No period_end for daily
  )
end

def aggregate_group_by_week(urls, opts) when is_list(urls) do
  fetch_daily_data_for_urls(urls, opts[:start_date], opts)
  |> aggregate_pipeline(
    &week_start_date/1,     # Group by week start (Monday)
    &week_end_date/1        # Calculate week end (Sunday)
  )
end

def aggregate_group_by_month(urls, opts) when is_list(urls) do
  fetch_daily_data_for_urls(urls, opts[:start_date], opts)
  |> aggregate_pipeline(
    &month_start_date/1,    # Group by month start (1st)
    &month_end_date/1       # Calculate month end (last day)
  )
end
```

### 3. Site-Wide Aggregations

```elixir
def fetch_site_aggregate_by_week(weeks \\ 12, opts \\ %{}) do
  days = weeks * 7
  start_date = Date.add(Date.utc_today(), -days)

  fetch_site_daily_data(start_date, opts)
  |> aggregate_pipeline(&week_start_date/1, &week_end_date/1)
end

def fetch_site_aggregate_by_month(months \\ 6, opts \\ %{}) do
  days = months * 31
  start_date = Date.add(Date.utc_today(), -days)

  fetch_site_daily_data(start_date, opts)
  |> aggregate_pipeline(&month_start_date/1, &month_end_date/1)
end
```

## Migration Strategy

### Phase 1: Add Pipeline Function
1. Create `aggregate_pipeline/3` private function
2. Keep existing functions intact for now
3. Add tests for the new pipeline

### Phase 2: Migrate Functions One-by-One
1. Start with `aggregate_group_by_day/2` (simplest)
2. Migrate `aggregate_group_by_week/2`
3. Migrate `aggregate_group_by_month/2`
4. Migrate site-wide aggregation functions
5. Run full test suite after each migration

### Phase 3: Cleanup
1. Remove old implementations if parallel versions exist
2. Update tests to focus on pipeline behavior
3. Remove all manual `Enum.sort_by` calls (delegated to `TimeSeriesData`)

## Acceptance Criteria

- [ ] `aggregate_pipeline/3` private function created and tested
- [ ] All group aggregation functions use the pipeline
- [ ] All site-wide aggregation functions use the pipeline
- [ ] All functions return `TimeSeriesData` structs
- [ ] All manual sorting removed (delegated to `TimeSeriesData.sort_chronologically/1`)
- [ ] Full test suite passes (mix test)
- [ ] No performance regressions (benchmark before/after)
- [ ] Code coverage maintained or improved
- [ ] Documentation updated to explain the pipeline pattern

## Test Plan

Update `/test/gsc_analytics/analytics/time_series_aggregator_test.exs`:

```elixir
describe "aggregate_pipeline/3" do
  test "groups data by provided grouping function" do
    daily_data = [
      %{date: ~D[2025-01-15], clicks: 100, impressions: 1000, ctr: 0.1, position: 5.0},
      %{date: ~D[2025-01-16], clicks: 110, impressions: 1100, ctr: 0.1, position: 5.5}
    ]

    # Group all into single bucket
    result = aggregate_pipeline(daily_data, fn _ -> :all end, fn _ -> nil end)

    assert length(result) == 1
    assert [%TimeSeriesData{clicks: 210}] = result
  end

  test "returns TimeSeriesData structs" do
    daily_data = [%{date: ~D[2025-01-15], clicks: 100, impressions: 1000, ctr: 0.1, position: 5.0}]

    result = aggregate_pipeline(daily_data, & &1.date, fn _ -> nil end)

    assert [%TimeSeriesData{}] = result
  end

  test "automatically sorts chronologically" do
    # Intentionally unsorted input
    daily_data = [
      %{date: ~D[2025-01-16], clicks: 110, impressions: 1100, ctr: 0.1, position: 5.5},
      %{date: ~D[2025-01-14], clicks: 90, impressions: 900, ctr: 0.1, position: 6.0},
      %{date: ~D[2025-01-15], clicks: 100, impressions: 1000, ctr: 0.1, position: 5.0}
    ]

    result = aggregate_pipeline(daily_data, & &1.date, fn _ -> nil end)
    dates = Enum.map(result, & &1.date)

    assert dates == [~D[2025-01-14], ~D[2025-01-15], ~D[2025-01-16]]
  end
end

describe "refactored aggregation functions" do
  test "aggregate_group_by_week returns TimeSeriesData with period_end" do
    # Setup test data...
    result = TimeSeriesAggregator.aggregate_group_by_week(urls, %{start_date: ~D[2025-01-01]})

    assert [%TimeSeriesData{} | _] = result
    assert Enum.all?(result, fn ts -> not is_nil(ts.period_end) end)
  end

  # Similar tests for other functions...
end
```

## Performance Benchmarking

Before and after refactoring, measure:

```elixir
# In IEx
:timer.tc(fn ->
  TimeSeriesAggregator.aggregate_group_by_week(
    ["https://example.com/page1", "https://example.com/page2"],
    %{start_date: ~D[2024-01-01], account_id: 1}
  )
end)
```

Target: No performance regression (ideally 5-10% improvement from cleaner code paths).

## Estimate

**4 hours total**
- 1.5h: Create pipeline function and initial integration
- 1.5h: Migrate all existing functions to use pipeline
- 0.5h: Update tests and verify coverage
- 0.5h: Performance benchmarking and documentation

## Rollback Plan

If issues arise:
1. Revert changes to `TimeSeriesAggregator` module
2. Keep `TimeSeriesData` module (already stable from #018)
3. Re-apply tactical fix from Sprint 2 if needed
4. Pause sprint to diagnose issues

## Success Metrics

- Code reduction: ~100+ lines eliminated through pipeline abstraction
- Single source of truth for sorting (in `TimeSeriesData`)
- All tests pass with no performance regressions
- Easier to add new aggregation periods in the future
