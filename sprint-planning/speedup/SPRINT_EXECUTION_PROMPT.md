# Phase 4 Sprint Execution Prompt for LLM

## Context

You are implementing Phase 4 of the GSC Sync Performance Optimization sprint for a Phoenix/Elixir application. This sprint adds concurrent HTTP batch processing to achieve ≥4× speedup (stretch: 8×) over the current sequential implementation.

## Required Reading (In Order)

Before starting, read these documents to understand the architecture:

1. **Sprint Overview**: `sprint-planning/speedup/README.md` - Background, decision rationale, architecture overview
2. **Implementation Plan**: `sprint-planning/speedup/PHASE4_IMPLEMENTATION_PLAN.md` - Detailed technical design
3. **Sprint Tickets**: `sprint-planning/speedup/TICKETS.md` - Task breakdown with acceptance criteria
4. **Pattern Docs**: `docs/elixir-patterns/README.md` - Elixir/OTP patterns you'll be implementing

## Current State

**Completed**: Phase 1 configuration optimizations (2-3× speedup)
- Batch sizes increased (8→50 for queries, 500→1000 for DB inserts)
- UPSERT instead of DELETE+INSERT
- Status: ✅ Merged and deployed

**Current bottleneck**: Sequential HTTP batch processing (one batch in flight at a time)

**Files to understand**:
- `lib/gsc_analytics/data_sources/gsc/support/query_paginator.ex` - Current sequential implementation
- `lib/gsc_analytics/data_sources/gsc/support/rate_limiter.ex` - Existing rate limiter
- `lib/gsc_analytics/data_sources/gsc/core/config.ex` - Configuration module
- `lib/gsc_analytics/data_sources/gsc/core/persistence.ex` - Database operations

## Sprint Goal

Replace sequential HTTP batch processing with concurrent batch workers coordinated by a GenServer, achieving:
- ≥4× faster sync operations (conservative baseline)
- Zero data corruption or loss
- Respect 1,200 QPM API limit (stay <80% = 960 QPM)
- Graceful backpressure and error handling
- Zero-downtime rollback capability (via config)

## Implementation Approach

### Phase 1: Foundation (Week 1-2)

**Ticket S01 - QueryCoordinator GenServer** (~3-4 days)

Create a GenServer that coordinates concurrent batch fetching:

```elixir
# lib/gsc_analytics/data_sources/gsc/support/query_coordinator.ex
defmodule GscAnalytics.DataSources.GSC.Support.QueryCoordinator do
  use GenServer

  # Public API
  def start_link(opts)
  def take_batch(pid, worker_id)
  def submit_results(pid, batch_id, results)
  def requeue_batch(pid, batch_id)
  def halt(pid, reason)
  def finalize(pid)

  # State management
  # - batch_queue: :queue of pending batches
  # - in_flight: Map of {batch_id => {worker_pid, timestamp}}
  # - in_flight_count: Current count (for backpressure)
  # - halted?: Boolean flag
  # - results: List of completed results
end
```

**Key features**:
1. **Queue management** with configurable limits (`max_queue_size: 1000`)
2. **Backpressure** via `max_in_flight: 10` limit
3. **ETS tracking** for crash recovery (table: `:gsc_in_flight_batches`)
4. **Idempotency** via `{date, start_row}` batch keys
5. **Halt propagation** to stop all workers on error

**Pattern reference**: `docs/elixir-patterns/genserver-coordination.md`

**Acceptance criteria**:
- [ ] Coordinator enforces queue limits (reject when queue full)
- [ ] Coordinator enforces in-flight limits (backpressure when exceeded)
- [ ] ETS table tracks in-flight batches with `{batch_id, worker_pid, timestamp}`
- [ ] Deduplication prevents same batch from being taken twice
- [ ] Halt flag stops new batches from being taken
- [ ] Unit tests cover: queue overflow, dedup, halt, requeue

---

**Ticket S02 - ConcurrentBatchWorker** (~2-3 days)

Create worker loop that fetches batches concurrently:

