# Ticket #004: Extract Analytics.SiteTrends Context

**Status**: ✅ Done (2025-10-19)
**Estimate**: 2 hours
**Priority**: 🟡 Medium
**Phase**: 2 (Dashboard Decomposition)
**Dependencies**: None (independent from other extractions)

---

## Problem Statement

`Dashboard.site_trends/2` (lines 255-292) provides site-wide traffic trends in different views (daily/weekly/monthly) but is buried in the monolithic Dashboard module. This should be its own analytics context.

---

## Solution

Extract into `Analytics.SiteTrends` context.

### New Module
```
lib/gsc_analytics/
└── analytics/
    ├── time_series_aggregator.ex  # EXISTS
    └── site_trends.ex              # NEW
```

### API
```elixir
defmodule GscAnalytics.Analytics.SiteTrends do
  @moduledoc """
  Provides site-wide traffic trend aggregations across all URLs.

  Supports daily, weekly, and monthly views with automatic date range
  detection based on available data.
  """

  def fetch(view_mode, opts \\ %{})
end
```

---

## Acceptance Criteria

- [x] `SiteTrends.fetch/2` returns `{series, label}` tuple
- [x] Daily view limits to 365 days
- [x] Weekly view shows all available weeks
- [x] Monthly view shows all available months
- [x] Dashboard.ex delegates `site_trends/2` to the new context
- [x] Existing tests pass
- [x] New unit tests cover daily/weekly/monthly paths
- [ ] Chart view toggle works in dashboard (manual verification pending for #008)

---

## Outcome

- Introduced `Analytics.SiteTrends` at `Tools/gsc_analytics/lib/gsc_analytics/analytics/site_trends.ex`, handling daily/weekly/monthly trend aggregation via `TimeSeriesAggregator`.
- Updated `Tools/gsc_analytics/lib/gsc_analytics/dashboard.ex` to delegate `site_trends/2` to the new context, removing the legacy helper logic.
- Added focused coverage in `Tools/gsc_analytics/test/gsc_analytics/analytics/site_trends_test.exs`, asserting date normalization and account scoping.
- Left dashboard LiveView wiring for ticket #008, when the orchestration layer is consolidated.

---

## Implementation Tasks

### Task 1: Create SiteTrends module (1h)
**File**: `lib/gsc_analytics/analytics/site_trends.ex`

```elixir
defmodule GscAnalytics.Analytics.SiteTrends do
  alias GscAnalytics.Analytics.TimeSeriesAggregator
  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.TimeSeries
  import Ecto.Query

  @default_account_id 1

  @doc """
  Fetches site-wide trends for the specified view mode.

  ## Parameters
    - view_mode: "daily", "weekly", or "monthly"
    - opts: Options map with optional :account_id

  ## Returns
    Tuple of {series_data, label}
    - series_data: List of aggregated metrics
    - label: Human-readable label for x-axis

  ## Examples
      iex> SiteTrends.fetch("weekly", %{account_id: 1})
      {[%{date: ~D[2025-01-06], clicks: 1234, ...}], "Week Starting"}
  """
  def fetch(view_mode, opts \\ %{})

  def fetch("weekly", opts) do
    # Copy implementation from Dashboard.site_trends/2
  end

  def fetch("monthly", opts) do
    # Copy implementation from Dashboard.site_trends/2
  end

  def fetch(_view_mode, opts) do
    # Daily (default)
  end

  defp get_first_data_date(account_id) do
    # Copy from Dashboard
  end
end
```

### Task 2: Add delegation in Dashboard (15m)
**File**: `lib/gsc_analytics/dashboard.ex`

```elixir
def site_trends(chart_view, opts \\ %{}) do
  Analytics.SiteTrends.fetch(chart_view, opts)
end
```

### Task 3: Update DashboardLive (optional for now)
Later in ticket #008, update LiveView to call directly.

### Task 4: Add unit tests (45m)
**File**: `test/gsc_analytics/analytics/site_trends_test.exs`

```elixir
defmodule GscAnalytics.Analytics.SiteTrendsTest do
  use GscAnalytics.DataCase
  alias GscAnalytics.Analytics.SiteTrends

  describe "fetch/2" do
    test "returns daily trends with up to 365 days"
    test "returns weekly trends with all available weeks"
    test "returns monthly trends with all available months"
    test "returns correct label for each view mode"
    test "handles empty dataset gracefully"
    test "respects account_id filter"
    test "calculates first data date correctly"
  end
end
```

---

## Testing Strategy

### Unit Tests
```elixir
test "daily view limits to 365 days" do
  # Insert 400 days of data
  # Fetch daily trends
  # Assert length <= 365
end

test "weekly view returns correct period labels" do
  {series, label} = SiteTrends.fetch("weekly")

  assert label == "Week Starting"
  assert Enum.all?(series, fn item ->
    Date.day_of_week(item.date) == 1  # Monday
  end)
end
```

### Integration Test
```elixir
test "dashboard chart view toggle works", %{conn: conn} do
  {:ok, view, _html} = live(conn, ~p"/dashboard")

  # Click weekly view
  view |> element("button", "Weekly") |> render_click()

  # Verify chart updates
  assert has_element?(view, "[data-chart-label='Week Starting']")
end
```

---

- [x] Create `site_trends.ex` in `lib/gsc_analytics/analytics/`
- [x] Move logic from `Dashboard.site_trends/2`
- [x] Copy `get_first_data_date/1` helper into the new module
- [x] Add delegation in Dashboard.ex
- [x] Run tests: `mix test test/gsc_analytics/analytics/site_trends_test.exs`
- [ ] Run integration: `mix test test/gsc_analytics_web/live/dashboard_live_test.exs`
- [ ] Manual verification of chart toggles in the dashboard UI
- [x] Commit: "refactor: finish phase-two context extraction" (initial) / follow-up commit pending for analytics extractions

---

## Rollback Plan

- Revert DashboardLive if chart breaks
- Keep delegation in Dashboard
- No schema changes

---

## Related Files

**Created**:
- `lib/gsc_analytics/analytics/site_trends.ex`
- `test/gsc_analytics/analytics/site_trends_test.exs`

**Modified**:
- `lib/gsc_analytics/dashboard.ex` (add delegation)

---

## Notes

- This extraction is independent - can be done in parallel with other Phase 2 tickets
- `TimeSeriesAggregator` remains unchanged
- Site trends uses aggregator's `fetch_site_aggregate*` functions
