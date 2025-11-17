# Ticket #002: Extract ContentInsights.UrlInsights Context

**Status**: ✅ Done (2025-10-19)
**Estimate**: 3 hours
**Priority**: 🟡 Medium
**Phase**: 2 (Dashboard Decomposition)
**Dependencies**: #003 (ChartPresenter), #011 (ContentInsights context API)

---

## Problem Statement

The `Dashboard.url_insights/3` function (lines 596-623) is buried in a 1040-line module, making it hard to test and maintain. It orchestrates:
- URL group resolution
- Time series data fetching
- Performance metric calculation
- Backlink aggregation
- Chart event building (delegates to Presentation.ChartPresenter)

This should be extracted into a focused context module.

---

## Solution

Create `ContentInsights.UrlInsights` context to own all URL detail page logic.

### New Module Structure
```
lib/gsc_analytics/
└── content_insights/
    └── url_insights.ex  # NEW
```

### API
```elixir
defmodule GscAnalytics.ContentInsights.UrlInsights do
  @moduledoc """
  Fetches comprehensive insights for a single URL including:
  - URL group resolution (canonical + redirects)
  - Time series metrics (daily/weekly/monthly)
  - Performance summary
  - Top search queries
  - Backlink data
  - Chart events (redirect milestones)
  """

  def fetch(url, view_mode, opts \\ %{})
end
```

---

## Acceptance Criteria

- [x] `ContentInsights.UrlInsights.fetch/3` returns same structure as `Dashboard.url_insights/3`
- [x] `DashboardUrlLive` updated to call `ContentInsights.url_insights/3`
- [x] Private helpers extracted (time series fetch, performance aggregation, top queries, date normalization)
- [x] Chart events delegated to `Presentation.ChartPresenter`
- [x] `Dashboard.url_insights/3` now delegates to `ContentInsights.url_insights/3` (full removal scheduled for ticket #008)
- [x] All existing tests pass
- [x] New unit tests for `UrlInsights` context cover daily/weekly/monthly flow
- [x] LiveView integration test verifies URL detail page works end-to-end

---

## Outcome

- Spun up `ContentInsights.UrlInsights` at `Tools/gsc_analytics/lib/gsc_analytics/content_insights/url_insights.ex` to encapsulate URL detail orchestration logic.
- Updated LiveView entrypoint in `Tools/gsc_analytics/lib/gsc_analytics_web/live/dashboard_url_live.ex` to consume the new context boundary.
- Delegated the legacy Dashboard wrapper in `Tools/gsc_analytics/lib/gsc_analytics/dashboard.ex` to the new boundary for backwards compatibility until ticket #008 removes it entirely.
- Backfilled comprehensive tests in `Tools/gsc_analytics/test/gsc_analytics/content_insights/url_insights_test.exs` alongside existing LiveView coverage.

---

## Implementation Tasks

### Task 1: Create UrlInsights module (1h)
**File**: `lib/gsc_analytics/content_insights/url_insights.ex`

```elixir
defmodule GscAnalytics.ContentInsights.UrlInsights do
  import Ecto.Query
  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.{Performance, TimeSeries}
  alias GscAnalytics.Analytics.TimeSeriesAggregator
  alias GscAnalytics.UrlGroups
  alias GscAnalytics.DataSources.Backlinks.Backlink, as: BacklinkContext
  alias GscAnalytics.Presentation.ChartPresenter

  @default_account_id 1

  def fetch(url, view_mode, opts \\ %{}) do
    # Copy implementation from Dashboard.url_insights/3
    # Replace inline chart event code with ChartPresenter.build_chart_events/2
  end

  # Private helpers (copy from Dashboard)
  defp build_time_series_for_view(...)
  defp calculate_performance_from_time_series(...)
  defp fetch_top_queries(...)
  defp start_date_for_view(...)
  defp view_label(...)
  defp format_range_summary(...)
  defp normalize_date_range(...)
  defp pluralize(...)
end
```

### Task 2: Expose helper on ContentInsights context (15m)
**File**: `lib/gsc_analytics/content_insights.ex`

Add a public function delegating to the new module:

```elixir
def url_insights(url, view_mode, opts \\ %{}) do
  ContentInsights.UrlInsights.fetch(url, view_mode, opts)
end
```

Keep `Dashboard.url_insights/3` delegating to `ContentInsights.url_insights/3` until ticket #008 removes it.

### Task 3: Update DashboardUrlLive (30m)
**File**: `lib/gsc_analytics_web/live/dashboard_url_live.ex:30`

```elixir
# Before
insights = Dashboard.url_insights(url, view_mode)

# After
insights = ContentInsights.url_insights(url, view_mode)
```

### Task 4: Add unit tests (1h)
**File**: `test/gsc_analytics/content_insights/url_insights_test.exs`

```elixir
defmodule GscAnalytics.ContentInsights.UrlInsightsTest do
  use GscAnalytics.DataCase
  alias GscAnalytics.ContentInsights.UrlInsights

  describe "fetch/3" do
    test "returns insights for URL with daily view"
    test "returns insights for URL with weekly view"
    test "returns insights for URL with monthly view"
    test "handles URL with no data"
    test "resolves canonical URL in group"
    test "includes top queries"
    test "includes backlinks"
    test "calculates performance from time series"
    test "delegates chart events to presenter"
  end
end
```

---

## Testing Strategy

### Unit Tests
- Test each view mode (daily, weekly, monthly)
- Test edge cases (no data, missing URL, invalid view mode)
- Test performance calculation accuracy
- Test date range normalization

### Integration Test
```elixir
# test/gsc_analytics_web/live/dashboard_url_live_test.exs
test "URL detail page loads with new context", %{conn: conn} do
  url = insert(:performance, url: "https://example.com/page").url
  {:ok, view, html} = live(conn, ~p"/dashboard/url?url=#{URI.encode(url)}")

  assert html =~ "URL Performance"
  assert has_element?(view, "#time-series-chart")
end
```

---

## Migration Checklist

- [x] Create `lib/gsc_analytics/content_insights/` directory
- [x] Create `url_insights.ex` module
- [x] Copy `url_insights/3` implementation
- [x] Copy private helpers (9 functions)
- [x] Add delegation wrapper in `Dashboard`
- [x] Update `DashboardUrlLive` import
- [x] Run targeted tests: `mix test test/gsc_analytics/content_insights/url_insights_test.exs`
- [x] Run LiveView regression subset
- [x] Manual verification: Navigate to URL detail page
- [x] Verify chart view toggles (daily/weekly/monthly)
- [x] Verify top queries table loads
- [x] Verify backlinks table loads
- [x] Commit with message: "refactor: extract ContentInsights.UrlInsights context"

---

## Rollback Plan

If LiveView breaks:
1. Revert `DashboardUrlLive` to call `Dashboard.url_insights/3`
2. Keep new `UrlInsights` module for future use
3. No schema changes, safe rollback

---

## Related Files

**Modified**:
- `lib/gsc_analytics/content_insights/url_insights.ex` (create)
- `lib/gsc_analytics/dashboard.ex` (add delegation)
- `lib/gsc_analytics_web/live/dashboard_url_live.ex` (update call site)

**Tests**:
- `test/gsc_analytics/content_insights/url_insights_test.exs` (create)
- `test/gsc_analytics_web/live/dashboard_url_live_test.exs` (verify)

---

## Notes

- Keep chart event building in Dashboard for now (extracted in ticket #003)
- `build_chart_events` will move to `Presentation.ChartPresenter` next
- Don't move formatting helpers (stay in `HTMLHelpers`)
