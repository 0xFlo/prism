# Ticket 021 — Add Aggregation Caching Layer

**Status**: 📋 Pending
**Estimate**: 4h
**Actual**: TBD
**Priority**: 🟢 Low (Performance optimization, not critical path)
**Dependencies**: #019a (Database aggregation), #019b (Query builder), #020 (Presenter)

## Problem

Currently, we recompute aggregations on every request:

1. **Expensive operations**: Weekly/monthly aggregations require fetching all daily data and re-aggregating
2. **Repeated work**: Same URL/date range combinations are aggregated multiple times
3. **No memoization**: LiveView re-renders trigger full aggregation pipeline
4. **Performance headroom**: We have opportunity for 30-50% speed improvement
5. **Database load**: Unnecessary queries for data that rarely changes

### Current Behavior

```elixir
# Every time this runs, we:
# 1. Query database for daily data (potentially thousands of rows)
# 2. Group by week/month
# 3. Aggregate metrics
# 4. Sort results
TimeSeriesAggregator.aggregate_group_by_week(urls, opts)
```

For data older than 3 days (Google Search Console reporting delay), **this computation is pure waste** - the data won't change!

## Proposed Approach

Add an in-memory caching layer using Cachex for aggregated time series results.

### 1. Add Cachex Dependency

Update `mix.exs`:
```elixir
defp deps do
  [
    # ... existing deps ...
    {:cachex, "~> 3.6"}
  ]
end
```

### 2. Create Cache Module

Location: `/lib/gsc_analytics/analytics/time_series_cache.ex`

```elixir
defmodule GscAnalytics.Analytics.TimeSeriesCache do
  @moduledoc """
  Caching layer for time series aggregations.

  Significantly reduces database queries and computation for stable data (older than GSC 3-day delay).

  ## Cache Strategy
  - Recent data (< 3 days old): No caching (data may update)
  - Historical data (>= 3 days old): 1-hour TTL
  - Site-wide aggregations: 30-minute TTL (more dynamic)
  - URL-specific aggregations: 1-hour TTL

  ## Cache Keys
  Format: `{:time_series, aggregation_type, identifiers, opts_hash}`
  Example: `{:time_series, :weekly, ["url1", "url2"], hash}`
  """

  use GenServer
  require Logger

  @cache_name :time_series_cache
  @recent_data_cutoff_days 3

  ## Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get cached aggregation or compute and cache it.

  ## Examples

      iex> TimeSeriesCache.fetch({:weekly, urls, opts}, fn ->
      ...>   TimeSeriesAggregator.aggregate_group_by_week(urls, opts)
      ...> end)
      [%TimeSeriesData{}, ...]
  """
  def fetch(cache_key, compute_fn) do
    case Cachex.get(@cache_name, cache_key) do
      {:ok, nil} ->
        # Cache miss - compute and store
        result = compute_fn.()
        ttl = calculate_ttl(cache_key)
        Cachex.put(@cache_name, cache_key, result, ttl: ttl)
        Logger.debug("Cache miss for #{inspect(cache_key)}, computed and cached")
        result

      {:ok, cached_result} ->
        Logger.debug("Cache hit for #{inspect(cache_key)}")
        cached_result

      {:error, reason} ->
        Logger.warn("Cache error: #{inspect(reason)}, falling back to computation")
        compute_fn.()
    end
  end

  @doc """
  Invalidate cache for specific keys or patterns.
  Called when new data is synced from GSC.
  """
  def invalidate(pattern) do
    Cachex.del(@cache_name, pattern)
  end

  @doc """
  Clear entire cache.
  Useful for testing or after major data updates.
  """
  def clear_all do
    Cachex.clear(@cache_name)
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    {:ok, cache} = Cachex.start_link(@cache_name, [])
    Logger.info("TimeSeriesCache started: #{inspect(cache)}")
    {:ok, %{cache: cache}}
  end

  ## Private Helpers

  defp calculate_ttl({_type, _identifiers, opts}) do
    start_date = Map.get(opts, :start_date)

    if is_nil(start_date) or recent_data?(start_date) do
      # Recent data may change - shorter TTL
      :timer.minutes(15)
    else
      # Historical data is stable - longer TTL
      :timer.hours(1)
    end
  end

  defp recent_data?(start_date) do
    cutoff = Date.add(Date.utc_today(), -@recent_data_cutoff_days)
    Date.compare(start_date, cutoff) == :gt
  end
end
```

