# Ticket #007: Extract ContentInsights.UrlPerformance

**Status**: ✅ Done (2025-10-19)
**Estimate**: 4 hours
**Priority**: 🟡 Medium
**Phase**: 2 (Dashboard Decomposition)
**Dependencies**: #011 (ContentInsights context API)

---

## Problem Statement

`Dashboard.list_urls/1` (lines 97-140) is the main dashboard data endpoint, handling:
- Hybrid lifetime + period metrics query
- URL enrichment (WoW growth, backlinks, HTTP status)
- Update status tagging
- Pagination and sorting

This core functionality should be in its own context.

---

## Solution

Extract into `ContentInsights.UrlPerformance` context.

### New Module
```
lib/gsc_analytics/
└── content_insights/
    ├── url_insights.ex        # Created in #002
    ├── keyword_aggregator.ex  # Created in #006
    └── url_performance.ex     # NEW
```

### API
```elixir
defmodule GscAnalytics.ContentInsights.UrlPerformance do
  @moduledoc """
  Lists and enriches URL performance metrics.

  Combines lifetime statistics with period-specific metrics, backlink counts,
  HTTP status checks, and WoW growth calculations for dashboard display.
  """

def list(opts \\ %{})
end
```

---

## Outcome

- Migrated the dashboard listing into `Tools/gsc_analytics/lib/gsc_analytics/content_insights/url_performance.ex`, preserving the hybrid lifetime/period query and enrichment steps.
- Updated the ContentInsights facade and main LiveView (`Tools/gsc_analytics/lib/gsc_analytics/content_insights.ex`, `Tools/gsc_analytics/lib/gsc_analytics_web/live/dashboard_live.ex`) to adopt the new boundary.
- Kept a compatibility wrapper in `Tools/gsc_analytics/lib/gsc_analytics/dashboard.ex` pending removal in ticket #008.
- Added regression coverage in `Tools/gsc_analytics/test/gsc_analytics/content_insights/url_performance_test.exs` to validate enrichment, search, and pagination.

---

## Acceptance Criteria