```elixir
# lib/gsc_analytics/data_sources/gsc/support/concurrent_batch_worker.ex
defmodule GscAnalytics.DataSources.GSC.Support.ConcurrentBatchWorker do

  def start_workers(coordinator_pid, count, opts) do
    for _ <- 1..count do
      Task.Supervisor.async_nolink(
        GscAnalytics.TaskSupervisor,
        fn -> worker_loop(coordinator_pid, opts) end
      )
    end
  end

  defp worker_loop(coordinator_pid, opts) do
    case QueryCoordinator.take_batch(coordinator_pid, self()) do
      {:ok, batch} ->
        # Check rate limit BEFORE HTTP call
        case RateLimiter.check_rate(batch.property_url, batch.size) do
          :ok ->
            # Fetch batch via Client
            result = fetch_batch(batch, opts)
            QueryCoordinator.submit_results(coordinator_pid, batch.id, result)

          {:error, :rate_limited, retry_ms} ->
            # Return batch to coordinator
            QueryCoordinator.requeue_batch(coordinator_pid, batch.id)
            Process.sleep(retry_ms)
        end

        # Continue loop
        worker_loop(coordinator_pid, opts)

      :no_batches ->
        Process.sleep(1000)
        worker_loop(coordinator_pid, opts)

      {:error, :halted} ->
        # Stop gracefully
        :ok
    end
  end
end
```

**Key features**:
1. **Rate limit check before HTTP** (fixes current bypass)
2. **Batch requeue on rate limit** (preserves work)
3. **Telemetry instrumentation** (duration, retries, errors)
4. **Halt detection** (check before and after HTTP call)

**Pattern reference**: `docs/elixir-patterns/concurrent-processing.md#taskasync_stream-pattern`

**Acceptance criteria**:
- [ ] Workers honor rate limits before HTTP calls
- [ ] Rate-limited batches are requeued (not dropped)
- [ ] Workers detect halt flag and exit gracefully
- [ ] Worker failures don't crash coordinator
- [ ] Telemetry emitted for: batch start, complete, failed, rate limited
- [ ] Unit tests cover: normal flow, rate limit, halt, worker crash

---

### Phase 2: Integration (Week 2-3)

**Ticket S03 - RateLimiter Enhancement** (~1 day)

Enhance existing rate limiter to support batch increments:

```elixir
# lib/gsc_analytics/data_sources/gsc/support/rate_limiter.ex

# Add batch support
def check_rate(property_url, request_count \\ 1) do
  key = "gsc_api:#{property_url}"

  case Hammer.hit(key, @window_ms, @qpm_limit, request_count) do
    {:allow, current_count} ->
      # Alert if approaching limit
      if current_count / @qpm_limit >= 0.8 do
        Logger.warn("Approaching rate limit: #{current_count}/#{@qpm_limit}")
        :telemetry.execute([:gsc_analytics, :rate_limit, :approaching],
          %{current: current_count, limit: @qpm_limit},
          %{property_url: property_url})
      end
      :ok

    {:deny, retry_ms} ->
      :telemetry.execute([:gsc_analytics, :rate_limit, :exceeded],
        %{limit: @qpm_limit},
        %{property_url: property_url, retry_ms: retry_ms})
      {:error, :rate_limited, retry_ms}
  end
end
```

**Config additions** (`lib/gsc_analytics/data_sources/gsc/core/config.ex`):

```elixir
def max_concurrency, do: get_env(:max_concurrency, 3)
def max_queue_size, do: get_env(:max_queue_size, 1000)
def max_in_flight, do: get_env(:max_in_flight, 10)
```

**Pattern reference**: `docs/elixir-patterns/rate-limiting.md#qpm-budget-management`

**Acceptance criteria**:
- [ ] `check_rate/2` accepts batch size parameter
- [ ] Telemetry emitted at 80% quota threshold
- [ ] Telemetry emitted on rate limit exceeded
- [ ] Config module exposes all concurrency settings
- [ ] Defaults are conservative: `max_concurrency: 3`

---

**Ticket S04 - QueryPaginator Refactor** (~2-3 days)

