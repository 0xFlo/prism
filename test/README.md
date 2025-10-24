# GSC Analytics Test Suite

## Overview

The GSC Analytics test suite provides comprehensive coverage for functionality, performance, and reliability. Our testing philosophy emphasizes performance from the start, not as an afterthought.

## Test Structure

```
test/
├── gsc_analytics/                      # Core business logic tests
│   ├── data_sources/
│   │   └── gsc/
│   │       ├── data_persistence_performance_test.exs  # Bulk operation performance
│   │       └── sync_benchmark_test.exs               # Sync throughput benchmarks
│   └── schemas/
│       └── # Schema validation tests
├── gsc_analytics_web/                  # Web layer tests
│   ├── live/
│   │   └── dashboard_performance_test.exs            # UI performance tests
│   └── controllers/
│       └── # Controller tests
├── support/                            # Test utilities
│   ├── query_counter.ex               # Database query analysis
│   ├── performance_monitor.ex         # System performance tracking
│   ├── conn_case.ex                   # Phoenix test helpers
│   ├── data_case.ex                   # Database test helpers
│   └── README.md                       # Support module documentation
└── test_helper.exs                    # Test configuration
```

## Test Categories

### 1. Unit Tests
Standard functional tests ensuring correctness of individual components.

**Location:** Throughout `test/gsc_analytics/` and `test/gsc_analytics_web/`

**Run with:** `mix test`

### 2. Performance Tests
Tests that validate performance requirements and prevent regressions.

**Location:** Files ending in `_performance_test.exs`

**Run with:** `mix test test/**/*_performance_test.exs`

**Key Features:**
- Query count assertions
- Throughput measurements
- Memory usage tracking
- Scalability validation

### 3. Benchmark Tests
Tests that measure and compare performance characteristics.

**Location:** Files ending in `_benchmark_test.exs`

**Run with:** `mix test test/**/*_benchmark_test.exs`

**Key Features:**
- Comparative analysis
- Scaling measurements
- Throughput benchmarks
- Memory profiling

### 4. Integration Tests
Tests that validate end-to-end workflows.

**Location:** Mixed throughout the test suite

**Run with:** `mix test --only integration`

## Performance Testing Tools

### QueryCounter
Tracks all database queries during test execution.

**Features:**
- Query counting and timing
- N+1 query detection
- Slow query identification
- Duplicate query detection

**Usage:**
```elixir
setup do
  QueryCounter.start()
  on_exit(fn -> QueryCounter.stop() end)
end
```

### PerformanceMonitor
Comprehensive system monitoring using telemetry.

**Features:**
- Database metrics
- API call tracking
- Memory profiling
- Process monitoring

**Usage:**
```elixir
setup do
  PerformanceMonitor.start()
  on_exit(fn -> PerformanceMonitor.stop() end)
end
```

## Running Tests

### Quick Test Commands

```bash
# Run all tests
mix test

# Run with coverage
mix test --cover
mix coveralls.html  # Generate HTML coverage report

# Run by test type (using tags)
mix test --only integration   # Integration tests only
mix test --only performance   # Performance tests only
mix test --only algorithm     # Algorithm tests only
mix test --exclude performance  # Skip slow performance tests

# Run performance tests only (by filename)
mix test test/**/*_performance_test.exs

# Run specific file
mix test test/path/to/test.exs

# Run specific test by line number
mix test test/path/to/test.exs:42

# Run tests with detailed output
mix test --trace

# Run failed tests only
mix test --failed
```

### Test Tags

Tests are tagged by type for easy filtering:

- **`:integration`** - Tests verifying complete user journeys and workflows
- **`:performance`** - Tests measuring and asserting on performance metrics
- **`:algorithm`** - Tests for complex calculation logic (WoW growth, aggregations)
- **`:stress`** - Heavy-load stress tests (optional, run manually)

Use tags to run fast tests during development and comprehensive tests in CI.

### Continuous Integration

Tests run automatically on every pull request via GitHub Actions. See `.github/workflows/test.yml` for configuration.

## Performance Baselines

Current performance metrics that tests validate against:

