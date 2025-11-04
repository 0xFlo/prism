# Sprint Planning Usage Guide

This directory contains the complete sprint plan for refactoring `sync.ex` into a pipeline architecture.

## 📂 File Structure

```
sprint-planning/refactor-sprint/
├── README.md                        # Sprint overview with status tracking
├── USAGE.md                         # This file
├── .update-status.sh                # Helper script to update ticket status
├── TICKET-001-state-foundation.md
├── TICKET-002-progress-tracker.md
├── TICKET-003-url-phase.md
├── TICKET-004-query-phase.md
├── TICKET-005-pipeline.md
└── TICKET-006-integration-cleanup.md
```

## 🎯 How to Use This Sprint Plan

### 1. Start with the Overview

Read `README.md` to understand:
- Sprint goals and success criteria
- Ticket dependencies
- Status overview table
- Progress log

### 2. Work Through Tickets Sequentially

Tickets **MUST** be completed in order due to dependencies:

```
001 (Foundation)
  ↓
002 (Progress Tracker)
  ↓
003 (URL Phase) ─┐
004 (Query Phase)─┤→ 005 (Pipeline) → 006 (Integration)
```

### 3. For Each Ticket

1. **Read the ticket file** (e.g., `TICKET-001-state-foundation.md`)
2. **Follow implementation steps** - code examples provided
3. **Run tests** after each change
4. **Update progress** in README.md
5. **Commit** when all success criteria met
6. **Move to next ticket**

### 4. Update Status

Edit `README.md` and:
1. Update the status emoji in the table
2. Update the status emoji in the tickets list
3. Check off items in the Progress Log
4. Add notes/blockers if needed

**Status Emojis:**
- ⚪ Not Started
- 🔵 In Progress
- ✅ Complete
- ❌ Blocked

### 5. Track Progress in Each Ticket

Each ticket has a **"What was done"** section with checkboxes. Update these as you complete each step:

```markdown
**What was done:**
- [x] Created `Sync.State` module with typed struct
- [x] Replaced Process dictionary with Agent-based metrics
- [ ] Pre-calculated date-to-step mapping in state initialization
```

Add notes about challenges, decisions, or changes:

```markdown
**Blockers/Notes:**
- Had to adjust Agent cleanup timing due to test interference
- Added extra validation in State.new for edge cases
```

## 📊 Tracking Sprint Progress

### Overall Progress

Check `README.md` "Sprint Status Overview" table:
- Shows completion percentage
- Shows total hours (estimated vs actual)
- Color-coded status

### Individual Ticket Progress

Each ticket section in Progress Log shows:
- Status emoji
- Checkbox for each implementation step
- Notes about blockers or decisions

### Commit Strategy

**Recommended approach:**
- One commit per ticket
- Use the provided commit message template
- Reference ticket number in commit (e.g., "Closes TICKET-001")

**Example:**
```bash
git add .
git commit -m "refactor(sync): Replace Process dictionary with SyncState struct

- Create Sync.State module with explicit struct
- Add Agent-based metrics storage for query counts
- Pre-calculate date-to-step mapping
- Replace ad-hoc map with typed state
- Add proper cleanup for Agent processes

Closes TICKET-001"
```

## ✅ Success Checklist (Per Ticket)

Before marking a ticket complete:

- [ ] All implementation steps completed
- [ ] All checkboxes in ticket checked
- [ ] Tests passing (`mix test`)
- [ ] No compiler warnings (`mix compile`)
- [ ] Code formatted (`mix format`)
- [ ] Commit created with template message
- [ ] Status updated in README.md
- [ ] Notes added if any deviations from plan

## 🚨 If Things Go Wrong

### Tests Failing

1. Check which test is failing
2. Compare behavior before/after
3. Review the specific section in the ticket
4. Add notes to Progress Log
5. Consider rolling back if stuck

### Blocked by Design Issue

1. Mark ticket as ❌ Blocked in README.md
2. Add detailed notes to Progress Log
3. Review original code review findings
4. Discuss design alternatives
5. Update ticket with solution before proceeding

### Need to Deviate from Plan

1. Document deviation in Progress Log
2. Explain why (better approach found, unforeseen issue)
3. Update ticket steps if needed
4. Ensure tests still pass
5. Note in commit message

## 📝 Example Workflow

```bash
# 1. Read the ticket
cat sprint-planning/refactor-sprint/TICKET-001-state-foundation.md

# 2. Update status in README.md (change ⚪ to 🔵)

# 3. Implement step by step
# ... coding ...

# 4. Test after each step
mix test test/gsc_analytics/data_sources/gsc/core/sync_test.exs

# 5. Update Progress Log in README.md (check off completed items)

# 6. Commit when complete
git add .
git commit -m "refactor(sync): Replace Process dictionary with SyncState struct

Closes TICKET-001"

# 7. Update status to ✅ Complete in README.md

# 8. Move to next ticket
cat sprint-planning/refactor-sprint/TICKET-002-progress-tracker.md
```

## 🎯 Tips for Success

1. **Read entire ticket first** - understand all steps before starting
2. **Test frequently** - after each major change
3. **Commit atomically** - one ticket = one commit
4. **Document deviations** - track why you diverged from plan
5. **Update progress** - keep README.md current
6. **Take breaks** - between tickets is a good time
7. **Review previous tickets** - to maintain consistency

## 🎉 Sprint Completion

When all tickets are ✅ Complete:

1. Verify "Sprint Status Overview" shows 100%
2. Run full test suite one final time
3. Review all Progress Log notes
4. Check that all blockers resolved
5. Celebrate! 🎊

The refactoring is complete when:
- All 6 tickets have ✅ status
- All tests passing
- Documentation updated
- Code committed
