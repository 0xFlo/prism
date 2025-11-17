# Ticket-002: Progress & Failure UX

## Status: TODO
**Priority:** P1
**Estimate:** 3 pts
**Dependencies:** ticket-001
**Blocks:** ticket-008

## Problem Statement
Bulk SERP checks will take up to a couple of minutes and can fail when ScrapFly times out. Analysts need an in-product experience that shows real-time progress, handles retries/timeouts gracefully, and persists the last successful run metadata so they know when to expect fresh data.

## Goals
- Provide a modal-based progress UI with PubSub updates and ETA messaging
- Surface explicit states for retries, partial failures, and overall timeout
- Store the last-run timestamp/keyword count/cost so the dashboard can surface it on reload
- Offer a CTA to the new SERP Landscape page once all jobs finish (or a warning if partial)

## Acceptance Criteria
- [ ] `DashboardUrlLive` subscribes to PubSub topics per URL and updates assigns as job updates arrive
- [ ] Progress modal shows `X / Y complete`, queued/failed counts, ETA, and cost info
- [ ] Timeout (>2 minutes) triggers a "Still running" state with instructions and the ability to leave the modal
- [ ] Partial failures display retry info and include a "Retry failed keywords" action
- [ ] Last-run metadata persists (e.g., ETS/cache or DB table) and renders on page load even after refresh

## Implementation Plan
1. **PubSub Wiring**
   - Subscribe to `"serp_check:#{account_id}:#{url}"` topic on mount; define `%{status: :started|:progress|:failed|:complete}` payload contract.
2. **Modal Component**
   - Build a reusable modal with progress bar, log stream, and action footer; disable the trigger button while `@checks_in_progress`.
3. **Timeout Handling**
   - Use `Process.send_after/3` or `:timer` to set a 2-minute guard; when it fires, update assigns to show the fallback message unless all jobs finished.
4. **Retry Flow**
   - Track failed keywords client-side; allow re-triggering only the failed subset via new event.
5. **Persistence**
   - Store `last_run_at`, `keyword_count`, `estimated_cost`, and `status` (success/partial/fail) in a metadata table or a JSON column.
   - Display this info in the dashboard header + tooltips.
6. **Tests**
   - LiveView tests for modal states, PubSub messages, and timeout transitions; verify metadata persists.

## Deliverables
- LiveView modal + state machine handling progress/failure
- PubSub payload contract + helper module
- Persistence for last-run metadata with tests
- Updated documentation capturing UX states and troubleshooting steps
