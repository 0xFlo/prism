# Ticket-005: Authenticated SERP Landscape LiveView

## Status: TODO
**Priority:** P2
**Estimate:** 5 pts
**Dependencies:** ticket-001, ticket-002, ticket-003, ticket-004
**Blocks:** ticket-008

## Problem Statement
We need a dedicated SERP Landscape page that aggregates the AI Overview, competitor, and content-type insights for a single URL. The route must live inside the authenticated `live_session :require_authenticated_user` scope (per AGENTS.md) and stream data efficiently.

## Goals
- Add `/dashboard/url/serp-landscape` route in the authenticated scope with documented reasoning
- Build `DashboardSerpLandscapeLive` that mounts with `current_scope`, loads snapshots via the context, and streams collections for performance
- Provide header metadata (URL, property, last checked, keyword count, stale warnings) and CTAs back to bulk check flow
- Handle empty/error states gracefully when no snapshots are available

## Acceptance Criteria
- [ ] Router updated with proper `scope`, `pipe_through`, and `live_session` plus inline comment describing placement
- [ ] LiveView access restricted to authenticated users; unauthorized access redirects to login per existing plugs
- [ ] Page renders AI Overview panel, competitor heatmap, and content-type chart once data is ready
- [ ] Header shows last checked timestamp, keyword count badge, stale warning when data older than threshold, and link to rerun checks
- [ ] Navigation link from dashboard URL detail LiveView opens the new page and is hidden/disabled if no snapshots exist yet

## Implementation Plan
1. **Router Update**
   - Insert route inside `scope "/", GscAnalyticsWeb` with `:browser, :require_authenticated_user` pipeline and `live_session :require_authenticated_user` block; document reasoning inline + RFC.
2. **LiveView Skeleton**
   - Build `DashboardSerpLandscapeLive` with `on_mount {UserAuth, :require_authenticated}`; assign `current_scope`, `target_url`, `property_url`, query params.
3. **Data Loading**
   - Use `SerpLandscape` context to load aggregates and snapshots; stream results into assigns; handle `{:error, :not_found}` states.
4. **Header + Navigation**
   - Display metadata, stale warning banner (`checked_at > threshold`), CTAs for "Run bulk check" and docs.
5. **Integration Tests**
   - Router tests for scope/pipeline; LiveView tests for mount, data load, empty states, and auth redirect.

## Deliverables
- Router changes + documentation of auth scope
- `DashboardSerpLandscapeLive` module + HEEx template
- Tests verifying auth, data loading, and empty states
