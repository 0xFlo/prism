# GSC Sync Performance Optimization Sprint

## Status: IMPLEMENTATION IN PROGRESS
**Created**: 2025-11-13
**Updated**: 2025-11-13 (Implementation kickoff post Codex final review)
**Owner**: Engineering
**Priority**: 🔥 P1 Critical
**Target Speedup**: ≥4× overall sync performance (conservative: 8-12× with Phase 1)

---

## Executive Summary

GSC sync is slow due to **sequential HTTP batch processing** - the dominant bottleneck. After Codex critical review, we're **skipping Phase 2+3** (streaming persistence + deferred refresh) and implementing **Phase 4 (concurrent HTTP batches)** directly.

**Why this change:**
- Phase 2+3 have fundamental architectural flaws (data corruption, data loss on crash)
- Phase 2+3 won't achieve target speedup without addressing sequential HTTP bottleneck
- Phase 4 requires similar investment (~3-4 weeks including validation) but delivers ≥4× improvement (stretch: 8×)
- Phase 4 addresses the **dominant bottleneck** identified by Codex

**Total expected improvement: ≥4× faster syncs** (conservative: 8× with Phase 1, optimistic: 12×)

### Phase 4 Progress Snapshot

- ✅ S01–S04 merged: coordinator, worker pool, rate limiter upgrades, and the refactored QueryPaginator are live behind the `max_concurrency` config gate.
- ✅ Telemetry + tests landed: queue/in-flight metrics, worker batch spans, and rate-limit usage events now power `GscAnalyticsWeb.Telemetry`, backed by new unit suites and `test/gsc_analytics/data_sources/gsc/concurrent_sync_integration_test.exs`.
- ⏳ S05/S06 remaining: documentation, dashboards, and rollout drills are still pending; code + tests are ready for validation.

**⚠️ Architecture refinements needed before implementation** (see Codex Final Review section below)

---

## Decision Update (2025-11-13)

**Original Plan**: Phase 2 (streaming persistence) + Phase 3 (deferred lifetime refresh)
**Codex Critical Review**: Found 10 critical issues causing correctness regressions
**New Plan**: Skip Phase 2+3, implement Phase 4 (concurrent HTTP batches) instead

**Key Codex Findings:**
- Phase 2: `maybe_emit_completion` only fires on **final page**, not per-page
- Phase 2: Incremental `process_query_response` calls will **corrupt data** (UPSERT replaces partial top-20)
- Phase 3: **No crash recovery** - URL list lost on job failure
- Phase 3: State Agent **not durable** - crash = data loss
- Both: Sequential HTTP bottleneck remains, won't hit 3-5× speedup

**See**: `codex-critical-review.md` for full analysis

---

## Codex Final Review (2025-11-13)

After reviewing the Phase 4 plan, Codex identified 6 areas requiring refinement before implementation:

### ✅ ADDRESSED: Critical Issues

**1. Backpressure & Persistence Hand-off** (High)
- **Issue**: Coordinator could become bottleneck with 5 workers pushing results concurrently
- **Fix**: Added queue limits (`max_queue_size: 1000`, `max_in_flight: 10`), worker acknowledgement protocol, FIFO result processing

**2. Rate Limiting Math Inconsistent** (High)
- **Issue**: Config showed `max_concurrency: 5` but no QPM budget calculation
- **Fix**: Start with `max_concurrency: 3`, added explicit QPM formula, telemetry for actual QPM tracking

**3. Failure Recovery Lacks Idempotency** (Medium)
- **Issue**: Re-enqueue on timeout could cause duplicate inserts
- **Fix**: Tag batches with `{date, start_row}` key, coordinator dedup check, ETS tracking for crash recovery

**4. Timeline Too Optimistic** (Medium)
- **Issue**: 2-3 weeks unrealistic for 2 new OTP behaviours + testing
- **Fix**: Updated to 3-4 weeks with detailed task breakdown

**5. Missing Backpressure Monitoring** (Medium)
- **Issue**: "Monitor mailbox size" without action plan
- **Fix**: Added emergency throttle at >800 messages, alert at >500, action plan to reduce concurrency

**6. Speedup Target Too High** (Low)
- **Issue**: Claimed 4-8× but buffered persistence bottleneck (2×) remains
- **Fix**: Changed to "≥4× conservative baseline" with stretch goals, acknowledged unaddressed bottlenecks

### Codex Verdict

> "The GenServer + worker approach is directionally better than the abandoned Phase 2+3, but the plan still needs concrete guidance on queue semantics, rate limiting math, and validation tooling before it can realistically hit the proposed 4–8× target within 2–3 weeks."