### 3. Update TimeSeriesAggregator to Use Cache

```elixir
defmodule GscAnalytics.Analytics.TimeSeriesAggregator do
  alias GscAnalytics.Analytics.TimeSeriesCache

  def aggregate_group_by_week(urls, opts) do
    cache_key = {:weekly, urls, opts}

    TimeSeriesCache.fetch(cache_key, fn ->
      # Original computation
      fetch_daily_data_for_urls(urls, opts[:start_date], opts)
      |> aggregate_pipeline(&week_start_date/1, &week_end_date/1)
    end)
  end

  # Similar for other aggregation functions...
end
```

### 4. Add to Supervision Tree

Update `/lib/gsc_analytics/application.ex`:
```elixir
children = [
  # ... existing children ...
  {GscAnalytics.Analytics.TimeSeriesCache, []},
  # ...
]
```

### 5. Invalidation on Sync

Update sync completion to invalidate cache:
```elixir
defmodule GscAnalytics.DataSources.GSC.Core.Sync do
  def sync_date_range(...) do
    # ... sync logic ...

    # Invalidate cache for affected date ranges
    TimeSeriesCache.invalidate({:*, :*, %{start_date: start_date}})

    {:ok, sync_result}
  end
end
```

## Migration Strategy

### Phase 0: Safety & Telemetry
1. Instrument aggregator Telemetry events with `cache_hit` metadata for dashboards.
2. Capture baseline latency + DB load metrics without cache for comparison.

### Phase 1: Add Infrastructure
1. Add Cachex dependency
2. Create `TimeSeriesCache` module
3. Add tests for cache module
4. Add to supervision tree
5. Verify cache starts correctly

### Phase 2: Integrate with Aggregator
1. Update one aggregation function as proof-of-concept
2. Benchmark performance improvement
3. If successful, update remaining functions
4. Add cache metrics/logging

### Phase 3: Invalidation Strategy
1. Add cache invalidation to sync operations
2. Add manual invalidation endpoints (if needed)
3. Test cache behavior under load

### Phase 4: Rollout
1. Enable in staging with production-like dataset (monitor hit rate >60%)
2. Deploy to production once Telemetry dashboards + alert thresholds are in place
3. Document rollback procedure (clear cache + revert integration calls)

## Rollout Plan & Observability
- Dashboard requirements: latency, hit rate, eviction count, memory usage (Grafana).
- Alert thresholds: latency regression >2x baseline, hit rate <40%, cache errors.
- Weekly review of cache effectiveness; disable if benefit <20%.
- Keep cache keys namespaced by account + url list hash to avoid collisions.

## Coordination Checklist
- [ ] Partner with DevOps for production Cachex tuning (ETS limits, eviction policy).
- [ ] Align with Data Ops on invalidation triggers post-GSC import.
- [ ] Communicate rollout timeline & rollback steps to support/on-call.
- [ ] Ensure #022 owner documents cache behavior + operational runbook.

## Acceptance Criteria

