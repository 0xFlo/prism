# 🚀 Get Started: ScrapFly SERP Integration Sprint

**Sprint Goal:** Integrate ScrapFly API for real-time SERP position checking

---

## ⚡ Quick Start

### 1. Review the Sprint
```bash
# Read the sprint overview
cat /Users/flor/Developer/prism/sprint-planning/scraping-support/README.md

# Check Codex architecture review
cat /Users/flor/Developer/prism/sprint-planning/scraping-support/docs/RESEARCH_SUMMARY.md

# Review sprint board
cat /Users/flor/Developer/prism/sprint-planning/scraping-support/SPRINT_BOARD.md
```

### 2. Start with T001
```bash
# Open the first ticket
cat /Users/flor/Developer/prism/sprint-planning/scraping-support/T001-create-serp-directory.md

# Execute the ticket (with Claude Code)
# Just say: "Let's start T001"
```

### 3. Track Progress
```bash
# Update the sprint board after each ticket
cat /Users/flor/Developer/prism/sprint-planning/scraping-support/SPRINT_BOARD.md
```

---

## 📁 Directory Structure

```
/Users/flor/Developer/prism/sprint-planning/scraping-support/
├── docs/
│   ├── DOCUMENTATION_INDEX.md        # Central hub for all documentation
│   └── RESEARCH_SUMMARY.md           # Codex architecture review
├── README.md                         # Sprint overview
├── SPRINT_BOARD.md                   # Active tracking board
├── GET_STARTED.md                    # This file
├── T001-create-serp-directory.md     # Infrastructure tickets
├── T002-scrapfly-config.md
├── T003-ecto-schema.md
├── T004-database-migration.md
├── T005-req-http-client-tdd.md       # TDD tickets
├── T006-json-parser-tdd.md
├── T007-persistence-layer.md
├── T008-rate-limiter-tdd.md          # TDD tickets
├── T009-oban-worker-tdd.md
├── T010-integration-tests-tdd.md
├── T011-dashboard-integration.md     # UI tickets
├── T012-serp-visualization.md
├── T013-data-pruning-worker.md       # Maintenance
└── T014-manual-verification.md       # Finalization
```

---

## 📚 Research Documentation

**All research documentation ready!**

### Primary Documents (in /Users/flor/Developer/prism/docs/):
- **OBAN_REFERENCE.md** (41KB) - Complete Oban v2.20.1 guide
- **elixir-tdd-research.md** (41KB) - TDD workflows and patterns
- **testing-quick-reference.md** (13KB) - Quick lookup for tests
- **phoenix-ecto-research.md** (35KB) - Phoenix/Ecto patterns
- **elixir_error_handling_research.md** (45KB) - Error handling guide

