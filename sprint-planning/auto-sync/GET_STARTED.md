# 🚀 Get Started: Auto-Sync Sprint

**Sprint Goal:** Implement automatic GSC sync every 6 hours using Oban

---

## ⚡ Quick Start

### 1. Review the Sprint
```bash
# Read the sprint overview
cat /Users/flor/Developer/prism/sprint-planning/auto-sync/README.md

# Check the documentation index
cat /Users/flor/Developer/prism/sprint-planning/auto-sync/docs/DOCUMENTATION_INDEX.md

# Review research summary
cat /Users/flor/Developer/prism/sprint-planning/auto-sync/docs/RESEARCH_SUMMARY.md
```

### 2. Start with T001
```bash
# Open the first ticket
cat /Users/flor/Developer/prism/sprint-planning/auto-sync/T001-add-oban-dependency.md

# Execute the ticket (with Claude Code)
# Just say: "Let's start T001"
```

### 3. Track Progress
```bash
# Update the sprint board after each ticket
cat /Users/flor/Developer/prism/sprint-planning/auto-sync/SPRINT_BOARD.md
```

---

## 📁 Directory Structure

```
/Users/flor/Developer/prism/sprint-planning/auto-sync/
├── docs/
│   ├── DOCUMENTATION_INDEX.md        # Central hub for all documentation
│   └── RESEARCH_SUMMARY.md           # Research findings and metrics
├── README.md                         # Sprint overview
├── SPRINT_BOARD.md                   # Active tracking board
├── GET_STARTED.md                    # This file
├── T001-add-oban-dependency.md       # Infrastructure tickets
├── T002-create-oban-migration.md
├── T003-configure-oban.md
├── T004-update-supervision-tree.md
├── T005-workspace-iterator-tdd.md    # TDD tickets
├── T006-oban-worker-tdd.md
├── T007-error-handling.md            # Enhancement tickets
├── T008-telemetry-integration.md
├── T009-environment-gating-tdd.md    # TDD tickets
├── T010-integration-tests-tdd.md
├── T011-documentation.md             # Finalization tickets
└── T012-manual-verification.md
```

---

## 📚 Research Documentation

**All research complete! 270KB of documentation ready.**

### Primary Documents (in /Users/flor/Developer/prism/docs/):
- **OBAN_REFERENCE.md** (41KB) - Complete Oban v2.20.1 guide
- **elixir-tdd-research.md** (41KB) - TDD workflows and patterns
- **testing-quick-reference.md** (13KB) - Quick lookup for tests
- **phoenix-ecto-research.md** (35KB) - Phoenix/Ecto patterns
- **elixir_error_handling_research.md** (45KB) - Error handling guide
- **cron-scheduling-research.md** (28KB) - Scheduling best practices
- **ENVIRONMENT_CONFIG_RESEARCH.md** (32KB) - Configuration patterns

### Quick Access:
```bash
# View documentation index
cat /Users/flor/Developer/prism/sprint-planning/auto-sync/docs/DOCUMENTATION_INDEX.md

# Open specific research doc
cat /Users/flor/Developer/prism/docs/OBAN_REFERENCE.md
```

---

## 🎯 Execution Plan

### Phase 1: Infrastructure (Day 1)
- ✅ **T001:** Add Oban Dependency (1 point)
- ✅ **T002:** Create Oban Migration (1 point)
- ✅ **T003:** Configure Oban (2 points)
- ✅ **T004:** Update Supervision Tree (1 point)

**Expected Duration:** 2-3 hours
**Deliverable:** Oban installed and running

### Phase 2: Core Logic with TDD (Day 2)
- ✅ **T005:** Workspace Iterator - TDD (3 points)
  - 🔴 RED: Write failing tests
  - 🟢 GREEN: Implement minimum code
  - 🔵 REFACTOR: Clean up
- ✅ **T009:** Environment Gating - TDD (2 points)
  - 🔴 RED: Write failing tests
  - 🟢 GREEN: Implement config helper
  - 🔵 REFACTOR: Add logging

**Expected Duration:** 3-4 hours
**Deliverable:** Workspace sync logic with environment control

### Phase 3: Worker & Testing (Day 2-3)
- ✅ **T006:** Oban Worker - TDD (3 points)
  - 🔴 RED: Write failing worker tests
  - 🟢 GREEN: Implement worker
  - 🔵 REFACTOR: Extract helpers
- ✅ **T010:** Integration Tests - TDD (3 points)
  - 🔴 RED: Write failing integration tests
  - 🟢 GREEN: Verify components work together
  - 🔵 REFACTOR: Extract test helpers

**Expected Duration:** 4-5 hours
**Deliverable:** Working auto-sync with comprehensive tests

### Phase 4: Polish (Day 3 - Optional)
- ⚪ **T007:** Error Handling (2 points)
- ⚪ **T008:** Telemetry Integration (2 points)
- ⚪ **T011:** Documentation (2 points)
- ⚪ **T012:** Manual Verification (2 points)

