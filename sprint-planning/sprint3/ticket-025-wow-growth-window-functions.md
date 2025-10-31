# Ticket 025 — Week-over-Week Growth with PostgreSQL Window Functions

**Status**: 📋 Pending
**Estimate**: 3h
**Actual**: TBD
**Priority**: 🟡 Medium (Performance optimization, completes the "critical three")
**Dependencies**: #019a (Database aggregation foundation)

## Problem

The `batch_calculate_wow_growth/3` function in TimeSeriesAggregator performs a **fetch-all-then-process pattern** that is fundamentally inefficient:

**File**: `lib/gsc_analytics/analytics/time_series_aggregator.ex`
**Lines**: 106-156

### Current Inefficient Pattern

```elixir
def batch_calculate_wow_growth(current_week_data, comparison_start_date, opts) do
  # STEP 1: Fetch ALL historical data (thousands of rows)
  previous_data =
    current_week_data
    |> Enum.map(& &1.url)
    |> fetch_daily_data_for_urls(comparison_start_date, opts)  # ❌ Fetches 7,300+ rows
    |> aggregate_by_week()  # ❌ Aggregates in Elixir

  # STEP 2: Nested loop to match current week with previous week
  Enum.map(current_week_data, fn current ->
    previous = Enum.find(previous_data, fn prev ->
      prev.url == current.url && prev.week_start == week_ago(current.week_start)
    end)

    # STEP 3: Calculate percentage change in Elixir
    calculate_percentage_change(current, previous)
  end)
end
```

### Why This Is Inefficient

**For calculating WoW growth for 10 URLs over 1 year:**

1. **Massive data fetch**:
   - Current week: 52 rows
   - Historical comparison: ~7,300 rows (full year of daily data)
   - **Total: 7,352 rows transferred**

2. **Application-layer aggregation**:
   - Aggregates historical data by week in Elixir (slow)
   - Already addressed by #019a but still fetching too much

3. **Nested loops for matching**:
   - O(n²) complexity: for each current week, find matching previous week
   - String comparisons, date math in Elixir

4. **Repeated computation**:
   - Same historical data re-fetched on every dashboard load
   - No opportunity for database optimization

### Performance Impact (Current State)

```
Query execution time: ~2000ms
Data transferred: ~7,300 rows
Memory allocated: ~15MB heap
Application complexity: High (nested loops, matching logic)
User experience: Slow dashboard loading with growth indicators
```

## Proposed Approach

Use PostgreSQL **window functions** to calculate WoW growth entirely in the database.

### Window Functions Explained

Window functions perform calculations across a set of table rows related to the current row. Key functions:

- **`LAG(value, offset)`**: Access value from previous row(s)
- **`LEAD(value, offset)`**: Access value from next row(s)
- **`PARTITION BY`**: Group rows for window calculation
- **`ORDER BY`**: Order rows within partition

```sql
-- Example: Get previous week's clicks for each URL
SELECT
  url,
  week_start,
  clicks,
  LAG(clicks, 1) OVER (
    PARTITION BY url
    ORDER BY week_start
  ) as prev_week_clicks
FROM weekly_metrics;
```

### Database-First Implementation

