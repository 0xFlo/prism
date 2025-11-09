# Documentation Index - ScrapFly SERP Integration

**Sprint:** ScrapFly SERP Integration
**Last Updated:** 2025-01-09

---

## 📚 Core Documentation

All primary documentation is located in `/Users/flor/Developer/prism/docs/`

### Oban (Job Queue)
- **File:** [OBAN_REFERENCE.md](/Users/flor/Developer/prism/docs/OBAN_REFERENCE.md)
- **Size:** 41KB
- **Version:** v2.20.1
- **Topics:**
  - Job queues and workers
  - Cron scheduling
  - unique_periods for idempotency ⭐ (Critical for T009)
  - Testing with Oban.Testing
  - Error handling and retries

### Test-Driven Development
- **File:** [elixir-tdd-research.md](/Users/flor/Developer/prism/docs/elixir-tdd-research.md)
- **Size:** 41KB
- **Topics:**
  - RED → GREEN → REFACTOR workflow
  - ExUnit patterns
  - Mox for mocking
  - Test organization

### Testing Quick Reference
- **File:** [testing-quick-reference.md](/Users/flor/Developer/prism/docs/testing-quick-reference.md)
- **Size:** 13KB
- **Topics:**
  - Quick lookup patterns
  - Common test assertions
  - Oban.Testing examples
  - Mox setup

### Phoenix & Ecto
- **File:** [phoenix-ecto-research.md](/Users/flor/Developer/prism/docs/phoenix-ecto-research.md)
- **Size:** 35KB
- **Topics:**
  - Ecto schemas and changesets
  - Query composition
  - LiveView patterns
  - PubSub integration

### Error Handling
- **File:** [elixir_error_handling_research.md](/Users/flor/Developer/prism/docs/elixir_error_handling_research.md)
- **Size:** 45KB
- **Topics:**
  - Error handling patterns
  - Retry logic
  - Circuit breakers
  - Resilience strategies

### Cron Scheduling
- **File:** [cron-scheduling-research.md](/Users/flor/Developer/prism/docs/cron-scheduling-research.md)
- **Size:** 28KB
- **Topics:**
  - Crontab syntax
  - Oban.Plugins.Cron
  - Scheduling best practices

### Environment Configuration
- **File:** [ENVIRONMENT_CONFIG_RESEARCH.md](/Users/flor/Developer/prism/ENVIRONMENT_CONFIG_RESEARCH.md)
- **Size:** 32KB
- **Topics:**
  - Runtime configuration
  - Environment variables
  - Config management patterns

---

## 🌐 External Resources

### Req HTTP Client
- **URL:** https://hexdocs.pm/req
- **Relevance:** T005 - Req HTTP Client implementation
- **Key Topics:**
  - Making HTTP requests
  - Retry strategies
  - Request/response handling
  - **IMPORTANT:** Use Req, NOT :httpc (Codex requirement)

### ScrapFly API
- **URL:** https://scrapfly.io/docs/scrape-api
- **Relevance:** T005, T006 - API integration and parsing
- **Key Topics:**
  - Authentication
  - Request parameters
  - Response formats (JSON, not markdown)
  - Rate limits and costs

### ScrapFly SERP API
- **URL:** https://scrapfly.io/docs/scrape-api/serp
- **Relevance:** T006 - JSON parser implementation
- **Key Topics:**
  - SERP-specific parameters
  - Response structure (organic_results, features)
  - Position extraction

### Hammer (Rate Limiting)
- **URL:** https://hexdocs.pm/hammer
- **Relevance:** T008 - Rate limiter implementation
- **Key Topics:**
  - ETS-based rate limiting
  - check_rate/3 function
  - Bucket configuration

### Oban Documentation
- **URL:** https://hexdocs.pm/oban
- **Relevance:** T009, T010, T013 - Worker implementation
- **Key Topics:**
  - Worker configuration
  - unique_periods (idempotency) ⭐
  - Cron plugins
  - Testing

---

## 📋 Sprint-Specific Documentation

### Architecture Review
- **File:** [RESEARCH_SUMMARY.md](RESEARCH_SUMMARY.md)
- **Topics:**
  - Codex architecture review feedback
  - Critical fixes applied
  - Key technical decisions
  - Compliance checklist

---

## 🗂️ Documentation by Ticket

### T001: Create SERP Directory Structure
- **No specific docs needed** - follows existing patterns

### T002: ScrapFly Config & Env Setup
- [ENVIRONMENT_CONFIG_RESEARCH.md](/Users/flor/Developer/prism/ENVIRONMENT_CONFIG_RESEARCH.md)
- Example: `lib/gsc_analytics/data_sources/gsc/core/config.ex`

### T003: SerpSnapshot Ecto Schema
- [phoenix-ecto-research.md](/Users/flor/Developer/prism/docs/phoenix-ecto-research.md)
- Example: `lib/gsc_analytics/schemas/performance.ex`

### T004: Database Migration
- [phoenix-ecto-research.md](/Users/flor/Developer/prism/docs/phoenix-ecto-research.md)
- Example migrations in `priv/repo/migrations/`

