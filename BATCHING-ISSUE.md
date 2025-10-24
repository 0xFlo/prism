# Batching Implementation Issue & Redesign Proposal

## Status
**DONE**: Multi-date query scheduler replaced legacy batching
**Priority**: High (quota + latency impact)
**Created**: 2025-10-05
**Updated**: 2025-10-07

---

## Problem Statement

The batching strategy introduced in commit `5a39bbf` was intended to speed up query ingestion by fetching multiple 25k pages per HTTP batch. In practice it routinely fires requests for start rows that have no data, because Google Search Console only reveals the existence of the next page after we retrieve the previous one.

### Latest Findings
- After adding `batch: true` and `start_row` metadata to audit logs (`lib/gsc_analytics/gsc/client.ex`), `logs/gsc_audit.log` shows long tails of `{rows: 0}` entries for every day that crosses the 25k threshold.
- Example investigation command:
  ```bash
  jq 'select(.metadata.batch == true) | {date: .metadata.date, start_row: .metadata.start_row, rows: .measurements.rows}' logs/gsc_audit.log
  ```
  Typical output ends with several zero-row sub-requests for each date.
- For dates with ~75k queries we currently issue 9 sub-requests (0..200k). Only three of them contain data; six are wasted.

### Why This Happens
- GSC provides **no** `total_count`, `has_next_page`, or pagination hints.
- The only signal that more data exists is a full page (25k rows).
- Our implementation (`build_query_start_rows/2` in `lib/gsc_analytics/gsc/sync.ex`) speculatively requests up to eight future pages once the first page is full, so empties are inevitable.

---

## Current Flow (references)
- `lib/gsc_analytics/gsc/sync.ex:404-464` orchestrates the per-date query fetching.
- `lib/gsc_analytics/gsc/sync.ex:596-619` calls `build_query_start_rows/2`, which emits `[start_row + (0..7)*25_000]` after the first full page.
- `lib/gsc_analytics/gsc/client.ex:252-315` sends each of those start rows inside a single HTTP batch.

Result: second and later batches for a date almost always contain a majority of zero-row responses.

---

## Proposed Solution: Batch Across Dates, Not Pages

Batching should group **the next required page for multiple dates**, not speculative future pages for a single date. Each sub-request must be backed by evidence (the previous page was full).

### Multi-Date Cascading Pagination (concept)
```
┌─────────────────────────────────────────────────────────────┐
│ BATCH 1: Fetch page 0 for several dates                    │
└─────────────────────────────────────────────────────────────┘
  Responses classify each date as complete or needing more pages.

┌─────────────────────────────────────────────────────────────┐
│ BATCH 2: Fetch page 1 only for dates that filled page 0    │
└─────────────────────────────────────────────────────────────┘
  Any date returning <25k rows is marked complete and removed.

┌─────────────────────────────────────────────────────────────┐
│ BATCH 3+: Continue for the remaining dates as needed       │
└─────────────────────────────────────────────────────────────┘
```

### Benefits
- ✅ Zero speculative calls: every `(date, start_row)` is requested only after we know it exists.
- ✅ Reduced total HTTP batches: 30 dates with mixed volumes drop from ~40 batches to ~3.
- ✅ Better latency: dates with <25k queries finish in the very first batch.
- ✅ Simplified retry logic: we can retry individual `(date, start_row)` pairs without losing progress.

### Costs / Trade-offs
- ❌ Requires new state management for multi-date pagination.
- ❌ Needs careful memory handling so we do not buffer too many rows.
- ✅ Complexity is justified by quota savings and clearer scheduling.

---

## Implementation Plan

### Phase 1 – Introduce a Query Scheduler
Create `GscAnalytics.GSC.QueryScheduler` responsible for orchestrating query pagination across dates.
- Maintains a queue of `{date, start_row}` pairs.
- Seeds the queue with `{date, 0}` for each active date.
- Pops up to `@query_batch_pages` entries per HTTP batch.
- Enqueues `{date, start_row + 25_000}` **only** when the previous response contained 25k rows.
- Emits a map `%{date => [rows...]}` to keep the rest of the pipeline per-date.

### Phase 2 – Integrate with Sync Pipeline
- Allow `sync_date_range/4` to process a small chunk of dates (e.g. 8–14) at a time.
- After URL ingestion for the chunk succeeds, call `QueryScheduler.fetch_all_queries/4` to retrieve query rows for the chunk in one cascade.
- Feed each date’s rows back into `process_queries_response/4` so downstream storage code remains unchanged.
- Update `SyncProgress` so it still reports progress per individual date.

### Phase 3 – Retire the Single-Date Paginator
- Delete `fetch_all_query_pages/3` and associated helpers once the scheduler path is stable.
- Move reusable helpers (`normalize_batch_responses/1`, `log_batch_part/4`, etc.) into a shared module that both the scheduler and client can access.

### Phase 4 – Feature Flag and Instrumentation *(completed)*
- Scheduler now ships as the default path; configuration exposes `query_batch_pages` and
  `query_scheduler_chunk_size` for tuning.
- Telemetry/logging enhancements in `BatchTransport` continue to emit per-part metadata
  (`batch: true`, `start_row`).
- Monitor `logs/gsc_audit.log` for unexpected zero-row requests; existing guards remain in place.

