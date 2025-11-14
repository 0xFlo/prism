# Phase 4 Sprint Tickets

| Ticket | Status | Scope | Key Deliverables | Dependencies |
|--------|--------|-------|------------------|--------------|
| **S01** | ✅ Complete | QueryCoordinator GenServer with queue/backpressure + ETS tracking | Coordinator module, unit tests, config knobs | None |
| **S02** | ✅ Complete | ConcurrentBatchWorker supervision + rate-limit aware worker loop | Worker module, supervision tree, worker telemetry | S01 |
| **S03** | ✅ Complete | RateLimiter + config plumbing + rollout switches | `RateLimiter.check_rate/3` update, config defaults (`max_concurrency`, queue limits), docs | S01, S02 inputs |
| **S04** | ✅ Complete | QueryPaginator refactor to orchestrate coordinator/workers | Updated paginator + persistence callbacks + config switch (`max_concurrency: 1` fallback) | S01–S03 |
| **S05** | ✅ Complete | Telemetry + tests (unit + integration) | QPM/queue/latency metrics, integration tests covering halt/backpressure/retry | S01–S04 |
| **S06** | ⏳ In Progress | Staging validation + rollout playbook execution | 150-day backfill checklist, telemetry dashboard links, rollback drill steps + captured metrics | S01–S05 |

---

## Ticket S01 — QueryCoordinator GenServer
- **Goal**: Replace the recursive paginator accumulator with a concurrency-safe GenServer that manages `{date, start_row}` jobs, enforces queue limits, and tracks in-flight batches for crash recovery.
- **Deliverables**:
  - `lib/gsc_analytics/data_sources/gsc/support/query_coordinator.ex`
  - Configurable options: `max_queue_size`, `max_in_flight`, `batch_size`.
  - ETS-backed in-flight registry; APIs `take_batch/2`, `submit_results/2`, `requeue_batch/2`, `halt/2`, `finalize/1`.
  - Unit tests covering queue drain, dedup, halt propagation, requeue path.
- **Acceptance Criteria**:
  - Coordinator never exceeds configured queue/in-flight limits.
  - Crash recovery scenario described (ETS entries rehydrated).
  - Documentation updated (`README.md`, `PHASE4_IMPLEMENTATION_PLAN.md` references S01).

## Ticket S02 — ConcurrentBatchWorker
- **Goal**: Introduce Task-supervised workers that fetch batches in parallel, respect backpressure, and re-enqueue work when rate-limited or failing transiently.
- **Deliverables**:
  - `lib/gsc_analytics/data_sources/gsc/support/concurrent_batch_worker.ex`
  - Worker supervision strategy (Task.Supervisor or DynamicSupervisor) plus tests/mocks.
  - Logging/telemetry for worker lifecycle, retries, halt propagation.
- **Acceptance Criteria**:
  - Workers honor `{:backpressure, reason}` responses and pause before retrying.
  - On rate-limit error, batches are requeued before sleeping.
  - Failures propagate halt signal and bubble up meaningful errors.

## Ticket S03 — Rate Limiting & Config
- **Goal**: Ensure every batch obeys the 1,200 QPM cap and provide configuration defaults/overrides for concurrency rollout.
- **Deliverables**:
  - `RateLimiter.check_rate/3` supporting `request_count`.
  - Config defaults (`max_concurrency: 3`, `batch_size: 50`, queue limits) plus dev/prod overrides.
  - Rollout instructions + telemetry thresholds (80% quota alert).
- **Acceptance Criteria**:
  - Workers always call rate limiter before HTTP calls.
  - Config documented in `README.md`, `PHASE4_IMPLEMENTATION_PLAN.md`, `QUICK_REFERENCE.md`.
  - Ability to drop to sequential mode by setting `max_concurrency: 1`.

## Ticket S04 — QueryPaginator Integration
- **Goal**: Wire the coordinator/workers into the existing paginator entry points without regressing current sync behavior.
- **Deliverables**:
  - Refactored `query_paginator.ex` to start coordinator, spawn workers, and stream results to persistence callbacks.
  - Config switch via `max_concurrency` (1 == legacy sequential path).
  - Documentation on how callbacks/on_complete hooks execute in the new model.
- **Acceptance Criteria**:
  - Sequential mode (concurrency 1) matches old behavior bit-for-bit in tests.
  - Concurrency path feeds persistence in FIFO order and enforces idempotent inserts.
  - Pipeline handles halt/error propagation across all workers.

## Ticket S05 — Telemetry & Test Coverage
- **Goal**: Instrument the new pipeline and add regression tests for backpressure, rate limiting, and crash recovery.
- **Deliverables**:
  - Telemetry events/metrics: QPM, mailbox depth, in-flight counts, batch latencies, worker retries/crashes, halt duration.
  - Unit tests for rate-limit backoff, worker halt, coordinator queue overflow, ETS requeue.
  - Integration test `test/gsc_analytics/data_sources/gsc/concurrent_sync_integration_test.exs`.
  - Documentation snippet in `PHASE4_ROLLOUT_PLAYBOOK.md` (Section 1) describing where to consume the metrics.
- **Acceptance Criteria**:
  - Dashboards/alert thresholds defined (even if mock links for now).
  - CI suite exercises concurrent path (with deterministic seeds/mocks).
  - Telemetry docs explain how to monitor <80% quota condition.

## Ticket S06 — Validation & Rollout Playbook
- **Goal**: Provide a concrete plan to validate ≥4× speedup and safely raise concurrency in staging/production.
- **Deliverables**:
  - 150-day backfill script/checklist (inputs, expected telemetry).
  - Rollout steps: staging soak, gating criteria for `max_concurrency: 5`, rollback drill instructions.
  - Success metrics template (QPM, batch latency, memory, data integrity checks).
  - Rollout playbook documented in `PHASE4_ROLLOUT_PLAYBOOK.md`.
- **Acceptance Criteria**:
  - Documented path to prove ≥4× speedup baseline and stretch goal.
  - Clear on-call guidance for throttling/rollback.
  - Links back to telemetry/alert config from S05.