### T005: Req HTTP Client (TDD)
- [elixir-tdd-research.md](/Users/flor/Developer/prism/docs/elixir-tdd-research.md) ⭐
- [testing-quick-reference.md](/Users/flor/Developer/prism/docs/testing-quick-reference.md)
- External: https://hexdocs.pm/req
- External: https://scrapfly.io/docs/scrape-api

### T006: JSON Parser (TDD)
- [elixir-tdd-research.md](/Users/flor/Developer/prism/docs/elixir-tdd-research.md) ⭐
- External: https://scrapfly.io/docs/scrape-api/serp

### T007: Persistence Layer
- [phoenix-ecto-research.md](/Users/flor/Developer/prism/docs/phoenix-ecto-research.md)
- Example: `lib/gsc_analytics/data_sources/gsc/core/persistence.ex`

### T008: Rate Limiter (TDD)
- [elixir-tdd-research.md](/Users/flor/Developer/prism/docs/elixir-tdd-research.md) ⭐
- [elixir_error_handling_research.md](/Users/flor/Developer/prism/docs/elixir_error_handling_research.md)
- External: https://hexdocs.pm/hammer

### T009: Oban SERP Worker (TDD)
- [OBAN_REFERENCE.md](/Users/flor/Developer/prism/docs/OBAN_REFERENCE.md) ⭐⭐
- [elixir-tdd-research.md](/Users/flor/Developer/prism/docs/elixir-tdd-research.md) ⭐
- **Focus:** unique_periods for idempotency
- External: https://hexdocs.pm/oban/Oban.Worker.html#module-unique-jobs

### T010: Integration Tests (TDD)
- [elixir-tdd-research.md](/Users/flor/Developer/prism/docs/elixir-tdd-research.md) ⭐
- [testing-quick-reference.md](/Users/flor/Developer/prism/docs/testing-quick-reference.md) ⭐
- [OBAN_REFERENCE.md](/Users/flor/Developer/prism/docs/OBAN_REFERENCE.md)
- External: https://hexdocs.pm/oban/Oban.Testing.html

### T011: Dashboard LiveView Integration
- [phoenix-ecto-research.md](/Users/flor/Developer/prism/docs/phoenix-ecto-research.md)
- Example: `lib/gsc_analytics_web/live/dashboard_url_live.ex`

### T012: SERP Visualization
- Example: `assets/js/charts/chartjs_performance_chart.js`

### T013: Data Pruning Worker
- [OBAN_REFERENCE.md](/Users/flor/Developer/prism/docs/OBAN_REFERENCE.md)
- [cron-scheduling-research.md](/Users/flor/Developer/prism/docs/cron-scheduling-research.md)

### T014: Manual Verification
- [testing-quick-reference.md](/Users/flor/Developer/prism/docs/testing-quick-reference.md)
- [RESEARCH_SUMMARY.md](RESEARCH_SUMMARY.md) - Acceptance criteria

---

## 🔍 Quick Lookups

### How do I...?

**...use Req instead of :httpc?**
→ See: https://hexdocs.pm/req and T005 ticket

**...parse ScrapFly JSON responses?**
→ See: https://scrapfly.io/docs/scrape-api/serp#response-format and T006 ticket

**...implement Oban unique_periods?**
→ See: [OBAN_REFERENCE.md](/Users/flor/Developer/prism/docs/OBAN_REFERENCE.md) and T009 ticket

**...write TDD tests?**
→ See: [elixir-tdd-research.md](/Users/flor/Developer/prism/docs/elixir-tdd-research.md)

**...test Oban workers?**
→ See: [testing-quick-reference.md](/Users/flor/Developer/prism/docs/testing-quick-reference.md) and T010 ticket

**...enforce LiveView authentication?**
→ See: [phoenix-ecto-research.md](/Users/flor/Developer/prism/docs/phoenix-ecto-research.md) and T011 ticket

**...schedule Oban cron jobs?**
→ See: [cron-scheduling-research.md](/Users/flor/Developer/prism/docs/cron-scheduling-research.md) and T013 ticket

---

## ⭐ Priority References

For TDD tickets (T005, T006, T008, T009, T010):
1. **Start here:** [elixir-tdd-research.md](/Users/flor/Developer/prism/docs/elixir-tdd-research.md)
2. **Quick reference:** [testing-quick-reference.md](/Users/flor/Developer/prism/docs/testing-quick-reference.md)

For Oban-related tickets (T009, T010, T013):
1. **Start here:** [OBAN_REFERENCE.md](/Users/flor/Developer/prism/docs/OBAN_REFERENCE.md)
2. **Unique jobs:** https://hexdocs.pm/oban/Oban.Worker.html#module-unique-jobs

For HTTP client (T005):
1. **Start here:** https://hexdocs.pm/req
2. **API reference:** https://scrapfly.io/docs/scrape-api

---

**Total Documentation Size:** ~270KB of local docs + external references

**Documentation Philosophy:**
- Official sources verified and linked
- Ready-to-use code examples
- Best practices from 2024-2025
- Production deployment patterns

---

**Need help finding docs?** All documentation files are in:
- `/Users/flor/Developer/prism/docs/` (local research)
- This sprint's `docs/` directory (sprint-specific)