| Component | Metric | Baseline | Test Assertion |
|-----------|--------|----------|----------------|
| DataPersistence | URL Processing | 7,353 URLs/sec | `> 5,000 URLs/sec` |
| DataPersistence | Query Count (1000 URLs) | 21 queries | `< 25 queries` |
| DataPersistence | Memory per URL | 2.93 KB | `< 5 KB` |
| Aggregation | Queries per Operation | 2 queries | `< 5 queries` |
| Dashboard | Initial Load (500 URLs) | 1.3 seconds | `< 2 seconds` |
| Sync | Batch Efficiency | 45 URLs/query | `> 20 URLs/query` |

## Writing New Tests

### Performance Test Template

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

  @tag :performance
  test "processes data efficiently" do
    # Arrange
    test_data = generate_test_data(1000)

    # Act
    {time_micros, result} = :timer.tc(fn ->
      MyFeature.process(test_data)
    end)

    # Assert correctness
    assert length(result) == 1000

    # Assert performance
    analysis = QueryCounter.analyze()
    metrics = PerformanceMonitor.get_metrics()

    assert analysis.total_count < 50, "Too many queries: #{analysis.total_count}"
    assert analysis.n_plus_one == [], "N+1 queries detected"
    assert time_micros / 1000 < 1000, "Operation too slow: #{time_micros / 1000}ms"

    # Log metrics for visibility
    IO.puts("Processed #{length(test_data)} items in #{time_micros / 1000}ms")
    IO.puts("Database queries: #{analysis.total_count}")
  end
end
```

### Best Practices

1. **Always test with realistic data volumes** - Small datasets hide performance issues
2. **Assert on performance metrics** - Don't just measure, enforce limits
3. **Test scalability** - Verify linear (not exponential) scaling
4. **Clean up properly** - Reset state between tests
5. **Document expectations** - Include target metrics in test names/docs
6. **Use tags** - Mark performance tests with `@tag :performance`

## Debugging Test Failures

### Common Issues

**1. Query Count Exceeded**
```
Assertion failed: Expected <10 queries, got 45
```
- Run `QueryCounter.print_analysis()` to see breakdown
- Look for N+1 patterns
- Check for missing preloads

**2. Performance Regression**
```
Operation took 5234ms, expected <1000ms
```
- Check recent code changes
- Verify database indexes exist
- Review query execution plans

**3. Memory Growth**
```
Excessive memory growth: 125.3 MB
```
- Look for data accumulation
- Check for missing cleanup
- Consider streaming/chunking

### Debugging Tools

```elixir
# In failing test, add debugging output:
QueryCounter.print_analysis()
PerformanceMonitor.print_report()

# Check specific metrics:
analysis = QueryCounter.analyze()
IO.inspect(analysis.slow_queries, label: "Slow queries")
IO.inspect(analysis.n_plus_one, label: "N+1 patterns")

# Memory debugging:
:erlang.memory() |> IO.inspect(label: "Memory stats")
```

## Contributing

When adding new features:

1. Write unit tests for correctness
2. Add performance tests for efficiency
3. Update baselines if performance improves
4. Document any new test utilities
5. Ensure CI passes before merging

## Resources

- [Performance Testing Guide](docs/PERFORMANCE_TESTING.md)
- [Test Support Modules](test/support/README.md)
- [Ecto Testing Guide](https://hexdocs.pm/ecto/testing-with-ecto.html)
- [Phoenix Testing Guide](https://hexdocs.pm/phoenix/testing.html)

## Performance History

### September 2025 (Before Optimization)
- Processing 1178 URLs: ~77 seconds
- Database queries: 900,000+
- UI: Severe freezing and crashes

### October 2025 (After Optimization)
- Processing 1178 URLs: 4.6 seconds
- Database queries: ~300
- UI: Smooth and responsive
- **Improvement: 1,178× fewer queries, 17× faster**

This dramatic improvement was achieved through:
1. Bulk database operations
2. Efficient aggregation queries
3. Elimination of N+1 patterns
4. Strategic database indexing
5. Comprehensive performance testing

The test suite ensures these optimizations remain effective as the codebase evolves.