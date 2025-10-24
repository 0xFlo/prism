# PostgreSQL Window Functions Research

## What Are Window Functions?

Window functions perform calculations across a set of table rows that are **related to the current row**. Unlike aggregate functions with `GROUP BY` that collapse multiple rows into one, window functions **preserve all rows** while allowing access to other rows within the "window".

## Key Concepts

### 1. Window Frame
A "window" is a set of rows related to the current row, defined by:
- **`PARTITION BY`**: Divides rows into groups (like GROUP BY, but doesn't collapse)
- **`ORDER BY`**: Orders rows within each partition

### 2. Core Window Functions

#### LAG(value, offset)
Access a value from a **previous row** within the partition:
```sql
LAG(clicks, 1) OVER (PARTITION BY url ORDER BY week_start)
-- Returns clicks from 1 week ago for the same URL
```

#### LEAD(value, offset)
Access a value from a **next row** within the partition:
```sql
LEAD(clicks, 1) OVER (PARTITION BY url ORDER BY week_start)
-- Returns clicks from 1 week ahead for the same URL
```

#### ROW_NUMBER()
Assigns sequential number to each row within partition:
```sql
ROW_NUMBER() OVER (PARTITION BY url ORDER BY week_start)
```

#### RANK() / DENSE_RANK()
Assigns rank with gaps (RANK) or without gaps (DENSE_RANK):
```sql
RANK() OVER (PARTITION BY url ORDER BY clicks DESC)
```

### 3. Window Syntax

```sql
<function>(...) OVER (
  PARTITION BY <partition_columns>
  ORDER BY <order_columns>
  [ROWS/RANGE BETWEEN ...]
)
```

**Named Windows** (cleaner):
```sql
SELECT
  url,
  clicks,
  LAG(clicks, 1) OVER w AS prev_clicks
FROM weekly_data
WINDOW w AS (PARTITION BY url ORDER BY week_start)
```

## WoW Growth Example

### Problem
Calculate week-over-week growth for multiple URLs:
- For each URL, compare current week's clicks to previous week
- Need: current_clicks, previous_clicks, growth percentage

### Solution with Window Functions

```sql
WITH weekly_metrics AS (
  -- First, aggregate daily data into weekly metrics
  SELECT
    url,
    DATE_TRUNC('week', date)::date AS week_start,
    SUM(clicks) AS clicks,
    SUM(impressions) AS impressions
  FROM gsc_time_series
  WHERE url IN ('https://example.com/page1', 'https://example.com/page2')
    AND date >= '2025-01-01'
  GROUP BY url, DATE_TRUNC('week', date)::date
)
SELECT
  url,
  week_start,
  clicks,
  impressions,

  -- Previous week metrics using LAG
  LAG(clicks, 1) OVER (PARTITION BY url ORDER BY week_start) AS prev_clicks,
  LAG(impressions, 1) OVER (PARTITION BY url ORDER BY week_start) AS prev_impressions,

  -- Growth calculation (handles NULL and division by zero)
  CASE
    WHEN LAG(clicks, 1) OVER (PARTITION BY url ORDER BY week_start) = 0
      OR LAG(clicks, 1) OVER (PARTITION BY url ORDER BY week_start) IS NULL
    THEN NULL
    ELSE (
      (clicks - LAG(clicks, 1) OVER (PARTITION BY url ORDER BY week_start))
      / LAG(clicks, 1) OVER (PARTITION BY url ORDER BY week_start)::float
    ) * 100
  END AS wow_growth_pct

FROM weekly_metrics
ORDER BY url, week_start;
```

### Example Results

| url | week_start | clicks | prev_clicks | wow_growth_pct |
|-----|-----------|--------|-------------|----------------|
| example.com/page1 | 2025-01-06 | 100 | NULL | NULL |
| example.com/page1 | 2025-01-13 | 110 | 100 | 10.0 |
| example.com/page1 | 2025-01-20 | 132 | 110 | 20.0 |
| example.com/page2 | 2025-01-06 | 200 | NULL | NULL |
| example.com/page2 | 2025-01-13 | 180 | 200 | -10.0 |

## Ecto Implementation Patterns

### Pattern 1: Using Fragments (Works on all Ecto versions)

```elixir
from(w in weekly_metrics_subquery,
  select: %{
    url: w.url,
    week_start: w.week_start,
    clicks: w.clicks,
    prev_clicks: fragment(
      "LAG(?, 1) OVER (PARTITION BY ? ORDER BY ?)",
      w.clicks, w.url, w.week_start
    ),
    wow_growth_pct: fragment("""
      CASE
        WHEN LAG(?, 1) OVER (PARTITION BY ? ORDER BY ?) = 0
          OR LAG(?, 1) OVER (PARTITION BY ? ORDER BY ?) IS NULL
        THEN NULL
        ELSE ((? - LAG(?, 1) OVER (PARTITION BY ? ORDER BY ?))
              / LAG(?, 1) OVER (PARTITION BY ? ORDER BY ?)::float) * 100
      END
    """,
      w.clicks, w.url, w.week_start,
      w.clicks, w.url, w.week_start,
      w.clicks, w.clicks, w.url, w.week_start,
      w.clicks, w.url, w.week_start
    )
  }
)
```

**Pros**: Works on any Ecto version
**Cons**: Verbose, repetitive window definitions

### Pattern 2: Named Windows (Cleaner)

```elixir
from(w in weekly_metrics_subquery,
  windows: [
    by_url: [
      partition_by: w.url,
      order_by: w.week_start
    ]
  ],
  select: %{
    url: w.url,
    week_start: w.week_start,
    clicks: w.clicks,
    prev_clicks: fragment("LAG(?, 1) OVER by_url", w.clicks),
    wow_growth_pct: fragment("""
      CASE
        WHEN LAG(?, 1) OVER by_url = 0 OR LAG(?, 1) OVER by_url IS NULL
        THEN NULL
        ELSE ((? - LAG(?, 1) OVER by_url) / LAG(?, 1) OVER by_url::float) * 100
      END
    """,
      w.clicks, w.clicks,
      w.clicks, w.clicks, w.clicks
    )
  }
)
```

**Pros**: Named windows reduce repetition
**Cons**: Still using fragments for LAG calls

### Pattern 3: Ecto.Query.WindowAPI (Ecto 3.x+, preferred)

```elixir
import Ecto.Query.WindowAPI

from(w in weekly_metrics_subquery,
  windows: [by_url: [partition_by: w.url, order_by: w.week_start]],
  select: %{
    url: w.url,
    week_start: w.week_start,
    clicks: w.clicks,
    prev_clicks: lag(w.clicks, 1) |> over(:by_url),
    impressions: w.impressions,
    prev_impressions: lag(w.impressions, 1) |> over(:by_url),
    # Note: Growth calc still needs fragment for CASE logic
    wow_growth_pct: fragment("""
      ((? - LAG(?, 1) OVER by_url) / NULLIF(LAG(?, 1) OVER by_url, 0)::float) * 100
    """,
      w.clicks, w.clicks, w.clicks
    )
  }
)
```

**Pros**: Clean, type-safe LAG/LEAD calls
**Cons**: Requires Ecto 3.x+, complex calculations still need fragments

## Performance Characteristics

### Before (Fetch-All-Then-Process)
```
1. Fetch 7,300+ rows from database
2. Transfer ~28MB over network
3. Allocate ~15MB heap memory
4. Nested loop matching: O(n²)
5. Total time: ~2000ms
```

### After (Window Functions)
```
1. PostgreSQL aggregates to 52 weekly rows
2. PostgreSQL calculates LAG values
3. PostgreSQL computes growth percentages
4. Transfer ~52 rows (~20KB) over network
5. Total time: ~100ms (20x faster)
```

### Why It's Faster
1. **Less data transfer**: 52 rows vs 7,300 rows (99.3% reduction)
2. **No nested loops**: PostgreSQL window functions are O(n log n)
3. **No heap allocation**: Calculations happen in database
4. **Index utilization**: Uses existing (url, date) indexes
5. **Compiled query plan**: PostgreSQL optimizes the query

## Gotchas & Best Practices

### 1. NULL Handling
LAG returns NULL if there's no previous row:
```sql
LAG(clicks, 1) OVER (...)  -- NULL for first row
```
Always check for NULL in growth calculations.

### 2. Division by Zero
Previous value might be 0:
```sql
CASE
  WHEN LAG(clicks, 1) OVER (...) = 0 THEN NULL
  ELSE (clicks - LAG(...)) / LAG(...)::float * 100
END
```
Or use `NULLIF`:
```sql
(clicks - LAG(...)) / NULLIF(LAG(...), 0)::float * 100
```

### 3. Partition Order Matters
```sql
-- WRONG: No partition, compares across all URLs
LAG(clicks, 1) OVER (ORDER BY week_start)

-- CORRECT: Partition by URL, compare within same URL
LAG(clicks, 1) OVER (PARTITION BY url ORDER BY week_start)
```

### 4. Window Function Execution Order
Window functions execute **after** WHERE, GROUP BY, HAVING:
```sql
SELECT LAG(clicks, 1) OVER (...)
FROM (
  SELECT url, DATE_TRUNC('week', date) AS week_start, SUM(clicks) AS clicks
  FROM gsc_time_series
  WHERE date >= '2025-01-01'  -- ✅ Filters before window
  GROUP BY url, week_start     -- ✅ Aggregates before window
) weekly_metrics
```

### 5. CTE vs Subquery
Common Table Expressions (CTEs) are clearer but may prevent optimization in PostgreSQL < 12:
```elixir
# Subquery (always optimized)
weekly_metrics = from(ts in TimeSeries, ...)
from(w in subquery(weekly_metrics), ...)

# CTE (clearer, but check EXPLAIN plan)
# Ecto doesn't directly support CTEs in from(), use raw SQL if needed
```

## Comparison: GROUP BY vs Window Functions

### GROUP BY (Aggregate Functions)
```sql
SELECT
  url,
  DATE_TRUNC('week', date) AS week_start,
  SUM(clicks) AS total_clicks  -- Collapses rows
FROM gsc_time_series
GROUP BY url, DATE_TRUNC('week', date)
```
**Result**: One row per (url, week) combination

### Window Functions
```sql
SELECT
  url,
  date,
  clicks,
  SUM(clicks) OVER (PARTITION BY url) AS url_total  -- Doesn't collapse
FROM gsc_time_series
```
**Result**: All original rows preserved, with url_total added

## When to Use Window Functions

✅ **Use window functions when:**
- Need current row + related row data (previous/next)
- Want to preserve row-level detail while computing aggregates
- Calculating running totals, moving averages, rankings
- Comparing rows within groups (WoW, MoM growth)

❌ **Use GROUP BY when:**
- Only need aggregated totals (don't need row-level detail)
- Reducing data volume is the goal
- No need to compare rows within groups

## PostgreSQL Version Requirements

- **Window functions**: PostgreSQL 8.4+ (released 2009)
- **LAG/LEAD**: PostgreSQL 8.4+
- **Named windows (WINDOW clause)**: PostgreSQL 9.0+
- **RANGE frames**: PostgreSQL 11+

Our requirement: PostgreSQL 9.4+ ✅ (all features available)

## Ecto Version Requirements

- **Basic fragments**: All Ecto versions ✅
- **`windows` option**: Ecto 3.0+ (2019)
- **Ecto.Query.WindowAPI**: Ecto 3.7+ (2021)

Check current version:
```bash
mix deps | grep ecto
```

## Implementation Plan for #025

1. **Check Ecto version** - Use WindowAPI if 3.7+, otherwise fragments
2. **Create CTE for weekly aggregation** - Reuse DATE_TRUNC pattern from #019a
3. **Apply LAG window function** - Get previous week metrics
4. **Calculate growth in SELECT** - Handle NULL and division by zero
5. **Keep legacy function temporarily** - For comparison testing
6. **Write comprehensive tests** - Verify growth calculations
7. **Benchmark performance** - Confirm 20x improvement

## References

- [PostgreSQL Window Functions Documentation](https://www.postgresql.org/docs/current/tutorial-window.html)
- [Ecto.Query.WindowAPI Documentation](https://hexdocs.pm/ecto/Ecto.Query.WindowAPI.html)
- [Use The Index, Luke: Window Functions](https://use-the-index-luke.com/sql/partial-results/window-functions)
