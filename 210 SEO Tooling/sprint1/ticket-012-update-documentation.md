# Ticket #012: Update Documentation and Architecture Notes

**Status**: ⏳ Blocked (awaiting #009-#010)
**Estimate**: 1 hour
**Priority**: 🟢 Medium
**Phase**: 3 (Wrap-up)
**Dependencies**: #002-#010 (all refactors complete)

---

## Problem Statement

After the refactor, documentation (`CLAUDE.md`, sprint notes, architecture overviews) still reference the old `Dashboard` monolith. We need to document the new contexts and aggregation pipeline so teammates know where to look.

---

## Solution

Refresh developer guidance and architecture docs to reflect the new module layout and performance characteristics.

---

## Acceptance Criteria

- [ ] Update `CLAUDE.md` with new context structure and public APIs
- [ ] Add architecture notes summarizing the new `ContentInsights` and `Analytics` modules
- [ ] Document benchmark results from ticket #010 (before/after numbers)
- [ ] Update sprint README and board links if necessary
- [ ] Ensure documentation references `ContentInsights` instead of `Dashboard` for URL insights/keywords
- [ ] All doc changes committed alongside changelog entry (if applicable)

---

## Current Notes

- Blocked until performance work (#009) and benchmarking (#010) finish so we can include final metrics.
- Capture module diffs already merged (tickets #001-#007, #011) for architecture diagrams to avoid re-scraping git history later.

---

## Implementation Tasks

1. `docs/claude_code_sdk_setup.md` – ensure examples reference the new contexts.
2. `CLAUDE.md` – update architecture overview, command examples, and LiveView guidance.
3. Create `docs/architecture/content_insights.md` summarizing responsibilities of each new module.
4. Append benchmark table to `docs/performance.md` (or create if absent) with weekly/monthly aggregation timings pre/post refactor.
5. Update sprint README/board if the final structure changes (module counts, metric targets).

---

## Testing Strategy

- Manual review of markdown rendering
- Run `mix docs` (if configured) to ensure no warnings
- Have a teammate sanity-check updated docs for clarity

---

## Rollback Plan

Revert documentation commit. No runtime code changes involved.
