# Ticket-004: AI Overview Intelligence Service & Panel

## Status: TODO
**Priority:** P1
**Estimate:** 8 pts
**Dependencies:** ticket-003
**Blocks:** ticket-005, ticket-008

## Problem Statement
We lack a consolidated service to compute AI Overview presence, citations, and ScrapFly mentions across multiple keywords. The new dashboard requires aggregated metrics plus UI components that highlight ScrapFly citations and handle empty/error states.

## Goals
- Implement `ContentInsights.SerpLandscape` context functions (`ai_overview_stats/2`, `citation_table/2`, etc.) that respect `current_scope`
- Cache expensive aggregates to avoid re-querying on every LiveView render
- Build `<.ai_overview_panel>` component with ScrapFly highlighting, keyword filters, and expandable AI text snippets
- Provide empty/error state messaging and export hooks

## Acceptance Criteria
- [ ] Context functions accept `(current_scope, target_url)` and use Repo queries filtered by scope + property
- [ ] Aggregations cached for ≥1 minute (configurable) and invalidated when new snapshots arrive
- [ ] Panel displays presence percentage, citation table (domain, count, keywords), and ScrapFly highlight with brand styling
- [ ] Expand/collapse reveals sanitized AI Overview text per keyword; large payloads truncated safely
- [ ] Empty-state cards instruct users to re-run checks when AI Overviews or citations are absent

## Implementation Plan
1. **Context Module**
   - Create `ContentInsights.SerpLandscape` with functions for AI overview stats, citation table, and text sample retrieval.
   - Use ETS/cache + `current_scope` as part of cache key; instrument queries with telemetry.
2. **Caching & Invalidations**
   - Add simple cache helper keyed by `#{account_id}-#{url}` and expire on PubSub message when new snapshots finish.
3. **Component**
   - Build `<.ai_overview_panel>` in `serp_components.ex` with slots for cards, tables, text accordions; pass snapshots or aggregated structs.
4. **Sanitization**
   - Use Phoenix.HTML sanitization (strip scripts) before rendering AI text; limit to e.g. 600 chars per snippet with "View full" link.
5. **Testing**
   - Unit tests for aggregation math + caching, component render tests with `Phoenix.Component` assertions, and integration test hooking LiveView + context.

## Deliverables
- `ContentInsights.SerpLandscape` context with caching + telemetry
- `<.ai_overview_panel>` component + styles/tests
- Documentation describing API, caching, invalidation, and expected assigns
