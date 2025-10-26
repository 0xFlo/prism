# Ticket #013: Finalise Dashboard LiveView Alignment

**Status**: ✅ Done (2025-10-19)
**Estimate**: 2 hours
**Priority**: 🟡 Medium
**Dependencies**: Dashboard cleanup (#008) completed

---

## Problem Statement

After removing the `Dashboard` delegations, the LiveView integration suite still targeted the old markup and data plumbing. Tests were failing due to stale selectors, legacy copy ("No URLs found" vs. new empty state copy), and missing lifetime stat seeding.

---

## Acceptance Criteria

- [x] Dashboard integration tests cover the new UI semantics (`#search-input`, pagination buttons, etc.).
- [x] Empty-state assertions match the current copy rendered by `<.url_table>`.
- [x] Integration tests seed `url_lifetime_stats` so `ContentInsights.UrlPerformance.list/1` behaves as expected.
- [x] `mix test test/gsc_analytics_web/live/dashboard_live_integration_test.exs` passes without flakes.

---

## Outcome

- Updated test selectors and assertions to reflect the refactored markup (`Tools/gsc_analytics/test/gsc_analytics_web/live/dashboard_live_integration_test.exs`).
- Added an explicit empty-state row to `<.url_table>` so the UI communicates "No URLs found for the current filters" and tests can assert on that (`Tools/gsc_analytics/lib/gsc_analytics_web/components/dashboard_components.ex`).
- Enhanced the test seeding helper to populate `url_lifetime_stats` alongside `gsc_time_series`, removing the dependency on legacy `Dashboard` helpers.
- Verified `mix test test/gsc_analytics_web/live/dashboard_live_integration_test.exs` succeeds.

---

## Implementation Notes

1. Extend `populate_time_series_data/3` to insert matching lifetime rows.
2. Align LiveView assertions with new selectors (`#search-input`, `button[phx-click=next_page]`, etc.).
3. Adjust empty-state assertions to match the new messaging.
4. Run the targeted test and document the command in this ticket.

---

## Test Log

```bash
mix test test/gsc_analytics_web/live/dashboard_live_integration_test.exs
```

