# Ticket 022 — Architecture Documentation & Comprehensive Tests

**Status**: 📋 Pending
**Estimate**: 2h
**Actual**: TBD
**Priority**: 🟡 Medium
**Dependencies**: #018, #019a, #019b, #020, #021 (All previous tickets)

## Problem

After the architectural refactor, we need to:

1. **Document the new architecture**: Future contributors need to understand the domain type pattern and pipeline approach
2. **Update CLAUDE.md**: AI assistant needs updated context about the new structure
3. **Verify test coverage**: Ensure all new code paths are tested
4. **Add integration tests**: Verify the complete pipeline works end-to-end
5. **Document rollback procedures**: If production issues arise, we need clear rollback steps

## Proposed Approach

### 1. Update Architecture Documentation

Update `/Tools/gsc_analytics/CLAUDE.md` with new patterns:

````markdown
## Architecture Patterns (Post Sprint 3 Refactor)

### Domain-Driven Time Series Handling

All time series data uses the `TimeSeriesData` struct for guaranteed structure and chronological sorting:

```elixir
alias GscAnalytics.Analytics.TimeSeriesData

# Convert raw data to domain type (automatically sorted)
time_series = TimeSeriesData.from_raw_data(raw_data)

# Always sorted chronologically
TimeSeriesData.sort_chronologically(time_series)

# Convert to JSON for frontend
TimeSeriesData.to_json_map(time_series_point)
```
````

### Unified Aggregation Pipeline

The `TimeSeriesAggregator` now composes period-specific SQL through `PeriodConfig` and executes aggregation in PostgreSQL:

```elixir
alias GscAnalytics.Analytics.TimeSeriesAggregator

# Weekly aggregation (DB-native)
TimeSeriesAggregator.aggregate_group_by_week(urls, %{start_date: ~D[2025-01-01], account_id: account_id})

# Under the hood:
def aggregate_group_by_week(urls, opts) do
  build_aggregation_query(urls, :week, opts)
end
```

Each period configuration defines the SQL fragments for grouping, select fields, and period end calculation. All results are coerced into `TimeSeriesData` structs and sorted chronologically before returning.

### Presentation Layer Separation

Chart data encoding is centralized in `ChartDataPresenter`:

```elixir
alias GscAnalyticsWeb.Presenters.ChartDataPresenter

# In LiveView handle_params
chart_data = ChartDataPresenter.prepare_chart_data(time_series, events)

socket
|> assign(:time_series_json, chart_data.time_series_json)
|> assign(:events_json, chart_data.events_json)
```

### Caching Strategy (Optional - #021)

Aggregations are cached with appropriate TTLs:

```elixir
# Recent data (< 3 days): bypass or use 15-minute TTL (data still settling)
# Historical URL-specific data: 1-hour TTL
# Site-wide aggregations: 30-minute TTL
# Automatic invalidation on data sync
```

## Common Patterns

**Adding a new aggregation period** (e.g., quarterly):

1. Extend `PeriodConfig.config/1` with `:quarter` fragments (grouping, date, period_end).
2. Add public function delegating to `build_aggregation_query(urls, :quarter, opts)`.
3. Update site-wide builder if applicable.
4. Add unit + integration tests covering new period, plus documentation snippet.
5. Update telemetry dashboards to include new `period_type`.

````

### 2. Add Integration Tests

Create `/test/gsc_analytics/integration/dashboard_data_pipeline_test.exs`:

