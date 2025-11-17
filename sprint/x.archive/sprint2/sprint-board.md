# Sprint 2: Stabilise Testing & Performance Harness

**Sprint Goal**: Lock in the dashboard refactor by aligning automated coverage, reinstating the performance suite, and hardening the dashboard charts.

**Duration**: 1 week (flex)
**Start Date**: TBD
**End Date**: TBD

---

## Progress Snapshot

- ✅ Completed: #013, #016, #014 (5.5h total logged)
- 🔄 Next Up: #015 (1h planned)
- 📋 Pending: None
- Remaining Estimate: 3.5h capacity

---

## Sprint Backlog

| Ticket | Title | Estimate | Status | Dependencies | Assignee |
| --- | --- | --- | --- | --- | --- |
| [#013](./ticket-013-liveview-test-alignment.md) | Finalise Dashboard LiveView alignment | 2h | ✅ Done | Migration prep complete | flor |
| [#016](./ticket-016-performance-chart-refactor.md) | Refactor PerformanceChart hook & LiveView handoff | ~~5h~~ 2h actual | ✅ Done | #013 | flor |
| [#014](./ticket-014-performance-harness-refresh.md) | Refresh performance harness & opt-in suite | ~~4h~~ 1.5h actual | ✅ Done | #013 | flor |
| [#015](./ticket-015-document-testing-guidance.md) | Update docs for new testing workflow | 1h | 🔄 Next Up | #013, #014, #016 | flor |

### Future Sprint

| Ticket | Title | Estimate | Status | Dependencies | Assignee |
| --- | --- | --- | --- | --- | --- |
| [#017](./ticket-017-javascript-testing-infrastructure.md) | JavaScript Testing Infrastructure | 3h | 📋 Future | #016 | TBD |

---

## Prioritization Notes

**Reordered on 2025-10-19**: Moved #016 (PerformanceChart refactor) ahead of #014 (performance harness) to maximize user impact. The chart refactor delivers immediate production value by eliminating double aggregation and improving dashboard performance, while the test harness is developer-facing and can wait.

**Technical Discovery (2025-10-19)**: During #016 investigation, discovered that adding Jest requires bootstrapping a full Node.js toolchain (Phoenix 1.8 uses esbuild via Elixir, no npm by default). Deferred Jest testing to future ticket #017 to keep sprint on track. Revised #016 from 5h to 4h.

**Faster Completion (2025-10-19)**: #016 completed in 2h instead of 4h estimate. Found that previous refactoring work had already extracted some modules and optimized JSON encoding. Main work focused on removing client-side sorting and creating additional geometry/drawing modules.

**Exceptional Sprint Velocity (2025-10-19)**: #014 completed in 1.5h instead of 4h estimate. Performance test suite was mostly working already - just needed minor fixes for SQL queries and test isolation. Sprint running at ~250% efficiency (5.5h actual vs 11h estimated for 3 tickets).

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| LiveView tests still rely on brittle markup selectors | Medium | Introduce `data-test` hooks or helper functions during #013 ✅ |
| Jest setup for #016 might add complexity | Low | Timebox to 1h; defer advanced testing to follow-up if needed |
| Chart refactor could introduce visual regressions | Medium | Manual QA of weekly/monthly views before marking complete |
| Performance harness remains flaky / slow | High | Limit dataset size, chunk inserts, gate behind `--only performance` (#014) |
| Docs lag behind new workflow | Medium | Capture commands + opt-in instructions in #015 |

---

## Definition of Done

1. ✅ Ticket acceptance criteria met with evidence in ticket file.
2. ✅ Targeted test suites run (and noted) for each change.
3. ✅ Documentation updated where behaviour or workflow changes (#015).
4. ✅ No new compiler warnings; CI-friendly by default (performance suite opt-in).
5. ✅ Sprint board updated with final status before closing.
