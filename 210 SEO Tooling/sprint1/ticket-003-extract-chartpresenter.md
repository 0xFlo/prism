# Ticket #003: Extract Presentation.ChartPresenter

**Status**: ✅ Done (2025-10-19)
**Estimate**: 2 hours
**Priority**: 🟡 Medium
**Phase**: 2 (Dashboard Decomposition)
**Dependencies**: None

---

## Problem Statement

Chart event formatting logic (lines 785-880 in Dashboard) mixes domain logic with presentation concerns:
- Building event structures from redirect data
- Normalizing dates to chart periods (weekly/monthly)
- Formatting event labels and tooltips
- Grouping multiple events on same date

This belongs in a focused presentation module, not in Dashboard.

---

## Solution

Create `Presentation.ChartPresenter` to handle chart event domain logic.

### New Module Structure
```
lib/gsc_analytics/
└── presentation/
    └── chart_presenter.ex  # NEW
```

### API
```elixir
defmodule GscAnalytics.Presentation.ChartPresenter do
  @moduledoc """
  Builds chart events from redirect history for visualization.

  Chart events mark significant URL changes (redirects) on time series charts,
  normalized to the appropriate time bucket (daily/weekly/monthly).
  """

  def build_chart_events(redirect_events, view_mode)
end
```

**Note**: Formatting helpers (number formatting, percentage conversion) stay in `GscAnalyticsWeb.Dashboard.HTMLHelpers`. `ChartPresenter` should emit plain data structs only.

---

## Acceptance Criteria

- [x] `ChartPresenter.build_chart_events/2` returns same structure as existing implementation
- [x] Event dates normalized to the proper bucket (daily: exact date, weekly: Monday, monthly: 1st)
- [x] Multiple events on same date collapse into a single entry with merged tooltip text
- [x] Module contains no HTML formatting or LiveView-specific code (pure data structures)
- [x] `ContentInsights.UrlInsights` delegates to `ChartPresenter`
- [x] Dashboard.ex removes event-building helpers
- [x] Existing tests pass
- [x] New unit tests cover daily/weekly/monthly normalization, grouping, and label generation

---

## Outcome

- Introduced `ChartPresenter` at `Tools/gsc_analytics/lib/gsc_analytics/presentation/chart_presenter.ex` with fully normalized chart event builder.
- Updated `Tools/gsc_analytics/lib/gsc_analytics/content_insights/url_insights.ex` to delegate chart event construction to the presenter boundary.
- Backfilled regression coverage in `Tools/gsc_analytics/test/gsc_analytics/presentation/chart_presenter_test.exs`, covering period normalization, grouping, and tooltips.
- Removed duplicated helpers from `Tools/gsc_analytics/lib/gsc_analytics/dashboard.ex`, shrinking the module surface and aligning with the decomposition plan.

---

## Implementation Tasks

### Task 1: Create ChartPresenter module (1h)
**File**: `lib/gsc_analytics/presentation/chart_presenter.ex`

```elixir
defmodule GscAnalytics.Presentation.ChartPresenter do
  @moduledoc """
  Builds chart events from URL redirect history.

  Events are normalized to the chart's time period (daily/weekly/monthly)
  and include labels and tooltips for visualization.
  """

  @doc """
  Builds chart events from redirect history.

  ## Parameters
    - redirect_events: List of redirect event maps with :checked_at, :status, :source_url, :target_url
    - view_mode: "daily", "weekly", or "monthly"

  ## Returns
    List of event maps with:
    - :date (string)
    - :label (string)
    - :tooltip (string or nil)

  ## Examples
      iex> events = [%{checked_at: ~U[2025-01-15 10:00:00Z], status: 301, ...}]
      iex> ChartPresenter.build_chart_events(events, "weekly")
      [%{date: "2025-01-13", label: "301 → /page", tooltip: "..."}]
  """
  def build_chart_events(redirect_events, view_mode)

  # Private helpers (copy from Dashboard.ex:785-880)
  defp normalize_event_date(date, view_mode)
  defp format_event_label(event)
  defp build_event_tooltip(event)
  defp extract_event_slug(url)
  defp slug_from_host(uri)
  defp truncate_string(string, max_length)
end
```

### Task 2: Update UrlInsights to use ChartPresenter (30m)
**File**: `lib/gsc_analytics/content_insights/url_insights.ex`

