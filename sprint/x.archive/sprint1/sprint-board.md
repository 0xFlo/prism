# Sprint 1: GSC Analytics Refactoring

**Sprint Goal**: Decompose monolithic Dashboard module and optimize data aggregation for improved maintainability and performance.

**Duration**: 6 days
**Start Date**: TBD
**End Date**: TBD

---

## Sprint Overview

This sprint tackles technical debt in the GSC Analytics codebase by:

1. Eliminating N+1 queries in redirect resolution
2. Decomposing the 1040-line Dashboard "god object" into focused contexts
3. Moving aggregation logic from in-memory to database for better performance

---

## Progress Snapshot

- ✅ Completed: #001, #002, #003, #004, #005, #006, #007, #008, #011 (24h logged)
- 🟡 Up Next: #009 (6h planned)
- ⏳ Blocked: #010, #012 (3h planned)
- Remaining Estimate: 9h of 33h total capacity

---

## Sprint Backlog

### 🔴 Phase 1: Quick Wins (Day 1)

| Ticket                                   | Title                                         | Estimate | Status  | Assignee |
| ---------------------------------------- | --------------------------------------------- | -------- | ------- | -------- |
| [#001](./ticket-001-urlgroups-n1-fix.md) | Fix UrlGroups N+1 query with chain preloading | 4h       | ✅ Done | flor     |

**Phase 1 Goal**: Reduce query count for redirect chains from O(n) to O(log n)

---

### 🟡 Phase 2: Dashboard Decomposition (Days 2-4)

| Ticket                                         | Title                                       | Estimate | Status  | Dependencies | Assignee |
| ---------------------------------------------- | ------------------------------------------- | -------- | ------- | ------------ | -------- |
| [#003](./ticket-003-extract-chartpresenter.md) | Extract Presentation.ChartPresenter         | 2h       | ✅ Done | None         | flor     |
| [#011](./ticket-011-content-insights-context.md) | Introduce ContentInsights context API      | 1h       | ✅ Done | #003         | flor     |
| [#002](./ticket-002-extract-urlinsights.md)    | Extract ContentInsights.UrlInsights context | 3h       | ✅ Done | #003, #011   | flor     |
| [#004](./ticket-004-extract-sitetrends.md)     | Extract Analytics.SiteTrends context        | 2h       | ✅ Done | None         | flor     |
| [#005](./ticket-005-extract-summarystats.md)   | Extract Analytics.SummaryStats context      | 3h       | ✅ Done | None         | flor     |
| [#006](./ticket-006-extract-keywords.md)       | Extract ContentInsights.KeywordAggregator   | 3h       | ✅ Done | #011         | flor     |
| [#007](./ticket-007-extract-urlperformance.md) | Extract ContentInsights.UrlPerformance      | 4h       | ✅ Done | #011         | flor     |
| [#008](./ticket-008-cleanup-dashboard.md)      | Clean up Dashboard orchestration layer      | 2h       | ✅ Done | #002-#007, #011 | flor     |

**Phase 2 Goal**: Reduce Dashboard.ex from 1040 lines to ~150 lines of orchestration

---

### 🟢 Phase 3: Performance Optimization (Days 5-6)

| Ticket                                       | Title                                           | Estimate | Status  | Dependencies | Assignee |
| -------------------------------------------- | ----------------------------------------------- | -------- | ------- | ------------ | -------- |
| [#009](./ticket-009-database-aggregation.md) | Move aggregation to database with DATE_TRUNC    | 6h       | 🟡 Next | #002-#008    | flor     |
| [#010](./ticket-010-performance-testing.md)  | Benchmark and validate performance improvements | 2h       | ⏳ Blocked | #001, #009   | flor     |
| [#012](./ticket-012-update-documentation.md) | Update docs/CLAUDE.md and architecture docs      | 1h       | ⏳ Blocked | #002-#010    | flor     |

**Phase 3 Goal**: Achieve 2-5x performance improvement on weekly/monthly aggregations

---

## Risk Register

| Risk                                          | Impact | Mitigation                                                            |
| --------------------------------------------- | ------ | --------------------------------------------------------------------- |
| LiveView breaks after context extraction      | High   | Run integration tests after each commit; keep commits atomic          |
| Database aggregation returns wrong date types | Medium | Write comprehensive type tests; verify Date structs not NaiveDateTime |
| UrlGroups preload doesn't handle deep chains  | Medium | Test with 5+ hop redirect chains; add logging                         |
| Performance regression instead of improvement | High   | Benchmark before/after; keep old implementation for rollback          |

---

## Definition of Done

Each ticket is "done" when:

1. ✅ Code implemented and committed
2. ✅ Unit tests added/updated (passing)
3. ✅ Integration tests pass
4. ✅ LiveView functionality verified manually
5. ✅ Code reviewed (if applicable)
6. ✅ Documentation updated
7. ✅ No new compiler warnings
