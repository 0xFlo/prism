# Ticket #011: Introduce ContentInsights Context API

**Status**: ✅ Done (2025-10-19)
**Estimate**: 1 hour
**Priority**: 🟡 Medium
**Phase**: 2 (Dashboard Decomposition)
**Dependencies**: #003 (ChartPresenter extracted)

---

## Problem Statement

We are introducing several modules under `lib/gsc_analytics/content_insights/` but there is no top-level context module exposing a public API. LiveViews would have to alias deep modules directly, which breaks Phoenix context conventions and makes future refactors harder.

---

## Solution

Create `lib/gsc_analytics/content_insights.ex` that:

1. Documents the ContentInsights boundary
2. Delegates to the extracted submodules (`UrlInsights`, `KeywordAggregator`, `UrlPerformance`)
3. Provides a single import point for LiveViews and controllers

---

## Acceptance Criteria

- [x] `ContentInsights` module exposes public functions:
  - [x] `url_insights/3`
  - [x] `list_keywords/1`
  - [x] `list_urls/1`
- [x] Each function delegates to its respective submodule (`UrlInsights`, `KeywordAggregator`, `UrlPerformance`)
- [x] Module is documented with `@moduledoc` describing purpose and usage
- [x] LiveViews use the new context module (tickets #002, #006, #007 depend on this)
- [x] Dashboard wrappers now delegate to ContentInsights for compatibility
- [x] Existing tests continue to pass

---

## Outcome

- Introduced the consolidated context in `Tools/gsc_analytics/lib/gsc_analytics/content_insights.ex`, delegating to UrlInsights, KeywordAggregator, and UrlPerformance without leaking Dashboard internals.
- Updated LiveViews and callers to rely on the new boundary, with backwards-compatible wrappers retained in `Tools/gsc_analytics/lib/gsc_analytics/dashboard.ex` for callers awaiting cleanup in ticket #008.
- Documented the new module boundary to clarify ownership of content insights domain logic.

---

## Implementation Tasks

1. Create `lib/gsc_analytics/content_insights.ex`
   ```elixir
   defmodule GscAnalytics.ContentInsights do
     @moduledoc """
     Public API for content insights (URL metrics, keyword aggregation, etc.).
     """

     alias GscAnalytics.ContentInsights.{UrlInsights, KeywordAggregator, UrlPerformance}

     def url_insights(url, view_mode, opts \\ %{}) do
       UrlInsights.fetch(url, view_mode, opts)
     end

     def list_keywords(opts \\ %{}) do
       KeywordAggregator.list(opts)
     end

     def list_urls(opts \\ %{}) do
       UrlPerformance.list(opts)
     end
   end
   ```

2. Update existing code (LiveViews/tests) to alias `GscAnalytics.ContentInsights` instead of touching child modules directly.

3. Confirm downstream wrappers (`Dashboard`) delegate to the context boundary until removal in ticket #008.

4. Verify existing tests continue to pass (context coverage lives in submodule + LiveView suites).

---

## Testing Strategy

- Unit tests asserting each public function delegates to the expected module (use `Mox` or `expect` via simple `assert` with inserted fixture)
- Run existing LiveView tests to ensure imports still resolve

---

## Rollback Plan

If any issues arise, delete the new file and revert LiveView alias changes. No schema or data migrations are touched, so rollback is safe.