```elixir
defmodule GscAnalytics.Analytics.TimeSeriesAggregator do
  @moduledoc """
  Calculates week-over-week growth using PostgreSQL window functions.

  This approach is 20x faster than fetching all data and computing in Elixir.
  """

  import Ecto.Query
  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.TimeSeries

  @doc """
  Calculate week-over-week growth for multiple URLs using database window functions.

  ## Options
  - `:start_date` - Calculate growth from this date forward
  - `:account_id` - Filter by account
  - `:weeks_back` - How many weeks back to compare (default: 1 for WoW)

  ## Examples

      iex> batch_calculate_wow_growth(
      ...>   ["https://example.com/page"],
      ...>   %{start_date: ~D[2025-01-01], weeks_back: 1}
      ...> )
      [
        %{
          url: "https://example.com/page",
          week_start: ~D[2025-01-13],
          clicks: 1200,
          prev_clicks: 1100,
          wow_growth_pct: 9.09,
          impressions: 15000,
          prev_impressions: 14000,
          wow_growth_impressions_pct: 7.14
        },
        ...
      ]

  ## Performance
  - Before: Fetch 7,300+ rows, aggregate in Elixir, nested loops (~2000ms)
  - After: Single query with window functions (~100ms)
  - **20x faster**
  """
  def batch_calculate_wow_growth(urls, opts \\\\ %{}) when is_list(urls) do
    start_date = Map.get(opts, :start_date)
    account_id = Map.get(opts, :account_id)
    weeks_back = Map.get(opts, :weeks_back, 1)

    # CTE: First aggregate daily data into weekly metrics
    weekly_metrics_cte = from(ts in TimeSeries,
      where: ts.url in ^urls,
      where: ts.date >= ^start_date,
      where: fragment("? = COALESCE(?, ?)", ts.account_id, ^account_id, ts.account_id),
      group_by: [
        ts.url,
        fragment("DATE_TRUNC('week', ?)::date", ts.date)
      ],
      select: %{
        url: ts.url,
        week_start: fragment("DATE_TRUNC('week', ?)::date", ts.date),
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
      }
    )

    # Main query: Apply window functions to calculate growth
    from(w in subquery(weekly_metrics_cte),
      windows: [
        url_window: [
          partition_by: w.url,
          order_by: w.week_start
        ]
      ],
      select: %{
        url: w.url,
        week_start: w.week_start,

        # Current metrics
        clicks: w.clicks,
        impressions: w.impressions,
        position: w.position,
        ctr: w.ctr,

        # Previous week metrics using LAG
        prev_clicks: over(lag(w.clicks, ^weeks_back), :url_window),
        prev_impressions: over(lag(w.impressions, ^weeks_back), :url_window),
        prev_position: over(lag(w.position, ^weeks_back), :url_window),

        # Growth calculations
        wow_growth_pct: fragment("""
          CASE
            WHEN LAG(?, ?) OVER (
              PARTITION BY ? ORDER BY ?
            ) = 0 OR LAG(?, ?) OVER (
              PARTITION BY ? ORDER BY ?
            ) IS NULL THEN NULL
            ELSE (
              (? - LAG(?, ?) OVER (
                PARTITION BY ? ORDER BY ?
              )) / LAG(?, ?) OVER (
                PARTITION BY ? ORDER BY ?
              )::float
            ) * 100
          END
        """,
          w.clicks, ^weeks_back, w.url, w.week_start,
          w.clicks, ^weeks_back, w.url, w.week_start,
          w.clicks, w.clicks, ^weeks_back, w.url, w.week_start,
          w.clicks, ^weeks_back, w.url, w.week_start
        ),

        wow_growth_impressions_pct: fragment("""
          CASE
            WHEN LAG(?, ?) OVER (
              PARTITION BY ? ORDER BY ?
            ) = 0 OR LAG(?, ?) OVER (
              PARTITION BY ? ORDER BY ?
            ) IS NULL THEN NULL
            ELSE (
              (? - LAG(?, ?) OVER (
                PARTITION BY ? ORDER BY ?
              )) / LAG(?, ?) OVER (
                PARTITION BY ? ORDER BY ?
              )::float
            ) * 100
          END
        """,
          w.impressions, ^weeks_back, w.url, w.week_start,
          w.impressions, ^weeks_back, w.url, w.week_start,
          w.impressions, w.impressions, ^weeks_back, w.url, w.week_start,
          w.impressions, ^weeks_back, w.url, w.week_start
        )
      },
      order_by: [w.url, w.week_start]
    )
    |> Repo.all()
  end

  @doc """
  Simplified version using Ecto.Query.WindowAPI (Ecto 3.x+)

  This is the preferred approach if your Ecto version supports WindowAPI.
  Cleaner syntax, same performance.
  """
  def batch_calculate_wow_growth_windowapi(urls, opts \\\\ %{}) do
    import Ecto.Query.WindowAPI

    start_date = Map.get(opts, :start_date)
    account_id = Map.get(opts, :account_id)
    weeks_back = Map.get(opts, :weeks_back, 1)

    # First aggregate to weekly metrics
    weekly_metrics = from(ts in TimeSeries,
      where: ts.url in ^urls,
      where: ts.date >= ^start_date,
      where: fragment("? = COALESCE(?, ?)", ts.account_id, ^account_id, ts.account_id),
      group_by: [ts.url, fragment("DATE_TRUNC('week', ?)", ts.date)],
      select: %{
        url: ts.url,
        week_start: fragment("DATE_TRUNC('week', ?)::date", ts.date),
        clicks: sum(ts.clicks),
        impressions: sum(ts.impressions)
      }
    )

    # Apply window functions with cleaner WindowAPI syntax
    from(w in subquery(weekly_metrics),
      windows: [by_url: [partition_by: w.url, order_by: w.week_start]],
      select: %{
        url: w.url,
        week_start: w.week_start,
        clicks: w.clicks,
        prev_clicks: lag(w.clicks, ^weeks_back) |> over(:by_url),
        wow_growth_pct: fragment("""
          ((? - LAG(?, ?) OVER (PARTITION BY ? ORDER BY ?)) /
           NULLIF(LAG(?, ?) OVER (PARTITION BY ? ORDER BY ?), 0)::float) * 100
        """,
          w.clicks, w.clicks, ^weeks_back, w.url, w.week_start,
          w.clicks, ^weeks_back, w.url, w.week_start
        )
      }
    )
    |> Repo.all()
  end
end
```

