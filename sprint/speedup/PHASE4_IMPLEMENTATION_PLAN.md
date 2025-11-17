# Phase 4: Concurrent HTTP Batches - Implementation Plan

**Status**: READY TO IMPLEMENT
**Created**: 2025-11-13
**Owner**: Engineering
**Priority**: 🔥 P1 Critical
**Target Speedup**: ≥4× additional sync performance (stretch: 8×)
**Estimated Time**: 3-4 weeks (includes staging validation + rollout buffer)

---

## Why Phase 4 Instead of Phase 2+3?

Based on Codex critical review, Phase 2+3 have fundamental architectural issues:
- Phase 2: Per-page callbacks won't work, will corrupt data
- Phase 3: No crash recovery, data loss on failure
- Both require same complexity as Phase 4 (persistent state, crash recovery)
- Both won't achieve 3-5× without addressing **sequential HTTP bottleneck**

**Phase 4 addresses the dominant bottleneck directly and delivers ≥4× improvement (stretch: 8×).**

---

## Executive Summary

Implement concurrent HTTP batch processing to eliminate the primary bottleneck: sequential batch fetching that leaves network latency idle. This requires:

1. **Redesign QueryPaginator** state management for concurrency-safety
2. **Wire rate limiting** into batch processing path
3. **Add atomic counters** for telemetry
4. **Implement halt propagation** across concurrent tasks

**Expected gain**: ≥4× additional speedup (stretch: 8×) on top of 2-3× from Phase 1
**Total improvement**: ~8-12× faster than original once Phase 4 is tuned

## Current Status (Week of 2025-11-13)

- ✅ QueryCoordinator, worker pool, rate limiter upgrades, and QueryPaginator refactor are merged with sequential fallback.
- ✅ Telemetry hooks for coordinator queue depth, worker batch latency, and rate-limit usage feed `GscAnalyticsWeb.Telemetry`.
- ✅ Test coverage: new unit suites plus `test/gsc_analytics/data_sources/gsc/concurrent_sync_integration_test.exs`.
- ⏳ Documentation + rollout playbook (S05/S06) still outstanding.

---

## Architecture Changes

### 1. Concurrency-Safe State Management

**Current Problem** (`query_paginator.ex:204-389`):
- Mutable state via tail recursion
- No Agent/GenServer coordination
- Concurrent tasks would drop re-enqueued pages

**Solution**: GenServer-based coordinator

