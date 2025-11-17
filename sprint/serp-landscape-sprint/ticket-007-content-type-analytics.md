# Ticket-007: Content-Type Distribution Analytics

## Status: TODO
**Priority:** P2
**Estimate:** 3 pts
**Dependencies:** ticket-003
**Blocks:** ticket-008

## Problem Statement
We need to summarize which content types (Reddit, YouTube, forums, PAA, websites, etc.) dominate the SERP across keywords so users can quickly tell if UGC is crowding them out.

## Goals
- Implement `SerpLandscape.content_type_distribution/2` returning counts, percentages, average positions, and example domains per type
- Create `<.content_type_chart>` component (pie/donut) plus a table view reusing the PerformanceChart pattern
- Provide filters (e.g., include/exclude AI Overview, show only UGC) and informative empty states

## Acceptance Criteria
- [ ] Aggregation helper returns a struct with `type`, `count`, `percentage`, `avg_position`, `example_domains`
- [ ] Component renders donut chart with legend + color palette consistent with existing charts
- [ ] Table lists each content type, average position, count, and clickable example domain chips
- [ ] Empty-state message shown when there are fewer than 3 results or only one type present
- [ ] Component covered by tests (assign validation + render) and documented in storybook or design system

## Implementation Plan
1. **Aggregation Function**
   - Use new `content_type` metadata in competitors to compute per-type stats; include ability to group "unknown".
2. **Chart Component**
   - Follow PerformanceChart approach; expose `data` and `config` assigns; include tooltip percentages.
3. **Table View**
   - Add sortable columns (count, avg position); render example domains with ellipsis for >3 entries.
4. **Filters & Empty State**
   - Add filter controls (checkboxes) to exclude AI Overview or show only `ugc`; default to all.
5. **Tests**
   - Unit test verifying percentages sum to 100 (± rounding), chart component render, and filter behavior.

## Deliverables
- Aggregation helper + tests
- Chart + table components with filters/empty state messaging
- Documentation snippet referencing data interpretation guidance
