# T012: Manual Verification and Acceptance Testing

**Status:** 🔵 Not Started
**Story Points:** 2
**Priority:** 🔥 P1 Critical
**TDD Required:** No (manual testing)
**Depends On:** T011

## Description
Perform comprehensive manual testing of the auto-sync feature to ensure it works correctly in real-world scenarios before marking the sprint complete.

## Acceptance Criteria
- [ ] Auto-sync runs successfully with `ENABLE_AUTO_SYNC=true`
- [ ] Manual job triggering works
- [ ] Environment variable gating verified
- [ ] Multiple workspaces sync correctly
- [ ] Error handling works as expected
- [ ] Telemetry events logged correctly
- [ ] Health endpoint responds properly
- [ ] Documentation is accurate and complete

## Manual Testing Checklist

### 1. Initial Setup Verification

**Test:** Fresh install and configuration
```bash
# Clone or reset to feature branch
git checkout feature/auto-sync

# Install dependencies
mix deps.get

# Run migrations
mix ecto.reset

# Compile
mix compile
```

**Expected:**
- [x] No compilation errors
- [x] All dependencies installed
- [x] Database created and migrated
- [x] Oban tables exist (`oban_jobs`, `oban_peers`)

### 2. Auto-Sync Disabled by Default

**Test:** Start app without `ENABLE_AUTO_SYNC`
```bash
# No env var set
mix phx.server
```

**Expected:**
- [x] Application starts successfully
- [x] Startup logs show: `"Auto-sync DISABLED (set ENABLE_AUTO_SYNC=true to enable)"`
- [x] Oban starts but no Cron plugin loaded
- [x] No automatic jobs scheduled

**Verify in IEx:**
```elixir
iex> Oban.config() |> Map.get(:plugins)
# Should show [{Oban.Plugins.Pruner, [...]}] only, no Cron
```

### 3. Auto-Sync Enabled

**Test:** Start app with `ENABLE_AUTO_SYNC=true`
```bash
ENABLE_AUTO_SYNC=true mix phx.server
```

**Expected:**
- [x] Application starts successfully
- [x] Startup logs show: `"Auto-sync ENABLED: Schedule: 0 */6 * * *, Sync days: 14"`
- [x] Oban Cron plugin loaded
- [x] Jobs will be scheduled automatically

**Verify in IEx:**
```elixir
iex> Oban.config() |> Map.get(:plugins)
# Should show both Pruner and Cron plugins

iex> plugins = Oban.config() |> Map.get(:plugins)
iex> Enum.find(plugins, fn {mod, _opts} -> mod == Oban.Plugins.Cron end)
# Should return {Oban.Plugins.Cron, [crontab: [...]]}
```

### 4. Manual Job Triggering

**Test:** Manually enqueue a sync job
```elixir
# In IEx (with or without ENABLE_AUTO_SYNC)
iex> alias GscAnalytics.Workers.GscSyncWorker

# Enqueue job
iex> {:ok, job} = GscSyncWorker.new(%{}) |> Oban.insert()

# Check job status
iex> Oban.check_queue(queue: :gsc_sync)

# Wait for execution (or use Oban.drain_queue in test mode)
iex> :timer.sleep(5000)

# Check job completed
iex> job = GscAnalytics.Repo.get(Oban.Job, job.id)
iex> job.state
# Should be "completed" or "retryable" if failed
```

**Expected:**
- [x] Job successfully enqueued
- [x] Job executes within timeout (10 min)
- [x] Job state changes to "completed"
- [x] Audit log shows `auto_sync.started` and `auto_sync.complete` events

### 5. Multi-Workspace Sync

**Test:** Create multiple workspaces and verify all sync
```elixir
# Create test account
iex> account = GscAnalytics.AccountsFixtures.account_fixture()

# Create 3 workspaces (2 active, 1 inactive)
iex> ws1 = GscAnalytics.WorkspacesFixtures.workspace_fixture(%{
       account_id: account.id,
       active: true,
       property_url: "sc-domain:site1.com",
       name: "Site 1"
     })

iex> ws2 = GscAnalytics.WorkspacesFixtures.workspace_fixture(%{
       account_id: account.id,
       active: true,
       property_url: "sc-domain:site2.com",
       name: "Site 2"
     })

iex> ws3 = GscAnalytics.WorkspacesFixtures.workspace_fixture(%{
       account_id: account.id,
       active: false,
       property_url: "sc-domain:site3.com",
       name: "Site 3 (Inactive)"
     })

# Trigger sync
iex> GscSyncWorker.new(%{}) |> Oban.insert()

# Wait and check results
iex> :timer.sleep(60_000)  # Wait up to 1 minute

# Check sync_days table
iex> import Ecto.Query
iex> ws1_syncs = GscAnalytics.Repo.all(
       from s in GscAnalytics.Schemas.SyncDay,
       where: s.workspace_id == ^ws1.id,
       select: count(s.id)
     )

iex> ws2_syncs = GscAnalytics.Repo.all(
       from s in GscAnalytics.Schemas.SyncDay,
       where: s.workspace_id == ^ws2.id,
       select: count(s.id)
     )

iex> ws3_syncs = GscAnalytics.Repo.all(
       from s in GscAnalytics.Schemas.SyncDay,
       where: s.workspace_id == ^ws3.id,
       select: count(s.id)
     )
```