## Migration Strategy

### Phase 1: Implement New Function
1. Add new `batch_calculate_wow_growth` with window functions
2. Keep old implementation temporarily as `batch_calculate_wow_growth_legacy`
3. Add comprehensive tests

### Phase 2: Comparison Testing
1. Run both implementations side-by-side
2. Verify results are identical (within floating point tolerance)
3. Benchmark performance (expect 20x improvement)

### Phase 3: Update Callers
1. Update callers (likely in UrlPerformance or dashboard contexts)
2. Verify growth indicators display correctly in UI
3. Run full test suite

### Phase 4: Cleanup
1. Remove legacy implementation
2. Archive for rollback reference
3. Update documentation

## Performance Benchmarking

### Before (Current Approach)

```elixir
:timer.tc(fn ->
  TimeSeriesAggregator.batch_calculate_wow_growth(
    current_week_data,
    comparison_start_date,
    %{account_id: 1}
  )
end)
# Expected: 1800-2200ms
# Data transferred: ~7,300 rows
# Memory: ~15MB heap
```

### After (Window Functions)

```elixir
:timer.tc(fn ->
  TimeSeriesAggregator.batch_calculate_wow_growth(
    urls,
    %{start_date: comparison_start_date, account_id: 1}
  )
end)
# Expected: 80-120ms
# Data transferred: ~52 rows (only weeks with growth calculated)
# Memory: ~1MB heap
```

### Metrics to Track
- Execution time (ms)
- Data transferred (rows)
- Memory allocated
- Database query time
- UI rendering time for growth indicators

### Expected Improvements
- **20x faster execution** (2000ms → 100ms)
- **99%+ reduction in data transfer** (7,300 rows → 52 rows)
- **93% reduction in memory** (15MB → 1MB)
- **Eliminates nested loops** (O(n²) → O(n log n))

## Required Dependencies

