# Ticket 023 — Move Keyword Aggregation to Database

**Status**: 📋 Pending
**Estimate**: 4h
**Actual**: TBD
**Priority**: 🔥 Critical (Highest ROI - 25-30x Performance Improvement)
**Dependencies**: #018 (TimeSeriesData domain type)

## Problem

The `KeywordAggregator.aggregate_keywords_for_urls/2` function performs **5 layers of processing in Elixir** that PostgreSQL can do natively with JSONB operations. This is the **single most inefficient query pattern** in the codebase after TimeSeriesAggregator.

### Current Inefficient Pattern

**File**: `lib/gsc_analytics/content_insights/keyword_aggregator.ex`
**Lines**: 41-106

```elixir
def aggregate_keywords_for_urls(urls, opts \\\\ []) when is_list(urls) do
  # LAYER 1: Fetch ALL top_queries JSONB arrays (thousands of rows)
  query =
    from ts in TimeSeries,
      where: ts.url in ^urls,
      where: not is_nil(ts.top_queries),
      select: ts.top_queries

  all_queries = Repo.all(query)  # ❌ Fetches ~14,250 JSONB arrays

  # LAYER 2: Aggregate in Elixir (nested reduces)
  aggregated =
    all_queries
    |> List.flatten()
    |> Enum.reduce(%{}, fn query_map, acc ->
      # Complex grouping and summing logic
      query = query_map["query"]
      clicks = query_map["clicks"]
      # ... aggregate metrics by query string
    end)

  # LAYER 3: Filter in Elixir
  |> Enum.filter(fn {query, _} ->
    String.length(query) >= min_length
  end)

  # LAYER 4: Sort in Elixir
  |> Enum.sort_by(fn {_, data} -> data.clicks end, :desc)

  # LAYER 5: Paginate in Elixir
  |> Enum.take(limit)
end
```

### Why This Is Catastrophically Inefficient

**For a year of data across 10 URLs:**

1. **Massive data transfer**:
   - Fetches: 14,250 JSONB arrays × ~2KB each = **~28MB transferred**
   - Needs: 100 aggregated rows × 200 bytes = **~20KB needed**
   - **Waste: 99.93% of transferred data is discarded!**

2. **Memory explosion**:
   - Loads 28MB into application heap
   - Flattens arrays (more memory allocation)
   - Builds aggregation maps (more memory)
   - **Peak memory: ~50MB+ for a single query**

3. **Slow aggregation**:
   - Elixir `Enum.reduce` over 100,000+ query objects
   - Nested hash map lookups for each query
   - String operations in hot loop
   - **~4000ms processing time**

4. **No index utilization**:
   - Can't use GIN indexes without database-side filtering
   - Full table scan on `top_queries IS NOT NULL`
   - No query planner optimization

5. **Repeated computation**:
   - Every page load recalculates the same aggregations
   - No opportunity for result caching (data too large)

### Performance Impact (Current State)

```
Query execution time: ~4000ms
Data transferred: ~28MB
Memory allocated: ~50MB heap
Database load: Minimal (just fetch)
Application load: Very high (aggregation, filtering, sorting)
User experience: 4-6 second page loads for URL detail
```

## Proposed Approach

Move **all 5 layers** to PostgreSQL using JSONB operators and native aggregation functions.

### Database-First Implementation