Refactor `query_paginator.ex` to use coordinator + workers:

```elixir
# lib/gsc_analytics/data_sources/gsc/support/query_paginator.ex

def fetch_all(state, opts) do
  max_concurrency = Config.max_concurrency()

  if max_concurrency == 1 do
    # Legacy sequential mode (for rollback)
    fetch_all_sequential(state, opts)
  else
    # New concurrent mode
    fetch_all_concurrent(state, opts)
  end
end

defp fetch_all_concurrent(state, opts) do
  # 1. Generate all batch descriptors
  batches = generate_batches(state)

  # 2. Start coordinator
  {:ok, coordinator} = QueryCoordinator.start_link(
    batches: batches,
    max_queue_size: Config.max_queue_size(),
    max_in_flight: Config.max_in_flight()
  )

  # 3. Start workers
  worker_tasks = ConcurrentBatchWorker.start_workers(
    coordinator,
    Config.max_concurrency(),
    client_opts: opts
  )

  # 4. Wait for completion
  results = QueryCoordinator.finalize(coordinator)

  # 5. Cleanup workers
  Enum.each(worker_tasks, &Task.shutdown(&1, :brutal_kill))

  # 6. Process results (existing persistence logic)
  process_results(state, results)
end

defp generate_batches(state) do
  # Convert current pagination logic into list of batch descriptors
  # Each descriptor: %{date: date, start_row: row, size: 50, property_url: url}
end
```

**Key changes**:
1. Config switch via `max_concurrency` (1 = sequential, >1 = concurrent)
2. Batch generation upfront (no more recursive loop)
3. Coordinator orchestrates workers
4. Results collected and processed in FIFO order
5. Existing persistence callbacks unchanged

**Pattern reference**: `docs/elixir-patterns/genserver-coordination.md#recommended-architecture-for-phase-4`

**Acceptance criteria**:
- [ ] Sequential mode (concurrency=1) matches old behavior exactly
- [ ] Concurrent mode (concurrency>1) uses coordinator + workers
- [ ] Results processed in FIFO order
- [ ] Persistence callbacks called correctly
- [ ] Halt propagates to all workers within 5 seconds
- [ ] Integration test: fetch 100 batches concurrently, verify results match sequential

---

### Phase 3: Observability & Testing (Week 3)

**Ticket S05 - Telemetry & Tests** (~2-3 days)

Add comprehensive telemetry and test coverage:

**Telemetry events to add**:

```elixir
# In QueryCoordinator
:telemetry.execute([:gsc_analytics, :coordinator, :queue_size],
  %{size: queue_length}, %{})

:telemetry.execute([:gsc_analytics, :coordinator, :in_flight],
  %{count: in_flight_count}, %{})

# In ConcurrentBatchWorker
:telemetry.span(
  [:gsc_analytics, :worker, :batch],
  %{batch_id: batch.id, worker_id: worker_id},
  fn ->
    result = fetch_batch(batch)
    {result, %{rows: length(result), duration_ms: duration}}
  end
)

# In RateLimiter
:telemetry.execute([:gsc_analytics, :rate_limit, :qpm],
  %{current: current_qpm, limit: 600},
  %{property_url: property_url})
```

**Metrics to add** (`lib/gsc_analytics_web/telemetry.ex`):

```elixir
# Coordinator metrics
counter("gsc_analytics.coordinator.batch.dequeued"),
last_value("gsc_analytics.coordinator.queue_size"),
last_value("gsc_analytics.coordinator.in_flight"),

# Worker metrics
counter("gsc_analytics.worker.batch.count", tags: [:result]),
summary("gsc_analytics.worker.batch.duration", unit: {:native, :millisecond}),

# Rate limit metrics
last_value("gsc_analytics.rate_limit.qpm"),
counter("gsc_analytics.rate_limit.exceeded")
```

**Tests to add**:

```elixir
# test/gsc_analytics/data_sources/gsc/support/query_coordinator_test.exs
- Queue overflow handling
- In-flight limit enforcement
- Batch deduplication
- Halt propagation
- Crash recovery (ETS rehydration)

# test/gsc_analytics/data_sources/gsc/support/concurrent_batch_worker_test.exs
- Normal batch processing
- Rate limit handling (requeue)
- Halt detection and graceful exit
- Worker crash recovery

# test/gsc_analytics/data_sources/gsc/concurrent_sync_integration_test.exs
- Full sync with 3 workers
- Verify data integrity (no duplicates, no missing batches)
- Halt propagation timing (<5s)
- Rate limit backoff behavior
- Coordinator crash recovery
```

**Pattern reference**: `docs/elixir-patterns/telemetry.md`

**Acceptance criteria**:
- [ ] All telemetry events documented and tested
- [ ] Metrics added to LiveDashboard
- [ ] Unit test coverage >90% for new modules
- [ ] Integration test validates data integrity
- [ ] Integration test measures halt propagation time
- [ ] CI passes all tests

---

### Phase 4: Validation & Rollout (Week 4)

**Ticket S06 - Staging Validation** (~2-3 days)

Validate performance and correctness on staging:

**Validation checklist**:

```bash
# 1. Deploy to staging with max_concurrency: 3
mix release
# Deploy...

# 2. Run 150-day backfill
iex> GscAnalytics.DataSources.GSC.Core.Sync.sync_date_range(
  "sc-domain:staging.com",
  ~D[2024-01-01],
  ~D[2024-05-30],
  account_id: 1
)

# 3. Capture metrics
# - Total duration (target: ≤37 minutes for 150 days, baseline: ~150 mins)
# - Actual QPM (target: <960)
# - Coordinator mailbox size (target: <500)
# - Worker crash count (target: 0)
# - Data integrity (spot check 100 URLs)

# 4. Run reconciliation
# Verify row counts match expected:
iex> GscAnalytics.ValidationHelper.reconcile_sync(
  "sc-domain:staging.com",
  ~D[2024-01-01],
  ~D[2024-05-30]
)
```

**Rollout plan**:

1. **Staging validation** (Week 4, Day 1-2)
   - Deploy with `max_concurrency: 3`
   - Run 150-day backfill
   - Verify ≥4× speedup
   - Check data integrity (zero duplicates/missing rows)
   - Monitor for 24 hours