- [x] `UrlPerformance.list/1` maintains exact same API as `Dashboard.list_urls/1`
- [x] Returns paginated URL data with same structure
- [x] Supports all options (limit, page, sort_by, search, period_days, needs_update)
- [x] `ContentInsights.list_urls/1` delegates to the new module
- [x] `DashboardLive` updated to call `ContentInsights.list_urls/1`
- [x] Dashboard.ex wrapper now delegates to ContentInsights (scheduled for removal in #008)
- [x] All URL listing helpers extracted
- [x] Existing tests pass
- [x] New unit tests for `UrlPerformance`
- [x] Main dashboard URL table functions correctly

---

## Implementation Tasks

### Task 1: Create UrlPerformance module (2h)
**File**: `lib/gsc_analytics/content_insights/url_performance.ex`

```elixir
defmodule GscAnalytics.ContentInsights.UrlPerformance do
  import Ecto.Query
  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.{Performance, TimeSeries, Backlink}
  alias GscAnalytics.Analytics.TimeSeriesAggregator

  @default_account_id 1
  @default_limit 100

  @doc """
  Lists URLs with hybrid lifetime + period metrics.

  ## Options
    - :account_id - Account ID filter (default: 1)
    - :limit - Results per page (default: 100, max: 1000)
    - :page - Page number (default: 1)
    - :period_days - Days for period metrics (default: 30)
    - :sort_by - Sort field (lifetime_* or period_* prefix)
    - :sort_direction - :asc or :desc (default: :desc)
    - :search - Filter URLs containing text
    - :needs_update - Filter for URLs needing updates (boolean)

  ## Returns
    Map with:
    - :urls - List of URL data with lifetime + period metrics
    - :total_count - Total URLs matching filters
    - :page, :per_page, :total_pages - Pagination metadata
  """
  def list(opts \\ %{}) do
    account_id = Map.get(opts, :account_id, @default_account_id)
    limit = normalize_limit(Map.get(opts, :limit))
    page = normalize_page(Map.get(opts, :page))
    period_days = Map.get(opts, :period_days, 30)
    search = Map.get(opts, :search)

    offset = (page - 1) * limit

    query = build_hybrid_query(account_id, period_days, opts)
    query = apply_search_filter(query, search)

    total_count = count_urls(query)

    urls =
      query
      |> apply_sort(Map.get(opts, :sort_by), Map.get(opts, :sort_direction))
      |> limit(^limit)
      |> offset(^offset)
      |> Repo.all()

    enriched_urls = enrich_urls(urls, account_id, period_days)

    %{
      urls: enriched_urls,
      total_count: total_count,
      page: page,
      per_page: limit,
      total_pages: max(ceil(total_count / limit), 1)
    }
  end

  # Private helpers (copy from Dashboard.ex:310-471)
  defp build_hybrid_query(account_id, period_days, opts)
  defp apply_search_filter(query, search)
  defp apply_sort(query, sort_by, sort_direction)
  defp enrich_urls(urls, account_id, period_days)
  defp tag_update_status(url_data, wow_growth)
  defp count_urls(query)
  defp normalize_limit(limit)
  defp normalize_page(page)
  defp normalize_sort_direction(direction)
end
```

### Task 2: Expose helper on ContentInsights context (15m)
**File**: `lib/gsc_analytics/content_insights.ex`

```elixir
def list_urls(opts \\ %{}) do
  ContentInsights.UrlPerformance.list(opts)
end
```

Keep `Dashboard.list_urls/1` delegating to this function until ticket #008 removes the wrapper.

### Task 3: Update DashboardLive (30m)
**File**: `lib/gsc_analytics_web/live/dashboard_live.ex`

```elixir
# Before
alias GscAnalytics.Dashboard
result = Dashboard.list_urls(%{...})

# After
alias GscAnalytics.ContentInsights
result = ContentInsights.list_urls(%{...})
```

### Task 4: Add comprehensive tests (1.5h)
**File**: `test/gsc_analytics/content_insights/url_performance_test.exs`

```elixir
defmodule GscAnalytics.ContentInsights.UrlPerformanceTest do
  use GscAnalytics.DataCase
  alias GscAnalytics.ContentInsights.UrlPerformance

  describe "list/1" do
    test "returns paginated URL list"
    test "includes lifetime metrics from url_lifetime_stats"
    test "includes period metrics from time_series"
    test "enriches with WoW growth"
    test "enriches with backlink count"
    test "enriches with HTTP status"
    test "tags URLs needing updates (WoW < -20%)"
    test "tags URLs needing updates (position > 10)"
    test "filters by search term"
    test "sorts by lifetime metrics"
    test "sorts by period metrics"
    test "sorts by backlinks"
    test "sorts by HTTP status"
    test "respects period_days parameter"
    test "handles empty dataset"
    test "calculates pagination correctly"
  end
end
```

---

## Testing Strategy

### Unit Tests
```elixir
test "enriches URLs with WoW growth and update status" do
  # Insert URL with declining traffic
  # Verify wow_growth calculated
  # Verify needs_update flag set
  # Verify update_reason provided
end

test "hybrid query joins lifetime + period metrics" do
  result = UrlPerformance.list(%{period_days: 30})

  assert Enum.all?(result.urls, fn url ->
    Map.has_key?(url, :lifetime_clicks) &&
    Map.has_key?(url, :period_clicks)
  end)
end
```

### Integration Test
```elixir
test "dashboard URL table loads and functions", %{conn: conn} do
  {:ok, view, html} = live(conn, ~p"/dashboard")

  assert html =~ "URL Performance"
  assert has_element?(view, "table")

  # Test search
  view
  |> element("form[phx-change='search']")
  |> render_change(%{search: "example"})

  # Test sort
  view
  |> element("th", "Clicks")
  |> render_click()

  # Test pagination
  assert has_element?(view, "nav[aria-label='pagination']")
end
```

---

## Migration Checklist

- [x] Create `url_performance.ex` in `lib/gsc_analytics/content_insights/`
- [x] Copy `list_urls/1` implementation (lines 97-140)
- [x] Copy private helpers (lines 310-471):
  - [x] `build_hybrid_query/3` - complex query with subqueries
  - [x] `apply_search_filter/2`
  - [x] `apply_sort/3` - handles 8+ sort fields
  - [x] `enrich_urls/3`
  - [x] `tag_update_status/2`
- [x] Copy normalization functions (temporarily, removed in #008)
- [x] Add delegation in Dashboard.ex
- [x] Update `DashboardLive` imports and calls
- [x] Run tests: `mix test test/gsc_analytics/content_insights/url_performance_test.exs`
- [x] Run integration: `mix test test/gsc_analytics_web/live/dashboard_live_test.exs`
- [x] Manual verification:
  - [x] Navigate to /dashboard
  - [x] Verify URL table loads
  - [x] Test search filter
  - [x] Test sorting by:
    - [x] Lifetime clicks
    - [x] Period clicks
    - [x] Position
    - [x] Backlinks
    - [x] HTTP status
  - [x] Test pagination (prev/next/goto)
  - [x] Verify period toggle (7/30/90 days)
  - [x] Check "Needs Update" filter
- [x] Commit: "refactor: extract ContentInsights.UrlPerformance"

---

## Rollback Plan

- Revert `DashboardLive` if main table breaks
- Keep delegation in Dashboard
- No schema changes

---

## Related Files

**Created**:
- `lib/gsc_analytics/content_insights/url_performance.ex`
- `test/gsc_analytics/content_insights/url_performance_test.exs`

**Modified**:
- `lib/gsc_analytics/dashboard.ex` (add delegation, remove ~160 lines)
- `lib/gsc_analytics_web/live/dashboard_live.ex` (update alias and calls)

---

## Notes

- This is the largest extraction (~160 lines removed from Dashboard)
- Hybrid query joins 4 sources: url_lifetime_stats, time_series subquery, backlinks subquery, performance table
- Sorting must handle both lifetime and period metrics
- WoW growth batch calculation prevents N+1 queries
- Update status tagging uses business rules (WoW threshold, position threshold)
- Critical path - main dashboard depends on this