```elixir
defmodule GscAnalytics.DataSources.GSC.Support.QueryCoordinator do
  use GenServer

  @moduledoc """
  Concurrency-safe coordinator for query pagination.

  Manages pagination queue, results accumulation, and completion tracking
  across concurrent HTTP batch fetches.
  """

  # State structure
  defstruct [
    :account_id,
    :site_url,
    :queue,            # Erlang queue of {date, start_row} pairs
    :results,          # Map of date => result_entry
    :completed,        # MapSet of completed dates
    :total_api_calls,  # Atomic counter reference
    :http_batch_calls, # Atomic counter reference
    :halt_flag,        # {halted?, reason}
    :on_complete,      # Callback function
    :max_queue_size,
    :max_in_flight,
    :in_flight,        # MapSet of in-flight batch keys
    :inflight_table    # ETS table for crash recovery
  ]

  # Client API
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def take_batch(coordinator, batch_size) do
    GenServer.call(coordinator, {:take_batch, batch_size})
  end

  def submit_results(coordinator, batch_results) do
    GenServer.call(coordinator, {:submit_results, batch_results})
  end

  def requeue_batch(coordinator, batch) do
    GenServer.call(coordinator, {:requeue_batch, batch})
  end

  def halt(coordinator, reason) do
    GenServer.call(coordinator, {:halt, reason})
  end

  def should_halt?(coordinator) do
    GenServer.call(coordinator, :should_halt?)
  end

  def finalize(coordinator) do
    GenServer.call(coordinator, :finalize)
  end

  # Server callbacks
  def init(opts) do
    state = %__MODULE__{
      account_id: Keyword.fetch!(opts, :account_id),
      site_url: Keyword.fetch!(opts, :site_url),
      queue: Keyword.get(opts, :queue, :queue.new()),
      results: Keyword.get(opts, :results, %{}),
      completed: MapSet.new(),
      total_api_calls: :atomics.new(1, []),
      http_batch_calls: :atomics.new(1, []),
      halt_flag: {false, nil},
      on_complete: Keyword.get(opts, :on_complete),
      max_queue_size: Keyword.get(opts, :max_queue_size, 1_000),
      max_in_flight: Keyword.get(opts, :max_in_flight, 10),
      in_flight: MapSet.new(),
      inflight_table:
        Keyword.get_lazy(opts, :inflight_table, fn ->
          :ets.new(__MODULE__, [:set, :public, read_concurrency: true])
        end)
    }
    {:ok, state}
  end

  def handle_call({:take_batch, batch_size}, _from, state) do
    cond do
      MapSet.size(state.in_flight) >= state.max_in_flight ->
        {:reply, {:backpressure, :max_in_flight}, state}

      true ->
        case state.halt_flag do
          {true, reason} ->
            {:reply, {:halted, reason}, state}

          {false, nil} ->
            {batch, remaining_queue} = do_take_batch(state.queue, batch_size, state.completed, [])

            if batch == [] do
              {:reply, :no_more_work, state}
            else
              updated_in_flight = mark_in_flight(state.in_flight, batch, state.inflight_table)
              {:reply, {:ok, batch}, %{state | queue: remaining_queue, in_flight: updated_in_flight}}
            end
        end
    end
  end

  def handle_call({:submit_results, batch_results}, _from, state) do
    # Process each result, update queue, check completion, clear in-flight markers
    updated_state =
      batch_results
      |> process_batch_results(state)
      |> clear_in_flight(batch_results)

    {:reply, :ok, updated_state}
  end

  def handle_call({:requeue_batch, batch}, _from, state) do
    if :queue.len(state.queue) + length(batch) > state.max_queue_size do
      {:reply, {:error, :queue_full}, state}
    else
      requeued =
        Enum.reduce(batch, state.queue, fn item, acc -> :queue.in_r(item, acc) end)

      new_in_flight =
        Enum.reduce(batch, state.in_flight, fn key, acc ->
          :ets.delete(state.inflight_table, key)
          MapSet.delete(acc, key)
        end)

      {:reply, :ok, %{state | queue: requeued, in_flight: new_in_flight}}
    end
  end

  def handle_call({:halt, reason}, _from, state) do
    {:reply, :ok, %{state | halt_flag: {true, reason}}}
  end

  def handle_call(:should_halt?, _from, state) do
    {halted?, _reason} = state.halt_flag
    {:reply, halted?, state}
  end

  def handle_call(:finalize, _from, state) do
    total_api_calls = :atomics.get(state.total_api_calls, 1)
    http_batch_calls = :atomics.get(state.http_batch_calls, 1)

    results = finalize_results(state.results)

    {:reply, {:ok, results, total_api_calls, http_batch_calls}, state}
  end

  # Private helpers
  defp do_take_batch(queue, batch_size, completed, acc) when length(acc) >= batch_size do
    {Enum.reverse(acc), queue}
  end

  defp do_take_batch(queue, batch_size, completed, acc) do
    case :queue.out(queue) do
      {{:value, {date, _start_row} = item}, rest} ->
        if MapSet.member?(completed, date) do
          # Skip completed dates
          do_take_batch(rest, batch_size, completed, acc)
        else
          do_take_batch(rest, batch_size, completed, [item | acc])
        end

      {:empty, queue} ->
        {Enum.reverse(acc), queue}
    end
  end

  defp process_batch_results(batch_results, state) do
    Enum.reduce(batch_results, state, fn result, acc_state ->
      case result do
        {:ok, date, start_row, part} ->
          process_successful_result(date, start_row, part, acc_state)

        {:error, date, _start_row, reason} ->
          # Set halt flag on error
          %{acc_state | halt_flag: {true, {:error, date, reason}}}
      end
    end)
  end

  defp process_successful_result(date, start_row, part, state) do
    # Increment API call counter
    :atomics.add(state.total_api_calls, 1, 1)

    # Extract rows and check if more pages needed
    rows = extract_rows(part)
    needs_next = needs_next_page?(rows)

    # Update result entry
    result_entry = Map.get(state.results, date, new_result_entry())
    updated_entry = append_rows(result_entry, rows, start_row)

    # Update queue if more pages needed
    updated_queue =
      if needs_next do
        next_start_row = start_row + length(rows)
        :queue.in({date, next_start_row}, state.queue)
      else
        state.queue
      end

    # Check if date is complete
    {updated_completed, final_state} =
      if needs_next do
        {state.completed, state}
      else
        # Date complete, invoke callback if present
        completed = MapSet.put(state.completed, date)

        case state.on_complete do
          nil ->
            {completed, state}
          callback when is_function(callback, 1) ->
            all_rows = flatten_rows(updated_entry)
            callback_result = callback.(%{date: date, rows: all_rows})

            case callback_result do
              {:ok, new_state} -> {completed, Map.merge(state, new_state)}
              {:halt, reason, new_state} ->
                merged = Map.merge(state, new_state)
                {completed, %{merged | halt_flag: {true, reason}}}
            end
        end
      end

    %{final_state |
      results: Map.put(state.results, date, updated_entry),
      queue: updated_queue,
      completed: updated_completed
    }
  end

  defp mark_in_flight(in_flight, batch, inflight_table) do
    Enum.reduce(batch, in_flight, fn key = {date, start_row}, acc ->
      :ets.insert(inflight_table, {key, System.monotonic_time()})
      MapSet.put(acc, key)
    end)
  end

  defp clear_in_flight(state, batch_results) do
    keys =
      batch_results
      |> Enum.map(fn
        {_status, date, start_row, _} -> {date, start_row}
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)

    new_in_flight =
      Enum.reduce(keys, state.in_flight, fn key, acc ->
        :ets.delete(state.inflight_table, key)
        MapSet.delete(acc, key)
      end)

    %{state | in_flight: new_in_flight}
  end

  # ... other helper functions
end
```