### Database Support
- PostgreSQL 9.4+ (window functions)
- No additional indexes required (uses same indexes as #019a)

### Ecto Version
- Ecto 3.x+ for WindowAPI support (optional, cleaner syntax)
- Works with fragments on older Ecto versions

## Test Plan

### Unit Tests

```elixir
defmodule GscAnalytics.Analytics.TimeSeriesAggregatorWoWTest do
  use GscAnalytics.DataCase

  alias GscAnalytics.Analytics.TimeSeriesAggregator
  alias GscAnalytics.Schemas.TimeSeries

  describe "batch_calculate_wow_growth/2" do
    setup do
      account_id = 1
      url = "https://example.com/test"

      # Insert 4 weeks of data
      weeks_data = [
        # Week 1 (baseline)
        %{date: ~D[2025-01-06], clicks: 100, impressions: 1000},
        %{date: ~D[2025-01-07], clicks: 110, impressions: 1100},

        # Week 2 (10% growth)
        %{date: ~D[2025-01-13], clicks: 110, impressions: 1100},
        %{date: ~D[2025-01-14], clicks: 121, impressions: 1210},

        # Week 3 (20% growth from week 2)
        %{date: ~D[2025-01-20], clicks: 132, impressions: 1320},
        %{date: ~D[2025-01-21], clicks: 145, impressions: 1452},

        # Week 4 (negative growth)
        %{date: ~D[2025-01-27], clicks: 100, impressions: 1000},
        %{date: ~D[2025-01-28], clicks: 110, impressions: 1100}
      ]

      Enum.each(weeks_data, fn data ->
        %TimeSeries{}
        |> TimeSeries.changeset(Map.merge(data, %{
          url: url,
          account_id: account_id,
          ctr: data.clicks / data.impressions,
          position: 5.0
        }))
        |> Repo.insert!()
      end)

      %{account_id: account_id, url: url}
    end

    test "calculates WoW growth correctly", %{url: url, account_id: account_id} do
      results = TimeSeriesAggregator.batch_calculate_wow_growth(
        [url],
        %{start_date: ~D[2025-01-01], account_id: account_id, weeks_back: 1}
      )

      # Week 1 has no previous data (NULL growth)
      week1 = Enum.find(results, &(&1.week_start == ~D[2025-01-06]))
      assert is_nil(week1.wow_growth_pct)

      # Week 2: (231 - 210) / 210 * 100 = 10%
      week2 = Enum.find(results, &(&1.week_start == ~D[2025-01-13]))
      assert week2.clicks == 231  # 110 + 121
      assert week2.prev_clicks == 210  # 100 + 110
      assert_in_delta week2.wow_growth_pct, 10.0, 0.5

      # Week 3: (277 - 231) / 231 * 100 ≈ 19.9%
      week3 = Enum.find(results, &(&1.week_start == ~D[2025-01-20]))
      assert_in_delta week3.wow_growth_pct, 19.9, 0.5

      # Week 4: Negative growth
      week4 = Enum.find(results, &(&1.week_start == ~D[2025-01-27]))
      assert week4.wow_growth_pct < 0
    end

    test "handles multiple URLs independently", %{account_id: account_id} do
      url2 = "https://example.com/other"

      # Add data for second URL with different growth pattern
      # ...

      results = TimeSeriesAggregator.batch_calculate_wow_growth(
        [url, url2],
        %{start_date: ~D[2025-01-01], account_id: account_id}
      )

      # Growth should be calculated independently per URL
      url1_results = Enum.filter(results, &(&1.url == url))
      url2_results = Enum.filter(results, &(&1.url == url2))

      assert length(url1_results) == 4
      assert length(url2_results) == 4
    end

    test "supports custom weeks_back parameter", %{url: url, account_id: account_id} do
      # Compare to 2 weeks back instead of 1 week
      results = TimeSeriesAggregator.batch_calculate_wow_growth(
        [url],
        %{start_date: ~D[2025-01-01], account_id: account_id, weeks_back: 2}
      )

      # Week 3 should compare to Week 1, not Week 2
      week3 = Enum.find(results, &(&1.week_start == ~D[2025-01-20]))
      assert week3.prev_clicks == 210  # Week 1 total
    end
  end
end
```

### Comparison Test

```elixir
@moduletag :comparison

test "window functions produce identical results to legacy approach" do
  legacy_results = TimeSeriesAggregator.batch_calculate_wow_growth_legacy(...)
  new_results = TimeSeriesAggregator.batch_calculate_wow_growth(...)

  Enum.zip(legacy_results, new_results)
  |> Enum.each(fn {legacy, new} ->
    assert legacy.url == new.url
    assert legacy.week_start == new.week_start
    assert_in_delta legacy.wow_growth_pct, new.wow_growth_pct, 0.01
  end)
end
```

## Rollback Plan

1. **Immediate rollback**: Restore legacy implementation
2. **Feature flag approach**: Keep both implementations, switch via config
3. **Verify recovery**: Growth indicators display correctly

## Coordination Checklist

- [ ] Verify Ecto version (3.x+ for WindowAPI, or use fragments)
- [ ] Confirm PostgreSQL version (9.4+ for window functions)
- [ ] Align with UI team: growth indicator format unchanged
- [ ] QA: Test growth calculations with various data patterns
- [ ] Document window function approach for future use

## Acceptance Criteria

- [ ] `batch_calculate_wow_growth/2` uses PostgreSQL window functions
- [ ] LAG function calculates previous week metrics
- [ ] Growth percentage calculated in database
- [ ] Comparison tests pass (results identical to legacy)
- [ ] Performance benchmarks show 20x improvement
- [ ] Data transfer reduced by 99%+
- [ ] Memory usage reduced by 90%+
- [ ] Full test suite passes
- [ ] Manual QA: Dashboard growth indicators display correctly
- [ ] Legacy implementation archived for rollback
- [ ] Documentation updated with window function pattern

## Success Metrics

- **Performance**: 20x faster growth calculation (2000ms → 100ms)
- **Network**: 99%+ reduction in data transferred (7,300 rows → 52 rows)
- **Memory**: 93% reduction in application memory (15MB → 1MB)
- **Complexity**: Eliminates nested loops (O(n²) → O(n log n))
- **User Experience**: Instant growth indicators on dashboard

## Notes

This ticket completes the "critical three" database optimizations identified in the technical debt audit:
1. ✅ #019a: TimeSeriesAggregator (time-series data)
2. ✅ #023: KeywordAggregator (JSONB data)
3. ✅ #025: WoW Growth (window functions)

After this ticket, **all major aggregation operations** happen in the database. The application layer focuses on business logic and presentation, not data processing.

Window functions are a powerful feature of modern SQL databases. This pattern can be applied to other growth calculations:
- Month-over-month (MoM) growth
- Year-over-year (YoY) growth
- Rolling averages
- Trend analysis

The Ecto.Query.WindowAPI syntax (shown in the simplified version) is the preferred approach for Ecto 3.x+. It provides cleaner, more readable code with the same performance.
