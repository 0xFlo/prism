# Sync.ex Refactoring Sprint

**Sprint Goal:** Transform monolithic `sync.ex` into maintainable pipeline architecture

**Duration:** 2-3 days
**Priority:** Code Quality & Maintainability
**Risk Level:** Medium-High (requires careful testing)

## Sprint Status Overview

| Ticket | Title | Status | Estimated | Actual | Completed |
|--------|-------|--------|-----------|--------|-----------|
| 001 | State Foundation | ⚪ Not Started | 4h | - | - |
| 002 | Progress Tracker | ⚪ Not Started | 3h | - | - |
| 003 | URL Phase | ⚪ Not Started | 4h | - | - |
| 004 | Query Phase | ⚪ Not Started | 5h | - | - |
| 005 | Pipeline | ⚪ Not Started | 4h | - | - |
| 006 | Integration & Cleanup | ⚪ Not Started | 4h | - | - |
| **TOTAL** | | **0/6 Complete** | **24h** | **0h** | **0%** |

**Status Legend:**
- ⚪ Not Started
- 🔵 In Progress
- ✅ Complete
- ❌ Blocked

## Sprint Overview

This sprint refactors the 680-line `Sync` module into a clean pipeline architecture with:
- Explicit state management (SyncState struct)
- Separated phase modules (URLPhase, QueryPhase)
- Clear progress tracking (ProgressTracker)
- Improved testability and maintainability

## Success Criteria

- ✅ All existing tests pass without modification
- ✅ No behavior changes (backwards compatible)
- ✅ Code reduced from 680 → ~200 lines in main module
- ✅ Each phase module < 200 lines
- ✅ Clear separation of concerns
- ✅ Process dictionary removed

## Tickets

See individual ticket files for detailed implementation plans:

1. **[TICKET-001]** Setup & State Foundation (4 hours) - ⚪ Not Started
2. **[TICKET-002]** Progress Tracking Extraction (3 hours) - ⚪ Not Started
3. **[TICKET-003]** URL Phase Extraction (4 hours) - ⚪ Not Started
4. **[TICKET-004]** Query Phase Extraction (5 hours) - ⚪ Not Started
5. **[TICKET-005]** Pipeline Coordination (4 hours) - ⚪ Not Started
6. **[TICKET-006]** Integration & Cleanup (4 hours) - ⚪ Not Started

**Total Estimated Effort:** 24 hours (3 days)

## Testing Strategy

- Run `mix test` after each ticket
- Run `mix test test/gsc_analytics/data_sources/gsc/core/sync_test.exs` for unit tests
- Run `mix test test/gsc_analytics/data_sources/gsc/core/sync_progress_integration_test.exs` for integration tests
- Manual smoke test: `GscAnalytics.DataSources.GSC.Core.Sync.sync_yesterday()` in IEx

## Progress Log

### TICKET-001: State Foundation
**Status:** ⚪ Not Started

**What was done:**
- [ ] Created `Sync.State` module with typed struct
- [ ] Replaced Process dictionary with Agent-based metrics
- [ ] Pre-calculated date-to-step mapping in state initialization
- [ ] Updated all Process.put/get calls to use State module
- [ ] Added Agent cleanup in finalize_sync
- [ ] All tests passing

**Blockers/Notes:**
_None yet_

---

### TICKET-002: Progress Tracker
**Status:** ⚪ Not Started

**What was done:**
- [ ] Created `Sync.ProgressTracker` module
- [ ] Extracted all progress reporting functions
- [ ] Removed step reconstruction logic (using pre-calculated steps)
- [ ] Deleted 5 private helper functions
- [ ] Simplified finalize_sync to use ProgressTracker
- [ ] Integration tests still passing

**Blockers/Notes:**
_None yet_

---

### TICKET-003: URL Phase
**Status:** ⚪ Not Started

**What was done:**
- [ ] Created `Sync.URLPhase` module
- [ ] Extracted batch_fetch_urls logic
- [ ] Separated filtering, fetching, storing, reporting
- [ ] Updated process_date_chunk to use URLPhase
- [ ] Deleted batch_fetch_urls function (~70 lines)
- [ ] All URL-related tests passing

**Blockers/Notes:**
_None yet_

---

### TICKET-004: Query Phase
**Status:** ⚪ Not Started

**What was done:**
- [ ] Created `Sync.QueryPhase` module
- [ ] Extracted batch_fetch_queries logic
- [ ] Moved callback creation and error handling
- [ ] Updated process_date_chunk to use QueryPhase
- [ ] Deleted 8 helper functions (~160 lines)
- [ ] Query pagination tests passing

**Blockers/Notes:**
_None yet_

---

### TICKET-005: Pipeline
**Status:** ⚪ Not Started

**What was done:**
- [ ] Created `Sync.Pipeline` module
- [ ] Extracted chunk processing logic
- [ ] Moved halt condition checking
- [ ] Moved metric update logic
- [ ] Simplified sync_date_range to thin orchestrator
- [ ] Deleted 4 orchestration functions (~150 lines)
- [ ] All orchestration tests passing

**Blockers/Notes:**
_None yet_

---

### TICKET-006: Integration & Cleanup
**Status:** ⚪ Not Started

**What was done:**
- [ ] Updated all @moduledoc with architecture overview
- [ ] Added usage examples to each module
- [ ] Created sync/README.md with diagrams
- [ ] Updated CLAUDE.md with refactoring notes
- [ ] Ran full test suite (100% pass)
- [ ] Manual smoke testing complete
- [ ] Performance validation done
- [ ] Code formatted and cleaned up

**Blockers/Notes:**
_None yet_

---

## Rollback Plan

Each ticket is independently committable. If issues arise:
1. Revert the specific commit
2. Fix issues in isolation
3. Re-apply with fixes

## Dependencies

- No external library changes needed
- No database migrations required
- No configuration changes required