### External Resources:
- **Req HTTP Client** - [HexDocs](https://hexdocs.pm/req)
- **ScrapFly SERP API** - [Official Docs](https://scrapfly.io/docs/scrape-api/serp)
- **Codex Review** - [Research Summary](docs/RESEARCH_SUMMARY.md)

### Quick Access:
```bash
# View documentation index
cat /Users/flor/Developer/prism/sprint-planning/scraping-support/docs/DOCUMENTATION_INDEX.md

# Open specific research doc
cat /Users/flor/Developer/prism/docs/OBAN_REFERENCE.md
```

---

## 🎯 Execution Plan

### Phase 1: Infrastructure (Day 1)
- ✅ **T001:** Create SERP Directory Structure (1 point)
- ✅ **T002:** ScrapFly Config & Env Setup (1 point)
- ✅ **T003:** SerpSnapshot Ecto Schema (2 points)
- ✅ **T004:** Database Migration (2 points)

**Expected Duration:** 2-3 hours
**Deliverable:** Database schema and directory structure ready

### Phase 2: Core Logic with TDD (Day 2)
- ✅ **T005:** Req HTTP Client - TDD (3 points)
  - 🔴 RED: Write failing tests for ScrapFly API
  - 🟢 GREEN: Implement Req client
  - 🔵 REFACTOR: Add retry logic
- ✅ **T006:** JSON Parser - TDD (2 points)
  - 🔴 RED: Write failing parser tests
  - 🟢 GREEN: Implement JSON parsing
  - 🔵 REFACTOR: Extract helpers
- ✅ **T007:** Persistence Layer (2 points)

**Expected Duration:** 4-5 hours
**Deliverable:** Working ScrapFly API integration with JSON parsing

### Phase 3: Background Jobs & Rate Limiting (Day 2-3)
- ✅ **T008:** Rate Limiter - TDD (2 points)
  - 🔴 RED: Write failing rate limiter tests
  - 🟢 GREEN: Implement quota tracking
  - 🔵 REFACTOR: Extract configuration
- ✅ **T009:** Oban SERP Worker - TDD (3 points)
  - 🔴 RED: Write failing worker tests
  - 🟢 GREEN: Implement worker with unique_periods
  - 🔵 REFACTOR: Extract job helpers
- ✅ **T010:** Integration Tests - TDD (2 points)
  - 🔴 RED: Write failing end-to-end tests
  - 🟢 GREEN: Verify components work together
  - 🔵 REFACTOR: Extract test helpers

**Expected Duration:** 4-5 hours
**Deliverable:** Async SERP checking with rate limiting and idempotency

### Phase 4: UI & Polish (Day 3-4)
- ✅ **T011:** Dashboard LiveView Integration (1 point)
- ✅ **T012:** SERP Visualization (1 point)
- ✅ **T013:** Data Pruning Worker (2 points)
- ✅ **T014:** Manual Verification (1 point)

**Expected Duration:** 3-4 hours
**Deliverable:** Production-ready SERP integration

---

## ✅ Pre-Flight Checklist

Before starting the sprint, verify:

- [ ] Project compiles: `mix compile`
- [ ] Tests pass: `mix test`
- [ ] Pre-commit works: `mix precommit`
- [ ] Database running: `psql -d gsc_analytics_dev -c "SELECT 1"`
- [ ] ScrapFly API key available: `echo $SCRAPFLY_API_KEY` (or set it)
- [ ] Documentation accessible: All docs in `/Users/flor/Developer/prism/docs/`
- [ ] Sprint planning reviewed: Read README.md
- [ ] Codex review read: Read RESEARCH_SUMMARY.md
- [ ] Understand Req client: Review [HexDocs](https://hexdocs.pm/req)

---

## 🎓 TDD Workflow Reminder

For tickets T005, T006, T008, T009, T010:

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

# Testing
mix test                                    # Run all tests
mix test test/path/to/test.exs              # Run specific test
mix test --failed                           # Re-run failed tests
mix test --cover                            # Coverage report
mix test --only tdd                         # Run only TDD tests

# Quality
mix compile --warnings-as-errors            # Strict compile
mix format                                  # Format code
mix precommit                               # Full pre-commit check

# Database
mix ecto.migrate                            # Run migrations
mix ecto.rollback                           # Rollback migration
MIX_ENV=test mix ecto.reset                 # Reset test DB

# Oban (in IEx)
Oban.check_queue(queue: :serp_check)        # Check queue status
GscAnalytics.Workers.SerpCheckWorker.new(%{
  property_id: 1,
  url: "https://example.com",
  keyword: "test query"
}) |> Oban.insert()                         # Manual job trigger

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
   - TDD: `/Users/flor/Developer/prism/docs/elixir-tdd-research.md`

3. **Check official sources**
   - Req: https://hexdocs.pm/req
   - ScrapFly SERP API: https://scrapfly.io/docs/scrape-api/serp
   - Oban: https://hexdocs.pm/oban

4. **Review Codex feedback**
   - Architecture concerns: `docs/RESEARCH_SUMMARY.md`

### Common Issues

**"Should I use :httpc or Req?"**
→ Use Req (Prism standard for new integrations)

**"How do I parse ScrapFly response?"**
→ It's JSON, use built-in `JSON.decode!/1` (Elixir 1.18+)

**"How do I prevent duplicate API calls?"**
→ Use Oban unique_periods with `{property_id, url, keyword, geo}` key

**"Tests failing with Oban.Testing"**
→ See docs/testing-quick-reference.md#oban for patterns

**"Rate limiter not working"**
→ Check Hammer ETS backend configuration

---

## 📊 Success Criteria

### Must Have (Sprint Complete)
- [ ] All P1 tickets completed (22 points)
- [ ] All automated tests passing
- [ ] `mix precommit` passes
- [ ] Req-based ScrapFly client working
- [ ] JSON parser extracts position accurately
- [ ] Oban worker processes jobs with idempotency
- [ ] Rate limiter prevents quota exhaustion
- [ ] LiveView button triggers SERP checks (with auth)
- [ ] Position displayed alongside GSC data
- [ ] 7-day auto-pruning works
- [ ] Documentation complete and accurate

### Nice to Have
- [ ] All P2 tickets completed (3 points)
- [ ] SERP position trend visualization
- [ ] Competitor analysis view
- [ ] Real-time progress updates via PubSub
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
2. For TDD tickets: RED → GREEN → REFACTOR
3. Reference documentation as needed
4. Update SPRINT_BOARD.md progress
5. Document blockers immediately

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

## 🚨 Important Reminders

### Codex Review Compliance
✅ Use Req (NOT :httpc)
✅ Parse JSON (NOT markdown)
✅ Use property_id foreign key (NOT just URLs)
✅ Add Oban unique_periods (prevent duplicates)
✅ LiveView routes under `live_session :require_authenticated_user`

### Cost Management
- 1 million free ScrapFly credits available
- ~31 credits per SERP query
- Rate limiter prevents accidental exhaustion
- Track costs in `api_cost` field

### Testing Requirements
- 95%+ coverage for new code
- TDD for: Client, Parser, Rate Limiter, Worker, Integration
- Test failure paths: API errors, quota exceeded, retries

---

## 🚦 Ready to Start?

**Everything is prepared. Just say:**

- **"Let's start T001"** - Begin the sprint
- **"Show me T001"** - Read the first ticket
- **"Check sprint status"** - View SPRINT_BOARD.md
- **"Open Codex review"** - Read RESEARCH_SUMMARY.md

---

**Sprint Duration:** 3-4 days
**Total Points:** 23
**TDD Tickets:** 5 (T005, T006, T008, T009, T010)
**Architecture:** Codex-reviewed ✅

**Let's build ScrapFly SERP integration! 🚀**