**Expected Duration:** 3-4 hours
**Deliverable:** Production-ready auto-sync

---

## ✅ Pre-Flight Checklist

Before starting the sprint, verify:

- [ ] Project compiles: `mix compile`
- [ ] Tests pass: `mix test`
- [ ] Pre-commit works: `mix precommit`
- [ ] Database running: `psql -d gsc_analytics_dev -c "SELECT 1"`
- [ ] Documentation accessible: All docs in `/Users/flor/Developer/prism/docs/`
- [ ] Sprint planning reviewed: Read README.md
- [ ] Research reviewed: Read RESEARCH_SUMMARY.md

---

## 🎓 TDD Workflow Reminder

For tickets T005, T006, T009, T010:

### 🔴 RED Phase
1. Write tests FIRST
2. Run tests (`mix test`)
3. Confirm they FAIL
4. Understand WHY they fail

### 🟢 GREEN Phase
1. Write MINIMUM code to pass
2. Run tests (`mix test`)
3. Confirm they PASS
4. No more, no less

### 🔵 REFACTOR Phase
1. Improve code quality
2. Extract functions
3. Add documentation
4. Run tests after each change
5. Keep tests PASSING

**Never skip phases. Never write code before tests (for TDD tickets).**

---

## 🔥 Hot Commands

```bash
# Development
mix phx.server                              # Start server
ENABLE_AUTO_SYNC=true mix phx.server        # Start with auto-sync

# Testing
mix test                                    # Run all tests
mix test test/path/to/test.exs              # Run specific test
mix test --failed                           # Re-run failed tests
mix test --cover                            # Coverage report

# Quality
mix compile --warnings-as-errors            # Strict compile
mix format                                  # Format code
mix precommit                               # Full pre-commit check

# Database
mix ecto.migrate                            # Run migrations
mix ecto.rollback                           # Rollback migration
MIX_ENV=test mix ecto.reset                 # Reset test DB

# Oban (in IEx)
Oban.check_queue(queue: :gsc_sync)          # Check queue status
GscSyncWorker.new(%{}) |> Oban.insert()     # Manual job trigger

# Documentation
cat docs/DOCUMENTATION_INDEX.md             # View doc index
cat docs/testing-quick-reference.md         # Quick test lookup
```

---

## 🆘 Getting Help

### During Implementation

1. **Check ticket documentation links**
   - Every ticket has "Reference Documentation" section
   - Links to relevant research docs

2. **Use quick reference guides**
   - Testing: `/Users/flor/Developer/prism/docs/testing-quick-reference.md`
   - Oban: `/Users/flor/Developer/prism/docs/OBAN_REFERENCE.md`

3. **Search research docs**
   - All docs have table of contents
   - Ctrl+F for specific topics

4. **Check official sources**
   - All docs include official URLs
   - HexDocs for API reference

### Common Issues

**"Tests failing"**
→ Check Testing Quick Reference for patterns

**"Oban not starting"**
→ Check OBAN_REFERENCE.md troubleshooting section

**"Config not working"**
→ Check ENVIRONMENT_CONFIG_RESEARCH.md

**"Mox expectation failures"**
→ See docs/testing-quick-reference.md#mox for fix patterns

---

## 📊 Success Criteria

### Must Have (Sprint Complete)
- [ ] All P1 tickets completed (16 points)
- [ ] All automated tests passing
- [ ] `mix precommit` passes
- [ ] Auto-sync runs successfully every 6 hours
- [ ] Environment variable controls behavior
- [ ] Documentation complete and accurate

### Nice to Have
- [ ] All P2 tickets completed (8 points)
- [ ] Circuit breaker implemented
- [ ] Health check endpoint working
- [ ] Log analysis tool functional
- [ ] >95% test coverage

---

## 🎯 Daily Workflow

### Start of Day
1. Review SPRINT_BOARD.md
2. Pick next ticket from Backlog
3. Read ticket + reference docs
4. Mark as "In Progress"

### During Ticket
1. Follow ticket implementation steps
2. Reference documentation as needed
3. Update SPRINT_BOARD.md progress
4. Document blockers immediately

### End of Ticket
1. Run `mix precommit`
2. Mark ticket "Completed" in SPRINT_BOARD.md
3. Update test coverage metrics
4. Note any learnings or issues

### End of Day
1. Update daily progress in SPRINT_BOARD.md
2. Document blockers for next day
3. Commit sprint board changes

---

## 🚦 Ready to Start?

**Everything is prepared. Just say:**

- **"Let's start T001"** - Begin the sprint
- **"Show me T001"** - Read the first ticket
- **"Check sprint status"** - View SPRINT_BOARD.md
- **"Open Oban docs"** - Read OBAN_REFERENCE.md

---

**Sprint Duration:** 2-3 days
**Total Points:** 21
**TDD Tickets:** 4 (T005, T006, T009, T010)
**Documentation:** 270KB ready

**Let's build automatic GSC sync! 🚀**