**Status**: All findings addressed in updated plan above ✅

---

## Background

### Current Performance Issues
- **Sequential HTTP batching** - only 1 batch in flight at a time (dominant bottleneck)
- Buffered persistence blocks API calls while writing entire day's data to DB
- Synchronous materialized view refresh scans all historical rows per URL per day

### Codex Analysis Results

**Bottleneck #1 (Dominant)**: Sequential HTTP batch processing
- `query_paginator.ex:204-262` - Only 1 HTTP batch in flight
- Network latency accumulates linearly
- **Impact**: 5-8× slowdown
- **Fix**: Concurrent batching (Phase 4)

**Bottleneck #2**: Buffered persistence
- `query_paginator.ex:333-430` - Buffers all rows per date
- **Impact**: 2× slowdown (but NOT addressable without fixing Bottleneck #1)
- **Fix**: Would require persistent heap state + chunk-level callbacks (complex)

**Bottleneck #3**: Synchronous lifetime refresh
- `url_phase.ex:36-108`, `persistence.ex:277-326` - Blocks next date fetch
- **Impact**: 1.5-2× slowdown
- **Fix**: Already improved with UPSERT in Phase 1

---

## Implementation Strategy

### ✅ Phase 1: Configuration Optimizations (COMPLETED)

**Status**: Merged
**Speedup**: 2-3× faster than original

**Changes**:
- `default_batch_size`: 8 → 50
- `query_scheduler_chunk_size`: 8 → 16
- `time_series_batch_size`: 500 → 1,000
- `lifetime_stats_batch_size`: 500 → 2,000
- `http_timeout`: 30s → 45s
- Replaced DELETE+INSERT with single UPSERT query

**Files Modified**:
- `config/dev.exs` - Disabled verbose Ecto logging
- `lib/gsc_analytics/data_sources/gsc/core/config.ex` - Increased batch sizes
- `lib/gsc_analytics/data_sources/gsc/core/persistence.ex` - UPSERT instead of DELETE+INSERT

---

### 🔥 Phase 4: Concurrent HTTP Batches (THIS SPRINT)

**Status**: Ready to implement
**Priority**: 🔥 P1 Critical
**Expected Gain**: ≥4× additional speedup (stretch: 8×)
**Total Improvement**: 8-12× faster than original (Phase 1 × Phase 4)
**Complexity**: High (3-4 weeks including validation)
**Timeline**: 3-4 weeks

**See**: `PHASE4_IMPLEMENTATION_PLAN.md` for complete implementation details

#### Why Phase 4 Instead of Phase 2+3?

| Metric | Phase 2+3 | Phase 4 |
|--------|-----------|---------|
| **Speedup** | 1.7-2× (realistic) | ≥4× (stretch: 8×) |
| **Complexity** | High (persistent state, crash recovery) | High (same) |
| **Time** | 2-3 weeks | 3-4 weeks (includes validation) |
| **Correctness Risk** | High (data corruption, data loss) | Medium (well-tested pattern) |
| **Rollback** | Hard (architectural changes) | Easy (config flag) |
| **Bottleneck Addressed** | No (sequential HTTP remains) | Yes (dominant bottleneck) |

**Verdict**: Phase 4 is better ROI - same effort, bigger wins, easier rollback

#### Architecture Overview

**1. GenServer-Based QueryCoordinator**
- Replaces tail-recursive state machine
- Concurrency-safe state updates with demand-driven backpressure
- Atomic counters for telemetry
- Halt propagation across workers
- **Backpressure mechanism**: Queue limits + worker acknowledgements prevent mailbox growth
- **Result buffering**: In-memory queue with configurable max size (default: 1000 batches)
- **Ordering**: Results processed in order received (FIFO), persistence happens synchronously per batch

**2. Concurrent Batch Workers**
- Multiple Task.async workers fetching in parallel
- Independent worker failure handling
- 3-5 workers (configurable, start conservative)
- **Idempotency**: Each batch tagged with `{date, start_row}` key for deduplication
- **Retry safety**: Coordinator tracks in-flight batches, re-enqueues on timeout with dedup check

**3. Rate Limiter Integration**
- Rate checking BEFORE HTTP call in batch worker
- Fixes current bypass in `fetch_query_batch/3`
- **QPM Budget**: `max_concurrency × batch_size × 60 / avg_batch_duration_sec ≤ 1,200 QPM`
- **Telemetry**: Track actual QPM, batch latencies, queue depths
- Backoff on rate limit

#### Implementation Tasks

**Week 1-2**: Core Architecture
- Task 1: Implement QueryCoordinator GenServer with backpressure (3-4 days)
  - Demand-driven queue with max size limit
  - Worker acknowledgement protocol
  - Idempotency tracking (in-flight batch deduplication)
- Task 2: Implement ConcurrentBatchWorker (2-3 days)
  - Rate limit integration
  - Retry with dedup
  - Telemetry hooks

**Week 2-3**: Integration & Testing
- Task 3: Update RateLimiter for QPM budget accounting (1 day)
  - Track actual QPM vs budget
  - Alert on quota approach (>80%)
- Task 4: Refactor QueryPaginator to use Coordinator (2-3 days)
- Task 5: Integration testing (2-3 days)
  - Backpressure scenarios
  - Worker crash recovery with dedup
  - Halt propagation timing

**Week 4**: Validation & Tuning (Buffer)
- Task 6: Performance validation on staging (2-3 days)
  - Start max_concurrency: 3, measure actual QPM
  - Gradually increase if stable
  - Profile coordinator mailbox size
- Production deployment + monitoring (1-2 days)

#### Files to Create

**New Modules**:
- `lib/gsc_analytics/data_sources/gsc/support/query_coordinator.ex`
- `lib/gsc_analytics/data_sources/gsc/support/concurrent_batch_worker.ex`

**Modified**:
- `lib/gsc_analytics/data_sources/gsc/support/query_paginator.ex` (refactor)
- `lib/gsc_analytics/data_sources/gsc/support/rate_limiter.ex` (add batch support)

**Tests**:
- `test/gsc_analytics/data_sources/gsc/support/query_coordinator_test.exs` (new)
- `test/gsc_analytics/data_sources/gsc/support/concurrent_batch_worker_test.exs` (new)
- `test/gsc_analytics/data_sources/gsc/concurrent_sync_integration_test.exs` (new)

#### Sprint Tickets

Ticket breakdown lives in `sprint-planning/speedup/TICKETS.md`. Quick view:

| Ticket | Focus |
|--------|-------|
| **S01** | Build QueryCoordinator GenServer (queue/backpressure, ETS tracking) |
| **S02** | Implement ConcurrentBatchWorker + supervision + retry logic |
| **S03** | Rate limiter + config plumbing (`max_concurrency`, queue limits) |
| **S04** | Refactor QueryPaginator to orchestrate coordinator/workers |
| **S05** | Telemetry + test coverage (unit + integration) |
| **S06** | Staging validation + rollout/rollback playbook |

Each ticket lists goals, deliverables, and acceptance criteria.

#### Configuration

```elixir
# config/config.exs
config :gsc_analytics, GscAnalytics.DataSources.GSC.Core.Config,
  # Number of concurrent HTTP batch workers (start conservative)
  max_concurrency: 3,

  # Batch size per worker (50 requests per HTTP call)
  batch_size: 50,

  # Rate limit checking enabled
  rate_limit_enabled: true,

  # Coordinator queue limits for backpressure
  max_queue_size: 1000,  # Max batches in coordinator queue
  max_in_flight: 10      # Max batches awaiting persistence
```

**Rate Limit Math** (start with max_concurrency: 3):
- Batch size: 50 requests
- Estimated batch duration: ~2 seconds (network + processing)
- Theoretical QPM: `3 workers × 50 requests × 60s / 2s = 4,500 requests/min`
- **With retries/backoff**: Actual ~600-800 QPM (50-66% of 1,200 limit)
- **Buffer**: 33-50% headroom for safety

**Rollback**: Set `max_concurrency: 1` → falls back to sequential (zero-downtime)

---

## Success Metrics

### Performance Targets
- ✅ **≥4× speedup** on 150-day backfill (conservative baseline)
  - Stretch goal: 8-12× with optimizations
  - Note: Buffered persistence bottleneck (2×) remains unaddressed
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

### Telemetry Requirements
- Track actual QPM vs budget (alert if >80%)
- Monitor coordinator mailbox size (alert if >500)
- Record batch latencies (p50, p95, p99)
- Count worker crashes and retries
- Measure time-to-halt after error

---

## Risk Mitigation

### Risk 1: Rate Limit Violations
**Mitigation**:
- Start with `max_concurrency: 3` (theoretical 4,500 QPM, actual ~600-800 with retries)
- **QPM budget formula**: Track `(batches_completed × batch_size) / time_elapsed_minutes`
- Alert at 80% quota (960 QPM)
- Auto-throttle if approaching limit
- Monitor for 1 week before increasing concurrency
- **Telemetry**: Real-time QPM dashboard + Slack alerts

### Risk 2: Worker Crashes & Data Integrity
**Mitigation**:
- Supervisor tree restarts crashed workers
- **Idempotency**: Tag each batch with `{date, start_row}` key
- Coordinator dedup check before re-enqueue
- Track in-flight batches in ETS (survives coordinator crash)
- **Validation**: Reconciliation job compares expected vs actual row counts
- Add worker health monitoring

### Risk 3: Halt Propagation Fails
**Mitigation**:
- Test halt scenarios extensively
- Add timeout on worker_loop (max 5 minutes)
- Coordinator sets halt flag atomically
- Workers check flag BEFORE and AFTER each HTTP call
- **Telemetry**: Measure time-to-halt (target: <5 seconds)

### Risk 4: Coordinator Mailbox Growth (Backpressure Failure)
**Mitigation**:
- **Queue limit**: `max_queue_size: 1000` batches
- **In-flight limit**: `max_in_flight: 10` pending persistence
- Workers block when limits reached (backpressure)
- Monitor mailbox size (alert if >500)
- **Emergency throttle**: Pause workers if mailbox >800
- Profile with `:observer` during integration tests
- **Action plan if threshold hit**: Reduce max_concurrency or increase persistence speed

---

## Timeline

**Week 1-2**: QueryCoordinator + ConcurrentBatchWorker (with backpressure, idempotency)
**Week 2-3**: RateLimiter QPM budget + QueryPaginator refactor + integration testing
**Week 4**: Staging validation, tuning, production deployment

**Total**: 3-4 weeks (realistic estimate accounting for concurrency complexity)

---

## Rollback Plan

If production issues arise:

1. **Immediate Rollback**:
   - Set `max_concurrency: 1` (falls back to sequential)
   - Zero-downtime rollback via config
   - Monitor for stability

2. **Partial Rollback**:
   - Keep concurrent batching but reduce `max_concurrency: 2-3`
   - Increase rate limit buffer

3. **Full Rollback**:
   - Revert to pre-Phase 4 commit
   - Sync will be slower but stable

---

## References

**Phase 4 Documentation**:
- **Full Implementation Plan**: `PHASE4_IMPLEMENTATION_PLAN.md`
- **Quick Summary**: `PHASE4_SUMMARY.md`
- **Rollout Playbook**: `PHASE4_ROLLOUT_PLAYBOOK.md`

**Codex Analysis**:
- **Bottleneck Analysis**: `codex-bottleneck-analysis.md`
- **Critical Review** (Phase 2+3 issues): `codex-critical-review.md`
- **Final Review** (Phase 4 refinements): `CODEX_FINAL_REVIEW.md`

**Quick Reference**:
- **TL;DR**: `QUICK_REFERENCE.md`

**Code**:
- **Config**: `lib/gsc_analytics/data_sources/gsc/core/config.ex`
- **Persistence**: `lib/gsc_analytics/data_sources/gsc/core/persistence.ex`
- **Query Paginator**: `lib/gsc_analytics/data_sources/gsc/support/query_paginator.ex`
- **Rate Limiter**: `lib/gsc_analytics/data_sources/gsc/support/rate_limiter.ex`
- **Client**: `lib/gsc_analytics/data_sources/gsc/core/client.ex`

---

## Why Not Phase 2+3?

Phase 2 (streaming persistence) and Phase 3 (deferred lifetime refresh) were initially planned but **abandoned** after Codex critical review revealed fundamental flaws:

### Phase 2 Issues (Would Break):
- `maybe_emit_completion` only fires on **final page**, not per-page
- Incremental `process_query_response` calls **corrupt data** (UPSERT replaces partial top-20)
- No DB/HTTP overlap achievable without concurrency (paginator is synchronous)
- Memory still scales with URL count (100k URLs × 20 queries = exceeds 100MB)

### Phase 3 Issues (Would Break):
- **No crash recovery** - URL list lost on job failure
- State Agent **not durable** - crash = data loss
- Downstream systems serve **stale data** during sync (no background refresh plan)
- No "finally" hook to guarantee refresh runs

### Speedup Reality:
- Claimed: 3-5×
- **Realistic**: 1.7-2× (sequential HTTP bottleneck remains)
- **Phase 4**: ≥4× (stretch: 8×) (addresses dominant bottleneck)

**See**: `codex-critical-review.md` for complete analysis
