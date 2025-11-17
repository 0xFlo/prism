# ScrapFly SERP Integration Sprint Board

**Sprint Goal:** Integrate ScrapFly API for real-time SERP position checking in GSC Analytics dashboard

**Last Updated:** 2025-01-09

---

## Sprint Summary

| Metric | Value |
|--------|-------|
| **Total Story Points** | 23 |
| **Completed Points** | 0 |
| **Remaining Points** | 23 |
| **Progress** | 0% |
| **Sprint Status** | 🔵 Not Started |

---

## Backlog (14 tickets)

### 🔥 P1 Critical Path

| ID | Ticket | Points | Status | TDD | Notes |
|----|--------|--------|--------|-----|-------|
| T001 | Create SERP Directory Structure | 1 | 🔵 Not Started | No | Foundation for all modules |
| T002 | ScrapFly Config & Env Setup | 1 | 🔵 Not Started | No | Requires T001 |
| T003 | SerpSnapshot Ecto Schema | 2 | 🔵 Not Started | No | Requires T002 |
| T004 | Database Migration | 2 | 🔵 Not Started | No | Requires T003 |
| T005 | Req HTTP Client (TDD) | 3 | 🔵 Not Started | ✅ Yes | Requires T004 |
| T006 | JSON Parser (TDD) | 2 | 🔵 Not Started | ✅ Yes | Requires T005 |
| T007 | Persistence Layer | 2 | 🔵 Not Started | No | Requires T006 |
| T008 | Rate Limiter (TDD) | 2 | 🔵 Not Started | ✅ Yes | Requires T007 |
| T009 | Oban SERP Worker (TDD) | 3 | 🔵 Not Started | ✅ Yes | Requires T008 |
| T010 | Integration Tests (TDD) | 2 | 🔵 Not Started | ✅ Yes | Requires T009 |
| T013 | Data Pruning Worker | 2 | 🔵 Not Started | No | Requires T007 |

**Critical Path Total:** 22 points

### 🟡 P2 Medium Priority

| ID | Ticket | Points | Status | TDD | Notes |
|----|--------|--------|--------|-----|-------|
| T011 | Dashboard LiveView Integration | 1 | 🔵 Not Started | No | Requires T010 |
| T012 | SERP Visualization | 1 | 🔵 Not Started | No | Requires T011 |
| T014 | Manual Verification | 1 | 🔵 Not Started | No | Requires T013 |

**Medium Priority Total:** 3 points

---

## Daily Progress Tracking

### Day 1: ____________

**Planned:**
- [ ] T001: Create SERP Directory Structure
- [ ] T002: ScrapFly Config & Env Setup
- [ ] T003: SerpSnapshot Ecto Schema
- [ ] T004: Database Migration

**Completed:**
-

**Blockers:**
-

**Notes:**
-

---

### Day 2: ____________

**Planned:**
- [ ] T005: Req HTTP Client (TDD)
  - [ ] RED: Write failing tests for ScrapFly API calls
  - [ ] GREEN: Implement minimum Req client
  - [ ] REFACTOR: Extract helpers, add retry logic
- [ ] T006: JSON Parser (TDD)
  - [ ] RED: Write failing tests for position extraction
  - [ ] GREEN: Implement JSON parser
  - [ ] REFACTOR: Clean up parsing logic

**Completed:**
-

**Blockers:**
-

**Notes:**
-

---

### Day 3: ____________

**Planned:**
- [ ] T007: Persistence Layer
- [ ] T008: Rate Limiter (TDD)
  - [ ] RED: Write failing rate limiter tests
  - [ ] GREEN: Implement quota tracking
  - [ ] REFACTOR: Extract configuration
- [ ] T009: Oban SERP Worker (TDD)
  - [ ] RED: Write failing worker tests
  - [ ] GREEN: Implement worker with idempotency
  - [ ] REFACTOR: Extract job helpers
- [ ] T010: Integration Tests (TDD)
  - [ ] RED: Write failing end-to-end tests
  - [ ] GREEN: Verify components work together
  - [ ] REFACTOR: Extract test helpers

**Completed:**
-

**Blockers:**
-

**Notes:**
-

---

### Day 4: ____________

**Planned:**
- [ ] T011: Dashboard LiveView Integration
- [ ] T012: SERP Visualization
- [ ] T013: Data Pruning Worker
- [ ] T014: Manual Verification
  - [ ] Test ScrapFly API with real queries
  - [ ] Verify position accuracy
  - [ ] Check cost tracking
  - [ ] Validate pruning logic

**Completed:**
-

**Blockers:**
-

**Notes:**
-

---

## Ticket Details Quick Reference

### Current Ticket: (Update as you progress)

**Ticket:** _______________
**Status:** _______________
**Started:** _______________
**TDD Phase:** [ ] RED [ ] GREEN [ ] REFACTOR

**Current Task:**
-

**Next Steps:**
1.
2.
3.

---

## TDD Tickets Tracker

| Ticket | RED Tests | GREEN Code | REFACTOR | Status |
|--------|-----------|------------|----------|--------|
| T005: Req HTTP Client | ☐ | ☐ | ☐ | 🔵 Not Started |
| T006: JSON Parser | ☐ | ☐ | ☐ | 🔵 Not Started |
| T008: Rate Limiter | ☐ | ☐ | ☐ | 🔵 Not Started |
| T009: Oban SERP Worker | ☐ | ☐ | ☐ | 🔵 Not Started |
| T010: Integration Tests | ☐ | ☐ | ☐ | 🔵 Not Started |

