# Ticket #005: Extract Analytics.SummaryStats Context

**Status**: ✅ Done (2025-10-19)
**Estimate**: 3 hours
**Priority**: 🟡 Medium
**Phase**: 2 (Dashboard Decomposition)
**Dependencies**: None (independent from other extractions)

---

## Problem Statement

`Dashboard.summary_stats/1` (lines 218-245) provides summary statistics (current month, last month, all time) but mixes this analytics logic with dashboard orchestration. Should be its own context.

---

## Solution

Extract into `Analytics.SummaryStats` context with comprehensive helpers.

### New Module
```
lib/gsc_analytics/
└── analytics/
    ├── time_series_aggregator.ex  # EXISTS
    ├── site_trends.ex             # Created in #004
    └── summary_stats.ex            # NEW
```

### API
```elixir
defmodule GscAnalytics.Analytics.SummaryStats do
  @moduledoc """
  Calculates summary statistics for site performance across time periods.

  Provides metrics for:
  - Current month (month-to-date)
  - Last month (full month)
  - All time (from lifetime stats table)
  - Month-over-month change percentage
  """

  def fetch(opts \\ %{})
end
```

---

## Acceptance Criteria

- [x] `SummaryStats.fetch/1` returns same structure as `Dashboard.summary_stats/1`
- [x] Includes current_month, last_month, all_time, month_over_month_change
- [x] Private helpers extracted for period aggregation
- [x] Dashboard.ex delegates `summary_stats/1` to the new context
- [x] Existing tests pass
- [x] New unit tests for `SummaryStats`
- [ ] Summary cards render correctly on dashboard (manual spot-check deferred to #008)

---

## Outcome

- Created `Analytics.SummaryStats` at `Tools/gsc_analytics/lib/gsc_analytics/analytics/summary_stats.ex`, moving the period aggregation logic out of Dashboard.
- Slimmed `Tools/gsc_analytics/lib/gsc_analytics/dashboard.ex` to a thin wrapper that delegates `summary_stats/1` to the analytics context.
- Added comprehensive coverage in `Tools/gsc_analytics/test/gsc_analytics/analytics/summary_stats_test.exs`, asserting month-to-date, last-month, and all-time calculations plus MoM percentage.
- Manual dashboard verification remains scheduled alongside the orchestration cleanup in ticket #008.

---

## Implementation Tasks

### Task 1: Create SummaryStats module (1.5h)
**File**: `lib/gsc_analytics/analytics/summary_stats.ex`

```elixir
defmodule GscAnalytics.Analytics.SummaryStats do
  import Ecto.Query
  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.TimeSeries

  @default_account_id 1

  @doc """
  Fetches summary statistics for the site.

  ## Returns
    Map with:
    - :current_month - MTD metrics
    - :last_month - Full month metrics
    - :all_time - Lifetime metrics
    - :month_over_month_change - MoM growth percentage
  """
  def fetch(opts \\ %{}) do
    account_id = Map.get(opts, :account_id, @default_account_id)
    today = Date.utc_today()

    current_month_start = Date.beginning_of_month(today)
    last_month_end = Date.add(current_month_start, -1)
    last_month_start = Date.beginning_of_month(last_month_end)

    current_month = aggregate_period(account_id, current_month_start, today)
    last_month = aggregate_period(account_id, last_month_start, last_month_end)
    all_time = aggregate_lifetime_from_table(account_id)

    mom_change = calculate_percentage_change(
      last_month.total_clicks,
      current_month.total_clicks
    )

    %{
      current_month: current_month,
      last_month: last_month,
      all_time: all_time,
      month_over_month_change: mom_change
    }
  end

  # Private helpers (copy from Dashboard.ex:473-587)
  defp aggregate_period(account_id, start_date, end_date)
  defp aggregate_lifetime_from_table(account_id)
  defp format_stats(stats)
  defp convert_to_integer(value)
  defp convert_to_float(value)
  defp maybe_add_date_fields(result, stats)
  defp maybe_put(map, key, value)
  defp calculate_percentage_change(old_value, new_value)
  defp format_period_label(start_date, end_date)
end
```

### Task 2: Add delegation in Dashboard (15m)
**File**: `lib/gsc_analytics/dashboard.ex`

```elixir
def summary_stats(opts \\ %{}) do
  Analytics.SummaryStats.fetch(opts)
end
```

### Task 3: Add comprehensive tests (1h)
**File**: `test/gsc_analytics/analytics/summary_stats_test.exs`

```elixir
defmodule GscAnalytics.Analytics.SummaryStatsTest do
  use GscAnalytics.DataCase
  alias GscAnalytics.Analytics.SummaryStats

  describe "fetch/1" do
    test "returns current month MTD metrics"
    test "returns last full month metrics"
    test "returns all-time metrics from lifetime table"
    test "calculates month-over-month change correctly"
    test "handles zero previous month clicks"
    test "formats period labels correctly"
    test "handles empty dataset gracefully"
    test "respects account_id filter"
    test "converts Decimal values to integers/floats"
    test "includes earliest and latest dates in all_time"
  end

  describe "calculate_percentage_change/2" do
    test "calculates positive growth"
    test "calculates negative growth"
    test "handles zero old value"
    test "handles nil values"
  end
end
```

---

## Testing Strategy

### Unit Tests
```elixir
test "calculates month-over-month change correctly" do
  # Insert data: Jan = 1000 clicks, Feb MTD = 1200 clicks
  result = SummaryStats.fetch()

  assert result.last_month.total_clicks == 1000
  assert result.current_month.total_clicks == 1200
  assert result.month_over_month_change == 20.0  # 20% growth
end

test "formats period labels for full months" do
  result = SummaryStats.fetch()

  assert result.last_month.period_label =~ ~r/\w+ \d{4}/  # "January 2025"
end
```

### Integration Test
```elixir
test "dashboard summary cards display correctly", %{conn: conn} do
  {:ok, _view, html} = live(conn, ~p"/dashboard")

  assert html =~ "Current Month"
  assert html =~ "Last Month"
  assert html =~ "All Time"
  assert html =~ "MoM Change"
end
```

---

- [x] Create `summary_stats.ex` in `lib/gsc_analytics/analytics/`
- [x] Move `summary_stats/1` implementation out of Dashboard
- [x] Port helper functions (`aggregate_period/3`, `aggregate_lifetime_from_table/1`, etc.)
- [x] Add delegation in Dashboard.ex
- [x] Run tests: `mix test test/gsc_analytics/analytics/summary_stats_test.exs`
- [ ] Run integration: `mix test test/gsc_analytics_web/live/dashboard_live_test.exs`
- [ ] Manual verification of summary cards in the dashboard UI
- [x] Commit: "refactor: finish phase-two context extraction" (initial) / follow-up commit pending for analytics extractions

---

## Rollback Plan

- Revert DashboardLive if summary cards break
- Keep delegation in Dashboard
- No schema changes

---

## Related Files

**Created**:
- `lib/gsc_analytics/analytics/summary_stats.ex`
- `test/gsc_analytics/analytics/summary_stats_test.exs`

**Modified**:
- `lib/gsc_analytics/dashboard.ex` (add delegation, remove 115 lines)

---

## Notes

- This extraction is independent - can be done in parallel with other Phase 2 tickets
- Removes ~115 lines from Dashboard.ex (main function + 8 helpers)
- `format_period_label` is used by multiple functions - keep copy in Dashboard until final cleanup (#008)
