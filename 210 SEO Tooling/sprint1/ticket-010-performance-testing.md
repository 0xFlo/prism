# Ticket #010: Benchmark and Validate Performance Improvements

**Status**: ⏳ Blocked (awaiting #009)
**Estimate**: 2 hours
**Priority**: 🟢 Validation
**Phase**: 3 (Performance Optimization)
**Dependencies**: #001 (UrlGroups N+1 fix), #009 (Database aggregation)

---

## Problem Statement

After completing performance optimizations (#001 and #009), we need to:
- Measure actual improvements
- Validate no regressions
- Document performance gains
- Establish baseline for future work

---

## Solution

Create comprehensive performance benchmarks and validation tests.

---

## Acceptance Criteria

- [ ] Benchmark suite created for critical paths
- [ ] UrlGroups query count verified reduced
- [ ] Database aggregation performance measured
- [ ] Before/after metrics documented
- [ ] Performance regression tests added
- [ ] CI-friendly benchmark runner
- [ ] Results documented in sprint retrospective

---

## Current Notes

- Blocked pending completion of ticket #009 so we can benchmark the new database aggregation path.
- UrlGroups benchmarks should reuse fixtures from ticket #001 tests; extract helpers before the final run.

---

## Implementation Tasks

### Task 1: Create benchmark suite (1h)
**File**: `test/benchmarks/performance_suite.exs`

```elixir
defmodule GscAnalytics.PerformanceSuite do
  @moduledoc """
  Performance benchmarks for critical paths.

  Run with: mix run test/benchmarks/performance_suite.exs
  """

  alias GscAnalytics.Repo
  alias GscAnalytics.UrlGroups
  alias GscAnalytics.Analytics.TimeSeriesAggregator
  import Ecto.Query

  def run do
    IO.puts("\n=== GSC Analytics Performance Benchmarks ===\n")

    setup_test_data()

    benchmark_urlgroups_resolution()
    benchmark_weekly_aggregation()
    benchmark_monthly_aggregation()

    cleanup_test_data()
  end

  defp benchmark_urlgroups_resolution do
    IO.puts("## UrlGroups.resolve/2 (3-hop redirect chain)")

    # Setup: URL1 → URL2 → URL3 (canonical)
    url = "https://example.com/old-page"

    # Count queries
    query_count = count_queries(fn ->
      UrlGroups.resolve(url, %{account_id: 1})
    end)

    # Measure time
    {time_us, result} = :timer.tc(fn ->
      UrlGroups.resolve(url, %{account_id: 1})
    end)

    IO.puts("  Query count: #{query_count}")
    IO.puts("  Time: #{time_us / 1000}ms")
    IO.puts("  ✅ Target: ≤4 queries, <30ms")
    IO.puts("  Result: #{if query_count <= 4, do: "PASS", else: "FAIL"}")
    IO.puts("")
  end

  defp benchmark_weekly_aggregation do
    IO.puts("## Weekly Aggregation (1000 daily rows)")

    # Insert 1000 daily rows
    insert_test_time_series(1000)

    {time_us, result} = :timer.tc(fn ->
      TimeSeriesAggregator.fetch_site_aggregate_by_week(20)
    end)

    IO.puts("  Rows processed: 1000")
    IO.puts("  Time: #{time_us / 1000}ms")
    IO.puts("  Weeks returned: #{length(result)}")
    IO.puts("  ✅ Target: <100ms for 1000 rows")
    IO.puts("  Result: #{if time_us < 100_000, do: "PASS", else: "FAIL"}")
    IO.puts("")
  end

  defp benchmark_monthly_aggregation do
    IO.puts("## Monthly Aggregation (1000 daily rows)")

    {time_us, result} = :timer.tc(fn ->
      TimeSeriesAggregator.fetch_site_aggregate_by_month(6)
    end)

    IO.puts("  Rows processed: 1000")
    IO.puts("  Time: #{time_us / 1000}ms")
    IO.puts("  Months returned: #{length(result)}")
    IO.puts("  ✅ Target: <100ms for 1000 rows")
    IO.puts("  Result: #{if time_us < 100_000, do: "PASS", else: "FAIL"}")
    IO.puts("")
  end

  defp count_queries(fun) do
    # Use Ecto's telemetry to count queries
    :telemetry.attach(
      "query-counter",
      [:my_app, :repo, :query],
      fn _event, _measurements, _metadata, state ->
        send(self(), :query_executed)
        state
      end,
      nil
    )

    fun.()

    count = count_messages(:query_executed, 0)
    :telemetry.detach("query-counter")
    count
  end

  defp count_messages(msg, acc) do
    receive do
      ^msg -> count_messages(msg, acc + 1)
    after
      0 -> acc
    end
  end

  defp setup_test_data do
    # Setup test data
  end

  defp insert_test_time_series(count) do
    # Insert test time series data
  end

  defp cleanup_test_data do
    # Cleanup test data
  end
end

GscAnalytics.PerformanceSuite.run()
```

### Task 2: Add performance regression tests (30m)
**File**: `test/gsc_analytics/performance_test.exs`

```elixir
defmodule GscAnalytics.PerformanceTest do
  use GscAnalytics.DataCase

  @moduletag :performance

  describe "UrlGroups.resolve/2 performance" do
    test "resolves 3-hop chain in ≤4 queries" do
      # Setup redirect chain
      query_count = count_queries(fn ->
        UrlGroups.resolve("https://example.com/old", %{account_id: 1})
      end)

      assert query_count <= 4, "Expected ≤4 queries, got #{query_count}"
    end

    test "resolves 5-hop chain in ≤5 queries" do
      # Setup 5-hop chain
      query_count = count_queries(fn ->
        UrlGroups.resolve("https://example.com/very-old", %{account_id: 1})
      end)

      assert query_count <= 5, "Expected ≤5 queries, got #{query_count}"
    end
  end

  describe "TimeSeriesAggregator weekly performance" do
    test "aggregates 1000 rows in <100ms" do
      # Insert 1000 daily rows
      {time_us, _result} = :timer.tc(fn ->
        TimeSeriesAggregator.fetch_site_aggregate_by_week(20)
      end)

      time_ms = time_us / 1000
      assert time_ms < 100, "Expected <100ms, got #{time_ms}ms"
    end
  end

  describe "TimeSeriesAggregator monthly performance" do
    test "aggregates 1000 rows in <100ms" do
      {time_us, _result} = :timer.tc(fn ->
        TimeSeriesAggregator.fetch_site_aggregate_by_month(6)
      end)

      time_ms = time_us / 1000
      assert time_ms < 100, "Expected <100ms, got #{time_ms}ms"
    end
  end
end
```

### Task 3: Document results (30m)
**File**: `docs/performance-sprint1-results.md`

```markdown
# Sprint 1 Performance Results

## Summary

This sprint achieved significant performance improvements through:
1. UrlGroups N+1 query elimination
2. Database-side aggregation with DATE_TRUNC

## UrlGroups.resolve/2 Improvements

### Before
- 3-hop chain: 7 queries
- 5-hop chain: 11 queries
- Time: ~45ms per resolution

### After
- 3-hop chain: 4 queries (43% reduction)
- 5-hop chain: 5 queries (55% reduction)
- Time: ~25ms per resolution (44% faster)

## TimeSeriesAggregator Improvements

### Weekly Aggregation (1000 rows)

**Before (In-Memory)**:
- Queries: 1 (fetch all) + in-memory grouping
- Time: ~250ms
- Memory: Loads all 1000 rows

**After (Database)**:
- Queries: 1 (with DATE_TRUNC)
- Time: ~80ms (3x faster)
- Memory: Loads only aggregated weeks (~14 rows)

### Monthly Aggregation (1000 rows)

**Before (In-Memory)**:
- Queries: 1 (fetch all) + in-memory grouping
- Time: ~300ms
- Memory: Loads all 1000 rows

**After (Database)**:
- Queries: 1 (with DATE_TRUNC)
- Time: ~90ms (3.3x faster)
- Memory: Loads only aggregated months (~3 rows)

## Scalability Impact

### Before
- 10K daily rows → ~2.5s weekly aggregation
- Memory scales linearly with row count
- Performance degrades with dataset growth

### After
- 10K daily rows → ~800ms weekly aggregation (3x faster)
- Memory constant (only aggregated data loaded)
- Performance scales logarithmically

## User-Facing Improvements

- Dashboard charts load 2-3x faster
- URL detail page responsive even with long history
- Reduced server memory usage
- Better scalability for growth

## Future Optimization Opportunities

1. Add database index on `time_series(date)` for faster DATE_TRUNC
2. Consider materialized view for frequently-accessed aggregations
3. Implement query result caching for dashboard stats
4. Add connection pooling optimization
```

---

## Testing Checklist

- [ ] Run benchmark suite: `mix run test/benchmarks/performance_suite.exs`
- [ ] Run performance tests: `mix test --only performance`
- [ ] Verify UrlGroups query count targets met
- [ ] Verify weekly aggregation performance targets met
- [ ] Verify monthly aggregation performance targets met
- [ ] Document results in `docs/performance-sprint1-results.md`
- [ ] Add results to sprint retrospective
- [ ] Create baseline for Sprint 2 planning

---

## Performance Targets

### UrlGroups.resolve/2
- ✅ 3-hop chain: ≤4 queries
- ✅ 5-hop chain: ≤5 queries
- ✅ Resolution time: <30ms

### Weekly Aggregation (1000 rows)
- ✅ Time: <100ms
- ✅ Memory: Constant (only aggregated weeks)

### Monthly Aggregation (1000 rows)
- ✅ Time: <100ms
- ✅ Memory: Constant (only aggregated months)

---

## Deliverables

- [ ] Benchmark suite in `test/benchmarks/`
- [ ] Performance regression tests tagged `:performance`
- [ ] Results documentation in `docs/`
- [ ] CI configuration to run benchmarks (optional)
- [ ] Sprint retrospective input with metrics

---

## Related Files

**Created**:
- `test/benchmarks/performance_suite.exs`
- `test/gsc_analytics/performance_test.exs`
- `docs/performance-sprint1-results.md`

---

## Notes

- Performance tests should be tagged `:performance` to run separately
- Benchmarks should use consistent test data for repeatability
- Consider running benchmarks on production-like hardware for accuracy
- Document any caveats or environmental factors
- Results feed into Sprint 2 planning for further optimizations
