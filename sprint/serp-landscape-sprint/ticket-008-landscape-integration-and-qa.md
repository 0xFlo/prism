# Ticket-008: Landscape Integration & QA

## Status: TODO
**Priority:** P2
**Estimate:** 3 pts
**Dependencies:** ticket-001, ticket-002, ticket-003, ticket-004, ticket-005, ticket-006, ticket-007
**Blocks:** None

## Problem Statement
After the individual panels and data plumbing are complete we need to integrate them into the new LiveView, rehearse migrations/backfills, and run QA (automated + manual + performance) before shipping.

## Goals
- Wire AI Overview, competitor heatmap, and content-type components into the SERP Landscape LiveView with cohesive layout
- Validate migrations/backfills in staging-like data and document rollback steps
- Execute automated tests (unit/integration/perf) plus manual checklist covering various SERP scenarios
- Capture telemetry + dashboards for ongoing monitoring

## Acceptance Criteria
- [ ] Landscape page loads all three panels with real snapshot fixtures and remains responsive (<1s idle CPU) for 50+ keywords
- [ ] Backfill task rehearsed against a copy of production data; runtime + resource usage documented, rollback tested
- [ ] `mix test`, targeted LiveView/component tests, and performance probes (aggregation + rendering) run and recorded
- [ ] Manual checklist (from RFC) completed, issues triaged, and sign-off recorded in README
- [ ] Telemetry dashboards updated (or created) to monitor job counts, AI Overview rates, and page load timings post-deploy

## Implementation Plan
1. **LiveView Integration**
   - Compose the header + three panel components, ensuring assigns/wiring consistent; add stream resets when PubSub indicates new data.
2. **Migration Rehearsal**
   - Run migration/backfill on staging DB snapshot; record timings, CPU, disk usage; validate data correctness using SQL spot checks.
3. **Testing Sweep**
   - Execute `mix test`, targeted component tests, and maybe `mix test --include serp_landscape`; run load scripts for aggregator queries.
4. **Manual QA**
   - Follow checklist (AI Overview present/absent, no rank, etc.); capture screenshots/gifs for release notes.
5. **Telemetry & Docs**
   - Ensure telemetry metrics feed Grafana/Datadog; update README + release plan with deployment steps and fallback instructions.

## Deliverables
- Integrated LiveView layout + styles
- QA checklist results + migration rehearsal notes
- Updated docs/telemetry dashboards ready for launch
