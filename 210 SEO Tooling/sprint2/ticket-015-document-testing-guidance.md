# Ticket #015: Document New Testing Workflow

**Status**: 📋 Todo
**Estimate**: 1 hour
**Priority**: 🟡 Medium
**Dependencies**: #013, #014

---

## Problem Statement

With the dashboard refactor complete, the testing workflow has changed (new selectors, opt-in performance suite). Existing docs still reference the legacy `Dashboard` API and `test/verify_phase2.exs`. We need updated guidance so contributors know which commands to run and how to enable the performance harness.

---

## Acceptance Criteria

- [ ] `CLAUDE.md` (and/or CONTRIBUTING) describes the new contexts (`ContentInsights`, `Analytics`) and how to run the relevant tests.
- [ ] Usage notes for the opt-in performance suite (`mix test --only performance`) are documented.
- [ ] Outdated references to `Dashboard.list_*` or `test/verify_phase2.exs` removed or replaced.
- [ ] Docs mention the new empty-state message and selectors where it aids testing.

---

## Implementation Tasks

1. Update testing commands and examples in `CLAUDE.md`.
2. Add a short “Performance Harness” section describing prerequisites and the new tag.
3. Search for legacy references (`Dashboard.list_urls`, `list_urls_v2`, `verify_phase2.exs`) and replace them with context API documentation.
4. Run spellcheck/markdown lint (if available) and note the command in this ticket.

---

## Verification

- [ ] Manual review of rendered Markdown (via editor/preview).
- [ ] Optional: `mix test --only docs` or `npm run lint:md` (if configured).

