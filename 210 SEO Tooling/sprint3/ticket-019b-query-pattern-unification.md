# Ticket 019b — Unified Database Query Pattern

**Status**: 📋 Pending
**Estimate**: 2h
**Actual**: TBD
**Priority**: 🟡 Medium (DRY improvement, not performance-critical)
**Dependencies**: #018 (TimeSeriesData), #019a (Database aggregation)

## Problem

After moving aggregation to the database (#019a), we still have code duplication across our query functions:

1. **Repeated query structure**: Daily, weekly, monthly queries follow identical patterns with slight variations
2. **Fragment duplication**: Same SQL fragments repeated (DATE_TRUNC, period_end calculations, weighted averages)
3. **Maintenance burden**: Changes to aggregation logic require updating multiple functions
4. **Testing overhead**: Each function needs separate tests despite sharing structure

### Current Pattern (After #019a)

All three functions share 90% of the same code:

```elixir
def aggregate_group_by_week(urls, opts) do
  TimeSeries
  |> where([ts], ts.url in ^urls)
  |> where([ts], ts.date >= ^start_date)
  |> maybe_filter_account(account_id)
  |> group_by([ts], fragment("DATE_TRUNC('week', ?)::date", ts.date))
  |> select([ts], %{...})  # 20 lines of aggregation fragments
  |> order_by([ts], asc: fragment("DATE_TRUNC('week', ?)", ts.date))
  |> Repo.all()
  |> TimeSeriesData.from_raw_data()
end

def aggregate_group_by_month(urls, opts) do
  # Almost identical, just 'month' instead of 'week'
end
```

## Proposed Approach

Create a **parameterized query builder** that handles all time periods through configuration.

### 1. Period Configuration Module

```elixir
defmodule GscAnalytics.Analytics.TimeSeriesAggregator.PeriodConfig do
  @moduledoc """
  Configuration for different aggregation periods.
  Defines SQL fragments and period calculations for each time granularity.
  """

  @type period_type :: :day | :week | :month

  @doc """
  Get configuration for a specific period type.
  """
  def config(:day) do
    %{
      group_by_fragment: "?",  # Group by exact date
      date_fragment: "?",
      period_end_fragment: "NULL",  # No period end for daily
      type: :day
    }
  end

  def config(:week) do
    %{
      group_by_fragment: "DATE_TRUNC('week', ?)::date",
      date_fragment: "DATE_TRUNC('week', ?)::date",
      period_end_fragment: "(DATE_TRUNC('week', ?)::date + INTERVAL '6 days')::date",
      type: :week
    }
  end

  def config(:month) do
    %{
      group_by_fragment: "DATE_TRUNC('month', ?)::date",
      date_fragment: "DATE_TRUNC('month', ?)::date",
      period_end_fragment: "(DATE_TRUNC('month', ?)::date + INTERVAL '1 month' - INTERVAL '1 day')::date",
      type: :month
    }
  end
end
```

### 2. Unified Query Builder

```elixir
@doc """
Build aggregation query for any time period using configuration.

## Parameters
  - urls: List of URLs to aggregate
  - period_type: :day | :week | :month
  - opts: Options including start_date, account_id

## Returns
  List of TimeSeriesData structs, aggregated and sorted

## Examples

    iex> build_aggregation_query(urls, :week, opts)
    [%TimeSeriesData{}, ...]
"""
defp build_aggregation_query(urls, period_type, opts) when is_list(urls) do
  start_date = Map.get(opts, :start_date)
  account_id = Map.get(opts, :account_id)
  config = PeriodConfig.config(period_type)

  TimeSeries
  |> where([ts], ts.url in ^urls)
  |> where([ts], ts.date >= ^start_date)
  |> maybe_filter_account(account_id)
  # Dynamic grouping based on period type
  |> group_by([ts], fragment(config.group_by_fragment, ts.date))
  # Dynamic select with period-specific fragments
  |> select([ts], %{
       date: fragment(config.date_fragment, ts.date),
       period_end: fragment(config.period_end_fragment, ts.date),
       clicks: sum(ts.clicks),
       impressions: sum(ts.impressions),
       position: fragment(
         "SUM(? * ?) / NULLIF(SUM(?), 0)",
         ts.position,
         ts.impressions,
         ts.impressions
       ),
       ctr: fragment(
         "SUM(?)::float / NULLIF(SUM(?), 0)",
         ts.clicks,
         ts.impressions
       )
     })
  |> order_by([ts], asc: fragment(config.group_by_fragment, ts.date))
  |> Repo.all()
  |> TimeSeriesData.from_raw_data()
end
```

### 3. Simplified Public Functions

```elixir
def aggregate_group_by_day(urls, opts \\ %{}) when is_list(urls) do
  build_aggregation_query(urls, :day, opts)
end

def aggregate_group_by_week(urls, opts \\ %{}) when is_list(urls) do
  build_aggregation_query(urls, :week, opts)
end

def aggregate_group_by_month(urls, opts \\ %{}) when is_list(urls) do
  build_aggregation_query(urls, :month, opts)
end

# Site-wide versions
def fetch_site_aggregate(days \\ 30, opts \\ %{}) do
  start_date = Date.add(Date.utc_today(), -days)
  opts = Map.put(opts, :start_date, start_date)

  build_site_aggregation_query(:day, opts)
end

def fetch_site_aggregate_by_week(weeks \\ 12, opts \\ %{}) do
  days = weeks * 7
  start_date = Date.add(Date.utc_today(), -days)
  opts = Map.put(opts, :start_date, start_date)

  build_site_aggregation_query(:week, opts)
end

def fetch_site_aggregate_by_month(months \\ 6, opts \\ %{}) do
  days = months * 31
  start_date = Date.add(Date.utc_today(), -days)
  opts = Map.put(opts, :start_date, start_date)

  build_site_aggregation_query(:month, opts)
end
```

### 4. Site-Wide Query Builder

```elixir
defp build_site_aggregation_query(period_type, opts) do
  start_date = Map.get(opts, :start_date)
  account_id = Map.get(opts, :account_id)
  config = PeriodConfig.config(period_type)

  TimeSeries
  |> where([ts], ts.date >= ^start_date)
  |> maybe_filter_account(account_id)
  |> group_by([ts], fragment(config.group_by_fragment, ts.date))
  |> select([ts], %{
       date: fragment(config.date_fragment, ts.date),
       period_end: fragment(config.period_end_fragment, ts.date),
       clicks: sum(ts.clicks),
       impressions: sum(ts.impressions),
       position: avg(ts.position),  # Simple average for site-wide
       ctr: fragment(
         "SUM(?)::float / NULLIF(SUM(?), 0)",
         ts.clicks,
         ts.impressions
       )
     })
  |> order_by([ts], asc: fragment(config.group_by_fragment, ts.date))
  |> Repo.all()
  |> TimeSeriesData.from_raw_data()
end
```

## Benefits

1. **DRY Compliance**: Single query builder for all time periods
2. **Easier to extend**: Adding quarterly/yearly is just adding config
3. **Easier to test**: Test the builder once, not each function
4. **Consistent behavior**: Same logic for all periods
5. **Maintainable**: Changes to aggregation update all periods

## Adding New Periods

Want quarterly aggregation? Just add config:

```elixir
def config(:quarter) do
  %{
    group_by_fragment: "DATE_TRUNC('quarter', ?)::date",
    date_fragment: "DATE_TRUNC('quarter', ?)::date",
    period_end_fragment: "(DATE_TRUNC('quarter', ?)::date + INTERVAL '3 months' - INTERVAL '1 day')::date",
    type: :quarter
  }
end

# Then add public function
def aggregate_group_by_quarter(urls, opts \\ %{}) when is_list(urls) do
  build_aggregation_query(urls, :quarter, opts)
end
```

That's it! No duplication of the 20-line aggregation logic.

## Migration Strategy

### Phase 0: Baseline & Safety Net
1. Capture explain plans + performance metrics for existing weekly/monthly functions (baseline).
2. Ensure regression tests from #019a comparison suite cover builder output (reuse fixtures).
3. Identify all old aggregation functions slated for deletion once builder is in place.

### Phase 1: Create Query Builder
1. Add `PeriodConfig` module
2. Add `build_aggregation_query/3` private function
3. Add tests for the builder

### Phase 2: Migrate Public Functions
1. Update `aggregate_group_by_day/2` to use builder
2. Update `aggregate_group_by_week/2` to use builder
3. Update `aggregate_group_by_month/2` to use builder
4. Verify all tests still pass

### Phase 3: Migrate Site-Wide Functions
1. Add `build_site_aggregation_query/2`
2. Update `fetch_site_aggregate_by_week/2`
3. Update `fetch_site_aggregate_by_month/2`
4. Verify all tests pass

### Phase 4: Cleanup
1. Remove any remaining helper functions
2. Update documentation
3. Add examples for extending with new periods

## Guardrails & Observability
- Reuse Telemetry event from #019a; ensure builder surfaces `period_type` in metadata for dashboard breakdowns.
- Capture diff report (lines removed vs added) to confirm duplication actually eliminated (~100 LOC target).
- Delete legacy helpers in the same change once tests pass.

## Coordination Checklist
- [ ] Align with QA that comparison suite assertions now use builder path.
- [ ] Update onboarding docs with new extension pattern (coordinate with #022 owner).
- [ ] Communicate to FE/Analytics stakeholders that JSON schema unchanged post-refactor.
- [ ] Confirm lints/formatters aware of new modules (ensure dialyzer/spec coverage if applicable).

## Acceptance Criteria

- [ ] `PeriodConfig` module created with config for :day, :week, :month
- [ ] `build_aggregation_query/3` private function created
- [ ] `build_site_aggregation_query/2` private function created
- [ ] All URL aggregation functions use the builder
- [ ] All site-wide aggregation functions use the builder
- [ ] Full test suite passes
- [ ] No duplicate SQL fragment code
- [ ] Documentation shows how to add new periods
- [ ] Performance same or better than #019a implementation
- [ ] Telemetry metadata includes `period_type` for dashboards
- [ ] Legacy helper functions removed after migration

## Test Plan

### Builder Tests

```elixir
describe "build_aggregation_query/3" do
  test "handles daily aggregation" do
    result = build_aggregation_query(urls, :day, opts)

    assert [%TimeSeriesData{} | _] = result
    # Daily shouldn't have period_end
    assert Enum.all?(result, &is_nil(&1.period_end))
  end

  test "handles weekly aggregation with period_end" do
    result = build_aggregation_query(urls, :week, opts)

    assert [%TimeSeriesData{} | _] = result
    # Weekly should have period_end
    assert Enum.all?(result, &(not is_nil(&1.period_end)))
  end

  test "produces same results as dedicated functions" do
    week_via_builder = build_aggregation_query(urls, :week, opts)
    week_via_function = aggregate_group_by_week(urls, opts)

    assert week_via_builder == week_via_function
  end
end
```

### Config Tests

```elixir
describe "PeriodConfig" do
  test "provides config for all period types" do
    assert %{group_by_fragment: _, type: :day} = PeriodConfig.config(:day)
    assert %{group_by_fragment: _, type: :week} = PeriodConfig.config(:week)
    assert %{group_by_fragment: _, type: :month} = PeriodConfig.config(:month)
  end

  test "week config uses Monday as start (ISO 8601)" do
    config = PeriodConfig.config(:week)
    assert config.group_by_fragment =~ "week"
  end
end
```

### Telemetry Tests
- Assert Telemetry event metadata contains `period_type: :week` etc. when builder executed.

## Estimate

**2 hours total**
- 0.5h: Create PeriodConfig module
- 0.5h: Create unified query builders
- 0.5h: Migrate all public functions
- 0.5h: Testing and documentation

## Rollback Plan

If issues arise:
1. Revert to #019a implementation (still has each function separate)
2. Keep PeriodConfig module (harmless if unused)
3. Can adopt incrementally (some functions use builder, others don't)

## Success Metrics

- Code reduction: ~100 lines eliminated through unification
- Single source of truth for query logic
- All tests pass
- Same performance as #019a
- Easier to add new aggregation periods

## Elixir/Ecto Best Practices

### Consider Ecto.Query.WindowAPI for Window Functions

**For Ecto 3.x+ (if applicable)**: When implementing window functions (like in ticket #025 for WoW growth), prefer Ecto's built-in `WindowAPI` over raw fragments:

```elixir
# Instead of raw fragments (works but verbose):
fragment("""
  LAG(?, 1) OVER (PARTITION BY ? ORDER BY ?)
""", ts.clicks, ts.url, ts.date)

# Prefer WindowAPI (Ecto 3.x+, cleaner syntax):
import Ecto.Query.WindowAPI

from(ts in TimeSeries,
  windows: [by_url: [partition_by: ts.url, order_by: ts.date]],
  select: %{
    clicks: ts.clicks,
    prev_clicks: lag(ts.clicks, 1) |> over(:by_url)
  }
)
```

**Benefits of WindowAPI**:
- Type-safe window function composition
- Cleaner, more maintainable code
- Better error messages
- Query planner optimization hints

**Community Guidance**: Ecto 3.x includes WindowAPI with functions like `row_number()`, `lag()`, `lead()`, and `over()` for complex aggregations. This is the recommended approach for window functions in modern Ecto applications.

### Query Timeout Protection

Add timeout protection to prevent runaway queries:

```elixir
# In application config
config :gsc_analytics, GscAnalytics.Repo,
  timeout: 15_000,  # 15 second query timeout
  statement_timeout: 14_000  # PostgreSQL-level timeout (slightly less)
```

This ensures that inefficient queries fail fast rather than consuming resources indefinitely.

## Notes

This ticket is **nice-to-have** rather than critical. The real performance win comes from #019a (database aggregation). This ticket is about maintainability and DRY compliance.

Can be deferred if time-constrained - #019a alone provides the major benefits.

**WindowAPI Note**: If using window functions elsewhere in the codebase (like #025), consider WindowAPI for cleaner syntax and better maintainability.