```elixir
defmodule GscAnalytics.Integration.DashboardDataPipelineTest do
  @moduledoc """
  Integration tests verifying the complete data pipeline from
  database → aggregation → presentation → JSON encoding.
  """

  use GscAnalytics.DataCase

  alias GscAnalytics.Analytics.{TimeSeriesAggregator, TimeSeriesData}
  alias GscAnalyticsWeb.Presenters.ChartDataPresenter
  alias GscAnalytics.Schemas.TimeSeries

  describe "complete pipeline: database → frontend" do
    setup do
      # Insert test data
      account_id = 1
      url = "https://example.com/test"

      daily_data = [
        %{date: ~D[2025-01-06], clicks: 100, impressions: 1000, ctr: 0.1, position: 5.0},
        %{date: ~D[2025-01-07], clicks: 110, impressions: 1100, ctr: 0.1, position: 5.5},
        %{date: ~D[2025-01-08], clicks: 120, impressions: 1200, ctr: 0.1, position: 5.2}
      ]

      Enum.each(daily_data, fn data ->
        %TimeSeries{}
        |> TimeSeries.changeset(Map.merge(data, %{account_id: account_id, url: url}))
        |> Repo.insert!()
      end)

      %{account_id: account_id, url: url}
    end

    test "weekly aggregation → domain type → JSON encoding", %{url: url, account_id: account_id} do
      # Step 1: Aggregate from database
      time_series = TimeSeriesAggregator.aggregate_group_by_week(
        [url],
        %{start_date: ~D[2025-01-01], account_id: account_id}
      )

      # Step 2: Verify domain type
      assert [%TimeSeriesData{} = ts] = time_series
      assert ts.date == ~D[2025-01-06]  # Monday (week start)
      assert ts.period_end == ~D[2025-01-12]  # Sunday (week end)
      assert ts.clicks == 330  # Sum of 100 + 110 + 120
      assert ts.impressions == 3300

      # Step 3: Encode for presentation
      json_string = ChartDataPresenter.encode_time_series(time_series)

      # Step 4: Verify JSON structure
      decoded = JSON.decode!(json_string)
      assert is_list(decoded)
      assert [point] = decoded

      assert point["date"] == "2025-01-06"
      assert point["period_end"] == "2025-01-12"
      assert point["clicks"] == 330
      assert point["impressions"] == 3300
    end

    test "date sorting works across year boundaries", %{url: url, account_id: account_id} do
      # Add data spanning year boundary
      late_2024 = %{
        date: ~D[2024-12-30],
        clicks: 50,
        impressions: 500,
        ctr: 0.1,
        position: 6.0,
        account_id: account_id,
        url: url
      }

      %TimeSeries{}
      |> TimeSeries.changeset(late_2024)
      |> Repo.insert!()

      # Aggregate across year boundary
      time_series = TimeSeriesAggregator.aggregate_group_by_week(
        [url],
        %{start_date: ~D[2024-12-20], account_id: account_id}
      )

      # Verify chronological order (this was the bug!)
      dates = Enum.map(time_series, & &1.date)

      assert Enum.sort(dates, Date) == dates
      assert List.first(dates).year == 2024
      assert List.last(dates).year == 2025
    end

    test "caching improves performance for repeat queries", %{url: url, account_id: account_id} do
      opts = %{start_date: ~D[2025-01-01], account_id: account_id}

      # First call - cache miss
      {time1, _result1} = :timer.tc(fn ->
        TimeSeriesAggregator.aggregate_group_by_week([url], opts)
      end)

      # Second call - cache hit (should be faster)
      {time2, _result2} = :timer.tc(fn ->
        TimeSeriesAggregator.aggregate_group_by_week([url], opts)
      end)

      # Cache hit should be at least 30% faster
      assert time2 < (time1 * 0.7)
    end
  end
end
````

### 3. Update Testing Guidance & Add Monitoring Tools

Update section in `/Tools/gsc_analytics/CLAUDE.md`:

````markdown
## Testing the Data Pipeline

### Unit Tests

- TimeSeriesData: Structure, sorting, JSON conversion
- TimeSeriesAggregator: Each aggregation function
- ChartDataPresenter: Encoding and preparation

### Integration Tests

- Complete pipeline: DB → aggregation → presentation → JSON
- Year boundary sorting behavior
- Caching performance improvements

### Performance Metrics & Targets

- **P95 query latency**: < 200ms (target after Sprint 3)
- **Database CPU utilization**: < 50%
- **Connection pool saturation**: < 80%
- **Cache hit rate**: > 60% after warmup (if caching enabled)
- **Index bloat**: < 20% (monitor monthly)

### Database Monitoring with ecto_psql_extras

Add `ecto_psql_extras` for PostgreSQL insights:

```elixir
# In mix.exs
{:ecto_psql_extras, "~> 0.7"}

# Usage in IEx or LiveDashboard
EctoPSQLExtras.long_running_queries(GscAnalytics.Repo)
EctoPSQLExtras.index_usage(GscAnalytics.Repo)
EctoPSQLExtras.table_cache_hit(GscAnalytics.Repo)
EctoPSQLExtras.index_cache_hit(GscAnalytics.Repo)
EctoPSQLExtras.unused_indexes(GscAnalytics.Repo)
```
````

**Key Commands**:

- `long_running_queries`: Identify slow queries (research shows ~30% of performance issues stem from a small subset)
- `index_usage`: Verify indexes from #024 are being used
- `table_cache_hit`: Aim for >99% cache hit rate on time_series table
- `unused_indexes`: Identify indexes to remove (idx_scan = 0)

**Best Practice**: "Nearly 30% of performance issues stem from a small subset of inefficient queries" - Use these tools regularly to maintain database health.

### Query Timeout Protection

Add to config:

```elixir
config :gsc_analytics, GscAnalytics.Repo,
  timeout: 15_000,  # 15 second query timeout
  statement_timeout: 14_000  # PostgreSQL-level timeout
