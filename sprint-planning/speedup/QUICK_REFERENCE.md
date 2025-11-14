# GSC Sync Speedup - Quick Reference

## TL;DR

- **Goal**: ≥4× faster end-to-end sync (stretch: 8×) by removing the sequential HTTP bottleneck; cumulative gain with Phase 1 lands at ~8-12× vs original.
- **Strategy**: Skip risky Phase 2+3. Ship **Phase 4** (GenServer coordinator + concurrent HTTP batches + strict rate limiting/backpressure).
- **Status**: Phase 1 done. Phase 4 architecture refined per Codex review and ready to implement. Target duration **3-4 weeks** including staging burn-in.
- **Rollout Guardrails**: Start with `max_concurrency: 3`, raise to 5 only after telemetry stays <80% of quota for 1 week. Rollback by setting `max_concurrency: 1`.

---

## Performance Roadmap

| Phase | Changes | Expected Speedup | Status |
|-------|---------|------------------|--------|
| **Phase 1** | Config tuning, UPSERT writes | 2-3× | ✅ Shipped |
| **Phase 4** | QueryCoordinator + concurrent workers + rate limiting + telemetry | ≥4× (stretch 8×) | 🚧 This sprint |
| **Phase 2/3** | Streaming persistence + deferred refresh | 1.7-2× (but unsafe) | ❌ Cancelled (see `codex-critical-review.md`) |

---

## Architecture Pillars (Phase 4)

1. **QueryCoordinator (GenServer)**
   - Manages pagination queue (`max_queue_size: 1000`) and tracks `max_in_flight: 10` persistence hand-offs.
   - Deduplicates batches via `{date, start_row}` keys and keeps ETS-backed in-flight registry for crash recovery.
   - Exposes `take_batch/2`, `submit_results/2`, `requeue_batch/2`, and `halt/2` APIs so workers can safely retry or stop.

2. **Concurrent Batch Workers**
   - `max_concurrency` configurable; default **3**, optional bump to 5 post-validation.
   - Each worker loop: `take_batch → RateLimiter.check_rate(count) → Client.fetch_query_batch → submit_results`.
   - On rate-limit or transient failure, workers **return the batch to the coordinator before sleeping/retrying** to avoid data loss.
   - Workers honor halt flags before/after HTTP calls and emit telemetry (`batch_latency`, `retries`, `worker_id`).

3. **Rate Limiting + Telemetry**
   - Budget formula: `max_concurrency × batch_size × 60 / avg_batch_duration_sec ≤ 1,200 QPM`.
   - Track actual QPM: `(batches_completed × batch_size) / elapsed_minutes` and alert at 80% (960 QPM).
   - Telemetry requirements: QPM, coordinator mailbox depth, `max_in_flight`, worker crashes, halt propagation time, rate-limit backoff counts.

---

## Implementation Checklist

### Week 1-2 — Core Architecture ✅
- `QueryCoordinator`, `ConcurrentBatchWorker`, and the refactored `QueryPaginator` are merged under the `max_concurrency` guard with sequential fallback.
- Rate limiter + config knobs now default to `max_concurrency: 3`, `max_queue_size: 1000`, `max_in_flight: 10`.
- Telemetry emits coordinator queue depth/in-flight counts and worker batch timings.

### Week 2-3 — Integration & Testing 🟡
- New suites cover coordinator behavior, worker loops, and rate limiter batches plus `test/gsc_analytics/data_sources/gsc/concurrent_sync_integration_test.exs` for the concurrent path.
- Remaining: dashboards, staging checklist, halt timing validation (<5s), and documentation for the telemetry surface.

### Week 4 — Validation & Rollout
- Stage 150-day backfill with `max_concurrency: 3`, capture QPM + mailbox dashboards.
- Run reconciliation job to ensure zero duplicate/missing `{date, start_row}` batches.
- Production rollout checklist: config switch for `max_concurrency`, real-time Slack alerts, rollback drill.

---

## Sprint Tickets

- Full breakdown: `sprint-planning/speedup/TICKETS.md`
- Quick map:
  1. **S01** – QueryCoordinator GenServer
  2. **S02** – ConcurrentBatchWorker + supervision
  3. **S03** – Rate limiter + config defaults
  4. **S04** – QueryPaginator refactor / config switch
  5. **S05** – Telemetry + tests (unit/integration)
  6. **S06** – Validation + rollout playbook

Current focus: finish S05 telemetry docs/dashboards; S06 (rollout playbook) stays blocked until S05 closes.

---

## Success Metrics & Alerts

- Performance: ≥4× faster 150-day backfill (stretch 8×), memory <500 MB per sync, batch latency p99 <5 s.
- Reliability: Zero data corruption (spot-check 100 URLs), worker uptime >99%, halt propagation <5 s.
- Rate limiting: Actual QPM <960 (80%), zero 429 bursts, rate-check overhead <10 ms/batch.
- Backpressure: Coordinator mailbox <500 (warn) / <800 (auto throttle), `max_in_flight` ≤10.
- Telemetry taps: `[:gsc_analytics, :coordinator, :queue_size|:in_flight]`, `[:gsc_analytics, :worker, :batch]`, `[:gsc_analytics, :rate_limit, :usage|:approaching|:exceeded]`.

---

## Risk & Rollback Cheatsheet

| Risk | Mitigation | Rollback Trigger |
|------|------------|------------------|
| Rate-limit violations | Start at `max_concurrency: 3`, exponential backoff, auto-throttle when QPM ≥80% | Immediate drop to 1, investigate telemetry |
| Worker crashes / duplicate inserts | Supervisor restarts + `{date, start_row}` dedup + reconciliation job | If duplicates detected, pause sync, replay via ETS backlog |
| Halt propagation failure | Workers check flag before/after HTTP, coordinator flip measured via telemetry | If halt >5 s, set concurrency=1 and capture traces |

Rollback hierarchy:
1. **Config flip**: `max_concurrency: 1` (sequential).
2. **Partial**: Keep concurrency but lower to 2-3 and/or shrink batch size.
3. **Full**: Revert Phase 4 deploy (pre-change commit).

---

## References & Commands

- Plan docs: `README.md`, `PHASE4_IMPLEMENTATION_PLAN.md`, `PHASE4_SUMMARY.md`, `CODEX_FINAL_REVIEW.md`.
- Rollout playbook: `PHASE4_ROLLOUT_PLAYBOOK.md`.
- Critical context: `codex-bottleneck-analysis.md`, `codex-critical-review.md`.
- Key modules: `lib/gsc_analytics/data_sources/gsc/support/{query_coordinator,concurrent_batch_worker,query_paginator,rate_limiter}.ex`.
- Tests to add/run: `test/gsc_analytics/data_sources/gsc/support/*`, `test/gsc_analytics/data_sources/gsc/concurrent_sync_integration_test.exs`.

Common commands:

```bash
mix test                                  # Run suite
mix precommit                             # Warnings-as-errors + format + tests
iex -S mix phx.server                     # Interactive dev server
GscAnalytics.DataSources.GSC.Core.Sync.sync_yesterday()
GscAnalytics.DataSources.GSC.Core.Sync.sync_full_history("sc-domain:example.com")
```
