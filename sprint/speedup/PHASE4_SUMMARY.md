# Phase 4: Concurrent HTTP Batches - Quick Summary

**Decision**: Skip Phase 2+3, implement Phase 4 (concurrent batches) instead

**Why**: Phase 2+3 have fundamental architectural flaws + won't achieve 3-5× without addressing sequential HTTP bottleneck

**Progress**:
- ✅ Coordinator + worker pool + rate limiter upgrades merged (feature-flagged via `max_concurrency`).
- ✅ Telemetry + tests (unit + `test/gsc_analytics/data_sources/gsc/concurrent_sync_integration_test.exs`) landed.
- ⏳ Docs/dashboards/rollout playbook (S05/S06) still pending.

---

## Key Changes

### 1. GenServer-Based Coordinator
**Replace**: Tail-recursive state machine in `query_paginator.ex`
**With**: `QueryCoordinator` GenServer for concurrency-safe state

**Benefits**:
- Atomic state updates
- Halt propagation across workers
- Shared counters for telemetry

### 2. Concurrent Batch Workers
**Replace**: Sequential `do_paginated_fetch` loop
**With**: Multiple Task.async workers fetching in parallel

**Benefits**:
- Start with 3 workers (safe-by-default), scale to 5 only after telemetry stays green
- Network latency hidden
- Independent worker failure handling

### 3. Rate Limit Integration
**Add**: Rate checking BEFORE HTTP call in batch worker
**Fix**: Current `fetch_query_batch/3` bypasses rate limiter

**Benefits**:
- No 429 errors
- Respects 1,200 QPM limit
- Backoff on rate limit

---

## Performance Expectations

**Current** (with Phase 1 config optimizations):
- Batch size: 50 requests/call
- Concurrency: 1 (sequential)
- Speedup: 2-3× vs original

**With Phase 4**:
- Batch size: 50 requests/call
- Concurrency: start at 3 workers (optional bump to 5 after validation)
- Speedup: ≥4× additional (stretch: 8×) → **~8-12× total vs original** once combined with Phase 1

**Conservative Math**:
- 3 workers = 3× parallelism → ~2.4× effective after overhead
- `2-3× (Phase 1)` × `≥2.4× (Phase 4 @3 workers)` ≈ **5-7× total** baseline
- Raising to 5 workers (post-validation) targets the 8-12× stretch goal

---

## Implementation Timeline

**Week 1-2**: Core architecture (QueryCoordinator, ConcurrentBatchWorker, telemetry hooks)
**Week 3**: Integration (RateLimiter, QueryPaginator refactor, integration tests)
**Week 4**: Staging backfill, production rollout, monitoring buffer

**Total**: 3-4 weeks (Week 4 is validation/rollout buffer)

---

## Risk Mitigation

**Start Conservative**:
- `max_concurrency: 3` (150 requests/batch = 12.5% of QPM limit)
- Monitor for 1 week
- Increase to 5 if stable

**Rollback Safety**:
- Set `max_concurrency: 1` → falls back to sequential
- No code changes needed
- Zero-downtime rollback

---

## Success Metrics

**Performance**:
- ✅ ≥4× speedup on 150-day backfill (stretch: 8×)
- ✅ Memory < 500MB per sync
- ✅ Zero rate limit violations

**Correctness**:
- ✅ Zero data corruption (spot check 100 URLs)
- ✅ Halt propagation < 5 seconds
- ✅ All integration tests passing

---

## Comparison: Phase 2+3 vs Phase 4

| Metric | Phase 2+3 | Phase 4 |
|--------|-----------|---------|
| **Speedup** | 1.7-2× (realistic) | ≥4× (stretch: 8×) |
| **Complexity** | High (persistent state, crash recovery) | High (same) |
| **Time** | 2-3 weeks | 3-4 weeks (includes validation) |
| **Correctness Risk** | High (data corruption, data loss) | Medium (well-tested pattern) |
| **Rollback** | Hard (architectural changes) | Easy (config flag) |
| **Bottleneck Addressed** | No (sequential HTTP remains) | Yes (dominant bottleneck) |

**Verdict**: Phase 4 is better ROI - same effort, bigger wins, easier rollback

---

## Next Steps

1. Review `PHASE4_IMPLEMENTATION_PLAN.md` for detailed architecture
2. Start with Task 1: Implement QueryCoordinator GenServer
3. Proceed through tasks 1-6 sequentially
4. Deploy to staging with `max_concurrency: 3`
5. Monitor for 1 week, increase to 5 if stable

---

## Files

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

---

## References

- Full plan: `PHASE4_IMPLEMENTATION_PLAN.md`
- Codex critical review: `codex-critical-review.md`
- Original (flawed) plan: `README.md`
