# Auto-Sync Sprint Documentation Index

**Last Updated:** 2025-01-08

This directory contains research documentation gathered from official sources to support the automatic GSC sync implementation. All documentation includes source URLs and is current as of January 2025.

---

## 📚 Research Documents

### 1. **Oban Job Queue**
**Location:** `/Users/flor/Developer/prism/docs/OBAN_REFERENCE.md`
**Size:** 41KB | 1,577 lines
**Topics Covered:**
- Installation and setup (v2.20.1)
- Worker configuration and return values
- Cron plugin scheduling
- Pruner plugin configuration
- Testing with Oban.Testing
- Error handling and retries
- Unique jobs and deduplication
- Telemetry and monitoring
- Production best practices
- Oban Pro features comparison

**Key Takeaways:**
- Use `Oban.Migration.up(version: 13)` for latest schema
- Pruner plugin is CRITICAL for production
- Testing mode: `:manual` with `Oban.drain_queue/1`
- Return `:ok`, `{:error, reason}`, `{:cancel, reason}`, or `{:snooze, seconds}`
- Default 20 retry attempts with exponential backoff + jitter

**Official Sources:**
- https://hexdocs.pm/oban/
- https://github.com/oban-bg/oban
- https://getoban.pro/

---

### 2. **Phoenix & Ecto Patterns**
**Location:** `/Users/flor/Developer/prism/docs/phoenix-ecto-research.md`
**Size:** 35KB | 1,200+ lines
**Topics Covered:**
- Background job patterns in Phoenix
- Ecto bulk operations and transactions
- Phoenix Telemetry integration
- Testing patterns with DataCase
- Phoenix 1.7/1.8 updates
- Performance optimization strategies
- Migration best practices

**Key Takeaways:**
- No official Phoenix background job framework (use Oban)
- `Repo.insert_all` has 65,535 parameter limit
- Use `Ecto.Multi` for complex transactions
- SQL Sandbox for async testing
- Telemetry for observability
- LiveView streams for large datasets

**Official Sources:**
- https://hexdocs.pm/phoenix/
- https://hexdocs.pm/ecto/
- https://hexdocs.pm/phoenix_live_view/
- https://phoenixframework.org/blog

---

### 3. **Elixir TDD Best Practices**
**Location:** `/Users/flor/Developer/prism/docs/elixir-tdd-research.md`
**Size:** 41KB | 1,577 lines
**Topics Covered:**
- Red-Green-Refactor workflow in Elixir
- Mox vs Meck comparison (official recommendation: Mox)
- ExUnit best practices
- Test coverage with ExCoveralls
- Phoenix-specific testing (LiveView, controllers, contexts)
- Property-based testing with StreamData
- Testing Oban workers

**Key Takeaways:**
- **Use Mox, not Meck** - Behaviour-based, compile-time safety, async support
- Target 80-85% coverage (90-95% for business logic)
- Test from user perspective for LiveViews
- `setup` vs `setup_all` for fixtures
- Use `:manual` testing mode for Oban

**Quick Reference:** `/Users/flor/Developer/prism/docs/testing-quick-reference.md` (13KB)

**Migration Guide:** `/Users/flor/Developer/prism/docs/meck-to-mox-migration.md`

**Official Sources:**
- https://hexdocs.pm/ex_unit/
- https://hexdocs.pm/mox/
- https://hexdocs.pm/stream_data/
- Testing Elixir book (Pragmatic)

---

### 4. **Cron Scheduling**
**Location:** `/Users/flor/Developer/prism/docs/cron-scheduling-research.md`
**Size:** 28KB | 950+ lines
**Topics Covered:**
- Cron expression syntax (5-field vs 6-field)
- Oban.Plugins.Cron vs Quantum comparison
- Timezone handling and DST considerations
- Overlapping job prevention
- Monitoring and alerting patterns
- GSC-specific scheduling recommendations

