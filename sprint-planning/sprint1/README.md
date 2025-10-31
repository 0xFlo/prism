# Sprint 1: GSC Analytics Refactoring

**Goal**: Decompose monolithic Dashboard module and optimize data aggregation for improved maintainability and performance.

---

## Quick Start

1. **Review**: Read [sprint-board.md](./sprint-board.md) for overview
2. **Plan**: Review tickets in order (#001-#010)
3. **Execute**: Follow phase-by-phase execution plan
4. **Track**: Update sprint board as tickets complete

---

## Sprint Structure

### 📋 [Sprint Board](./sprint-board.md)
Main tracking document with:
- Sprint backlog table
- Progress metrics
- Risk register
- Definition of done

### 🎫 Tickets

#### Phase 1: Quick Wins (Day 1)
- [#001](./ticket-001-urlgroups-n1-fix.md) - Fix UrlGroups N+1 queries **(4h)**

#### Phase 2: Dashboard Decomposition (Days 2-4)
- [#003](./ticket-003-extract-chartpresenter.md) - Extract Presentation.ChartPresenter **(2h)**
- [#011](./ticket-011-content-insights-context.md) - Introduce ContentInsights context API **(1h)**
- [#002](./ticket-002-extract-urlinsights.md) - Extract ContentInsights.UrlInsights **(3h)**
- [#004](./ticket-004-extract-sitetrends.md) - Extract Analytics.SiteTrends **(2h)**
- [#005](./ticket-005-extract-summarystats.md) - Extract Analytics.SummaryStats **(3h)**
- [#006](./ticket-006-extract-keywords.md) - Extract ContentInsights.KeywordAggregator **(3h)**
- [#007](./ticket-007-extract-urlperformance.md) - Extract ContentInsights.UrlPerformance **(4h)**
- [#008](./ticket-008-cleanup-dashboard.md) - Clean up Dashboard orchestration **(2h)**

#### Phase 3: Performance Optimization (Days 5-6)
- [#009](./ticket-009-database-aggregation.md) - Move aggregation to database **(6h)**
- [#010](./ticket-010-performance-testing.md) - Benchmark and validate **(2h)**
- [#012](./ticket-012-update-documentation.md) - Update documentation and architecture notes **(1h)**

**Total**: 33 hours over 6 days (~5.5h/day)

---

## Success Metrics

### Code Quality
- ✅ Dashboard.ex: 1040 lines → 150 lines (86% reduction)
- ✅ 6 new focused context modules created
- ✅ Improved testability and maintainability

### Performance
- ✅ UrlGroups queries: 7 → 4 for 3-hop chains (43% reduction)
- ✅ Weekly aggregation: 250ms → 80ms (3x faster)
- ✅ Monthly aggregation: 300ms → 90ms (3.3x faster)

### Quality Gates
- ✅ All tests pass after each ticket
- ✅ No regression in LiveView functionality
- ✅ No new compiler warnings
- ✅ Code review approved (if applicable)

---

## Architecture Changes

### Before
```
lib/gsc_analytics/
└── dashboard.ex (1040 lines - "god object")
    ├── URL listing + enrichment
    ├── URL detail insights
    ├── Keyword aggregation
    ├── Site trends
    ├── Summary stats
    └── Chart event building
```

### After
```
lib/gsc_analytics/
├── dashboard.ex (150 lines - orchestration only)
├── content_insights/
│   ├── url_performance.ex      # URL listing & enrichment
│   ├── url_insights.ex         # Single URL details
│   └── keyword_aggregator.ex   # Keyword aggregation
├── analytics/
│   ├── site_trends.ex          # Site-wide trends
│   ├── summary_stats.ex        # Summary statistics
│   ├── time_series_aggregator.ex  # Optimized aggregation
│   └── period_aggregator.ex    # Database-side grouping (NEW)
└── presentation/
    └── chart_presenter.ex      # Chart event formatting
```

---

## Ticket Template

Each ticket includes:
- **Problem Statement**: What needs fixing/extracting
- **Solution**: Approach and new module structure
- **Acceptance Criteria**: Definition of done
- **Implementation Tasks**: Step-by-step breakdown
- **Testing Strategy**: Unit + integration tests
- **Migration Checklist**: Verification steps
- **Rollback Plan**: Safety net if issues arise
- **Related Files**: What gets created/modified
- **Notes**: Important caveats and considerations

---

## Daily Workflow

### Morning
1. Review sprint board
2. Pick next ticket in sequence
3. Read ticket thoroughly
4. Understand dependencies

### During Work
1. Follow implementation tasks
2. Run tests after each change
3. Update ticket status
4. Commit atomically

### End of Day
1. Update sprint board progress
2. Note any blockers
3. Prepare next ticket
4. Commit all work

---

## Testing Protocol

### After Each Ticket
```bash
# Run specific tests
mix test test/path/to/new_test.exs

# Run integration tests
mix test test/gsc_analytics_web/live/

# Run full suite
mix test

# Check for warnings
mix compile --warnings-as-errors
```

### Manual Verification
- [ ] Navigate to affected LiveView pages
- [ ] Test user interactions (search, sort, filter, pagination)
- [ ] Verify no JavaScript console errors
- [ ] Verify no Phoenix log errors

---

## Git Workflow

### Commit Messages
```bash
# Phase 1
git commit -m "perf: reduce UrlGroups queries with chain preloading"

# Phase 2
git commit -m "refactor: extract ContentInsights.UrlInsights context"
git commit -m "refactor: extract Presentation.ChartPresenter"
# ... etc

# Phase 3
git commit -m "perf: move time series aggregation to database with DATE_TRUNC"
git commit -m "test: add performance benchmarks and regression tests"
```

### Atomic Commits
- One ticket = one commit
- Include tests in same commit
- Update documentation in same commit
- Keep commits focused and reversible

---

## Risk Mitigation

| Risk | Mitigation |
|------|-----------|
| LiveView breaks | Run integration tests after each ticket |
| Context extraction order issues | Follow dependency graph strictly |
| Database aggregation type issues | Comprehensive date type tests |
| Performance regression | Benchmark before/after with rollback plan |

---

## Retrospective Topics

### What Went Well?
- Incremental extraction strategy
- Comprehensive ticket documentation
- Clear acceptance criteria
- Rollback plans for each change

### What Could Improve?
- TBD after sprint completion

### Action Items for Next Sprint
- TBD after sprint completion

---

## References

### Project Documentation
- [Project CLAUDE.md](../../../Tools/gsc_analytics/CLAUDE.md) - Architecture overview
- [Performance Results](./docs/performance-sprint1-results.md) - Benchmark data (created in #010)

### Related Sprints
- Sprint 2: TBD (based on retrospective learnings)

---

## Quick Commands

```bash
# Navigate to project
cd /Users/flor/Developer/PKMS/Tools/gsc_analytics

# Run all tests
mix test

# Run specific test file
mix test test/gsc_analytics/content_insights/url_insights_test.exs

# Run performance tests
mix test --only performance

# Run benchmarks
mix run test/benchmarks/performance_suite.exs

# Check code quality
mix compile --warnings-as-errors
mix format --check-formatted

# Start server for manual testing
mix phx.server
```

---

**Sprint Start**: TBD
**Sprint End**: TBD
**Velocity Target**: 5 hours/day
**Total Story Points**: 33 hours
