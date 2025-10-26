# Sprint 3: Architectural Refactor - Data Pipeline & DRY Principles

**Sprint Goal**: Transform the dashboard from tactical fixes to systematic architecture with domain types, unified pipelines, and proper separation of concerns.

**Duration**: 2 weeks (flex based on testing outcomes)
**Start Date**: 2025-10-20
**End Date**: TBD

---

## Progress Snapshot

- ✅ Completed: #018 (TimeSeriesData domain type), #024 (critical database indexes)
- 🔄 Next Up: #019a (database aggregation - depends on #018)
- 📋 Pending: #019b, #020, #021, #022, #023, #025
- Remaining Estimate: 21.5h (4.5h completed, 21.5h remaining)
- **Revision Note**: Split #019 into #019a (critical DB optimization) and #019b (DRY improvement)
- **Expansion Note**: Added #023 (KeywordAggregator), #024 (critical indexes), and #025 (WoW growth window functions) based on technical debt audit and Elixir/Ecto best practices

---

## Sprint Backlog

| Ticket | Title | Estimate | Status | Dependencies | Assignee |
| --- | --- | --- | --- | --- | --- |
| [#018](./ticket-018-time-series-domain-type.md) | Create TimeSeriesData domain type | 3h | ✅ Complete | None | flor |
| [#019a](./ticket-019a-database-aggregation.md) | **Move aggregation to database** | **5h** | 📋 Pending | #018 | flor |
| [#024](./ticket-024-critical-database-indexes.md) | **Add critical database indexes (GIN, covering, BRIN)** | **1h** | ✅ Complete | None | flor |
| [#023](./ticket-023-keyword-aggregator-database-optimization.md) | **Optimize KeywordAggregator with JSONB** | **4h** | 📋 Pending | #018, #024 | flor |
| [#025](./ticket-025-wow-growth-window-functions.md) | **WoW growth with PostgreSQL window functions** | **3h** | 📋 Pending | #019a | flor |
| [#019b](./ticket-019b-query-pattern-unification.md) | Unified query builder pattern | 2h | 📋 Pending | #018, #019a | flor |
| [#020](./ticket-020-chart-data-presenter.md) | Centralize presentation logic | 3h | 📋 Pending | #018, #019a | flor |
| [#021](./ticket-021-aggregation-cache-layer.md) | Add aggregation caching layer | 3h | 📋 Pending | #019a, #019b, #020 | flor |
| [#022](./ticket-022-documentation-and-tests.md) | Architecture docs & comprehensive tests | 2h | 📋 Pending | #018-#025 | flor |

### Archived

| Ticket | Title | Status | Reason |
| --- | --- | --- | --- |
| [#019](./ticket-019-unified-aggregation-pipeline.ARCHIVED.md) | Unified aggregation pipeline (original) | 🗄️ Archived | Split into #019a (DB optimization) and #019b (DRY pattern) after discovering performance issue |

---

## Prioritization Notes

**Foundation First (2025-10-20)**: Ticket #018 is critical path - all other work depends on the domain type. Must complete and validate before proceeding to database optimization.

**Major Revision (2025-10-20)**: After reviewing performance analysis, split #019 into two tickets:
- **#019a** (5h) - Move aggregation to database (10-100x performance improvement)
- **#019b** (2h) - Unify query patterns (DRY compliance, optional)

This addresses the fundamental inefficiency of fetching thousands of rows for application-layer aggregation when PostgreSQL can do it natively. #019a is now the **highest ROI ticket** in the sprint.

**Sprint Expansion (2025-10-19)**: Added three tickets based on technical debt audit and Elixir/Ecto best practices:
- **#024** (1h) - Critical database indexes (GIN for JSONB, covering index for time-series, BRIN for dates)
- **#023** (4h) - KeywordAggregator database optimization (25-30x improvement, 99%+ less data transfer)
- **#025** (3h) - WoW growth with PostgreSQL window functions (20x improvement, completes the "critical three")

These follow the same database-first principle as #019a. Total sprint estimate increased from 18h to 26h.

**Rationale**: With AI implementation, 26h of work is achievable in hours rather than days. All three critical inefficiencies identified in the audit will be addressed in one sprint.

**Database-First Architecture**: #019a and #023 shift from "pipeline pattern" to "leverage the database." This is more impactful than caching (#021) because the queries become fast enough that caching is less critical.

**Incremental Rollout**: Each ticket includes rollback plan. If issues arise, we can pause sprint and operate on tactical fixes until ready to resume.

**Test Coverage**: Each ticket requires passing full test suite before proceeding. Sprint 2 taught us that comprehensive testing prevents rework.

**Leadership Alignment**:
- Daily async update (Slack) should include benchmark deltas vs. baseline, outstanding risks/blockers, and any legacy code removed that day.
- Schedule 30-minute mid-sprint architecture review (Day 5) to confirm DB parity results before moving on to caching (#021).
- Partner with Data Ops for refreshed production-scale dataset prior to comparison testing.

**Decision Log (maintain in tickets)**:
- DB rewrite signoff: require ≥3 identical comparison runs across daily/weekly/monthly aggregations before deleting legacy modules.
- Cache enablement: proceed only after Telemetry dashboards exist for hit rate + latency with alert thresholds defined.

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Domain type changes break existing code | High | Comprehensive test coverage; incremental migration strategy |
| **DB aggregation produces different results** | **High** | **Comparison tests; run both implementations in parallel initially** |
| **PostgreSQL DATE_TRUNC behavior differs** | **Medium** | **Verify ISO 8601 week start (Monday); extensive edge case testing** |
| **JSONB aggregation differs from Elixir (#023)** | **High** | **Comparison tests with tolerance for float precision; verify weighted averages** |
| **Index creation blocks production writes (#024)** | **Medium** | **Use CONCURRENTLY; schedule during low-traffic window if possible** |
| **GIN index takes too long to create (#024)** | **Low** | **Monitor with pg_stat_progress_create_index; expect 5-15 minutes** |
| Performance testing reveals slowdowns | Low | DB aggregation should be 10-100x faster; benchmark before/after |
| LiveView re-renders increase with new structure | Medium | Pre-encode JSON in assigns; avoid re-computation in templates |
| Migration creates temporary inconsistency | High | Sequence deletions with validated benchmarks; keep git revert plan handy rather than retaining legacy code |
| Caching adds complexity without clear wins | Low | Make #021 optional; less critical after #019a and #023 DB optimizations |
| Timeline extends beyond 2 weeks | Medium | Tickets are independent; can pause/defer #019b, #021 if needed; #023 can be moved to Sprint 4 |
| Benchmark environment diverges from production | Medium | Lock staging dataset snapshot before sprint; re-run comparison on prod-like data |
| Missing telemetry to detect regressions | High | Instrument aggregator + cache before rollout; create dashboards/alerts prior to enabling cache |

---

## Definition of Done

1. ✅ All ticket acceptance criteria met with evidence in ticket files.
2. ✅ Full test suite passes (mix test) with zero failures.
3. ✅ Performance benchmarks show no regressions (ideally improvements).
4. ✅ Manual QA of both main dashboard and URL detail charts (daily/weekly/monthly).
5. ✅ Documentation updated to reflect new architecture (#022).
6. ✅ Code review completed for each ticket before merging.
7. ✅ No new compiler warnings introduced.
8. ✅ Sprint retrospective completed with lessons learned.
9. ✅ Telemetry dashboards updated with new metrics (latency, cache hits, DB query time).

---

## Success Criteria

### Code Quality
- [ ] Zero duplicate `encode_time_series_json` functions
- [ ] Single `Enum.sort_by` call in `TimeSeriesData.sort_chronologically/1`
- [ ] All time series data uses `TimeSeriesData` struct
- [ ] Clear separation: data layer → business logic → presentation
- [ ] Aggregation done in PostgreSQL, not application code
- [ ] KeywordAggregator uses JSONB operations, not Elixir processing

### Performance
- [ ] **DB aggregation is 10-100x faster than application-layer** (#019a)
- [ ] **Keyword aggregation is 25-30x faster** (#023)
- [ ] **WoW growth calculation is 20x faster** (#025)
- [ ] **Network data transfer reduced by 90%+ for time series** (#019a)
- [ ] **Network data transfer reduced by 99%+ for keywords** (#023)
- [ ] **Network data transfer reduced by 99%+ for growth data** (#025)
- [ ] **GIN index enables fast JSONB queries (100-1000x)** (#024)
- [ ] **Covering index enables index-only scans** (#024)
- [ ] **BRIN index speeds date range queries (3-5x)** (#024)
- [ ] **P95 query latency < 200ms** (quantitative target)
- [ ] **Database CPU utilization < 50%**
- [ ] **Connection pool saturation < 80%**
- [ ] Aggregation cache reduces computation by 30-50% (#021, optional)
- [ ] No increase in LiveView re-render frequency
- [ ] Chart load time significantly improved from current
- [ ] URL detail page loads in <1 second (vs 4-6 seconds)

### Reliability
- [ ] Date sorting bug cannot reoccur (enforced by domain type)
- [ ] Type safety prevents structural data errors
- [ ] **DB aggregation produces identical results to old implementation**
- [ ] **JSONB aggregation produces identical results to Elixir aggregation**
- [ ] **Year boundary handling works correctly in PostgreSQL**
- [ ] Indexes created with CONCURRENTLY (zero downtime)
- [ ] Comprehensive test coverage for all transformations

---

## Sprint Retrospective Template

_(To be filled at sprint end)_

**What Went Well:**
-

**What Could Be Improved:**
-

**Action Items for Next Sprint:**
-

**Technical Debt Created/Resolved:**
-