**Benefits**:
- ✅ Concurrency-safe state updates
- ✅ Atomic counters for telemetry
- ✅ Halt propagation via shared flag
- ✅ Clean separation of concerns
- ✅ Backpressure via `max_queue_size` + `max_in_flight`
- ✅ Crash recovery + idempotency through ETS-tracked in-flight keys and requeue API

---

### 2. Concurrent Batch Worker

```elixir
defmodule GscAnalytics.DataSources.GSC.Support.ConcurrentBatchWorker do
  @moduledoc """
  Concurrent HTTP batch fetcher with rate limiting.

  Spawns multiple workers that:
  1. Take batch from coordinator
  2. Check rate limit
  3. Fetch via HTTP
  4. Submit results back to coordinator
  """

  require Logger
  alias GscAnalytics.DataSources.GSC.Support.{QueryCoordinator, RateLimiter}
  alias GscAnalytics.DataSources.GSC.Core.Client

  def start_workers(coordinator, opts) do
    account_id = Keyword.fetch!(opts, :account_id)
    site_url = Keyword.fetch!(opts, :site_url)
    operation = Keyword.fetch!(opts, :operation)
    dimensions = Keyword.fetch!(opts, :dimensions)
    batch_size = Keyword.get(opts, :batch_size, 50)
    max_concurrency = Keyword.get(opts, :max_concurrency, 3)

    # Spawn workers
    tasks =
      1..max_concurrency
      |> Enum.map(fn worker_id ->
        Task.async(fn ->
          worker_loop(
            coordinator,
            account_id,
            site_url,
            operation,
            dimensions,
            batch_size,
            worker_id
          )
        end)
      end)

    # Wait for all workers to complete
    results = Task.await_many(tasks, :infinity)

    # Return any errors
    errors = Enum.filter(results, &match?({:error, _}, &1))

    if errors == [] do
      :ok
    else
      {:error, errors}
    end
  end

  defp worker_loop(coordinator, account_id, site_url, operation, dimensions, batch_size, worker_id) do
    case QueryCoordinator.take_batch(coordinator, batch_size) do
      {:halted, reason} ->
        Logger.debug("Worker #{worker_id} stopping: halted (#{inspect(reason)})")
        {:ok, :halted}

      :no_more_work ->
        Logger.debug("Worker #{worker_id} stopping: no more work")
        {:ok, :completed}

      {:backpressure, reason} ->
        Logger.debug("Worker #{worker_id} pausing due to #{inspect(reason)} backpressure")
        Process.sleep(100)
        worker_loop(coordinator, account_id, site_url, operation, dimensions, batch_size, worker_id)

      {:ok, batch} ->
        # Check rate limit BEFORE making HTTP call
        case check_rate_limit_for_batch(account_id, site_url, batch) do
          :ok ->
            # Fetch batch via HTTP
            batch_results = fetch_and_process_batch(
              account_id,
              site_url,
              operation,
              dimensions,
              batch,
              worker_id
            )

            # Submit results back to coordinator
            QueryCoordinator.submit_results(coordinator, batch_results)

            # Check if we should halt
            if QueryCoordinator.should_halt?(coordinator) do
              Logger.debug("Worker #{worker_id} stopping: halt flag set")
              {:ok, :halted}
            else
              # Continue working
              worker_loop(coordinator, account_id, site_url, operation, dimensions, batch_size, worker_id)
            end

          {:error, :rate_limited, wait_ms} ->
            Logger.warning("Worker #{worker_id} rate limited, waiting #{wait_ms}ms")
            QueryCoordinator.requeue_batch(coordinator, batch)
            Process.sleep(wait_ms)
            worker_loop(coordinator, account_id, site_url, operation, dimensions, batch_size, worker_id)
        end
    end
  end

  defp check_rate_limit_for_batch(account_id, site_url, batch) do
    # Check rate limit for number of requests in batch
    # Each batch item is 1 API call
    case RateLimiter.check_rate(account_id, site_url, length(batch)) do
      :ok -> :ok
      {:error, :rate_limited, wait_ms} -> {:error, :rate_limited, wait_ms}
    end
  end

  defp fetch_and_process_batch(account_id, site_url, operation, dimensions, batch, worker_id) do
    Logger.debug("Worker #{worker_id} fetching batch of #{length(batch)} requests")

    # Build batch requests
    requests = build_batch_requests(site_url, batch, operation, dimensions)

    # Fetch via HTTP
    case Client.fetch_query_batch(account_id, requests, operation) do
      {:ok, responses, _batch_count} ->
        # Match responses to batch items
        response_map = Map.new(responses, fn part -> {part.id, part} end)

        Enum.map(batch, fn {date, start_row} ->
          id = request_id(date, start_row)

          case Map.fetch(response_map, id) do
            {:ok, part} ->
              if part.status == 200 do
                {:ok, date, start_row, part}
              else
                {:error, date, start_row, {:http_error, part.status}}
              end

            :error ->
              {:error, date, start_row, :response_not_found}
          end
        end)

      {:error, reason} ->
        # All requests in batch failed
        Enum.map(batch, fn {date, start_row} ->
          {:error, date, start_row, reason}
        end)
    end
  end

  # ... helper functions
end
```

