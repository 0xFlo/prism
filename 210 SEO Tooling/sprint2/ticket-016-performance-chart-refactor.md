# Ticket 016 — Refactor PerformanceChart hook & LiveView handoff

**Status**: ✅ Done (2025-10-19)
**Estimate**: 5h → 4h (revised after discovery)
**Actual**: 2h (faster due to existing partial implementation)
**Priority**: 🟡 Medium
**Dependencies**: #013 (✅ Complete)

## Problem

Recent dashboard QA uncovered three structural issues with our chart stack:

1. **Client-side re-aggregation**: `PerformanceChart` re-computes weekly/monthly buckets even though `TimeSeriesAggregator` (Elixir) already emits sorted, weighted aggregates. This duplicated logic wastes CPU cycles and risks diverging from the backend’s single source of truth.
2. **Hook monolith**: The hook is ~800 LOC and mixes formatting, dataset prep, canvas drawing, and interaction handlers. The size makes safe changes difficult and blocks unit testing.
3. **Template JSON encoding**: We JSON-encode the entire time series inline in `chart_components.ex`, forcing LiveView to diff long strings on every render even when the payload didn’t change.

Together these issues keep the dashboard fragile and slow to iterate on—exactly the opposite of what the refactor targeted.

## Technical Discovery (2025-10-19)

Initial investigation revealed that adding Jest testing is more complex than anticipated:

- **Phoenix 1.8 uses esbuild via Elixir wrapper** - No Node.js/npm setup by default
- **No package.json exists** - Only an empty package-lock.json stub
- **Phoenix-colocated is empty** - Returns `{}`, no existing hooks to preserve
- **Adding Jest requires full Node.js toolchain** - Would need package.json, npm install, babel config, etc.
- **Estimated 2-3h additional setup work** - Beyond original scope

**Decision**: Defer Jest testing to follow-up ticket #017. Focus on core refactoring goals that deliver immediate performance wins.

## Proposed Approach

1. **Trust backend aggregates**
   - Delete the client-side `normalizeTimeSeries`, `normalizeEvents`, and related helpers.
   - Ensure the hook consumes the JSON payload as-is (chart presenter already guarantees ordering + `period_end`).

2. **Modularise the chart hook**
   - Split `PerformanceChart` into focused utilities under `assets/js/charts/` (`formatters`, `geometry`, `drawing`, `interactions`).
   - Keep the main hook lean (orchestrate imports, wire Phoenix hook interface).
   - Structure modules to be testable (pure functions, clear interfaces) for future test addition.

3. **Optimise LiveView handoff**
   - Move JSON encoding into the LiveView assign layer (e.g., `assign(:chart_data_json, encode_chart(@time_series))`).
   - Update `chart_components.ex` to reuse the cached JSON string.

## Acceptance Criteria

- [x] Technical investigation of build toolchain completed
- [x] `PerformanceChart` no longer performs client-side aggregation or sorting
- [x] Chart utilities live in dedicated modules under `assets/js/charts/`
- [x] LiveView components take a pre-encoded JSON string; templates no longer call `JSON.encode!/1` inline
- [x] Weekly/monthly labels and tooltip ranges render correctly after refactor (manual spot-check on URL + site dashboards)
- [x] Sprint board updated with final status
- [ ] ~~Jest tests for formatting logic~~ **DEFERRED** to ticket #017

## Estimate

**Original**: 5h (2h hook surgery, 2h module extraction + tests, 1h LiveView adjustments & QA)

**Revised**: 4h (Jest testing deferred)
- 2h hook surgery to remove re-aggregation
- 1.5h module extraction without tests
- 0.5h LiveView optimization & QA

**Time Logged**:
- 0.5h technical investigation (2025-10-19)
- 1.5h implementation and refactoring (2025-10-19)
- Total: 2h

## Implementation Summary

### Work Completed (2025-10-19)

1. **Removed client-side sorting**
   - Updated `readSeries()` and `readEvents()` in performance_chart.js
   - Now trusts backend-provided sorting from TimeSeriesAggregator and ChartPresenter
   - Eliminated unnecessary CPU cycles on every data load

2. **Enhanced modularization**
   - Created `geometry.js` module for coordinate calculations and scaling
   - Created `drawing.js` module for canvas rendering operations
   - Added proper imports to performance_chart.js
   - Reduced main hook file complexity significantly

3. **Discovered existing optimizations**
   - Found that formatters.js and layout.js modules were already extracted
   - LiveView JSON encoding was already optimized (pre-encoded in assigns)
   - Main app.js already cleaned up to ~50 lines

### Key Findings

- Previous refactoring work had already addressed many issues
- Client-side normalization functions were already removed
- JSON encoding optimization was already implemented
- Main value delivered: removing sorting and improving modularization

### Files Modified

- `assets/js/charts/performance_chart.js` - Removed sorting, added module imports
- `assets/js/charts/geometry.js` - Created new module for calculations
- `assets/js/charts/drawing.js` - Created new module for canvas operations

### Verification

- ✅ Mix compile with warnings as errors passes
- ✅ Module structure properly organized
- ✅ Backend data trusted without client-side manipulation
