# Sprint 3: Architectural Refactor - Data Pipeline & DRY Principles

**Goal**: Transform the dashboard data pipeline from ad-hoc implementations into a robust, maintainable architecture with proper domain types, single source of truth for data transformations, and systematic elimination of code duplication.

---

## Quick Start

1. **Review**: Open [sprint-board.md](./sprint-board.md) for status, risks, and dependencies.
2. **Plan**: Work tickets in priority order (#018 → #024 → #019a → #023 → #025 → #019b → #020 → #021 → #022).
3. **Execute**: Keep commits atomic; each ticket builds on the previous foundation.
4. **Validate**: Run full test suite + manual QA after each ticket completion.

**Enhanced Scope (2025-10-19)**: Sprint capacity increased from 18h to 26h to include:
- Critical database indexes with BRIN (#024)
- Keyword aggregation optimization (#023)
- WoW growth with window functions (#025)

With AI implementation, 26h of work is achievable quickly. All three critical inefficiencies from the audit will be addressed.

### Sprint Kickoff Checklist (CTO Sign-off)

- [ ] Confirm staging dataset mirrors production scale for aggregation benchmarking
- [ ] Schedule comparison-test signoff review (eng + data) before merging DB aggregation rewrite
- [ ] Ensure Telemetry hooks exist (or are planned) for `TimeSeriesAggregator` latency and cache hit rates
- [ ] Assign DRI for nightly verification of dashboard metrics during rollout week
- [ ] Inventory legacy aggregation helpers slated for deletion; confirm cleanup owners
- [ ] Lock calendar slots for mid-sprint architecture sync + end-of-sprint retrospective

---

## Context: Why This Sprint?

During Sprint 2's chart refactoring work, we discovered a **date sorting bug** where December 2024 data appeared among 2025 dates in the weekly view. The root cause revealed deeper architectural issues:

### Issues Discovered

1. **Inconsistent date handling** - 8 different places doing `Enum.sort_by(& &1.date)`, some with `Date` module, some without
2. **Scattered data transformation** - JSON encoding in LiveViews, sorting in aggregators, no clear separation
3. **Missing type safety** - Raw maps passed around with implicit structure assumptions
4. **Code duplication** - Identical `encode_time_series_json` functions in both LiveViews
5. **No single source of truth** - Each function assumes data shape without contracts

### The Quick Fix vs. The Right Fix

We applied a tactical fix (adding `Date` module to 3 sorting calls), but this is a **band-aid on systemic issues**. Sprint 3 addresses the root causes with proper architecture.

---

## Focus Areas

- **Domain modeling**: Create `TimeSeriesData` type with guaranteed sorting and structure
- **Database-first aggregation**: Move grouping and aggregation from application to PostgreSQL (biggest performance win)
- **JSONB optimization**: Move keyword aggregation from 5-layer Elixir processing to PostgreSQL JSONB operations
- **Database indexes**: Add GIN indexes for JSONB and covering indexes for time-series queries
- **Query pattern unification**: DRY compliance for database query builders
- **Presentation layer**: Centralize all JSON encoding and chart data prep
- **Performance**: Leverage database aggregation; optional caching layer for further optimization
- **DRY compliance**: Eliminate duplicate code across LiveViews and contexts

---

## Ticket Reference

### Core Architecture (Foundation)
- [#018](./ticket-018-time-series-domain-type.md) – Create TimeSeriesData domain type with guaranteed structure (3h)

### Database Optimization (Critical Path - "The Critical Three")
- [#019a](./ticket-019a-database-aggregation.md) – **Move time-series aggregation to database** (10-100x performance, 5h)
- [#024](./ticket-024-critical-database-indexes.md) – **Add critical database indexes** (GIN for JSONB, covering for time-series, BRIN for dates, 1h)
- [#023](./ticket-023-keyword-aggregator-database-optimization.md) – **Optimize KeywordAggregator with JSONB** (25-30x performance, 99%+ less data, 4h)
- [#025](./ticket-025-wow-growth-window-functions.md) – **WoW growth with PostgreSQL window functions** (20x performance, completes the audit's "critical three", 3h)

### Code Quality & DRY
- [#019b](./ticket-019b-query-pattern-unification.md) – Unify query builder patterns (DRY compliance, optional, 2h)
- [#020](./ticket-020-chart-data-presenter.md) – Centralize presentation logic and eliminate duplicate JSON encoding (3h)

### Performance & Documentation
- [#021](./ticket-021-aggregation-cache-layer.md) – Add caching layer for computed aggregations (less critical after #019a & #023, 3h)
- [#022](./ticket-022-documentation-and-tests.md) – Update architecture docs and add comprehensive tests (2h)

**Notes**:
- Original #019 was split into #019a (critical database optimization) and #019b (query pattern unification) after discovering the fundamental performance issue of application-layer aggregation.
- Sprint expanded (2025-10-19) to include #023 and #024 based on technical debt audit findings. See [TECHNICAL-DEBT-AUDIT.md](./TECHNICAL-DEBT-AUDIT.md) for full analysis.

---

## Success Metrics

### Reliability & Code Quality
1. **Bug Prevention**: Date sorting bug cannot reoccur (enforced by domain type)
2. **Code Reduction**: Eliminate 50+ lines of duplicate code
3. **Type Safety**: Compile-time guarantees for time series data structure
4. **Maintainability**: Clear separation of concerns across data/logic/presentation layers

### Performance Improvements
5. **Time-Series Aggregation**: 10-100x faster by leveraging PostgreSQL DATE_TRUNC (#019a)
6. **Keyword Aggregation**: 25-30x faster using JSONB operations (#023)
7. **WoW Growth Calculation**: 20x faster using window functions (#025)
8. **Network Efficiency (Time-Series)**: 90%+ reduction in data transferred (#019a)
9. **Network Efficiency (Keywords)**: 99%+ reduction in data transferred (#023)
10. **Network Efficiency (Growth Data)**: 99%+ reduction in data transferred (#025)
11. **Index Performance**: 100-1000x faster JSONB queries with GIN index (#024)
12. **P95 Query Latency**: < 200ms (quantitative target)
13. **Database CPU**: < 50% utilization
14. **Connection Pool**: < 80% saturation
15. **User Experience**: URL detail page loads in <1 second (vs 4-6 seconds currently)

### Architecture
16. **Database-First Design**: All aggregation happens in PostgreSQL, not application layer
17. **Index Strategy**: GIN indexes for JSONB, covering indexes for hot data, BRIN for dates
18. **Query Optimization**: Index-only scans for common time-series queries
19. **Window Functions**: LAG/LEAD for growth calculations, avoiding application-layer loops
20. **Best Practices**: Follows Elixir/Ecto community recommendations (ecto_psql_extras, batch operations)

---

## Status Tracking

- Sprint board tracks current state, blockers, and remaining effort.
- Update tickets with implementation details, test results, and outcomes as you go.
- Each ticket includes rollback plan in case of issues.
- Weekly leadership review expects: updated benchmark numbers, cache hit rates (if enabled), and open risk log entries.

## Elixir best Practices

I'll search for Elixir best practices regarding database optimization and moving computation closer to the data.## Elixir/Ecto Best Practices for Database Optimization

Based on current Elixir/Ecto best practices, your audit findings align perfectly with community recommendations. Here are the key best practices from the Elixir ecosystem:

### 🎯 Core Principle Validation

The principle of pushing computation to the database is strongly supported - studies show that proper database optimization can improve performance by 200-300%, with unoptimized approaches taking 10 times longer.

### 📊 Key Best Practices

#### 1. **Eliminate N+1 Queries with Smart Preloading**

The N+1 query problem is one of the most common performance issues in Ecto applications, occurring when an application loads parent records and their associated child records in separate queries.

**Best Practice Solutions:**

- Use `preload` with joins for has_many associations to avoid large ANY arrays in queries, as bigger arrays take more planning time
- When using preload without joins, each association generates a separate query - for example, preloading two associations results in three total queries
- Combining `join/5` with `preload/3` allows fetching all data in a single query, avoiding the N+1 problem entirely

#### 2. **Use Ecto Fragments for Complex Database Operations**

Ecto provides fragments to send expressions directly to the database when Ecto's query syntax cannot represent all possible database queries. This is essential for:

- **Window functions**: Ecto 3.x includes WindowAPI with functions like `row_number()`, `lag()`, `lead()`, and `over()` for complex aggregations
- **JSONB operations**: PostgreSQL's `jsonb_to_recordset` can be used with fragments to query JSONB arrays efficiently, though it requires wrapping subqueries in parentheses to avoid AS clause conflicts
- **Complex aggregations**: Using `DATE_TRUNC`, mathematical operations, and PostgreSQL-specific functions

#### 3. **Leverage PostgreSQL-Specific Features**

PostgreSQL keeps statistics about data distribution in indexes, allowing it to decide which plan is best for any given input. Key optimizations include:

- **JSONB GIN Indexes**: PostgreSQL supports indexing on JSONB columns via GIN indexes, and Ecto will use the containment operator @> which is optimized
- **LATERAL Joins**: As of Ecto 3.4.3, lateral joins can be constructed without using fragments, making them simpler to write and faster to execute than correlated subqueries
- **Prepared Statements**: Consider using `prepare: :unnamed` in Ecto database configuration for better query plan selection in PostgreSQL

#### 4. **Optimize Query Execution Patterns**

Key optimization strategies include batch operations (which can be up to 10 times faster than individual executions), using PostgreSQL's LISTEN/NOTIFY instead of polling (freeing up to 30% of system resources), and limiting SELECT fields (reducing response time by up to 40%).

**Red Flags to Avoid:**

- `Repo.all()` followed by `Enum.group_by`, `Enum.filter`, or `Enum.sort_by`
- Fetching thousands of rows to calculate aggregates
- Processing JSONB arrays in application code

#### 5. **Database Performance Monitoring**

Use tools like pg_stat_statements to gather statistics on query executions, as research indicates nearly 30% of performance issues stem from a small subset of inefficient queries. The `ecto_psql_extras` package provides powerful insights including lock information, index usage, and buffer cache hit ratios.

### 🚀 Performance Impact Examples

Benchmark results show that using proper preload strategies provides nearly identical performance between "Preload 5 query async" and "Preload 1 query async", but the single query approach uses 5.8 times more memory.

Real-world optimizations have shown Elixir/Ecto achieving 87-107% of pgbench performance after proper optimization, with some cases showing Elixir and Ecto actually outperforming pgbench.

### ✅ Your Audit Recommendations Are On Point

Your technical debt audit perfectly aligns with Elixir/Ecto best practices:

1. **Moving aggregation to database** (#019a) - Critical and widely recommended
2. **KeywordAggregator optimization** - Using JSONB functions is the correct approach
3. **Database indexes** - Essential for performance, especially GIN indexes for JSONB
4. **Window functions for complex calculations** - Modern Ecto fully supports these

The estimated **95% performance improvement** from your audit is realistic based on community benchmarks. Your approach of "computation as close to the data as possible" is not just a best practice—it's considered fundamental to building performant Elixir applications.