```elixir
defmodule GscAnalytics.ContentInsights.KeywordAggregator do
  @moduledoc """
  Aggregates keyword performance data from time_series.top_queries JSONB arrays.

  PostgreSQL-native implementation using:
  - jsonb_array_elements() to unnest arrays
  - Native aggregation (SUM, weighted averages)
  - Database filtering, sorting, pagination
  """

  import Ecto.Query
  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.TimeSeries

  @doc """
  Aggregate keywords for one or more URLs with database-native processing.

  ## Options
  - `:start_date` - Filter to dates >= this value
  - `:end_date` - Filter to dates <= this value
  - `:account_id` - Filter by account
  - `:min_length` - Minimum query string length (default: 3)
  - `:min_impressions` - Minimum total impressions (default: 10)
  - `:limit` - Max results to return (default: 100)

  ## Examples

      iex> aggregate_keywords_for_urls(["https://example.com/page"],
      ...>   start_date: ~D[2025-01-01], limit: 50)
      [
        %{query: "best seo tools", clicks: 1250, impressions: 15000, ...},
        ...
      ]
  """
  def aggregate_keywords_for_urls(urls, opts \\\\ []) when is_list(urls) do
    # Extract options
    start_date = Keyword.get(opts, :start_date)
    end_date = Keyword.get(opts, :end_date)
    account_id = Keyword.get(opts, :account_id)
    min_length = Keyword.get(opts, :min_length, 3)
    min_impressions = Keyword.get(opts, :min_impressions, 10)
    limit = Keyword.get(opts, :limit, 100)

    from(ts in TimeSeries,
      # Base filters
      where: ts.url in ^urls,
      where: not is_nil(ts.top_queries),

      # Date range filters
      where:
        fragment("? >= COALESCE(?, '1900-01-01'::date)", ts.date, ^start_date),
      where:
        fragment("? <= COALESCE(?, '2100-01-01'::date)", ts.date, ^end_date),

      # Account filter (if provided)
      where:
        fragment("? = COALESCE(?, ?)", ts.account_id, ^account_id, ts.account_id),

      # ✅ GOOD: Unnest JSONB array in PostgreSQL
      # This is the key optimization - PostgreSQL handles the array explosion
      cross_join:
        fragment(
          "jsonb_array_elements(?::jsonb) AS query_obj",
          ts.top_queries
        ),

      # ✅ GOOD: Filter in PostgreSQL (Layer 3 moved to DB)
      where:
        fragment(
          "length(query_obj->>'query') >= ?",
          ^min_length
        ),

      # ✅ GOOD: Group by query string in PostgreSQL (Layer 2 moved to DB)
      group_by: fragment("query_obj->>'query'"),

      # ✅ GOOD: Filter by minimum impressions in HAVING clause
      having:
        fragment(
          "SUM((query_obj->>'impressions')::int) >= ?",
          ^min_impressions
        ),

      # ✅ GOOD: Aggregate in PostgreSQL (Layer 2 moved to DB)
      select: %{
        query: fragment("query_obj->>'query'"),

        clicks: sum(fragment("(query_obj->>'clicks')::int")),

        impressions: sum(fragment("(query_obj->>'impressions')::int")),

        # Weighted average position
        position: fragment("""
          SUM((query_obj->>'position')::float * (query_obj->>'impressions')::int) /
          NULLIF(SUM((query_obj->>'impressions')::int), 0)
        """),

        # CTR from aggregated values
        ctr: fragment("""
          SUM((query_obj->>'clicks')::int)::float /
          NULLIF(SUM((query_obj->>'impressions')::int), 0)
        """)
      },

      # ✅ GOOD: Sort in PostgreSQL (Layer 4 moved to DB)
      order_by: [
        desc: fragment("SUM((query_obj->>'clicks')::int)")
      ],

      # ✅ GOOD: Paginate in PostgreSQL (Layer 5 moved to DB)
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Site-wide keyword aggregation (all URLs in account).
  Same optimization pattern as per-URL aggregation.
  """
  def aggregate_keywords_for_account(account_id, opts \\\\ []) do
    start_date = Keyword.get(opts, :start_date)
    end_date = Keyword.get(opts, :end_date)
    min_length = Keyword.get(opts, :min_length, 3)
    min_impressions = Keyword.get(opts, :min_impressions, 10)
    limit = Keyword.get(opts, :limit, 100)

    from(ts in TimeSeries,
      where: ts.account_id == ^account_id,
      where: not is_nil(ts.top_queries),
      where: fragment("? >= COALESCE(?, '1900-01-01'::date)", ts.date, ^start_date),
      where: fragment("? <= COALESCE(?, '2100-01-01'::date)", ts.date, ^end_date),

      cross_join:
        fragment("jsonb_array_elements(?::jsonb) AS query_obj", ts.top_queries),

      where: fragment("length(query_obj->>'query') >= ?", ^min_length),

      group_by: fragment("query_obj->>'query'"),

      having: fragment("SUM((query_obj->>'impressions')::int) >= ?", ^min_impressions),

      select: %{
        query: fragment("query_obj->>'query'"),
        clicks: sum(fragment("(query_obj->>'clicks')::int")),
        impressions: sum(fragment("(query_obj->>'impressions')::int")),
        position: fragment("""
          SUM((query_obj->>'position')::float * (query_obj->>'impressions')::int) /
          NULLIF(SUM((query_obj->>'impressions')::int), 0)
        """),
        ctr: fragment("""
          SUM((query_obj->>'clicks')::int)::float /
          NULLIF(SUM((query_obj->>'impressions')::int), 0)
        """)
      },

      order_by: [desc: fragment("SUM((query_obj->>'clicks')::int)")],
      limit: ^limit
    )
    |> Repo.all()
  end
end
```

## PostgreSQL JSONB Operations Explained

### `jsonb_array_elements()`

Unnests a JSONB array into a set of rows:

```sql
-- Input: top_queries = [{"query": "seo", "clicks": 100}, {"query": "tools", "clicks": 50}]
SELECT jsonb_array_elements(top_queries) AS query_obj
FROM time_series
WHERE url = 'https://example.com';

-- Output (2 rows):
-- query_obj: {"query": "seo", "clicks": 100}
-- query_obj: {"query": "tools", "clicks": 50}
```

### JSONB Operators

- `->` : Get JSONB object field (returns JSONB)
- `->>` : Get JSONB object field as text (returns TEXT)
- `::int`, `::float` : Cast text to numeric types

```sql
-- Extract and cast values
SELECT
  query_obj->>'query' AS query_text,           -- TEXT
  (query_obj->>'clicks')::int AS clicks,       -- INTEGER
  (query_obj->>'position')::float AS position  -- FLOAT
FROM ...
```

## Migration Strategy

### Phase 0: Preparation
1. **Create GIN index** (see ticket #024 - must be completed first!)
   ```sql
   CREATE INDEX idx_time_series_top_queries_gin
   ON time_series USING GIN (top_queries jsonb_path_ops);
   ```
2. Capture baseline metrics (execution time, memory, data transfer)
3. Add Telemetry instrumentation for new query

### Phase 1: Implement New Function
1. Create new database-first implementation alongside old one
2. Name it `aggregate_keywords_for_urls_v2` temporarily
3. Add comprehensive tests comparing results
4. Benchmark performance improvement

### Phase 2: Comparison Testing
1. Run both implementations side-by-side with production data
2. Verify results are identical (within floating point tolerance)
3. Confirm 20-30x performance improvement
4. Document comparison in ticket

### Phase 3: Cutover
1. Update callers to use new implementation:
   - `UrlPerformance.get_url_insights/2` (primary caller)
   - `DashboardUrlLive` (via UrlPerformance)
   - Any other keyword analysis features
2. Run full test suite
3. Manual QA on URL detail pages

### Phase 4: Cleanup
1. Remove old `aggregate_keywords_for_urls` implementation
2. Rename `_v2` function to original name
3. Archive old implementation for rollback reference
4. Update documentation

## Performance Benchmarking

### Test Scenario
Aggregate keywords for 1 year of data across 10 URLs (typical dashboard query).

### Before (Current Approach)

```elixir
:timer.tc(fn ->
  KeywordAggregator.aggregate_keywords_for_urls(
    urls,
    start_date: ~D[2024-01-01],
    limit: 100
  )
end)
# Expected: 3500-4500ms
# Data transferred: ~28MB (14,250 JSONB arrays)
# Memory allocated: ~50MB heap
```

### After (Database Optimization)

```elixir
:timer.tc(fn ->
  KeywordAggregator.aggregate_keywords_for_urls(
    urls,
    start_date: ~D[2024-01-01],
    limit: 100
  )
end)
# Expected: 120-180ms (with GIN index)
# Data transferred: ~20KB (100 aggregated rows)
# Memory allocated: ~1MB heap
```

### Metrics to Track
- Execution time (ms)
- Data transferred (bytes)
- Memory allocated (heap size)
- Database query time (via pg_stat_statements)
- Telemetry events (cache hit rate after #021)

### Expected Improvements
- **25-30x faster query execution** (4000ms → 140ms)
- **99.93% reduction in data transfer** (28MB → 20KB)
- **98% reduction in memory usage** (50MB → 1MB)
- **10-100x faster with GIN index** on JSONB queries

## Required Dependencies

### Ticket #024: Critical Database Indexes

**Must be completed before or alongside this ticket.**

```sql
-- GIN index for JSONB operations (CRITICAL)
CREATE INDEX idx_time_series_top_queries_gin
ON time_series USING GIN (top_queries jsonb_path_ops);

-- Composite index for filtering + JSONB (HELPFUL)
CREATE INDEX idx_time_series_url_date_top_queries
ON time_series (url, date)
WHERE top_queries IS NOT NULL;
```

Without the GIN index:
- ✅ Query will still work
- ❌ But performance gain will be only ~5-10x instead of 25-30x
- ❌ PostgreSQL will do sequential scan on `top_queries IS NOT NULL`

With the GIN index:
- ✅ 100-1000x faster JSONB element lookups
- ✅ Query planner can optimize JSONB operations
- ✅ Full 25-30x performance improvement

## Test Plan

### Unit Tests

Create `/test/gsc_analytics/content_insights/keyword_aggregator_test.exs`:

```elixir
defmodule GscAnalytics.ContentInsights.KeywordAggregatorTest do
  use GscAnalytics.DataCase

  alias GscAnalytics.ContentInsights.KeywordAggregator
  alias GscAnalytics.Schemas.TimeSeries

  describe "aggregate_keywords_for_urls/2" do
    setup do
      account_id = 1
      url = "https://example.com/test"

      # Insert test data with JSONB top_queries
      daily_data = [
        %{
          date: ~D[2025-01-06],
          url: url,
          account_id: account_id,
          clicks: 100,
          impressions: 1000,
          top_queries: [
            %{"query" => "seo tools", "clicks" => 50, "impressions" => 500, "position" => 3.2},
            %{"query" => "best seo", "clicks" => 30, "impressions" => 300, "position" => 5.1}
          ]
        },
        %{
          date: ~D[2025-01-07],
          url: url,
          account_id: account_id,
          clicks: 110,
          impressions: 1100,
          top_queries: [
            %{"query" => "seo tools", "clicks" => 60, "impressions" => 600, "position" => 3.0},
            %{"query" => "analytics", "clicks" => 25, "impressions" => 250, "position" => 7.2}
          ]
        }
      ]

      Enum.each(daily_data, fn data ->
        %TimeSeries{}
        |> TimeSeries.changeset(data)
        |> Repo.insert!()
      end)

      %{account_id: account_id, url: url}
    end

    test "aggregates keywords across multiple days", %{url: url} do
      results = KeywordAggregator.aggregate_keywords_for_urls(
        [url],
        start_date: ~D[2025-01-01]
      )

      # Should have 3 unique queries
      assert length(results) == 3

      # "seo tools" should be first (most clicks: 50 + 60 = 110)
      assert List.first(results).query == "seo tools"
      assert List.first(results).clicks == 110
      assert List.first(results).impressions == 1100

      # Verify weighted average position
      # (3.2 * 500 + 3.0 * 600) / 1100 = 3.09...
      assert_in_delta List.first(results).position, 3.09, 0.01
    end

    test "filters by minimum query length", %{url: url} do
      results = KeywordAggregator.aggregate_keywords_for_urls(
        [url],
        start_date: ~D[2025-01-01],
        min_length: 8  # Only "seo tools" and "analytics"
      )

      queries = Enum.map(results, & &1.query)
      assert "seo tools" in queries
      assert "analytics" in queries
      refute "best seo" in queries  # Only 8 chars, need >8
    end

    test "filters by minimum impressions", %{url: url} do
      results = KeywordAggregator.aggregate_keywords_for_urls(
        [url],
        start_date: ~D[2025-01-01],
        min_impressions: 500  # Only "seo tools" with 1100 total
      )

      assert length(results) == 1
      assert List.first(results).query == "seo tools"
    end

    test "respects limit parameter", %{url: url} do
      results = KeywordAggregator.aggregate_keywords_for_urls(
        [url],
        start_date: ~D[2025-01-01],
        limit: 2
      )

      assert length(results) == 2
    end

    test "handles date range filtering", %{url: url} do
      results = KeywordAggregator.aggregate_keywords_for_urls(
        [url],
        start_date: ~D[2025-01-07],
        end_date: ~D[2025-01-07]
      )

      # Should only include day 2 data
      seo_tools = Enum.find(results, &(&1.query == "seo tools"))
      assert seo_tools.clicks == 60  # Only day 2
    end

    test "aggregates across multiple URLs", %{account_id: account_id} do
      url2 = "https://example.com/other"

      %TimeSeries{}
      |> TimeSeries.changeset(%{
        date: ~D[2025-01-06],
        url: url2,
        account_id: account_id,
        clicks: 50,
        impressions: 500,
        top_queries: [
          %{"query" => "seo tools", "clicks" => 40, "impressions" => 400, "position" => 2.5}
        ]
      })
      |> Repo.insert!()

      results = KeywordAggregator.aggregate_keywords_for_urls(
        [url, url2],
        start_date: ~D[2025-01-01]
      )

      # "seo tools" should aggregate across both URLs
      seo_tools = Enum.find(results, &(&1.query == "seo tools"))
      assert seo_tools.clicks == 150  # 110 from url1 + 40 from url2
    end
  end

  describe "aggregate_keywords_for_account/2" do
    test "aggregates across all URLs in account" do
      # Similar test pattern to above
      # ...
    end
  end
end
```

### Comparison Test (Critical!)

```elixir
defmodule GscAnalytics.ContentInsights.KeywordAggregatorComparisonTest do
  use GscAnalytics.DataCase

  @moduletag :comparison

  test "new implementation produces identical results to old" do
    # Use archived old implementation
    old_results = OldKeywordAggregator.aggregate_keywords_for_urls(urls, opts)

    # Use new DB implementation
    new_results = KeywordAggregator.aggregate_keywords_for_urls(urls, opts)

    # Results should be identical
    assert length(old_results) == length(new_results)

    Enum.zip(old_results, new_results)
    |> Enum.each(fn {old, new} ->
      assert old.query == new.query
      assert old.clicks == new.clicks
      assert old.impressions == new.impressions
      assert_in_delta old.ctr, new.ctr, 0.0001
      assert_in_delta old.position, new.position, 0.01
    end)
  end
end
```

### Performance Test

```elixir
test "new implementation is at least 20x faster" do
  {old_time, _} = :timer.tc(fn ->
    OldKeywordAggregator.aggregate_keywords_for_urls(urls, opts)
  end)

  {new_time, _} = :timer.tc(fn ->
    KeywordAggregator.aggregate_keywords_for_urls(urls, opts)
  end)

  improvement_ratio = old_time / new_time
  assert improvement_ratio >= 20.0
end
```

## Rollback Plan

If issues arise after deployment:

1. **Immediate rollback**: Restore old implementation from git
   ```bash
   git revert <commit-hash>
   git push origin main
   # Redeploy
   ```

2. **Investigate discrepancies**: Use archived comparison test outputs

3. **Selective rollback**: Keep new implementation but don't use it
   ```elixir
   # Add feature flag
   def aggregate_keywords_for_urls(urls, opts) do
     if Application.get_env(:gsc_analytics, :use_db_keyword_aggregation, false) do
       aggregate_keywords_for_urls_db(urls, opts)
     else
       aggregate_keywords_for_urls_legacy(urls, opts)
     end
   end
   ```

4. **Verify recovery**: Dashboard loads, keyword data displays correctly

## Coordination Checklist

- [ ] Sync with DevOps: Ensure GIN index (#024) is deployed before or with this ticket
- [ ] Align with QA: Comparison test harness ready with production-scale data
- [ ] Communicate to stakeholders: URL detail page performance will improve dramatically
- [ ] Data Ops: Confirm JSONB data quality in `top_queries` column
- [ ] On-call: Provide rollback procedure and expected performance metrics

## Rollout & Observability

### Telemetry
- Add span: `[:gsc_analytics, :keyword_aggregator, :db_aggregation]`
- Metadata: query time, row count, cache hit (after #021)
- Alert threshold: >500ms (should be ~150ms with index)

### Staged Rollout
1. **Staging**: Run comparison tests with production snapshot
2. **Canary**: Deploy to 10% of traffic, monitor metrics
3. **Full rollout**: If metrics good, enable for 100%
4. **Cleanup**: Remove old implementation after 1 week stable

### Success Metrics
- Average query time < 200ms (target: 140ms)
- Data transfer < 50KB per request
- Memory usage < 5MB per request
- User-reported page load times improve

## Acceptance Criteria

- [ ] `aggregate_keywords_for_urls/2` uses PostgreSQL JSONB operations
- [ ] `aggregate_keywords_for_account/2` uses same optimization pattern
- [ ] All filtering done in database (min_length, min_impressions)
- [ ] Grouping and aggregation done in database
- [ ] Sorting and pagination done in database
- [ ] GIN index on `top_queries` exists (ticket #024)
- [ ] Comparison tests pass (results identical to old implementation)
- [ ] Performance benchmarks show 25-30x improvement
- [ ] Data transfer reduced by 99%+
- [ ] Memory usage reduced by 95%+
- [ ] Full test suite passes
- [ ] Manual QA: URL detail keyword table loads fast (<200ms)
- [ ] Telemetry events emit timing and row count
- [ ] Old implementation archived for rollback reference
- [ ] Documentation updated in CLAUDE.md

## Success Metrics

- **Performance**: 25-30x faster keyword aggregation
- **Network**: 99.93% reduction in data transferred (28MB → 20KB)
- **Memory**: 98% reduction in application memory (50MB → 1MB)
- **User Experience**: URL detail page loads in <1 second (vs 4-6 seconds)
- **Database Load**: Minimal with GIN index
- **Code Quality**: Single query replaces 5-layer processing pipeline

## Notes

This ticket represents the **highest ROI database optimization** after TimeSeriesAggregator (#019a). The keyword analysis feature is heavily used on every URL detail page, making this optimization visible to users immediately.

The pattern here is identical to #019a: move application-layer processing to the database where it belongs. PostgreSQL's JSONB support is mature, fast, and designed for exactly this use case.

After this ticket, the only remaining major optimization is WoW growth calculation with window functions (deferred to Sprint 4).