**Key Takeaways:**
- Oban Cron uses standard 5-field format (no seconds)
- Supports nicknames: `@hourly`, `@daily`, `@weekly`, `@monthly`, `@reboot`
- Minimum interval: 1 minute
- Use UTC to avoid DST issues
- Prevent overlaps with unique constraints (`:infinity` period)
- **Recommended GSC schedule:** `"0 4 * * *"` (4am UTC after data finalization)

**Official Sources:**
- https://hexdocs.pm/oban/Oban.Plugins.Cron.html
- https://hexdocs.pm/quantum/
- https://crontab.guru/ (expression tester)

---

### 5. **Error Handling & Resilience**
**Location:** `/Users/flor/Developer/prism/docs/elixir_error_handling_research.md`
**Size:** 45KB | 1,600+ lines
**Topics Covered:**
- "Let it crash" philosophy (properly contextualized)
- Supervisor strategies
- Error tuple patterns
- Retry strategies (exponential backoff, circuit breakers)
- Observability (Telemetry, structured logging, APM)
- Graceful degradation and fallback patterns
- Testing error scenarios (fault injection, chaos engineering)
- Production best practices

**Key Takeaways:**
- Use `{:ok, result}` / `{:error, reason}` for expected failures
- Reserve exceptions for unexpected errors
- Circuit breaker library: `fuse` (Erlang, battle-tested)
- APM recommendation: AppSignal (best Elixir support) or Sentry (free tier)
- Use Telemetry for instrumentation
- Test timeouts with `Process.sleep` or `Task.yield_many`

**Libraries Documented:**
- retry, gen_retry, exbackoff (exponential backoff)
- fuse, external_service (circuit breakers)
- telemetry, logger_json (observability)
- snabbkaffe (chaos engineering)

**Official Sources:**
- https://hexdocs.pm/elixir/Supervisor.html
- https://hexdocs.pm/telemetry/
- https://docs.appsignal.com/elixir/
- https://blog.appsignal.com/category/elixir-alchemy.html

---

### 6. **Environment Configuration**
**Location:** `/Users/flor/Developer/prism/ENVIRONMENT_CONFIG_RESEARCH.md`
**Size:** 32KB | 1,100+ lines
**Topics Covered:**
- Phoenix 1.7+ configuration patterns
- config/runtime.exs vs config/config.exs
- 12-Factor App principles
- Environment variable best practices
- Configuration libraries (Vapor, Dotenvy, NimbleOptions)
- Feature flags (FunWithFlags)
- Gradual rollouts and A/B testing
- Testing with different configs

**Key Takeaways:**
- **Prefer runtime.exs** over compile-time config
- Use `System.fetch_env!/1` for required vars (fail fast)
- Topic-based config organization > environment-based
- Pass config as function arguments (avoid `Application.get_env` in hot paths)
- FunWithFlags for feature flags (5 gate types: boolean, actor, group, % time, % actors)
- Gradual rollout: 1% → 5% → 25% → 50% → 100%

**Libraries Documented:**
- Vapor (runtime config with validation)
- Dotenvy (.env file support)
- NimbleOptions (schema-based validation)
- FunWithFlags (feature flags)

**Official Sources:**
- https://hexdocs.pm/phoenix/config.html
- https://12factor.net/config
- https://hexdocs.pm/vapor/
- https://hexdocs.pm/fun_with_flags/

---

## 🎯 Ticket-to-Documentation Mapping

| Ticket | Primary Docs | Secondary Docs |
|--------|-------------|----------------|
| T001: Add Oban Dependency | Oban Reference | - |
| T002: Oban Migration | Oban Reference (Migration V13) | Phoenix/Ecto Research |
| T003: Configure Oban | Oban Reference (Config), Environment Config | - |
| T004: Supervision Tree | Oban Reference (Supervision), Phoenix/Ecto Research | - |
| T005: Workspace Iterator (TDD) | Elixir TDD Research, Testing Quick Ref | Phoenix/Ecto Research |
| T006: Oban Worker (TDD) | Oban Reference (Workers), Elixir TDD Research | - |
| T007: Error Handling | Error Handling Research | Oban Reference (Retries) |
| T008: Telemetry Integration | Phoenix/Ecto Research (Telemetry) | Error Handling Research |
| T009: Environment Gating (TDD) | Environment Config Research, Elixir TDD Research | - |
| T010: Integration Tests (TDD) | Elixir TDD Research, Testing Quick Ref | Oban Reference (Testing) |
| T011: Documentation | All docs | - |
| T012: Manual Verification | Oban Reference, Cron Scheduling Research | All docs |