**Key behaviors**:
- Workers pause when the coordinator signals `{:backpressure, reason}` to keep `max_in_flight` under control.
- Rate-limit hits trigger `QueryCoordinator.requeue_batch/2` before sleeping, guaranteeing no batches are lost.
- Default `max_concurrency: 3` keeps QPM <80% of quota; bump to 5 only after telemetry stays green for a week.

---

### 3. Rate Limiter Integration

**Current Problem**: `client.ex:164-168` - `fetch_query_batch/3` never calls `RateLimiter.check_rate/2`

**Solution**: Add rate checking to batch worker BEFORE HTTP call

**Updated RateLimiter**:

```elixir
defmodule GscAnalytics.DataSources.GSC.Support.RateLimiter do
  @moduledoc """
  Rate limiter with support for batch request accounting.

  GSC allows 1,200 queries per minute per site.
  """

  @queries_per_minute 1_200
  @window_ms 60_000

  @doc """
  Check rate limit for a batch of N requests.
  """
  @spec check_rate(integer(), String.t(), integer()) ::
          :ok | {:error, :rate_limited, non_neg_integer()}
  def check_rate(account_id, site_url, request_count \\ 1) do
    bucket_key = bucket_key(account_id, site_url)

    case Hammer.check_rate(bucket_key, @window_ms, @queries_per_minute, request_count) do
      {:allow, _count} ->
        :ok

      {:deny, limit} ->
        # Calculate wait time until bucket resets
        wait_ms = calculate_wait_time(limit)
        {:error, :rate_limited, wait_ms}
    end
  end

  defp bucket_key(account_id, site_url) do
    "gsc_queries:#{account_id}:#{site_url}"
  end

  defp calculate_wait_time(limit) do
    # Return time until window resets
    # For now, use conservative 10 seconds
    10_000
  end
end
```