### Phase 5 – Rollout & Cleanup *(completed)*
- Legacy paginator removed; scheduler is the only path in `Sync`.
- Remaining rollout tasks: monitor telemetry, tune chunk/batch sizes, and update operational docs.

---

## Post-MVP Fixes (2025-10-07)

We addressed the critical follow-ups identified during the audit:

### 1. Resilient batch transport (lib/gsc_analytics/gsc/client.ex)
- Added exponential backoff, rate-limit retrying, and token refresh handling to
  `fetch_search_analytics_batch/3` so transient 429/5xx/transport failures no longer abort the
  scheduler. All retries log succinct telemetry and respect the existing `@max_retries` window.
- Protected Agent lifecycle with try/after blocks to prevent memory leaks on exceptions

### 2. O(n) row accumulation (lib/gsc_analytics/gsc/query_scheduler.ex)
- Replaced repeated list appends with chunked storage so each page is consed once and flattened only
  when needed. The scheduler now supports an optional `on_complete` callback that streams rows as soon
  as a date finishes, clearing its in-memory buffer immediately.
- Added comprehensive test coverage for callback halt scenarios and exception handling
- Fixed unused variable warnings and unreachable clause issues

### 3. Streaming finalization (lib/gsc_analytics/gsc/sync.ex)
- Completely rewrote `finalize_pending_days/3` to ensure dates are processed in chronological order
  (newest first), fixing empty_streak calculation bugs that caused incorrect halt behavior
- Implemented `process_entries_in_order/3` that maintains order regardless of whether dates have queries
- Enhanced callback mechanism to track `remaining_dates` and process only when date is next in sequence
- Fixed halt_reason propagation so intentional halts (empty threshold) preserve correct reason
- Failures still fall back to the previous error path for reliable recovery

### 4. Test Coverage & Validation
- All 18 tests passing, including new tests for callback halt and exception handling
- Fixed two critical bugs uncovered by existing backfill tests:
  - Date ordering: `Enum.split_with` was breaking chronological order, causing process_without_queries
    to run before process_with_queries
  - Halt reason: Scheduler halt was calling `handle_scheduler_failure` even for intentional halts,
    overwriting the correct `halt_reason`

---

## Acceptance Criteria
1. Scheduler never issues a `(date, start_row)` request unless the previous page for that date returned 25,000 rows (verified via telemetry and tests).
2. New tests cover mixed volumes, rate-limit retries, and partial batch failures (`test/gsc_analytics/gsc/query_scheduler_test.exs` or similar).
3. Audit logs (`logs/gsc_audit.log`) show `batch: true` entries with `rows > 0` for all sub-requests when the scheduler is enabled.
4. Feature flag allows immediate rollback to the legacy path.
5. SyncProgress UI remains per-day and chronological despite the internal batching.

---

## Risks & Mitigations
- **Batch size too large** → Timeouts or memory pressure.
  - Mitigation: make batch size configurable; default to 8; monitor telemetry.
- **Rate limiting** → Larger cascades might hit API quotas.
  - Mitigation: keep `RateLimiter.check_rate/1` for every enqueued sub-request; back off progressively on rate-limit responses.
- **Error propagation** → One bad date must not poison the entire batch.
  - Mitigation: carry per-date error state, continue processing the rest, surface failures via SyncProgress and summary logs.
- **Telemetry noise** → Need clear insight into scheduler efficiency.
  - Mitigation: add explicit counters for pages enqueued, pages completed, zero-row responses, and retry counts.

---

## Deployment Playbook *(completed)*
1. Scheduler merged and enabled by default.
2. Legacy paginator removed; rollback requires reverting the commit.
3. Remaining action: monitor telemetry/quota usage and adjust `query_batch_pages` / `query_scheduler_chunk_size` as needed.

---

## Open Questions
1. **Optimal batch size** – start with 8? 16? decide after telemetry.
2. **Concurrent URL batching** – worth extending the scheduler to URLs? (Recommendation: no, minimal gain.)
3. **Rate limiter semantics** – do we need to adjust tokens per batch? (Likely no; keep per-sub-request checks.)
4. **Audit log shape** – should we add a `batch_id` so we can correlate grouped sub-requests easily? (Recommendation: yes.)

---

## References
- Current implementation: `lib/gsc_analytics/gsc/client.ex:252-315`, `lib/gsc_analytics/gsc/sync.ex:404-619`
- Audit logging: `lib/gsc_analytics/gsc/audit_logger.ex`
- Google batch API docs: https://developers.google.com/webmaster-tools/v1/how-tos/batch
- Original batching commit: `5a39bbf`

---

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2025-10-05 | Issue identified | Current batching wastes API calls on empty pages |
| 2025-10-06 | Query scheduler enabled by default; legacy path removed | Multi-date batching integrated into `sync_date_range/4`; old paginator retired |
| 2025-10-07 | Dashboard metrics upgraded | Sync dashboard now surfaces query rows, batches, and API counts |
| 2025-10-07 | Batch resiliency + streaming | Added batch retries, O(n) accumulation, and streaming finalization |
| 2025-10-07 | Critical bug fixes for streaming | Fixed date ordering and halt_reason propagation; all tests passing |
| TBD | Set initial batch size | Pending telemetry review |