---

## 📖 Quick Reference Guides

### For Daily Development
1. **Testing Quick Reference** - `/Users/flor/Developer/prism/docs/testing-quick-reference.md`
   - Copy-paste ready test patterns
   - Common assertions
   - Troubleshooting section

2. **Oban Worker Template**
   ```elixir
   defmodule MyApp.Workers.ExampleWorker do
     use Oban.Worker,
       queue: :default,
       max_attempts: 3,
       priority: 1,
       timeout: :timer.minutes(5)

     @impl Oban.Worker
     def perform(%Oban.Job{args: args}) do
       # Return :ok, {:ok, value}, {:error, reason}, {:cancel, reason}, or {:snooze, seconds}
       :ok
     end
   end
   ```

3. **TDD Workflow Reminder**
   - 🔴 **RED:** Write failing test
   - 🟢 **GREEN:** Write minimum code to pass
   - 🔵 **REFACTOR:** Improve while tests stay green

### For Configuration
1. **Environment Variable Pattern**
   ```elixir
   # config/runtime.exs
   config :my_app, MyApp.Feature,
     enabled: System.fetch_env!("FEATURE_ENABLED"),
     days: System.get_env("FEATURE_DAYS", "14") |> String.to_integer()
   ```

2. **Cron Schedule Examples**
   - Every 6 hours: `"0 */6 * * *"`
   - Daily at 4am UTC: `"0 4 * * *"`
   - Weekly on Sunday: `"0 2 * * 0"`
   - Monthly on 1st: `"0 3 1 * *"`

---

## 🔍 Additional Resources

### Migration Guides
- **Meck to Mox Migration** - `/Users/flor/Developer/prism/docs/meck-to-mox-migration.md`
  - Step-by-step migration process
  - Before/after code examples
  - 4-week rollout plan

### Elixir/Phoenix Community
- **ElixirForum** - https://elixirforum.com/
- **Elixir Slack** - https://elixir-slackin.herokuapp.com/
- **Phoenix GitHub** - https://github.com/phoenixframework/phoenix
- **Oban GitHub** - https://github.com/oban-bg/oban

### Recommended Reading
1. **Programming Phoenix LiveView** (Pragmatic, 2024)
2. **Testing Elixir** (Pragmatic, 2021)
3. **Designing Elixir Systems with OTP** (Pragmatic, 2019)
4. **Real-Time Phoenix** (Pragmatic, 2020)

---

## 📊 Research Methodology

All documentation was gathered using:
1. **Official sources first** - HexDocs, GitHub repos, official blogs
2. **Community validation** - ElixirForum, conference talks, company blogs
3. **Recency filter** - Prioritized 2024-2025 content, noted version compatibility
4. **Practical focus** - Code examples, production patterns, real-world usage

**Research completed:** 2025-01-08
**Elixir version compatibility:** 1.15+
**Phoenix version compatibility:** 1.7+
**Oban version compatibility:** 2.18+

---

## 🚀 Using This Documentation

### During Sprint Execution
1. **Before starting a ticket** - Review the Primary Docs listed in mapping table
2. **During implementation** - Reference Quick Reference Guides for patterns
3. **When stuck** - Check troubleshooting sections in research docs
4. **For decisions** - Consult best practices sections and official sources

### After Sprint
- Archive this documentation with the sprint
- Update project CLAUDE.md with key learnings
- Share migration guides (Meck→Mox) with team
- Consider contributing improvements back to community

---

**All documentation is available locally and includes complete source citations for verification and deeper reading.**