---

## Implementation Tasks

### Task 1: Implement QueryCoordinator GenServer
**Time**: 2-3 days

**Subtasks**:
- [x] Create GenServer module with state struct
- [x] Implement `take_batch/2` for concurrent workers
- [x] Implement `submit_results/2` for result accumulation
- [x] Add halt flag propagation
- [x] Add atomic counters for telemetry
- [x] Write unit tests for concurrency scenarios
- [x] Test halt propagation across workers

**Files**:
- `lib/gsc_analytics/data_sources/gsc/support/query_coordinator.ex` (new)
- `test/gsc_analytics/data_sources/gsc/support/query_coordinator_test.exs` (new)

---

### Task 2: Implement ConcurrentBatchWorker
**Time**: 1-2 days

**Subtasks**:
- [x] Create worker loop with Task.async
- [x] Integrate rate limit checking
- [x] Handle halt propagation
- [x] Add worker-level error handling
- [x] Add telemetry for worker activity
- [x] Write unit tests for worker behavior

**Files**:
- `lib/gsc_analytics/data_sources/gsc/support/concurrent_batch_worker.ex` (new)
- `test/gsc_analytics/data_sources/gsc/support/concurrent_batch_worker_test.exs` (new)

---

### Task 3: Update RateLimiter for Batch Accounting
**Time**: 0.5 days

**Subtasks**:
- [x] Add `request_count` parameter to `check_rate/3`
- [x] Update Hammer integration
- [x] Add backoff calculation
- [x] Write tests for batch rate limiting

**Files**:
- `lib/gsc_analytics/data_sources/gsc/support/rate_limiter.ex` (modify)
- `test/gsc_analytics/data_sources/gsc/support/rate_limiter_test.exs` (update)

---

### Task 4: Refactor QueryPaginator to Use Coordinator
**Time**: 1-2 days

**Subtasks**:
- [x] Replace tail recursion with GenServer calls
- [x] Update `fetch_all/4` to spawn coordinator + workers
- [x] Preserve callback semantics
- [x] Update progress reporting
- [x] Write integration tests

**Files**:
- `lib/gsc_analytics/data_sources/gsc/support/query_paginator.ex` (refactor)
- `test/gsc_analytics/data_sources/gsc/support/query_paginator_test.exs` (update)

---

### Task 5: Integration Testing
**Time**: 1-2 days

**Subtasks**:
- [x] Test with max_concurrency: 1 (should match sequential behavior)
- [x] Test with max_concurrency: 3
- [x] Test with max_concurrency: 5
- [x] Test halt propagation across all workers
- [x] Test rate limit handling with concurrent workers
- [x] Test crash recovery (worker dies mid-fetch)
- [x] Measure actual speedup on production-like data

**Files**:
- `test/gsc_analytics/data_sources/gsc/concurrent_sync_integration_test.exs` (new)

---

### Task 6: Performance Validation
**Time**: 1 day

**Subtasks**:
- [x] Run 150-day backfill on staging
- [x] Collect telemetry metrics
- [x] Validate ≥4× speedup claim (stretch target: 8×)
- [x] Monitor memory usage
- [x] Check for rate limit violations
- [x] Validate data correctness (spot check)

---

## Configuration

**New Config Options**:

```elixir
# config/config.exs
config :gsc_analytics, GscAnalytics.DataSources.GSC.Core.Config,
  # Default number of concurrent HTTP batch workers (safe baseline)
  max_concurrency: 3,

  # Batch size per worker (50 requests per HTTP call)
  batch_size: 50,

  # Rate limit checking enabled
  rate_limit_enabled: true,

  # Coordinator backpressure settings
  max_queue_size: 1_000,
  max_in_flight: 10
```

**Environment Overrides**:

```elixir
# config/dev.exs
config :gsc_analytics, GscAnalytics.DataSources.GSC.Core.Config,
  max_concurrency: 2  # Keep dev lighter to simplify local testing

# config/prod.exs
config :gsc_analytics, GscAnalytics.DataSources.GSC.Core.Config,
  max_concurrency: 3  # Raise to 5 only after telemetry <80% QPM for 1 week
```