**TDD Best Practices:**
- ✅ Write tests FIRST (RED phase)
- ✅ Run tests and confirm they FAIL
- ✅ Write minimum code to pass (GREEN phase)
- ✅ Run tests and confirm they PASS
- ✅ Refactor while keeping tests passing (REFACTOR phase)
- ✅ Never skip phases

---

## Dependency Graph

```
T001 (Directory Structure)
  ↓
T002 (ScrapFly Config)
  ↓
T003 (Ecto Schema)
  ↓
T004 (Migration)
  ↓
T005 (Req Client - TDD)
  ↓
T006 (JSON Parser - TDD)
  ↓
T007 (Persistence Layer) ────┐
  ↓                          ↓
T008 (Rate Limiter - TDD)  T013 (Pruning Worker)
  ↓
T009 (Oban Worker - TDD)
  ↓
T010 (Integration Tests - TDD)
  ↓
T011 (Dashboard Integration)
  ↓
T012 (SERP Visualization)
  ↓
T014 (Manual Verification)
```

---

## Testing Progress

### Automated Tests

| Test Suite | Tests | Passing | Coverage | Status |
|------------|-------|---------|----------|--------|
| Client Tests | 0 | 0 | 0% | ⚪ Not Started |
| Parser Tests | 0 | 0 | 0% | ⚪ Not Started |
| Persistence Tests | 0 | 0 | 0% | ⚪ Not Started |
| Rate Limiter Tests | 0 | 0 | 0% | ⚪ Not Started |
| Worker Tests | 0 | 0 | 0% | ⚪ Not Started |
| Integration Tests | 0 | 0 | 0% | ⚪ Not Started |

**Target:** 95%+ coverage for SERP module code

### Manual Tests

- [ ] ScrapFly API connectivity
- [ ] JSON response parsing
- [ ] Position extraction accuracy
- [ ] Rate limiting enforcement
- [ ] Oban job idempotency
- [ ] LiveView auth enforcement
- [ ] Property-level data filtering
- [ ] 7-day data pruning
- [ ] Cost tracking accuracy
- [ ] Error handling (API failures, quota exceeded)

---

## Blockers & Risks

### Current Blockers
- None (sprint not started)

### Identified Risks
1. **ScrapFly API Changes** - Mitigation: Store raw JSON, version parser logic
2. **Rate Limit Exhaustion** - Mitigation: Implement rate limiter, cost tracking
3. **Parsing Fragility** - Mitigation: Use structured JSON API (not HTML/markdown)
4. **Concurrent Worker Duplicates** - Mitigation: Oban unique_periods with dedupe keys

---

## Success Metrics

### Must Have (Sprint Complete)
- [ ] All P1 tickets completed (22 points)
- [ ] All automated tests passing
- [ ] mix precommit passes
- [ ] ScrapFly API integration working
- [ ] SERP position extraction accurate
- [ ] Oban worker processes jobs async with idempotency
- [ ] Rate limiter prevents quota exhaustion
- [ ] LiveView button triggers SERP checks (with auth)
- [ ] Documentation complete and accurate

### Nice to Have
- [ ] All P2 tickets completed (3 points)
- [ ] SERP position trend visualization
- [ ] Competitor analysis view
- [ ] Real-time progress updates via PubSub
- [ ] >95% test coverage

---

## Architecture Review Compliance

**Codex Feedback Applied:**

| Issue | Original Plan | Fixed Plan | Status |
|-------|--------------|------------|---------|
| HTTP Client | `:httpc` | Req | ✅ Fixed |
| Response Format | Markdown parsing | JSON API | ✅ Fixed |
| Data Model | Copy URLs | property_id FK | ✅ Fixed |
| Idempotency | None | Oban unique_periods | ✅ Fixed |
| Testing | Underspecified | 5 TDD tickets | ✅ Fixed |
| Auth | Not mentioned | live_session scope | ✅ Fixed |
| Data Retention | No pruning | Pruning worker | ✅ Fixed |
| Acceptance Criteria | Missing | Added to T014 | ✅ Fixed |

See [docs/RESEARCH_SUMMARY.md](docs/RESEARCH_SUMMARY.md) for full review.

---

## Retrospective (After Sprint)

### What Went Well
-

### What Could Improve
-

### Action Items
-

---

## Quick Commands

```bash
# Start server
mix phx.server

# Run all tests
mix test

# Run specific test file
mix test test/gsc_analytics/data_sources/serp/core/client_test.exs

# Run TDD workflow
mix test --only tdd
mix test --failed  # Re-run only failed tests

# Check test coverage
mix test --cover

# Run pre-commit checks
mix precommit

# Database operations
mix ecto.migrate
mix ecto.rollback
MIX_ENV=test mix ecto.reset

# Oban operations (in IEx)
Oban.check_queue(queue: :serp_check)
GscAnalytics.Workers.SerpCheckWorker.new(%{
  property_id: 1,
  url: "https://example.com",
  keyword: "test query"
}) |> Oban.insert()

# Check ScrapFly API credits
# Visit: https://scrapfly.io/dashboard/api
```

---

**Sprint Start Date:** _______________
**Sprint End Date:** _______________
**Sprint Lead:** Claude Code
**Product Owner:** User (Flor)