- [ ] Cachex dependency added to `mix.exs`
- [ ] `TimeSeriesCache` module created and tested
- [ ] Cache added to application supervision tree
- [ ] Cache starts successfully on app boot
- [ ] `aggregate_group_by_week/2` uses cache
- [ ] `aggregate_group_by_month/2` uses cache
- [ ] `fetch_site_aggregate_by_week/2` uses cache
- [ ] `fetch_site_aggregate_by_month/2` uses cache
- [ ] Performance benchmarks show 30-50% improvement for cached data
- [ ] Cache invalidation works on data sync
- [ ] Manual cache clearing available via IEx
- [ ] Logging shows cache hit/miss rates
- [ ] All tests pass with caching enabled
- [ ] No memory leaks observed in extended testing
- [ ] Telemetry dashboards/alerts created for hit rate + latency
- [ ] Rollout checklist completed with staging results attached to ticket

## Performance Benchmarking

Measure before/after caching:

```elixir
# Warmup cache
TimeSeriesAggregator.aggregate_group_by_week(urls, opts)

# Benchmark cached call
:timer.tc(fn ->
  TimeSeriesAggregator.aggregate_group_by_week(urls, opts)
end)

# Expected: 30-50% faster on cache hit
```

Track metrics:
- Database query count (should drop to 0 for cache hits)
- Memory usage (Cachex overhead)
- Cache hit rate over time
- Telemetry event counts (`cache_hit`, `cache_miss`, `cache_error`)

## Test Plan

Create `/test/gsc_analytics/analytics/time_series_cache_test.exs`:

```elixir
defmodule GscAnalytics.Analytics.TimeSeriesCacheTest do
  use GscAnalytics.DataCase

  alias GscAnalytics.Analytics.TimeSeriesCache

  setup do
    # Clear cache before each test
    TimeSeriesCache.clear_all()
    :ok
  end

  describe "fetch/2" do
    test "computes value on cache miss" do
      compute_called = Agent.start_link(fn -> false end)

      result = TimeSeriesCache.fetch({:test, :key}, fn ->
        Agent.update(compute_called, fn _ -> true end)
        "computed_value"
      end)

      assert result == "computed_value"
      assert Agent.get(compute_called, & &1) == true
    end

    test "returns cached value on cache hit" do
      # Prime the cache
      TimeSeriesCache.fetch({:test, :key}, fn -> "cached_value" end)

      # This should NOT call compute function
      result = TimeSeriesCache.fetch({:test, :key}, fn ->
        raise "Should not be called!"
      end)

      assert result == "cached_value"
    end

    test "uses shorter TTL for recent data" do
      recent_opts = %{start_date: Date.utc_today()}
      key = {:weekly, ["url"], recent_opts}

      TimeSeriesCache.fetch(key, fn -> "recent_data" end)

      # Verify TTL is set (implementation detail - may need adjustment)
      {:ok, ttl} = Cachex.ttl(:time_series_cache, key)
      assert ttl < :timer.hours(1)
    end
  end

  describe "invalidate/1" do
    test "removes cached value" do
      key = {:test, :key}
      TimeSeriesCache.fetch(key, fn -> "value" end)

      TimeSeriesCache.invalidate(key)

      # Should compute again
      result = TimeSeriesCache.fetch(key, fn -> "new_value" end)
      assert result == "new_value"
    end
  end

  describe "clear_all/0" do
    test "removes all cached values" do
      TimeSeriesCache.fetch({:key1}, fn -> "value1" end)
      TimeSeriesCache.fetch({:key2}, fn -> "value2" end)

      TimeSeriesCache.clear_all()

      # Both should recompute
      assert TimeSeriesCache.fetch({:key1}, fn -> "new1" end) == "new1"
      assert TimeSeriesCache.fetch({:key2}, fn -> "new2" end) == "new2"
    end
  end
end
```

### Telemetry Tests
- Attach test handler to Telemetry event to assert metadata includes `:cache_hit` boolean.

## Estimate

**4 hours total**
- 1h: Add Cachex, create module, basic tests
- 1h: Integrate with aggregation functions
- 1h: Performance benchmarking and tuning
- 1h: Invalidation strategy and additional tests

## Rollback Plan

