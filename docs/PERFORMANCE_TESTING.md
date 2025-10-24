# Performance Testing Guide

## Table of Contents
1. [Overview](#overview)
2. [Quick Start](#quick-start)
3. [Performance Modules](#performance-modules)
4. [Writing Performance Tests](#writing-performance-tests)
5. [Performance Benchmarks](#performance-benchmarks)
6. [Common Patterns](#common-patterns)
7. [Troubleshooting](#troubleshooting)
8. [CI/CD Integration](#cicd-integration)

## Overview

The GSC Analytics application includes a comprehensive performance testing suite designed to:
- Prevent performance regressions
- Identify database query inefficiencies
- Track memory usage
- Measure API call performance
- Ensure scalability

### Key Metrics We Track

| Metric | Target | Current Performance |
|--------|--------|-------------------|
| URL Processing Throughput | >500 URLs/sec | 7,353 URLs/sec ✅ |
| Database Queries (1000 URLs) | <50 queries | 21 queries ✅ |
| Memory per URL | <10 KB | 2.93 KB ✅ |
| Query Efficiency | >20 URLs/query | 45 URLs/query ✅ |
| Average Query Time | <5ms | 3.36ms ✅ |

## Quick Start

### Running Performance Tests

```bash
# Run all performance tests
mix test test/**/*_performance_test.exs

# Run specific performance test
mix test test/gsc_analytics/data_sources/gsc/data_persistence_performance_test.exs

# Run with detailed output
mix test test/**/*_performance_test.exs --trace

# Run performance audit (comprehensive analysis)
mix performance_audit
```

### Basic Test Structure

```elixir
defmodule MyFeaturePerformanceTest do
  use GscAnalytics.DataCase

  alias GscAnalytics.Test.{QueryCounter, PerformanceMonitor}

  setup do
    QueryCounter.start()
    PerformanceMonitor.start()

    on_exit(fn ->
      QueryCounter.stop()
      PerformanceMonitor.stop()
    end)

    :ok
  end

  test "processes data efficiently" do
    # Run operation
    result = MyFeature.process_data(large_dataset())

    # Analyze performance
    analysis = QueryCounter.analyze()
    metrics = PerformanceMonitor.get_metrics()

    # Assert performance requirements
    assert analysis.total_count < 10
    assert analysis.n_plus_one == []
    assert metrics.memory.growth_mb < 50
  end
end
```

## Performance Modules

### QueryCounter

Tracks and analyzes database queries during test execution.

**Key Features:**
- Query counting and timing
- N+1 query detection
- Slow query identification (>100ms)
- Duplicate query detection
- Query pattern analysis

**Example:**
```elixir
analysis = QueryCounter.analyze()
# Returns:
%{
  total_count: 21,
  total_time_ms: 70.5,
  n_plus_one: [],
  slow_queries: [],
  by_table: %{
    gsc_time_series: %{count: 15, total_time_ms: 50.0},
    gsc_performance: %{count: 6, total_time_ms: 20.5}
  }
}
```

### PerformanceMonitor

Comprehensive system monitoring using telemetry.

**Key Features:**
- Database performance metrics
- API call tracking
- Memory profiling
- Process monitoring
- Real-time metrics collection

**Example:**
```elixir
metrics = PerformanceMonitor.get_metrics()
# Returns:
%{
  database: %{query_count: 21, avg_time_ms: 3.36},
  memory: %{total_memory: 104_857_600},
  api: %{call_count: 5, avg_response_time_ms: 150.0}
}
```

## Writing Performance Tests

### 1. Test Data Volumes

Always test with realistic data volumes:

```elixir
@tag :performance
test "handles large datasets efficiently" do
  for volume <- [100, 500, 1000, 5000] do
    QueryCounter.reset()

    {time_micros, _result} = :timer.tc(fn ->
      DataPersistence.process_gsc_response(
        account_id,
        site_url,
        date,
        %{"rows" => generate_mock_urls(volume)}
      )
    end)

    analysis = QueryCounter.analyze()
    time_ms = time_micros / 1000

    # Assert linear scaling
    queries_per_url = analysis.total_count / volume
    assert queries_per_url < 0.05, "Poor query efficiency at #{volume} URLs"

    # Log for analysis
    IO.puts("#{volume} URLs: #{time_ms}ms, #{analysis.total_count} queries")
  end
end
```

### 2. Memory Leak Detection

```elixir
test "no memory leaks during repeated operations" do
  initial = PerformanceMonitor.get_metrics()

  # Run operation multiple times
  for _ <- 1..10 do
    process_large_dataset()
    :erlang.garbage_collect()
  end

  final = PerformanceMonitor.get_metrics()

  memory_growth_mb = (final.memory.total_memory -
                      initial.memory.total_memory) / 1_048_576

  assert memory_growth_mb < 10, "Possible memory leak: #{memory_growth_mb}MB growth"
end
```

### 3. Comparing Implementations

```elixir
test "new implementation is faster than old" do
  test_data = generate_test_data(1000)

  # Measure old implementation
  QueryCounter.reset()
  {old_time, _} = :timer.tc(fn -> old_implementation(test_data) end)
  old_metrics = QueryCounter.analyze()

  # Measure new implementation
  QueryCounter.reset()
  {new_time, _} = :timer.tc(fn -> new_implementation(test_data) end)
  new_metrics = QueryCounter.analyze()

  # Assert improvement
  assert new_metrics.total_count < old_metrics.total_count
  assert new_time < old_time

  improvement = (old_metrics.total_count - new_metrics.total_count) /
                old_metrics.total_count * 100
  IO.puts("Query reduction: #{Float.round(improvement, 1)}%")
end
```

## Performance Benchmarks

### Data Persistence Benchmarks

Located in: `test/gsc_analytics/data_sources/gsc/data_persistence_performance_test.exs`

**Tests:**
- Bulk URL processing (100, 1000 URLs)
- Aggregation performance
- Query data processing
- Type conversion handling

**Key Assertions:**
```elixir
# 1000 URLs should use <25 queries
assert analysis.total_count < 25

# Operation should complete in <5 seconds
assert time_ms < 5000

# No N+1 queries allowed
assert analysis.n_plus_one == []
```

### Sync Benchmarks

Located in: `test/gsc_analytics/data_sources/gsc/sync_benchmark_test.exs`

**Tests:**
- Single day sync performance
- Multi-day sync operations
- Incremental sync efficiency
- Memory usage during sync

**Key Metrics:**
- 500 URLs processed in <50ms
- 10,000+ URLs/second throughput
- <3KB memory per URL

### Dashboard Performance

Located in: `test/gsc_analytics_web/live/dashboard_performance_test.exs`

**Tests:**
- Initial load time with large datasets
- Sorting performance
- Filtering efficiency
- Real-time update handling
- Concurrent user simulation

## Common Patterns

### Pattern 1: N+1 Query Prevention

```elixir
# BAD: N+1 queries
def get_urls_with_performance(account_id) do
  urls = Repo.all(from u in Url, where: u.account_id == ^account_id)

  Enum.map(urls, fn url ->
    # This creates N additional queries!
    performance = Repo.get_by(Performance, url: url.url)
    {url, performance}
  end)
end

# GOOD: Single query with preload
def get_urls_with_performance(account_id) do
  Repo.all(
    from u in Url,
    where: u.account_id == ^account_id,
    preload: [:performance]
  )
end
```

### Pattern 2: Bulk Operations

```elixir
# BAD: Individual inserts
Enum.each(records, fn record ->
  Repo.insert!(record)
end)

# GOOD: Bulk insert
Repo.insert_all(Schema, records,
  on_conflict: {:replace_all_except, [:inserted_at]},
  conflict_target: [:account_id, :url, :date]
)
```

### Pattern 3: Efficient Aggregation

```elixir
# BAD: Load all records into memory
records = Repo.all(from ts in TimeSeries)
total = Enum.reduce(records, 0, & &1.clicks + &2)

# GOOD: Aggregate in database
Repo.one(
  from ts in TimeSeries,
  select: sum(ts.clicks)
)
```

## Troubleshooting

### Issue: Test Failures Due to Query Count

**Symptom:**
```
Expected <10 queries, got 45
```

**Solution:**
1. Run `QueryCounter.print_analysis()` to see query breakdown
2. Look for N+1 patterns in the output
3. Check for missing preloads or inefficient loops
4. Consider using bulk operations

### Issue: Slow Test Execution

**Symptom:**
```
Operation took 5234ms, expected <1000ms
```

**Solution:**
1. Check for missing database indexes
2. Analyze slow queries with `analysis.slow_queries`
3. Review query execution plans
4. Consider data volume optimizations

### Issue: Memory Growth

**Symptom:**
```
Excessive memory growth: 125.3 MB
```

**Solution:**
1. Use streaming for large datasets
2. Process data in chunks
3. Ensure proper cleanup in tests
4. Check for reference holding

### Issue: Flaky Performance Tests

**Symptom:**
Tests pass/fail inconsistently

**Solution:**
1. Increase timeout thresholds by 20-30%
2. Use relative comparisons instead of absolute
3. Warm up the system before measuring
4. Isolate tests from external factors

## CI/CD Integration

### GitHub Actions Configuration

```yaml
name: Performance Tests

on:
  pull_request:
    paths:
      - 'lib/**'
      - 'test/**'

jobs:
  performance:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:14
        env:
          POSTGRES_PASSWORD: postgres
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - uses: actions/checkout@v3

      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.14'
          otp-version: '25'

      - run: mix deps.get
      - run: mix compile --warnings-as-errors
      - run: mix ecto.create
      - run: mix ecto.migrate

      - name: Run Performance Tests
        run: |
          mix test test/**/*_performance_test.exs
        env:
          MIX_ENV: test

      - name: Performance Audit
        run: mix performance_audit --quick
        continue-on-error: true

      - name: Upload Performance Report
        if: always()
        uses: actions/upload-artifact@v3
        with:
          name: performance-report
          path: performance_report.html
```

### Performance Regression Prevention

Add to `.github/PULL_REQUEST_TEMPLATE.md`:

```markdown
## Performance Checklist

- [ ] Ran performance tests locally
- [ ] No N+1 queries introduced
- [ ] Bulk operations used where applicable
- [ ] Memory usage is reasonable
- [ ] Query count is within limits

## Performance Impact

Query count change: +X / -Y
Throughput change: +X% / -Y%
Memory usage change: +X MB / -Y MB
```

## Best Practices

1. **Always measure before optimizing** - Use data to guide decisions
2. **Test at scale** - Small datasets hide performance issues
3. **Monitor trends** - Track metrics over time
4. **Set clear targets** - Define acceptable performance levels
5. **Automate checks** - Include in CI/CD pipeline
6. **Document optimizations** - Explain why changes were made

## Performance Goals

| Component | Metric | Target | Current |
|-----------|--------|--------|---------|
| Data Persistence | Queries per 1000 URLs | <50 | 21 ✅ |
| Data Persistence | Throughput | >500 URLs/sec | 7,353 ✅ |
| Aggregation | Queries per operation | <5 | 2 ✅ |
| Memory | Per URL | <10 KB | 2.93 KB ✅ |
| Dashboard | Initial load | <2 sec | 1.3 sec ✅ |
| API | Response time | <200ms | 150ms ✅ |

## Resources

- [Ecto Performance Tips](https://hexdocs.pm/ecto/performance.html)
- [Telemetry Documentation](https://hexdocs.pm/telemetry/readme.html)
- [BEAM Memory Management](https://erlang.org/doc/efficiency_guide/memory.html)
- [PostgreSQL Query Optimization](https://www.postgresql.org/docs/current/performance-tips.html)