# Ticket #009: Move Aggregation to Database with DATE_TRUNC

**Status**: ⏳ Blocked (awaiting #004-#008)
**Estimate**: 6 hours
**Priority**: 🟢 High Impact
**Phase**: 3 (Performance Optimization)
**Dependencies**: #002-#008 (Dashboard decomposition complete)

---

## Problem Statement

`TimeSeriesAggregator` currently loads thousands of daily rows into memory and groups them with `Enum.group_by`, which:
- Loads all data into BEAM memory
- Performs aggregation in Elixir
- Doesn't scale well (10K+ rows = performance hit)
- Duplicates work the database could do efficiently

**Files**:
- `lib/gsc_analytics/analytics/time_series_aggregator.ex:361-449` (site aggregates)
- `lib/gsc_analytics/analytics/time_series_aggregator.ex:275-308` (URL group aggregates)

---

## Solution

Replace in-memory grouping with PostgreSQL `DATE_TRUNC` for database-side aggregation.

### Benefits
- 2-5x performance improvement on large datasets
- Constant memory usage regardless of dataset size
- Cleaner code (remove ~60 lines of grouping logic)
- Leverages PostgreSQL's optimized aggregation

---

## Acceptance Criteria

- [ ] Weekly aggregation uses `DATE_TRUNC('week', date)` in database
- [ ] Monthly aggregation uses `DATE_TRUNC('month', date)` in database
- [ ] Returns same data structure as before (backward compatible)
- [ ] `date` field returns `Date` struct (not `NaiveDateTime`)
- [ ] `period_end` field calculated correctly (Sunday for weeks, last day for months)
- [ ] Weekly dates are Mondays (ISO 8601)
- [ ] All tests pass
- [ ] Performance benchmark shows >= 2x improvement
- [ ] No regression in chart rendering

---

## Current Notes

- Blocked until Dashboard cleanup (ticket #008) lands so that the new PeriodAggregator can plug into the slimmer contexts without reintroducing legacy helpers.
- Benchmark harness from ticket #010 will reuse the aggregation endpoints; plan sequence accordingly once unblocked.

---

## Implementation Tasks

### Task 1: Create PeriodAggregator module (2h)
**File**: `lib/gsc_analytics/analytics/period_aggregator.ex`

```elixir
defmodule GscAnalytics.Analytics.PeriodAggregator do
  @moduledoc """
  Database-side aggregation of time series data into periods.

  Uses PostgreSQL DATE_TRUNC for efficient grouping, avoiding in-memory
  aggregation of large datasets.
  """

  import Ecto.Query
  alias GscAnalytics.Schemas.TimeSeries

  @doc """
  Aggregates a base query by the specified period.

  ## Parameters
    - base_query: Ecto query for TimeSeries
    - period: :daily, :weekly, or :monthly
    - opts: Options map

  ## Returns
    List of aggregated metrics with date, period_end, and metrics
  """
  def aggregate(base_query, period, opts \\ %{})

  def aggregate(base_query, :daily, _opts) do
    # No grouping needed for daily
    base_query
    |> order_by([ts], asc: ts.date)
    |> select([ts], %{
      date: ts.date,
      clicks: sum(ts.clicks),
      impressions: sum(ts.impressions),
      ctr: fragment("SUM(?)::float / NULLIF(SUM(?), 0)", ts.clicks, ts.impressions),
      position: fragment("SUM(? * ?) / NULLIF(SUM(?), 0)", ts.position, ts.impressions, ts.impressions)
    })
  end

  def aggregate(base_query, :weekly, _opts) do
    base_query
    |> group_by([ts], fragment("DATE_TRUNC('week', ?)::date", ts.date))
    |> order_by([ts], fragment("DATE_TRUNC('week', ?)::date", ts.date))
    |> select([ts], %{
      # Monday (PostgreSQL week starts on Monday by default)
      date: type(fragment("DATE_TRUNC('week', ?)", ts.date), :date),
      # Sunday = week start + 6 days
      period_end: type(
        fragment("(DATE_TRUNC('week', ?) + INTERVAL '6 days')::date", ts.date),
        :date
      ),
      clicks: sum(ts.clicks),
      impressions: sum(ts.impressions),
      ctr: fragment("SUM(?)::float / NULLIF(SUM(?), 0)", ts.clicks, ts.impressions),
      position: fragment("SUM(? * ?) / NULLIF(SUM(?), 0)", ts.position, ts.impressions, ts.impressions)
    })
  end

  def aggregate(base_query, :monthly, _opts) do
    base_query
    |> group_by([ts], fragment("DATE_TRUNC('month', ?)::date", ts.date))
    |> order_by([ts], fragment("DATE_TRUNC('month', ?)::date", ts.date))
    |> select([ts], %{
      # First day of month
      date: type(fragment("DATE_TRUNC('month', ?)", ts.date), :date),
      # Last day of month (first day of next month - 1 day)
      period_end: type(
        fragment("(DATE_TRUNC('month', ?) + INTERVAL '1 month' - INTERVAL '1 day')::date", ts.date),
        :date
      ),
      clicks: sum(ts.clicks),
      impressions: sum(ts.impressions),
      ctr: fragment("SUM(?)::float / NULLIF(SUM(?), 0)", ts.clicks, ts.impressions),
      position: fragment("SUM(? * ?) / NULLIF(SUM(?), 0)", ts.position, ts.impressions, ts.impressions)
    })
  end
end
```

### Task 2: Replace site aggregate functions in TimeSeriesAggregator (1.5h)
**File**: `lib/gsc_analytics/analytics/time_series_aggregator.ex`

```elixir
# Replace fetch_site_aggregate_by_week/2 (lines 361-393)
def fetch_site_aggregate_by_week(weeks \\ 12, opts \\ %{}) do
  days = weeks * 7
  start_date = Date.add(Date.utc_today(), -days)
  account_id = Map.get(opts, :account_id)

  base_query =
    from ts in TimeSeries,
      where: ts.date >= ^start_date

  base_query
  |> maybe_filter_account(account_id)
  |> PeriodAggregator.aggregate(:weekly)
  |> Repo.all()
end

# Replace fetch_site_aggregate_by_month/2 (lines 416-449)
def fetch_site_aggregate_by_month(months \\ 6, opts \\ %{}) do
  days = months * 31
  start_date = Date.add(Date.utc_today(), -days)
  account_id = Map.get(opts, :account_id)

  base_query =
    from ts in TimeSeries,
      where: ts.date >= ^start_date

  base_query
  |> maybe_filter_account(account_id)
  |> PeriodAggregator.aggregate(:monthly)
  |> Repo.all()
end
```

**Lines removed**: ~70 lines of in-memory grouping code

### Task 3: Replace URL group aggregate functions (1h)
**File**: `lib/gsc_analytics/analytics/time_series_aggregator.ex`

```elixir
# Replace aggregate_group_by_week/2 (lines 275-288)
def aggregate_group_by_week(urls, opts \\ %{}) when is_list(urls) do
  start_date = Map.get(opts, :start_date)
  account_id = Map.get(opts, :account_id)

  base_query =
    from ts in TimeSeries,
      where: ts.url in ^urls

  base_query
  |> maybe_filter_start_date(start_date)
  |> maybe_filter_account(account_id)
  |> PeriodAggregator.aggregate(:weekly)
  |> Repo.all()
end

# Similar for aggregate_group_by_month/2
```

### Task 4: Add comprehensive tests (1h)
**File**: `test/gsc_analytics/analytics/period_aggregator_test.exs`

```elixir
defmodule GscAnalytics.Analytics.PeriodAggregatorTest do
  use GscAnalytics.DataCase
  alias GscAnalytics.Analytics.PeriodAggregator
  import Ecto.Query

  describe "aggregate/3 with :weekly" do
    test "groups by week with Monday as start" do
      # Insert daily data across a week
      # Wed Jan 15, Thu Jan 16, Fri Jan 17
      # Should group to week starting Mon Jan 13

      base_query = from(ts in TimeSeries)
      result = base_query |> PeriodAggregator.aggregate(:weekly) |> Repo.all()

      assert [week] = result
      assert %Date{} = week.date
      assert Date.day_of_week(week.date) == 1  # Monday
      assert week.date == ~D[2025-01-13]
      assert week.period_end == ~D[2025-01-19]  # Sunday
    end

    test "returns Date structs not NaiveDateTime" do
      base_query = from(ts in TimeSeries)
      result = base_query |> PeriodAggregator.aggregate(:weekly) |> Repo.all()

      assert Enum.all?(result, fn week ->
        match?(%Date{}, week.date) && match?(%Date{}, week.period_end)
      end)
    end

    test "aggregates metrics correctly across week" do
      # Insert: Mon 100 clicks, Tue 150 clicks, Wed 200 clicks
      # Expected: 450 total clicks for week
    end

    test "calculates weighted average position" do
      # Insert: Day 1: position 5.0, 100 impressions
      #         Day 2: position 10.0, 200 impressions
      # Expected: (5*100 + 10*200) / 300 = 8.33
    end
  end

  describe "aggregate/3 with :monthly" do
    test "groups by month with 1st as start and last day as end" do
      # Insert data across January
      # Should group to month starting Jan 1, ending Jan 31

      base_query = from(ts in TimeSeries)
      result = base_query |> PeriodAggregator.aggregate(:monthly) |> Repo.all()

      assert [month] = result
      assert month.date.day == 1
      assert month.period_end.day == 31
    end
  end

  describe "aggregate/3 with :daily" do
    test "returns daily data unchanged" do
      # Should not group, just return daily rows
    end
  end
end
```

### Task 5: Integration testing and verification (30m)
- [ ] Run full test suite
- [ ] Manual verification: Check charts render correctly
- [ ] Verify weekly chart shows Monday dates
- [ ] Verify monthly chart shows 1st of month dates
- [ ] Verify period labels display correctly

---

## Testing Strategy

### Performance Benchmark
**File**: `test/gsc_analytics/analytics/period_aggregator_benchmark.exs`

```elixir
# Before (in-memory):
{time_before, _} = :timer.tc(fn ->
  # Old fetch_site_aggregate_by_week using Enum.group_by
end)

# After (database):
{time_after, _} = :timer.tc(fn ->
  # New PeriodAggregator.aggregate(:weekly)
end)

improvement = (time_before - time_after) / time_before * 100
assert improvement >= 50  # At least 2x faster
```

### Type Verification Tests
```elixir
test "date field returns Date struct not NaiveDateTime" do
  result = PeriodAggregator.aggregate(base_query, :weekly) |> Repo.all()

  assert [week | _] = result
  assert %Date{} = week.date
  refute match?(%NaiveDateTime{}, week.date)
end
```

---

## Migration Checklist

- [ ] Create `period_aggregator.ex`
- [ ] Add tests for `PeriodAggregator`
- [ ] Replace `fetch_site_aggregate_by_week/2` implementation
- [ ] Replace `fetch_site_aggregate_by_month/2` implementation
- [ ] Replace `aggregate_group_by_week/2` implementation
- [ ] Replace `aggregate_group_by_month/2` implementation
- [ ] Remove in-memory grouping helpers
- [ ] Run unit tests: `mix test test/gsc_analytics/analytics/`
- [ ] Run integration tests: `mix test test/gsc_analytics_web/live/`
- [ ] Performance benchmark: verify 2x+ improvement
- [ ] Manual verification:
  - [ ] Dashboard weekly chart loads
  - [ ] Dashboard monthly chart loads
  - [ ] URL detail weekly chart loads
  - [ ] URL detail monthly chart loads
  - [ ] Verify dates are Mondays for weekly
  - [ ] Verify dates are 1st for monthly
  - [ ] Verify period labels show correct ranges
- [ ] Commit: "perf: move time series aggregation to database with DATE_TRUNC"

---

## Performance Targets

### Before (In-Memory)
```
10,000 daily rows → weekly aggregation: ~250ms
10,000 daily rows → monthly aggregation: ~300ms
Memory: Loads all rows into BEAM
```

### After (Database)
```
10,000 daily rows → weekly aggregation: ~80ms (3x faster)
10,000 daily rows → monthly aggregation: ~90ms (3.3x faster)
Memory: Constant (only aggregated rows loaded)
```

---

## Rollback Plan

If performance doesn't improve or charts break:
1. Revert to in-memory grouping
2. Keep `PeriodAggregator` for future refinement
3. Investigate PostgreSQL query plan
4. Consider adding indexes on TimeSeries.date

---

## Related Files

**Created**:
- `lib/gsc_analytics/analytics/period_aggregator.ex`
- `test/gsc_analytics/analytics/period_aggregator_test.exs`

**Modified**:
- `lib/gsc_analytics/analytics/time_series_aggregator.ex` (replace 6 functions, remove ~70 lines)

---

## Notes

- PostgreSQL `DATE_TRUNC('week')` starts weeks on Monday by default (ISO 8601)
- Must cast to `::date` to get Date struct instead of timestamp
- Weighted position formula must remain: `SUM(position * impressions) / SUM(impressions)`
- CTR formula: `SUM(clicks)::float / NULLIF(SUM(impressions), 0)`
- This is the highest-impact performance optimization in the sprint
- Critical: Test thoroughly - affects all chart views