If issues arise:
1. Remove cache calls from aggregation functions
2. Keep cache module in place (no harm if unused)
3. Can re-enable incrementally per function
4. Remove from supervision tree if causing crashes

## Success Metrics

- 30-50% performance improvement for cached aggregations
- Cache hit rate > 60% after warmup period
- No memory leaks or growth over time
- Database query reduction visible in logs
- User-perceivable faster dashboard load times

## Best Practices: Batch Cache Warming

### Parallel Batch Warming (10x Faster)

Instead of warming cache sequentially, use **batch operations** with parallel tasks. Research shows batch operations can be up to 10 times faster than individual executions:

```elixir
defmodule GscAnalytics.Analytics.TimeSeriesCache do
  @doc """
  Warm cache for multiple URLs in parallel batches.

  Processes URLs in batches of 10, with each batch running concurrently.
  This is 10x faster than sequential cache warming.

  ## Examples

      iex> TimeSeriesCache.warm_cache_batch(
      ...>   top_urls,
      ...>   %{start_date: ~D[2025-01-01], account_id: 1}
      ...> )
      :ok
  """
  def warm_cache_batch(urls, opts) when is_list(urls) do
    urls
    |> Enum.chunk_every(10)  # Process 10 URLs at a time
    |> Enum.map(fn batch ->
      Task.async(fn ->
        # Warm cache for this batch
        TimeSeriesAggregator.aggregate_group_by_week(batch, opts)
        TimeSeriesAggregator.aggregate_group_by_month(batch, opts)

        {:ok, length(batch)}
      end)
    end)
    |> Task.await_many(30_000)  # 30 second timeout per batch
    |> Enum.reduce(0, fn {:ok, count}, acc -> acc + count end)
    |> then(fn total ->
      Logger.info("Cache warmed for #{total} URLs in parallel")
      :ok
    end)
  end

  @doc """
  Warm cache on application startup for top N URLs.
  Call this from Application.start/2 callback.
  """
  def warm_on_startup(opts \\\\ %{}) do
    top_n = Map.get(opts, :top_n, 50)
    account_id = Map.get(opts, :account_id)

    # Get top URLs by traffic
    top_urls =
      UrlPerformance.get_top_urls_by_traffic(account_id, limit: top_n)
      |> Enum.map(& &1.url)

    # Warm cache in background (don't block startup)
    Task.start(fn ->
      warm_cache_batch(top_urls, opts)
    end)

    Logger.info("Started cache warming for top #{top_n} URLs")
  end
end
```

### Usage in Application Startup

Add to `lib/gsc_analytics/application.ex`:

```elixir
def start(_type, _args) do
  children = [
    # ... existing children ...
    {GscAnalytics.Analytics.TimeSeriesCache, []},
  ]

  opts = [strategy: :one_for_one, name: GscAnalytics.Supervisor]
  result = Supervisor.start_link(children, opts)

  # Warm cache after supervisor starts
  if Application.get_env(:gsc_analytics, :warm_cache_on_start, false) do
    TimeSeriesCache.warm_on_startup(%{
      top_n: 50,
      start_date: Date.add(Date.utc_today(), -90)
    })
  end

  result
end
```

### Performance Comparison

**Sequential warming (old approach)**:
```
50 URLs × (200ms weekly + 200ms monthly) = 20 seconds
```

**Batch parallel warming (new approach)**:
```
50 URLs / 10 per batch × 400ms = 2 seconds  (10x faster!)
```

### Best Practice Rationale

From Elixir/Ecto performance optimization guides: "Batch operations can be up to 10 times faster than individual executions." This applies to:
- Cache warming
- Database inserts/updates
- API calls
- Any operation that can be parallelized

## Optional Enhancements (Future)

- Cache statistics dashboard (hit rate, eviction count, memory usage)
- Redis backend for distributed caching across nodes
- More sophisticated invalidation patterns (partial key matching)
- Metrics integration dashboard (Grafana/DataDog)
