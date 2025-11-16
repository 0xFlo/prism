# Phase 4 Rollout & Validation Playbook

**Status**: READY — instrumentation + tests merged (S05), documentation + rollout drill defined (S06).

**Audience**: GSC sync owners, on-call engineers, and anyone coordinating the Phase 4 staged rollout.

---

## 1. Telemetry Surface (S05)

| Event | Measurements | Metadata | Source |
|-------|--------------|----------|--------|
| `[:gsc_analytics, :coordinator, :queue_size]` | `size` (batches enqueued) | `account_id`, `site_url` | `QueryCoordinator` |
| `[:gsc_analytics, :coordinator, :in_flight]` | `count` (awaiting persistence) | `account_id`, `site_url` | `QueryCoordinator` |
| `[:gsc_analytics, :worker, :batch]` | `duration_ms`, `batch_size` | `worker_id`, `account_id`, `site_url`, `status` | `ConcurrentBatchWorker` |
| `[:gsc_analytics, :rate_limit, :usage]` | `count` (current minute total) | `account_id`, `site_url` | `RateLimiter` |
| `[:gsc_analytics, :rate_limit, :approaching]` | `count` (increment) | `account_id`, `site_url`, `limit` | `RateLimiter` |
| `[:gsc_analytics, :rate_limit, :exceeded]` | `count`, `retry_ms` | `account_id`, `site_url` | `RateLimiter` |

Metrics are exposed in `lib/gsc_analytics_web/telemetry.ex` so they land in whichever reporter is configured (Grafana/Loki/Console).

### Dashboard Cards (add in Grafana or equivalent)

| Panel | Query | Thresholds |
|-------|-------|------------|
| **Queue Depth** | `last_value(gsc_analytics.coordinator.queue_size)` | Warn ≥500, Page ≥800 |
| **In-Flight Batches** | `last_value(gsc_analytics.coordinator.in_flight)` | Warn ≥8, Page ≥10 |
| **Worker Batch Duration** | `summary(gsc_analytics.worker.batch.duration)` (p50/p95/p99) | Page p99 ≥5000 ms |
| **QPM vs Budget** | `rate_limit.usage` counter × `batch_size` ÷ minutes | Warn ≥960; Page ≥1100 |
| **Rate Limit Events** | Counters for `approaching` / `exceeded` | Alert on any `exceeded` |

---

## 2. 150-Day Staging Backfill Checklist (S06)

1. **Pre-flight**
   - Ensure `max_concurrency: 1` in staging; migrate DB to latest.
   - Seed telemetry dashboards; confirm reporters running.
   - Run `mix test` (already green) and smoke `Sync.sync_yesterday/0`.
   - For automation, run `mix phase4.rollout --site-url "sc-domain:rula.com" --account-id 4 --days 150 --concurrency 3 --queue-size 1000 --in-flight 10` (adjust identifiers). The task disables auto-sync, forces reprocessing (even if data already synced), and emits `output/phase4_rollout_<timestamp>.md` ready for copy/paste. Pass `--keep-auto-sync` only if you explicitly want background jobs running.
2. **Warm-up (Sequential Baseline)**
   - Capture QPM, queue depth (should be near zero), memory footprint.
   - Snapshot baseline duration for 150-day range.
3. **Enable Concurrent Mode**
   - Update staging runtime config: `max_concurrency: 3`, `max_queue_size: 1000`, `max_in_flight: 10`.
   - Kick off `GscAnalytics.DataSources.GSC.Core.Sync.sync_date_range/4` covering 150 days.
4. **Monitor During Run**
   - Queue depth <500, in-flight <10, worker p99 <5 s, rate-limit usage <80% (no `:exceeded`).
   - Capture `:approaching` count; should be ≤1 per hour.
5. **Post-Run Validation**
   - Compare row counts per day vs sequential baseline (±0% tolerance).
   - Verify ETS requeue table empty (`:ets.tab2list(QueryCoordinator)` from console).
   - Log findings + metrics screenshot in sprint doc.

Escalate immediately if: QPM ≥1,000 for >1 minute, queue depth >800, or halt propagation >5 s.

---

## 3. Production Rollout Steps

| Phase | Config | Duration | Exit Criteria |
|-------|--------|----------|----------------|
| **Phase A** | `max_concurrency: 1` (observe) | 24 h | No regressions vs baseline |
| **Phase B** | `max_concurrency: 3` | 1 week | QPM <960, no alerts, queue depth avg <200 |
| **Phase C** | `max_concurrency: 5` (optional) | 1 week | Same metrics + positive product sign-off |

### Operational Steps
1. Update runtime config via `runtime.exs` env or feature matrix (no deploy required).
2. Announce in #gsc-sync with metrics link + escalation contact.
3. Log start/stop timestamps and key telemetry snapshots in `PHASE4_ROLLOUT_PLAYBOOK.md` (append at bottom).

---

## 4. Rollback & Drill

| Scenario | Action | Time Budget |
|----------|--------|-------------|
| Rate limit spike | Set `max_concurrency: 1`, wait 5 min, inspect `usage` events | <2 min |
| Persistence backlog | Drop `max_in_flight` to 5, then `max_concurrency: 2` | <5 min |
| Coordinator fault | Stop sync job, flush ETS via `:ets.delete_all_objects/1`, restart job sequentially | <10 min |

**Drill cadence**: run the “rate limit spike” drill weekly until Phase 4 sits in prod for 30 days; afterwards monthly.

---

## 5. Success Metrics Template

| Metric | Target | Observed (fill in) |
|--------|--------|--------------------|
| Overall speedup | ≥4× (stretch 8×) | |
| Worker p99 latency | <5 s | |
| Coordinator queue depth | <500 steady / <800 peak | |
| Memory footprint | <500 MB per sync | |
| QPM (avg / peak) | <960 / <1,100 | |
| Data integrity | 0 missing/duplicate `{date, start_row}` | |

Fill this table per environment (staging, prod). Paste telemetry links or screenshots alongside.

---

## 6. References

- Code: `lib/gsc_analytics/data_sources/gsc/support/{query_coordinator,concurrent_batch_worker,query_paginator,rate_limiter}.ex`
- Tests: `test/gsc_analytics/data_sources/gsc/support/*`, `test/gsc_analytics/data_sources/gsc/concurrent_sync_integration_test.exs`
- Docs: `README.md`, `PHASE4_IMPLEMENTATION_PLAN.md`, `PHASE4_SUMMARY.md`, `QUICK_REFERENCE.md`

Owner: Engineering (GSC Sync). Update this playbook whenever telemetry or rollout levers change.