**Expected:**
- [x] Workspace 1 has 14 sync days (last 14 days)
- [x] Workspace 2 has 14 sync days
- [x] Workspace 3 has 0 sync days (inactive, skipped)
- [x] Audit log shows both workspaces processed

### 6. Error Handling

**Test:** Trigger job with invalid workspace configuration
```elixir
# Create workspace with invalid property URL
iex> bad_ws = GscAnalytics.WorkspacesFixtures.workspace_fixture(%{
       account_id: account.id,
       active: true,
       property_url: "invalid-url",
       name: "Bad Workspace"
     })

# Trigger sync (should handle error gracefully)
iex> GscSyncWorker.new(%{}) |> Oban.insert()

# Wait and check job status
iex> :timer.sleep(60_000)

# Check audit log for failures
```

**Expected:**
- [x] Job completes (doesn't crash)
- [x] Other workspaces still sync successfully
- [x] Failed workspace logged in `auto_sync.complete` metadata
- [x] Error details in audit log

### 7. Telemetry and Audit Logging

**Test:** Verify telemetry events and audit log entries
```bash
# Start server with auto-sync
ENABLE_AUTO_SYNC=true mix phx.server

# In another terminal, watch audit log
tail -f logs/gsc_audit.log | grep auto_sync | jq
```

**Trigger manual job:**
```elixir
iex> GscAnalytics.Workers.GscSyncWorker.new(%{}) |> Oban.insert()
```

**Expected log entries:**
```json
{"ts":"2025-01-08T15:00:00Z","event":"auto_sync.started","metadata":{"job_id":123,"sync_days":14,"total_workspaces":2}}
{"ts":"2025-01-08T15:05:30Z","event":"auto_sync.complete","measurements":{"duration_ms":330000,"total_workspaces":2,"successes":2,"failures":0,...}}
```

**Expected:**
- [x] `auto_sync.started` event logged at job start
- [x] `auto_sync.complete` event logged on success
- [x] Measurements include duration, workspace counts, URLs synced
- [x] Metadata includes workspace details
- [x] Timestamps are correct (UTC)

### 8. Custom Configuration

**Test:** Verify custom env var configuration
```bash
# Custom schedule (once daily at noon)
ENABLE_AUTO_SYNC=true AUTO_SYNC_CRON="0 12 * * *" AUTO_SYNC_DAYS=7 mix phx.server
```

**Verify in IEx:**
```elixir
iex> GscAnalytics.Config.AutoSync.cron_schedule()
# Should return "0 12 * * *"

iex> GscAnalytics.Config.AutoSync.sync_days()
# Should return 7
```

**Expected:**
- [x] Custom cron schedule applied
- [x] Custom sync days applied
- [x] Startup logs show custom configuration

### 9. Health Endpoint

**Test:** Health check endpoint
```bash
# Start server
ENABLE_AUTO_SYNC=true mix phx.server

# Trigger a sync job
curl -X POST http://localhost:4000/api/sync/trigger  # If endpoint exists

# Check health status
curl http://localhost:4000/health/sync | jq
```

**Expected response:**
```json
{
  "last_sync": {
    "status": "completed",
    "scheduled_at": "2025-01-08T15:00:00Z",
    "completed_at": "2025-01-08T15:05:30Z",
    "attempt": 1,
    "errors": []
  },
  "oban_health": "ok",
  "database": "ok"
}
```

**Expected:**
- [x] HTTP 200 status when healthy
- [x] HTTP 503 status when unhealthy
- [x] Correct job status shown
- [x] Oban and database health checks work

### 10. Retry Logic

**Test:** Verify Oban retries failed jobs
```elixir
# Define a temporary auto-sync module that always fails
iex> defmodule GscAnalytics.Testing.FailingAutoSync do
...>   @behaviour GscAnalytics.AutoSync
...>   def sync_all(_opts), do: {:error, :temporary_failure}
...> end

# Point the app at the failing module
iex> original = Application.get_env(:gsc_analytics, :auto_sync_module)
iex> Application.put_env(:gsc_analytics, :auto_sync_module, GscAnalytics.Testing.FailingAutoSync)

# Trigger job
iex> {:ok, job} = GscAnalytics.Workers.GscSyncWorker.new(%{}) |> Oban.insert()
iex> Oban.drain_queue(queue: :gsc_sync)

# Check job state (should be retryable with attempt=1)
iex> job = GscAnalytics.Repo.get(Oban.Job, job.id)
iex> job.state
"retryable"
iex> job.attempt
1
iex> length(job.errors)
1

# Restore original module to allow retries to succeed
iex> Application.put_env(:gsc_analytics, :auto_sync_module, original)
```

**Expected:**
- [x] Failed job moves to "retryable" state
- [x] Attempt count increments
- [x] Errors array populated
- [x] Job retries automatically (up to 3 attempts)
- [x] Eventually succeeds after fix

### 11. Log Analysis Tool

**Test:** Verify log analysis Mix task
```bash
# Run some sync jobs first
ENABLE_AUTO_SYNC=true iex -S mix phx.server

# Manually trigger a few jobs over time
# iex> GscSyncWorker.new(%{}) |> Oban.insert()

# Then analyze logs
mix gsc.analyze_logs --auto-sync-only
```

**Expected output:**
```
=== GSC Audit Log Analysis ===
Total events: 10

Events by type:
  auto_sync.complete: 5
  auto_sync.started: 5

=== Auto-Sync Metrics ===
Runs: 5
Average duration: 245000ms
Total workspaces processed: 15
Total successes: 14
Total failures: 1
Overall success rate: 93.33%
```

**Expected:**
- [x] Mix task runs without errors
- [x] Correct event counts
- [x] Accurate metrics calculated
- [x] Success rate correct

### 12. Documentation Accuracy

**Test:** Follow documentation step-by-step
```bash
# Follow CLAUDE.md "Quick Start" section exactly
# Verify every command works as documented
# Check that example outputs match reality
```

**Expected:**
- [x] All documented commands work
- [x] Example outputs match actual outputs
- [x] No missing steps
- [x] Configuration examples work
- [x] Troubleshooting guide is helpful

## Performance Testing

### Load Test: Multiple Workspaces

**Test:** Sync 10+ workspaces simultaneously
```elixir
# Create 10 active workspaces
iex> account = GscAnalytics.AccountsFixtures.account_fixture()
iex> for i <- 1..10 do
       GscAnalytics.WorkspacesFixtures.workspace_fixture(%{
         account_id: account.id,
         active: true,
         property_url: "sc-domain:site#{i}.com",
         name: "Site #{i}"
       })
     end

# Trigger sync
iex> GscSyncWorker.new(%{}) |> Oban.insert()

# Monitor performance
# - Watch CPU/memory usage
# - Check database connection count
# - Verify completion time < 10 minutes
```

**Expected:**
- [x] All workspaces sync successfully
- [x] Completes within timeout (10 minutes)
- [x] No memory leaks
- [x] Database connections released properly

## Acceptance Criteria Verification

After completing all tests above, verify:

- [x] **Functional Requirements:**
  - [ ] Auto-sync runs automatically every 6 hours when enabled
  - [ ] Syncs last 14 days for all active workspaces
  - [ ] Skips inactive workspaces
  - [ ] Environment variable controls behavior
  - [ ] Manual triggering works regardless of env var

- [x] **Quality Requirements:**
  - [ ] All automated tests pass (`mix test`)
  - [ ] No compilation warnings (`mix compile --warnings-as-errors`)
  - [ ] Code formatted (`mix format --check-formatted`)
  - [ ] Pre-commit checks pass (`mix precommit`)

- [x] **Operational Requirements:**
  - [ ] Telemetry events logged correctly
  - [ ] Audit log contains all sync operations
  - [ ] Health endpoint responds correctly
  - [ ] Error handling is graceful
  - [ ] Retries work as expected

- [x] **Documentation Requirements:**
  - [ ] CLAUDE.md updated and accurate
  - [ ] README.md updated
  - [ ] Troubleshooting guide complete
  - [ ] All examples work as documented

## Sign-Off

**Tested by:** _________________
**Date:** _________________
**Version:** _________________

**Issues found:** (list any issues discovered during testing)
-

**Overall status:** [ ] PASS [ ] FAIL [ ] PASS WITH ISSUES

**Notes:**


---

## Rollback Plan

If critical issues are found:

1. **Disable auto-sync immediately:**
   ```bash
   export ENABLE_AUTO_SYNC=false
   # Restart application
   ```

2. **Revert code changes:**
   ```bash
   git revert <commit-hash>
   ```

3. **Clean up Oban jobs:**
   ```elixir
   iex> import Ecto.Query
   iex> GscAnalytics.Repo.delete_all(
          from j in Oban.Job,
          where: j.queue == "gsc_sync"
        )
   ```

4. **Document issues and plan fix**

---

## 📚 Reference Documentation
- **Primary:** [Oban Reference](/Users/flor/Developer/prism/docs/OBAN_REFERENCE.md) - Complete Oban guide
- **Secondary:** [Cron Scheduling Research](/Users/flor/Developer/prism/docs/cron-scheduling-research.md) - Scheduling and monitoring
- **Tertiary:** All research docs - For comprehensive understanding
- **Index:** [Documentation Index](docs/DOCUMENTATION_INDEX.md) - Central hub for all documentation