```

### Manual QA Checklist

1. Main dashboard chart (site-wide trends)

   - [ ] Daily view renders correctly
   - [ ] Weekly view renders correctly with period labels
   - [ ] Monthly view renders correctly with period labels
   - [ ] Dates are chronologically ordered

2. URL detail chart

   - [ ] Daily view renders correctly
   - [ ] Weekly view renders correctly
   - [ ] Monthly view renders correctly
   - [ ] Switch between views works smoothly

3. Performance
   - [ ] Initial load time < 1 second (Sprint 3 target)
   - [ ] Subsequent loads use cache (faster)
   - [ ] No visual lag when switching views
   - [ ] Growth indicators display instantly

````

### 4. Document Rollback Procedures

Create `/Tools/gsc_analytics/ROLLBACK-SPRINT3.md`:

```markdown
# Sprint 3 Rollback Procedures

If production issues arise after Sprint 3 deployment, follow these steps:

## Quick Rollback (Emergency)

```bash
# Revert to previous commit before sprint 3
git revert <sprint-3-merge-commit>
git push origin main

# Redeploy
# ... your deployment process ...
````

## Selective Rollback (By Component)

### Rollback Caching (#021)

If caching causes issues:

```elixir
# Comment out cache usage in TimeSeriesAggregator
def aggregate_group_by_week(urls, opts) do
  # TimeSeriesCache.fetch(cache_key, fn ->  # DISABLED
    build_aggregation_query(urls, :week, opts)
  # end)
end
```

### Rollback Presenter (#020)

If JSON encoding has issues:

```elixir
# In DashboardLive, replace ChartDataPresenter with inline encoding
defp encode_time_series_json(series) do
  series
  |> Enum.map(fn ts ->
    %{
      date: Date.to_string(ts.date),
      clicks: ts.clicks,
      # ... rest of fields
    }
  end)
  |> JSON.encode!()
end
```

### Rollback Domain Type (#018, #019a)

If TimeSeriesData causes structural issues:

1. Revert the relevant merge commit (preserve tag in git history for quick reference).
2. Redeploy prior revision; confirm dashboards recovered.
3. Investigate discrepancies using archived benchmark/comparison data before reapplying refactor.

## Verification After Rollback

- [ ] Dashboard loads without errors
- [ ] Charts render correctly
- [ ] All tests pass
- [ ] No performance regressions

```

## Rollout Communication & Observability Deliverables
- Publish sprint-3 launch note (Confluence/Notion) summarizing rollout timeline and owner contacts.
- Link Telemetry dashboards (aggregator latency, cache hit rate) and document alert thresholds.
- Archive benchmark + comparison test results in `/20-29 Client Work/24 SEO Tooling/sprint3/reports/`.
- Provide checklist for on-call engineers covering how to revert commits, clear cache, and verify recovery.
- Update stakeholder communication template (email/Slack) for announcing rollout completion.

## Acceptance Criteria

- [ ] `CLAUDE.md` updated with new architecture patterns
- [ ] Integration test suite created and passing
- [ ] Testing guidance updated
- [ ] Rollback procedures documented
- [ ] Test coverage report generated (>90% for new code)
- [ ] All previous tickets' tests still passing
- [ ] Manual QA checklist completed
- [ ] Sprint retrospective prepared
- [ ] Telemetry dashboards + alert thresholds linked in documentation
- [ ] Benchmark/comparison artifacts archived with ticket references
- [ ] Cache/rollback runbook documented for on-call

## Test Coverage Goals

- `TimeSeriesData`: 100% (critical domain type)
- `TimeSeriesAggregator`: >95% (core business logic)
- `ChartDataPresenter`: 100% (presentation layer)
- `TimeSeriesCache`: >90% (optional feature)
- Integration tests: Core flows covered

## Manual QA Checklist

### Main Dashboard
- [ ] Load dashboard at `/dashboard`
- [ ] Verify chart renders with data
- [ ] Switch to weekly view
- [ ] Switch to monthly view
- [ ] Check date labels are correct
- [ ] Verify no console errors
- [ ] Test with empty dataset

### URL Detail Page
- [ ] Navigate to URL detail page
- [ ] Daily view renders correctly
- [ ] Weekly view renders correctly
- [ ] Monthly view renders correctly
- [ ] Date range displayed correctly
- [ ] Top queries table loads
- [ ] No console errors

### Performance
- [ ] Initial page load < 2 seconds
- [ ] Chart view switches < 500ms
- [ ] No visible lag or jank
- [ ] Memory usage stable over time

## Estimate

**2 hours total**
- 0.5h: Update CLAUDE.md documentation
- 0.5h: Create integration test suite
- 0.5h: Document rollback procedures
- 0.5h: Manual QA and final verification

## Success Metrics

- All documentation updated and reviewed
- Integration tests added and passing
- Manual QA checklist 100% complete
- Rollback procedures tested (in staging)
- Sprint retrospective delivered
```
