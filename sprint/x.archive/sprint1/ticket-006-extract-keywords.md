# Ticket #006: Extract ContentInsights.KeywordAggregator

**Status**: ✅ Done (2025-10-19)
**Estimate**: 3 hours
**Priority**: 🟡 Medium
**Phase**: 2 (Dashboard Decomposition)
**Dependencies**: #011 (ContentInsights context API)

---

## Problem Statement

`Dashboard.list_top_keywords/1` (lines 164-208) aggregates keywords across all URLs using JSONB queries, but this content analysis logic is buried in the monolithic Dashboard module. Should be extracted to ContentInsights context.

---

## Solution

Extract into `ContentInsights.KeywordAggregator` context.

### New Module
```
lib/gsc_analytics/
└── content_insights/
    ├── url_insights.ex        # Created in #002
    └── keyword_aggregator.ex  # NEW
```

Keep `Dashboard.list_top_keywords/1` delegating to `ContentInsights.list_keywords/1` until ticket #008 removes it.
### API
```elixir
defmodule GscAnalytics.ContentInsights.KeywordAggregator do
  @moduledoc """
  Aggregates search keyword data across all URLs.

  Combines `top_queries` data from TimeSeries records, grouping by query text
  and calculating aggregated metrics (clicks, impressions, position, URL count).
  """

def list(opts \\ %{})
end
```

---

## Outcome

- Added dedicated aggregator boundary at `Tools/gsc_analytics/lib/gsc_analytics/content_insights/keyword_aggregator.ex`, preserving pagination, sorting, and filtering behaviour.
- Updated the ContentInsights facade and LiveView (`Tools/gsc_analytics/lib/gsc_analytics/content_insights.ex`, `Tools/gsc_analytics/lib/gsc_analytics_web/live/dashboard_keywords_live.ex`) to consume the new module.
- Left a backwards compatible wrapper in `Tools/gsc_analytics/lib/gsc_analytics/dashboard.ex` pending full removal in ticket #008.
- Strengthened coverage via `Tools/gsc_analytics/test/gsc_analytics/content_insights/keyword_aggregator_test.exs`, validating aggregation math, search filters, and sorting.

---

## Acceptance Criteria

