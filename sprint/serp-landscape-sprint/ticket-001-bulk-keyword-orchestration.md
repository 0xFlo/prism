# Ticket-001: Bulk Keyword Orchestration

## Status: TODO
**Priority:** P1
**Estimate:** 5 pts
**Dependencies:** None
**Blocks:** ticket-002

## Problem Statement
We currently trigger a single SERP check from the URL dashboard. Analysts need a way to automatically select the top-performing Search Console queries for the active scope and enqueue a controlled batch of SERP checks without violating ScrapFly rate limits or losing track of cost.

## Goals
- Pull the top N (5–10) GSC queries for the URL within the authenticated `current_scope`
- Estimate ScrapFly credits before scheduling checks and log that projection for auditing
- Fan-out one Oban job per keyword with retries, idempotency keys, and per-scope throttling
- Emit telemetry so we can monitor queue depth, in-flight checks, and credit consumption

## Acceptance Criteria
- [ ] `ContentInsights.top_queries/3` returns deduped keywords filtered by property/url, geo, and per-account caps
- [ ] `DashboardUrlLive` computes credit estimates, disables the CTA while jobs are scheduled, and logs telemetry events
- [ ] One Oban job per keyword is enqueued with tenant-specific idempotency keys and retry/backoff logic
- [ ] Per-scope throttling prevents more than X concurrent jobs; additional requests queue until capacity frees up
- [ ] Telemetry events (`:serp_bulk_check`, `:serp_job_enqueued`) capture account, keyword count, and cost projections

## Implementation Plan
1. **Top Query Helper**
   - Add `ContentInsights.top_queries(current_scope, target_url, opts)` returning keyword structs with CTR, clicks, country, etc.
   - Respect account-level caps (config), dedupe keywords, and ensure geo filter matches ScrapFly locale.
2. **Dashboard Event Handler**
   - Add `handle_event("check_top_keywords", _, socket)` that loads keywords, computes credit estimate (keywords × 36), and records telemetry before scheduling.
   - Persist last-run metadata into the socket assigns + optionally `serp_snapshots_meta` table for persistence.
3. **Oban Fan-out**
   - Build helper to enqueue `SerpCheckWorker.new/1` per keyword with args: account id, property url, target url, keyword, geo, request uuid.
   - Use Oban unique settings keyed by `account_id + target_url + keyword` for a short window; apply rate limit plugin if available.
4. **Telemetry Hooks**
   - Instrument the event handler and job creation with `:telemetry.span/3`; include cost estimate, keyword count, and actor info.
5. **Config + Tests**
   - Add configuration for default keyword cap (per scope) and throttle numbers.
   - Unit tests for `top_queries/3`, event handler credit estimation, and job args; integration test verifying jobs enqueue with uniq keys.

## Deliverables
- Updated context (`ContentInsights.top_queries/3`) with tests
- Dashboard event handler + telemetry instrumentation
- Oban enqueue helper respecting throttles and idempotency
- Documentation snippet in RFC/README summarizing the workflow