```elixir
# Add alias
alias GscAnalytics.Presentation.ChartPresenter

# Update fetch/3 to call presenter
chart_events =
  ChartPresenter.build_chart_events(url_group.redirect_events, view_mode)

%{
  # ... existing fields ...
  chart_events: chart_events,
  # ... rest of fields ...
}
```

### Task 3: Remove from Dashboard.ex (15m)
**File**: `lib/gsc_analytics/dashboard.ex`

Delete lines 785-880:
- `build_chart_events/2`
- `normalize_event_date/2`
- `format_event_label/1`
- `build_event_tooltip/1`
- `extract_event_slug/1`
- `slug_from_host/1`
- `truncate_string/2`

### Task 4: Add unit tests (45m)
**File**: `test/gsc_analytics/presentation/chart_presenter_test.exs`

```elixir
defmodule GscAnalytics.Presentation.ChartPresenterTest do
  use ExUnit.Case, async: true
  alias GscAnalytics.Presentation.ChartPresenter

  describe "build_chart_events/2" do
    test "builds events for daily view"
    test "builds events for weekly view (normalizes to Monday)"
    test "builds events for monthly view (normalizes to 1st)"
    test "groups multiple events on same date"
    test "handles empty redirect events list"
    test "handles events without checked_at timestamp"
    test "formats event label with status and slug"
    test "builds tooltip with source and target URLs"
    test "truncates long URL slugs to 32 chars"
  end
end
```

---

## Testing Strategy

### Unit Tests
```elixir
test "normalizes weekly events to Monday" do
  events = [
    %{
      checked_at: ~U[2025-01-15 10:00:00Z],  # Wednesday
      status: 301,
      source_url: "https://example.com/old",
      target_url: "https://example.com/new"
    }
  ]

  result = ChartPresenter.build_chart_events(events, "weekly")

  assert [%{date: "2025-01-13"}] = result  # Monday
end

test "groups multiple events on same date" do
  events = [
    %{checked_at: ~U[2025-01-15 08:00:00Z], status: 301, ...},
    %{checked_at: ~U[2025-01-15 14:00:00Z], status: 302, ...}
  ]

  result = ChartPresenter.build_chart_events(events, "daily")

  assert [%{label: "URL changes (2)", tooltip: tooltip}] = result
  assert tooltip =~ "301"
  assert tooltip =~ "302"
end
```

### Integration Test
Verify chart events still render in URL detail page:
```elixir
test "URL detail page displays chart events", %{conn: conn} do
  # Setup URL with redirect history
  # Navigate to URL detail page
  # Verify event markers appear on chart
end
```

---

## Migration Checklist

- [ ] Create `lib/gsc_analytics/presentation/` directory
- [ ] Create `chart_presenter.ex` module
- [ ] Copy event building functions from Dashboard (lines 785-880)
- [ ] Update `UrlInsights.fetch/3` to use `ChartPresenter`
- [ ] Remove event functions from `Dashboard.ex`
- [ ] Run tests: `mix test test/gsc_analytics/presentation/chart_presenter_test.exs`
- [ ] Run integration test: `mix test test/gsc_analytics_web/live/dashboard_url_live_test.exs`
- [ ] Manual verification: Check chart events render on URL detail page
- [ ] Verify weekly view shows events on Monday
- [ ] Verify monthly view shows events on 1st of month
- [ ] Commit: "refactor: extract Presentation.ChartPresenter"

---

## Rollback Plan

If chart events break:
1. Revert `UrlInsights` to call inline event building
2. Keep `ChartPresenter` for future use
3. Restore deleted functions to Dashboard temporarily

---

## Related Files

**Created**:
- `lib/gsc_analytics/presentation/chart_presenter.ex`
- `test/gsc_analytics/presentation/chart_presenter_test.exs`

**Modified**:
- `lib/gsc_analytics/content_insights/url_insights.ex` (use ChartPresenter)
- `lib/gsc_analytics/dashboard.ex` (remove 95 lines of event code)

**No changes**:
- `lib/gsc_analytics_web/dashboard/html_helpers.ex` (formatting stays here)

---

## Notes

- Chart events are domain logic (how to represent redirects), not formatting
- Formatting helpers (`format_number`, `format_date`) remain in `HTMLHelpers`
- This extraction makes chart event building independently testable
- Future enhancement: Add chart events for other milestones (content updates, etc.)
