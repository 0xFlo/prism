# Ticket-006: Competitor Landscape Heatmap

## Status: TODO
**Priority:** P2
**Estimate:** 5 pts
**Dependencies:** ticket-003
**Blocks:** ticket-008

## Problem Statement
Analysts need a cross-keyword view of which domains appear in the top 10 positions. We must aggregate competitor positions across snapshots and render a heatmap that highlights ScrapFly while staying performant.

## Goals
- Implement `SerpLandscape.competitor_positions/2` returning domains × keywords with position + average rank data
- Build `<.competitor_heatmap>` Phoenix component with Tailwind-based color scale, tooltips, and ScrapFly highlighting
- Cap domains (e.g., top 20 by impressions) and provide pagination or scroll behavior for large sets
- Support CSV export hook for downstream analysis

## Acceptance Criteria
- [ ] Aggregation helper returns sorted domains with per-keyword positions (nil when absent) and average rank values
- [ ] Component renders grid with consistent color scale (position 1 dark green → position 10 light yellow → nil gray)
- [ ] ScrapFly domain row pinned/highlighted even if outside top 20 (if missing, show empty row)
- [ ] Tooltips show keyword + exact position on hover/focus; accessible for keyboard users
- [ ] Optional CSV export triggered via header action and reuses aggregation output

## Implementation Plan
1. **Aggregation**
   - Extend `SerpLandscape` context to compute competitor matrix grouped by domain, limited via config; include metadata (avg position, appearances).
2. **Component**
   - Build heatmap component with `for` comprehension generating rows/columns; add legend and average column.
3. **Highlighting**
   - Detect ScrapFly domain (config) and apply brand classes; ensure row pinned to top or bottom depending on presence.
4. **Accessibility**
   - Provide `aria-labels`, keyboard focus wrappers, and tooltips (Phoenix.Component or headless UI pattern).
5. **Tests**
   - Unit tests for aggregation sorting + limiting; component render test verifying color classes + pinned row.

## Deliverables
- Aggregation helpers with tests
- Heatmap component + CSS/legend
- Optional CSV export builder + documentation