- [x] `KeywordAggregator.list/1` maintains exact same API as `Dashboard.list_top_keywords/1`
- [x] Returns paginated keyword data with same structure
- [x] Supports all existing options (limit, page, period_days, sort_by, search)
- [x] `ContentInsights.list_keywords/1` delegates to the new module
- [x] `DashboardKeywordsLive` updated to call `ContentInsights.list_keywords/1`
- [x] Dashboard.ex wrapper now delegates to ContentInsights (full removal tracked in #008)
- [x] All keyword-related helpers extracted
- [x] Existing tests pass
- [x] New unit tests for `KeywordAggregator`
- [x] Keywords page loads and functions correctly

---

## Implementation Tasks

### Task 1: Create KeywordAggregator module (1.5h)
**File**: `lib/gsc_analytics/content_insights/keyword_aggregator.ex`

```elixir
defmodule GscAnalytics.ContentInsights.KeywordAggregator do
  import Ecto.Query
  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.TimeSeries

  @default_account_id 1
  @default_limit 100

  @doc """
  Lists top keywords aggregated across all URLs.

  ## Options
    - :account_id - Account ID filter (default: 1)
    - :limit - Results per page (default: 100, max: 1000)
    - :page - Page number (default: 1)
    - :period_days - Days to look back (default: 30)
    - :sort_by - Sort field: "query", "clicks", "impressions", "ctr", "position", "url_count"
    - :sort_direction - :asc or :desc (default: :desc)
    - :search - Filter keywords containing text

  ## Returns
    Map with:
    - :keywords - List of keyword data
    - :total_count - Total keywords matching filters
    - :page - Current page
    - :per_page - Items per page
    - :total_pages - Total pages
  """
  def list(opts \\ %{}) do
    account_id = Map.get(opts, :account_id, @default_account_id)
    limit = normalize_limit(Map.get(opts, :limit))
    page = normalize_page(Map.get(opts, :page))
    period_days = Map.get(opts, :period_days, 30)
    search = Map.get(opts, :search)
    sort_by = Map.get(opts, :sort_by, "clicks")
    sort_direction = normalize_sort_direction(Map.get(opts, :sort_direction))

    period_start = Date.add(Date.utc_today(), -period_days)

    query = build_keywords_query(account_id, period_start)
    query = apply_keyword_search_filter(query, search)

    total_count = count_keywords(query)
    offset = (page - 1) * limit

    keywords =
      query
      |> apply_keyword_sort(sort_by, sort_direction)
      |> limit(^limit)
      |> offset(^offset)
      |> Repo.all()

    %{
      keywords: keywords,
      total_count: total_count,
      page: page,
      per_page: limit,
      total_pages: max(ceil(total_count / limit), 1)
    }
  end

  # Private helpers (copy from Dashboard.ex:962-1039)
  defp build_keywords_query(account_id, period_start)
  defp apply_keyword_search_filter(query, search)
  defp apply_keyword_sort(query, sort_by, sort_direction)
  defp count_keywords(query)
  defp normalize_limit(limit)
  defp normalize_page(page)
  defp normalize_sort_direction(direction)
end
```

### Task 2: Expose helper on ContentInsights context (15m)
**File**: `lib/gsc_analytics/content_insights.ex`

```elixir
def list_keywords(opts \\ %{}) do
  ContentInsights.KeywordAggregator.list(opts)
end
```

### Task 3: Update DashboardKeywordsLive (30m)
**File**: `lib/gsc_analytics_web/live/dashboard_keywords_live.ex`

```elixir
# Before
alias GscAnalytics.Dashboard
result = Dashboard.list_top_keywords(%{...})

# After
alias GscAnalytics.ContentInsights
result = ContentInsights.list_keywords(%{...})
```

Keep `Dashboard.list_top_keywords/1` delegating to `ContentInsights.list_keywords/1` until ticket #008 removes it.

### Task 4: Add comprehensive tests (1h)
**File**: `test/gsc_analytics/content_insights/keyword_aggregator_test.exs`

```elixir
defmodule GscAnalytics.ContentInsights.KeywordAggregatorTest do
  use GscAnalytics.DataCase
  alias GscAnalytics.ContentInsights.KeywordAggregator

  describe "list/1" do
    test "aggregates keywords across all URLs"
    test "calculates weighted average position"
    test "counts unique URLs per keyword"
    test "filters by period_days"
    test "supports pagination"
    test "sorts by clicks descending by default"
    test "sorts by all supported fields"
    test "filters keywords by search term"
    test "handles empty dataset"
    test "respects account_id filter"
    test "calculates CTR correctly"
    test "returns correct total_count and total_pages"
  end
end
```

---

## Testing Strategy

### Unit Tests
```elixir
test "aggregates keywords across multiple URLs" do
  # Insert TimeSeries for 3 URLs with overlapping keywords
  # URL1: "python scraping" (10 clicks)
  # URL2: "python scraping" (15 clicks)
  # URL3: "web scraping" (20 clicks)

  result = KeywordAggregator.list()

  assert length(result.keywords) == 2

  python_kw = Enum.find(result.keywords, &(&1.query == "python scraping"))
  assert python_kw.clicks == 25  # 10 + 15
  assert python_kw.url_count == 2
end

test "filters keywords by search term" do
  result = KeywordAggregator.list(%{search: "python"})

  assert Enum.all?(result.keywords, fn kw ->
    String.contains?(String.downcase(kw.query), "python")
  end)
end
```

### Integration Test
```elixir
test "keywords page loads and functions", %{conn: conn} do
  {:ok, view, html} = live(conn, ~p"/dashboard/keywords")

  assert html =~ "Top Keywords"
  assert has_element?(view, "table")

  # Test search
  view
  |> element("form")
  |> render_change(%{search: "test"})

  # Test sort
  view
  |> element("th", "Clicks")
  |> render_click()
end
```

---

## Migration Checklist

- [x] Create `keyword_aggregator.ex` in `lib/gsc_analytics/content_insights/`
- [x] Copy `list_top_keywords/1` implementation (lines 164-208)
- [x] Copy private helpers (lines 962-1039):
  - [x] `build_keywords_query/2`
  - [x] `apply_keyword_search_filter/2`
  - [x] `apply_keyword_sort/3`
- [x] Copy normalization functions (will be removed in #008)
- [x] Add delegation in Dashboard.ex
- [x] Update `DashboardKeywordsLive` imports and calls
- [x] Run tests: `mix test test/gsc_analytics/content_insights/keyword_aggregator_test.exs`
- [x] Run integration: `mix test test/gsc_analytics_web/live/dashboard_keywords_live_test.exs`
- [x] Manual verification:
  - [x] Navigate to /dashboard/keywords
  - [x] Verify keyword list loads
  - [x] Test search filter
  - [x] Test sorting by different columns
  - [x] Test pagination
  - [x] Verify metrics (clicks, impressions, position, URL count)
- [x] Commit: "refactor: extract ContentInsights.KeywordAggregator"

---

## Rollback Plan

- Revert `DashboardKeywordsLive` if keywords page breaks
- Keep delegation in Dashboard
- No schema changes

---

## Related Files

**Created**:
- `lib/gsc_analytics/content_insights/keyword_aggregator.ex`
- `test/gsc_analytics/content_insights/keyword_aggregator_test.exs`

**Modified**:
- `lib/gsc_analytics/dashboard.ex` (add delegation, remove ~80 lines)
- `lib/gsc_analytics_web/live/dashboard_keywords_live.ex` (update alias and call)

---

## Notes

- JSONB aggregation query is complex - test thoroughly
- Weighted average position formula must remain accurate
- Search filter uses ILIKE for case-insensitive matching
- URL count shows how many different URLs rank for each keyword
- This extraction removes ~80 lines from Dashboard.ex