**How to bump to 5 workers safely**:
1. Confirm telemetry dashboard shows actual QPM <80% of quota, mailbox <500, retries nominal for 7 days.
2. Land PR updating `config/prod.exs` (runtime config switch) to `max_concurrency: 5`.
3. Deploy with on-call present, watch QPM + halt propagation for at least one full sync.

---

## Risk Mitigation

### Risk 1: Rate Limit Violations
**Mitigation**:
- Start with `max_concurrency: 3` (150 requests/batch = 12.5% of 1,200 QPM)
- Add telemetry for 429 responses
- Implement exponential backoff on rate limit errors
- Monitor first week in production

### Risk 2: Worker Crashes
**Mitigation**:
- Supervisor tree restarts crashed workers
- Coordinator tracks in-flight batches
- Re-enqueue on worker timeout
- Add worker health monitoring

### Risk 3: Halt Propagation Fails
**Mitigation**:
- Test halt scenarios extensively
- Add timeout on worker_loop (max 5 minutes)
- Coordinator sets halt flag atomically
- Workers check flag after every batch

### Risk 4: Memory Leaks
**Mitigation**:
- Monitor GenServer mailbox size
- Set max queue size (alert if exceeded)
- Use :atomics for counters (not process state)
- Profile with `:observer` during integration tests

---

## Success Metrics

**Performance Targets**:
- ✅ **≥4× speedup** on 150-day backfill (stretch: 8× after tuning)
- ✅ Memory usage stays under 500MB per sync
- ✅ Zero rate limit violations (even after increasing to max_concurrency: 5)
- ✅ Zero data corruption (spot check 100 random URLs)

**Operational Metrics**:
- ✅ Worker uptime > 99%
- ✅ Halt propagation < 5 seconds
- ✅ Rate limit checks add < 10ms overhead per batch

---

## Rollback Plan

If production issues arise:

1. **Immediate Rollback**:
   - Set `max_concurrency: 1` (falls back to sequential behavior)
   - Redeploy if needed
   - Monitor for stability

2. **Partial Rollback**:
   - Keep concurrent batching but reduce `max_concurrency: 2-3`
   - Increase rate limit buffer

3. **Full Rollback**:
   - Revert to pre-Phase 4 commit
   - Sync will be slower but stable

---

## Timeline

**Week 1**:
- Days 1-3: Task 1 (QueryCoordinator + backpressure + ETS tracking)
- Days 4-5: Task 2 (ConcurrentBatchWorker + telemetry)

**Week 2**:
- Day 1: Task 3 (RateLimiter batch accounting)
- Days 2-3: Task 4 (QueryPaginator refactor)
- Days 4-5: Task 5 (Integration testing: backpressure, crash recovery, halt propagation)

**Week 3**:
- Task 6 (Performance validation) + staging burn-in

**Week 4**:
- Production deployment, monitoring, buffer for issues / tuning

**Total**: 3-4 weeks (Week 4 is validation + rollout buffer)

---

## Open Questions

1. **When do we raise `max_concurrency` from 3 to 5?**
   - **Recommendation**: After ≥1 week of telemetry showing QPM <80% of quota, mailbox <500, zero rate-limit spikes

2. **Should workers share a single GenServer or use one per property?**
   - **Recommendation**: Single GenServer (simpler), monitor for bottleneck

3. **How do we handle worker timeouts?**
   - **Recommendation**: 5-minute timeout per worker, re-enqueue batch

4. **Should we add circuit breaker pattern?**
   - **Recommendation**: Not initially, add if rate limits become issue

---

## References

- **Codex Bottleneck Analysis**: `sprint-planning/speedup/codex-bottleneck-analysis.md`
- **Codex Critical Review**: `sprint-planning/speedup/codex-critical-review.md`
- **Original Sprint Plan**: `sprint-planning/speedup/README.md`
- **QueryPaginator**: `lib/gsc_analytics/data_sources/gsc/support/query_paginator.ex`
- **RateLimiter**: `lib/gsc_analytics/data_sources/gsc/support/rate_limiter.ex`
- **Client**: `lib/gsc_analytics/data_sources/gsc/core/client.ex`
