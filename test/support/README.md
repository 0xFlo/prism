# Test Support Modules

This directory contains testing utilities and helpers for the GSC Analytics application, with a strong focus on performance monitoring and database query analysis.

## Overview

Our test suite includes specialized modules for tracking and analyzing application performance during tests. These tools help ensure that code changes don't introduce performance regressions and that the application maintains efficient database usage patterns.

## Available Modules

### 🔍 QueryCounter (`query_counter.ex`)

A GenServer that tracks all database queries executed during tests. It provides detailed analysis including:

- Total query count and execution time
- N+1 query detection
- Slow query identification
- Duplicate query detection
- Query pattern normalization

**Usage:**

```elixir
setup do
  QueryCounter.start()
  on_exit(fn -> QueryCounter.stop() end)
  :ok
end

test "my performance test" do
  # Run your code
  perform_some_operations()

  # Analyze the queries
  analysis = QueryCounter.analyze()

  assert analysis.total_count < 10
  assert analysis.n_plus_one == []
  assert analysis.slow_queries == []

  # Print detailed report
  QueryCounter.print_analysis()
end
```

**Analysis Structure:**

```elixir
%{
  total_count: 42,                    # Total number of queries
  total_time_ms: 125.5,               # Total time spent in DB
  by_table: %{users: %{count: 10}},  # Queries grouped by table
  by_operation: %{select: %{}},      # Queries grouped by operation
  slow_queries: [...],                # Queries > 100ms
  n_plus_one: [...],                  # Detected N+1 patterns
  duplicate_queries: [...]            # Exact duplicate queries
}
```

### 📊 PerformanceMonitor (`performance_monitor.ex`)

A comprehensive performance monitoring system that uses telemetry to track:

- Database query performance
- GSC API call metrics
- Sync operation throughput
- Memory usage
- Process metrics

**Usage:**

```elixir
setup do
  PerformanceMonitor.start()
  on_exit(fn -> PerformanceMonitor.stop() end)
  :ok
end

test "memory efficiency test" do
  initial = PerformanceMonitor.get_metrics()

  # Run memory-intensive operations
  process_large_dataset()

  final = PerformanceMonitor.get_metrics()

  memory_growth_mb = (final.memory.total_memory -
                      initial.memory.total_memory) / 1_048_576

  assert memory_growth_mb < 100

  # Print comprehensive report
  PerformanceMonitor.print_report()
end
```

**Metrics Structure:**

```elixir
%{
  elapsed_seconds: 10.5,
  database: %{
    query_count: 100,
    total_time_ms: 250.0,
    avg_time_ms: 2.5,
    queries_per_second: 10.0
  },
  api: %{
    call_count: 50,
    total_rows: 5000,
    avg_response_time_ms: 150.0,
    rate_limited_count: 0
  },
  memory: %{
    process_memory: 104857600,  # bytes
    ets_memory: 2097152,
    total_memory: 209715200
  }
}
```

## Performance Testing Best Practices

### 1. Always Reset Counters

When testing multiple scenarios, reset counters between tests:

```elixir
test "compare different approaches" do
  # Test approach A
  QueryCounter.reset()
  approach_a()
  a_metrics = QueryCounter.analyze()

  # Test approach B
  QueryCounter.reset()
  approach_b()
  b_metrics = QueryCounter.analyze()

  assert a_metrics.total_count < b_metrics.total_count
end
```

### 2. Use Meaningful Assertions

Don't just collect metrics - assert on them:

```elixir
# Good - specific performance requirements
assert analysis.total_count < 10, "Too many queries: #{analysis.total_count}"
assert time_ms < 1000, "Operation too slow: #{time_ms}ms"

# Bad - no assertions
analysis = QueryCounter.analyze()
IO.inspect(analysis)
```

### 3. Test at Different Scales

Always test with various data volumes:

```elixir
for count <- [10, 100, 1000] do
  test "scales linearly with #{count} items" do
    # Test with different data sizes
  end
end
```

### 4. Document Expected Performance

Include performance expectations in test names and comments:

```elixir
test "processes 1000 URLs in <200ms with <20 queries" do
  # Implementation
end
```

## Telemetry Events

Both modules hook into these telemetry events:

- `[:gsc_analytics, :repo, :query]` - Database queries
- `[:gsc_analytics, :api, :request]` - GSC API calls
- `[:gsc_analytics, :sync, :complete]` - Sync operations

## Environment Considerations

These modules are only available in the `:test` environment. They're automatically compiled when running tests but not included in production builds.

To use them in development for debugging:

```elixir
# In IEx during development
Code.require_file("test/support/query_counter.ex")
{:ok, _} = GscAnalytics.Test.QueryCounter.start()

# Run your code
GscAnalytics.DataSources.GSC.Sync.sync_date(1, "sc-domain:example.com", ~D[2024-01-01])

# Analyze
GscAnalytics.Test.QueryCounter.print_analysis()
```

## Common Performance Issues

### N+1 Queries

**Symptom:** Query count grows linearly with data size
**Detection:** `analysis.n_plus_one != []`
**Solution:** Use preloading or batch operations

### Slow Queries

**Symptom:** Individual queries taking >100ms
**Detection:** `analysis.slow_queries != []`
**Solution:** Add indexes or optimize query

### Memory Leaks

**Symptom:** Memory grows without bounds
**Detection:** Monitor `memory.total_memory` over time
**Solution:** Ensure proper cleanup, use streams for large datasets

## Integration with CI/CD

These tools can be integrated into CI pipelines:

```yaml
# .github/workflows/test.yml
- name: Run Performance Tests
  run: |
    mix test test/gsc_analytics/data_sources/gsc/*_performance_test.exs
  env:
    PERFORMANCE_THRESHOLD_QUERIES: 50
    PERFORMANCE_THRESHOLD_TIME_MS: 1000
```

## Contributing

When adding new performance tests:

1. Use both QueryCounter and PerformanceMonitor
2. Test with realistic data volumes
3. Document expected performance in test names
4. Add assertions for both correctness and performance
5. Include a "scales linearly" test for data-intensive operations

## Examples

See these files for comprehensive examples:
- `test/gsc_analytics/data_sources/gsc/data_persistence_performance_test.exs`
- `test/gsc_analytics/data_sources/gsc/sync_benchmark_test.exs`
- `test/gsc_analytics_web/live/dashboard_performance_test.exs`