2. **Production canary** (Week 4, Day 3)
   - Deploy to single production workspace
   - Monitor QPM, error rates, memory usage
   - Run incremental sync (yesterday's data)
   - If stable after 6 hours, proceed

3. **Production rollout** (Week 4, Day 4)
   - Deploy to all workspaces
   - Monitor dashboards for 24 hours
   - Alert thresholds:
     - QPM >80% (960) → Auto-throttle
     - Mailbox >500 → Investigate
     - Error rate >1% → Rollback

4. **Optional: Increase concurrency** (Week 5+)
   - If metrics stable for 1 week at concurrency=3
   - Increase to `max_concurrency: 5`
   - Monitor for another week

**Rollback procedure**:

```elixir
# Immediate rollback (zero downtime)
# config/prod.exs or runtime config
config :gsc_analytics, GscAnalytics.DataSources.GSC.Core.Config,
  max_concurrency: 1  # Falls back to sequential mode

# Restart application (or hot code reload)
# Syncs continue with old sequential behavior
```

**Pattern reference**: `sprint-planning/speedup/README.md#rollback-plan`

**Acceptance criteria**:
- [ ] ≥4× speedup measured on staging (150-day backfill)
- [ ] Actual QPM <80% of limit (960)
- [ ] Zero data corruption (reconciliation passes)
- [ ] Coordinator mailbox <500 messages
- [ ] Worker uptime >99%
- [ ] Rollback procedure tested and documented
- [ ] Production deployment checklist completed

---

## Success Metrics

### Performance Targets
- ✅ **≥4× speedup** on 150-day backfill (conservative baseline)
  - Stretch goal: 8-12× with optimizations
- ✅ Memory usage < 500MB per sync
- ✅ Zero rate limit violations (target: <80% of 1,200 QPM)
- ✅ Same or fewer API calls (no regression)
- ✅ Actual QPM < 960 (80% of quota)

### Operational Metrics
- ✅ Zero data corruption (spot check 100 random URLs)
- ✅ Halt propagation < 5 seconds
- ✅ Worker uptime > 99%
- ✅ Rate limit checks add < 10ms overhead per batch
- ✅ Coordinator mailbox size < 1000 messages (backpressure working)
- ✅ Batch latency p99 < 5 seconds

## Important Constraints

### Rate Limiting Math

**Conservative start** (`max_concurrency: 3`):
```
Theoretical QPM = 3 workers × 50 requests/batch × 60s / 2s batch time
                = 4,500 requests/min

Realistic QPM (with retries/backoff) = ~600-800 requests/min
Buffer = 33-50% headroom below 1,200 limit
```

**After validation** (optional increase to 5):
```
Theoretical QPM = 5 workers × 50 requests/batch × 60s / 2s
                = 7,500 requests/min

Realistic QPM = ~1,000 requests/min
Buffer = 16% headroom (only if stable at 3 for 1 week)
```

### Backpressure Thresholds

```elixir
# Coordinator state limits
@max_queue_size 1000   # Max batches in queue
@max_in_flight 10      # Max batches awaiting persistence

# Mailbox monitoring
@alert_threshold 500    # Log warning
@critical_threshold 800 # Auto-throttle (pause workers)
```

### Idempotency

Every batch must be tagged with `{date, start_row}` key for deduplication:

```elixir
batch_id = {batch.date, batch.start_row}

# Coordinator checks before returning batch
if MapSet.member?(state.seen_batches, batch_id) do
  # Skip, already taken
else
  # Mark as seen, return to worker
end
```

### Error Handling

**Transient errors** (retry with backoff):
- Rate limit (429)
- Server errors (5xx)
- Network timeouts
- Connection refused

**Permanent errors** (don't retry):
- Unauthorized (401)
- Bad request (4xx except 429)
- Token refresh needed

## Development Guidelines

### Code Style

- Follow existing patterns in `lib/gsc_analytics/data_sources/gsc/`
- Use `alias` for module references (avoid full paths)
- Add `@moduledoc` and `@doc` for all public functions
- Use typespecs for public APIs
- Add telemetry spans with `:telemetry.span/3` (see pattern docs)

### Testing Requirements

- All new modules must have unit tests
- Integration test must validate data integrity
- Use `ExUnit.Case, async: false` for tests that modify global state
- Mock external HTTP calls with bypass or mox
- Test both success and failure paths

### Git Workflow

1. Create feature branch: `git checkout -b phase4-s01-query-coordinator`
2. Commit frequently with clear messages: `feat(s01): Add QueryCoordinator GenServer`
3. Run pre-commit validation: `mix precommit` (compile, format, test)
4. Create PR referencing ticket: "Implements S01: QueryCoordinator GenServer"
5. After review and CI pass, squash and merge

### Pre-commit Checklist

Before each commit:
- [ ] `mix precommit` passes (compile, format, test)
- [ ] All new code has tests
- [ ] All tests pass locally
- [ ] No hardcoded values (use Config module)
- [ ] Telemetry events added for new operations
- [ ] Documentation updated if adding public APIs

## Troubleshooting Guide

### Issue: Rate limit violations

**Symptoms**: Seeing 429 errors in logs, QPM >80%

**Actions**:
1. Check actual QPM: `grep rate_limit logs/gsc_audit.log | tail -20 | jq`
2. Verify workers are checking rate limit before HTTP
3. Reduce `max_concurrency` temporarily
4. Increase `batch_size` (fewer HTTP calls per request)

### Issue: Coordinator mailbox growth

**Symptoms**: Mailbox size >500, increasing over time

**Actions**:
1. Check in-flight count: Should be ≤10
2. Check queue size: Should be ≤1000
3. Profile persistence speed (may be bottleneck)
4. Reduce `max_concurrency` if persistence can't keep up

### Issue: Data duplication

**Symptoms**: Same URL/date appears multiple times in TimeSeries

**Actions**:
1. Check batch deduplication in coordinator
2. Verify ETS in-flight tracking
3. Check database UPSERT conflict targets
4. Run reconciliation query to identify duplicates
5. Fix dedup logic, run cleanup script

### Issue: Halt propagation slow (>5s)

**Symptoms**: Workers continue after error, timeout before stopping

**Actions**:
1. Verify workers check halt flag before AND after HTTP call
2. Reduce HTTP timeout (currently 45s)
3. Add timeout on worker loop (max 5 min per batch)
4. Check if workers are stuck in rate limit sleep

## Files You'll Create

```
lib/gsc_analytics/data_sources/gsc/support/
  query_coordinator.ex           (NEW - S01)
  concurrent_batch_worker.ex     (NEW - S02)
  query_paginator.ex             (REFACTOR - S04)
  rate_limiter.ex                (ENHANCE - S03)

lib/gsc_analytics/data_sources/gsc/core/
  config.ex                      (ENHANCE - S03)

test/gsc_analytics/data_sources/gsc/support/
  query_coordinator_test.exs     (NEW - S05)
  concurrent_batch_worker_test.exs (NEW - S05)

test/gsc_analytics/data_sources/gsc/
  concurrent_sync_integration_test.exs (NEW - S05)

lib/gsc_analytics_web/
  telemetry.ex                   (ENHANCE - S05)
```

## Execution Instructions for LLM

To execute this sprint, follow these steps:

### Step 1: Understand the Context
1. Read `sprint-planning/speedup/README.md` completely
2. Read `sprint-planning/speedup/PHASE4_IMPLEMENTATION_PLAN.md`
3. Read `docs/elixir-patterns/README.md` for pattern reference
4. Review existing files listed in "Current State" section above

### Step 2: Execute Tickets Sequentially
1. Start with S01 (QueryCoordinator)
2. After S01 tests pass, move to S02 (ConcurrentBatchWorker)
3. After S02 tests pass, move to S03 (RateLimiter)
4. After S03 tests pass, move to S04 (QueryPaginator refactor)
5. After S04 integration test passes, move to S05 (Telemetry)
6. After S05 complete, move to S06 (Validation)

### Step 3: For Each Ticket
1. Create the new file(s) or identify files to modify
2. Implement the functionality per the specification above
3. Add unit tests (use existing test files as reference for style)
4. Run `mix precommit` and fix any issues
5. Run integration tests if applicable
6. Mark ticket acceptance criteria as complete
7. Commit with descriptive message

### Step 4: Integration & Validation
1. After S01-S05 complete, run full integration test
2. Verify all acceptance criteria are met
3. Create staging deployment checklist
4. Document rollback procedure

### Step 5: Documentation Updates
1. Update CLAUDE.md with any new patterns or gotchas
2. Add performance benchmark results to README
3. Document configuration options
4. Add troubleshooting entries if you encountered issues

## Questions to Ask

If you encounter ambiguity, ask the user:

1. **Configuration values**: "Should I use X or Y for [setting]?"
2. **Error handling**: "How should we handle [edge case]?"
3. **Performance tradeoffs**: "Should we optimize for X or Y?"
4. **Testing scope**: "Do you want me to test [scenario]?"
5. **Rollout strategy**: "Should we deploy to staging first?"

## Success Indicators

You'll know the sprint is successful when:

✅ All 6 tickets (S01-S06) have acceptance criteria met
✅ `mix precommit` passes with no warnings or failures
✅ Integration test shows ≥4× speedup vs baseline
✅ Zero data integrity issues (no duplicates, no missing rows)
✅ Actual QPM stays <80% of limit
✅ Coordinator mailbox stays <500 messages
✅ Rollback procedure tested and documented
✅ Staging deployment successful

## Ready to Start?

Begin with: "I'm ready to start Phase 4 implementation. Starting with S01 (QueryCoordinator GenServer). Let me first review the existing query_paginator.ex to understand the current flow..."

Then proceed through tickets S01 → S02 → S03 → S04 → S05 → S06 sequentially.

Good luck! 🚀
