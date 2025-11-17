# T011: Documentation and User Guide

**Status:** 🔵 Not Started
**Story Points:** 2
**Priority:** 🟡 P2 Medium
**TDD Required:** No (documentation)
**Depends On:** T010

## Description
Create comprehensive documentation for the automatic sync feature, including setup guide, configuration options, monitoring, and troubleshooting.

## Acceptance Criteria
- [ ] CLAUDE.md updated with auto-sync documentation
- [ ] README updated with environment variables
- [ ] Inline code documentation (moduledocs, typespecs)
- [ ] Troubleshooting guide created
- [ ] Example configurations provided
- [ ] Monitoring and alerting guide

## Implementation Steps

### 1. Update CLAUDE.md

**File:** `CLAUDE.md`

Add new section:

```markdown
## Automatic Syncing with Oban

### Overview

The application supports automatic background syncing of Google Search Console data using Oban, an enterprise-grade job queue for Elixir. When enabled, the system automatically syncs the last 14 days of data for all active workspaces every 6 hours.

### Quick Start

1. **Enable automatic syncing:**
   ```bash
   export ENABLE_AUTO_SYNC=true
   mix phx.server
   ```

2. **Verify it's running:**
   ```bash
   # Check logs on startup
   # Should see: "Auto-sync ENABLED: Schedule: 0 */6 * * *, Sync days: 14"

   # In IEx
   iex> Oban.check_queue(queue: :gsc_sync)
   ```

3. **Monitor sync jobs:**
   ```bash
   # View audit log in real-time
   tail -f logs/gsc_audit.log | grep auto_sync | jq

   # Analyze auto-sync performance
   mix gsc.analyze_logs --auto-sync-only
   ```

### Configuration

#### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ENABLE_AUTO_SYNC` | `false` | Enable/disable automatic syncing |
| `AUTO_SYNC_DAYS` | `14` | Number of days to sync per run |
| `AUTO_SYNC_CRON` | `0 */6 * * *` | Cron schedule (every 6 hours) |

#### Example Configurations

**Daily sync at 8 AM UTC:**
```bash
export ENABLE_AUTO_SYNC=true
export AUTO_SYNC_CRON="0 8 * * *"
export AUTO_SYNC_DAYS=7
```

**Aggressive syncing every 4 hours:**
```bash
export ENABLE_AUTO_SYNC=true
export AUTO_SYNC_CRON="0 */4 * * *"
export AUTO_SYNC_DAYS=14
```

**Development (auto-sync disabled):**
```bash
# ENABLE_AUTO_SYNC not set - uses default (disabled)
mix phx.server
```

### Manual Job Triggering

Auto-sync can be disabled while still allowing manual job execution:

```elixir
# In IEx console
iex> GscAnalytics.Workers.GscSyncWorker.new(%{}) |> Oban.insert()

# Check job status
iex> Oban.check_queue(queue: :gsc_sync)

# View recent jobs
iex> import Ecto.Query
iex> GscAnalytics.Repo.all(
       from j in Oban.Job,
       where: j.queue == "gsc_sync",
       order_by: [desc: j.inserted_at],
       limit: 10
     )
```

### Architecture

#### Components

1. **Worker** (`GscAnalytics.Workers.GscSyncWorker`)
   - Executes every 6 hours (configurable)
   - Calls `Sync.sync_all_workspaces(days: 14)`
   - Emits telemetry events
   - Retries up to 3 times on failure

2. **Queue** (`:gsc_sync`)
   - Dedicated queue for GSC sync jobs
   - Concurrency: 1 (prevents overlapping syncs)
   - Priority: 1 (high priority)
   - Timeout: 10 minutes

3. **Scheduler** (`Oban.Plugins.Cron`)
   - Only loads when `ENABLE_AUTO_SYNC=true`
   - Uses cron syntax for scheduling
   - Automatically enqueues jobs

#### Data Flow

```
Oban Cron Plugin
  ↓ (every 6 hours)
Enqueue GscSyncWorker job
  ↓
Worker.perform/1
  ↓
Sync.sync_all_workspaces(days: 14)
  ↓
Iterate active workspaces
  ↓
For each workspace:
  - Sync.sync_last_n_days(site, 14)
  - URLPhase → Fetch URLs
  - QueryPhase → Fetch queries
  - Store in Performance & TimeSeries tables
  ↓
Emit telemetry events
  ↓
Log to logs/gsc_audit.log
```

### Monitoring

#### Telemetry Events

The auto-sync system emits three telemetry events:

1. **`[:gsc_analytics, :auto_sync, :started]`**
   - Metadata: `job_id`, `sync_days`, `total_workspaces`

2. **`[:gsc_analytics, :auto_sync, :complete]`**
   - Measurements: `duration_ms`, `total_workspaces`, `successes`, `failures`, `total_urls`, `total_queries`, `urls_per_second`
   - Metadata: `results` (full workspace sync results)

3. **`[:gsc_analytics, :auto_sync, :failure]`**
   - Measurements: `duration_ms`, `attempt`
   - Metadata: `error`, `stacktrace`, `job_id`

#### Audit Log

All auto-sync events are logged to `logs/gsc_audit.log` in JSON format:

```bash
# View live auto-sync activity
tail -f logs/gsc_audit.log | grep auto_sync | jq

# Example log entries:
{
  "ts": "2025-01-08T14:00:00Z",
  "event": "auto_sync.started",
  "metadata": {"job_id": 123, "sync_days": 14, "total_workspaces": 3}
}

{
  "ts": "2025-01-08T14:05:30Z",
  "event": "auto_sync.complete",
  "measurements": {
    "duration_ms": 330000,
    "total_workspaces": 3,
    "successes": 3,
    "failures": 0,
    "total_urls": 1250,
    "urls_per_second": 3.79
  }
}
```

#### Log Analysis

Use the built-in Mix task for quick insights:

```bash
# Analyze all auto-sync runs
mix gsc.analyze_logs --auto-sync-only

# Example output:
# === GSC Audit Log Analysis ===
# Total events: 156
#
# Events by type:
#   auto_sync.complete: 52
#   auto_sync.started: 52
#
# === Auto-Sync Metrics ===
# Runs: 52
# Average duration: 245000ms
# Total workspaces processed: 156
# Total successes: 154
# Total failures: 2
# Overall success rate: 98.72%
```

### Troubleshooting

#### Auto-sync not running

**Symptom:** No jobs appearing in Oban queue

**Check:**
1. Verify environment variable:
   ```bash
   echo $ENABLE_AUTO_SYNC
   # Should output: true
   ```

2. Check startup logs:
   ```bash
   # Should see: "Auto-sync ENABLED: Schedule: 0 */6 * * *"
   # If you see: "Auto-sync DISABLED" - check env var
   ```

3. Verify Oban configuration:
   ```elixir
   iex> Oban.config() |> Map.get(:plugins)
   # Should include {Oban.Plugins.Cron, [...]}
   ```

#### Jobs failing repeatedly

**Symptom:** Jobs in "retryable" state with errors

**Check:**
1. View job errors:
   ```elixir
   iex> import Ecto.Query
   iex> failed_jobs = GscAnalytics.Repo.all(
          from j in Oban.Job,
          where: j.queue == "gsc_sync" and j.state == "retryable",
          order_by: [desc: j.inserted_at]
        )
   iex> List.first(failed_jobs).errors
   ```

2. Check audit log for failures:
   ```bash
   grep "auto_sync.failure" logs/gsc_audit.log | tail -5 | jq
   ```

3. Common causes:
   - **API quota exceeded:** Reduce `AUTO_SYNC_DAYS` or frequency
   - **Authentication failure:** Check OAuth token in database
   - **Network timeout:** Increase worker timeout in config
   - **Database issues:** Check PostgreSQL connection

#### Partial workspace failures

**Symptom:** Some workspaces sync, others fail

**Check:**
1. View workspace sync results:
   ```bash
   grep "auto_sync.complete" logs/gsc_audit.log | tail -1 | jq '.metadata.workspace_details'
   ```

2. Identify failing workspaces:
   ```elixir
   iex> import Ecto.Query
   iex> GscAnalytics.Repo.all(
          from s in GscAnalytics.Schemas.SyncDay,
          where: s.status == :failed,
          order_by: [desc: s.inserted_at],
          limit: 10,
          preload: :workspace
        )
   ```

3. Fix workspace issues:
   - **Invalid property URL:** Update workspace `property_url`
   - **No GSC access:** Grant service account access to property
   - **Workspace inactive:** Set `active: true` if needed

#### Performance issues

**Symptom:** Syncs taking too long (>10 minutes)

**Check:**
1. Analyze sync duration:
   ```bash
   cat logs/gsc_audit.log | jq -s '
     map(select(.event=="auto_sync.complete")) |
     map(.measurements.duration_ms) |
     add/length
   '
   # Shows average duration in milliseconds
   ```

2. Optimize:
   - **Reduce sync days:** Set `AUTO_SYNC_DAYS=7` instead of 14
   - **Reduce frequency:** Change to `AUTO_SYNC_CRON="0 12 * * *"` (once daily)
   - **Check API rate limits:** Review `rate_limited` flags in audit log
   - **Database indexes:** Ensure proper indexes on Performance and TimeSeries tables

### Production Deployment

#### Recommended Configuration

```bash
# Production environment
export ENABLE_AUTO_SYNC=true
export AUTO_SYNC_DAYS=14
export AUTO_SYNC_CRON="0 */6 * * *"  # Every 6 hours
export DATABASE_URL="postgresql://..."
```

#### Health Checks

Monitor auto-sync health via HTTP endpoint:

```bash
curl http://localhost:4000/health/sync

# Example response:
{
  "last_sync": {
    "status": "completed",
    "scheduled_at": "2025-01-08T14:00:00Z",
    "completed_at": "2025-01-08T14:05:30Z",
    "attempt": 1,
    "errors": []
  },
  "oban_health": "ok",
  "database": "ok"
}
```

#### Alerting

Set up alerts based on:
- **HTTP health endpoint:** 503 status = unhealthy
- **Audit log failures:** `auto_sync.failure` events
- **Success rate:** Drop below 95%
- **Duration:** Exceeds 15 minutes

Example monitoring script:

```bash
#!/bin/bash
# check_auto_sync.sh

HEALTH_URL="http://localhost:4000/health/sync"
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" $HEALTH_URL)

if [ "$RESPONSE" != "200" ]; then
  echo "ALERT: Auto-sync health check failed (HTTP $RESPONSE)"
  # Send notification (Slack, PagerDuty, etc.)
  exit 1
fi

echo "Auto-sync healthy"
exit 0
```

### Migration from Manual Sync

If migrating from manual sync to auto-sync:

1. **Do initial backfill manually:**
   ```elixir
   iex> GscAnalytics.DataSources.GSC.Core.Sync.sync_full_history("sc-domain:example.com")
   ```

2. **Enable auto-sync:**
   ```bash
   export ENABLE_AUTO_SYNC=true
   ```

3. **Monitor first few runs:**
   ```bash
   tail -f logs/gsc_audit.log | grep auto_sync | jq
   ```

4. **Verify no gaps:**
   ```elixir
   iex> import Ecto.Query
   iex> GscAnalytics.Repo.all(
          from s in GscAnalytics.Schemas.SyncDay,
          where: s.status == :failed or is_nil(s.status),
          group_by: s.date,
          select: s.date
        )
   # Should return empty list (no failed/missing dates)
   ```
```

### 2. Update Project README

**File:** `README.md`

Add to existing content:

```markdown
## Automatic Background Syncing

This application supports automatic background syncing of Google Search Console data using Oban.

### Quick Setup

1. Enable auto-sync:
   ```bash
   export ENABLE_AUTO_SYNC=true
   ```

2. Start the server:
   ```bash
   mix phx.server
   ```

3. Monitor sync status:
   ```bash
   tail -f logs/gsc_audit.log | grep auto_sync | jq
   ```

For detailed configuration and troubleshooting, see [CLAUDE.md](CLAUDE.md#automatic-syncing-with-oban).

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ENABLE_AUTO_SYNC` | `false` | Enable automatic background syncing |
| `AUTO_SYNC_DAYS` | `14` | Days of data to sync per run |
| `AUTO_SYNC_CRON` | `0 */6 * * *` | Cron schedule for syncing |
```

### 3. Add Inline Documentation

**Update module documentation:**

**File:** `lib/gsc_analytics/workers/gsc_sync_worker.ex`

Ensure comprehensive moduledoc (already added in T006)

**File:** `lib/gsc_analytics/config/auto_sync.ex`

Ensure all functions have @doc and @spec (already added in T009)

### 4. Create Troubleshooting Runbook

**File:** `docs/troubleshooting/auto-sync.md`

```markdown
# Auto-Sync Troubleshooting Runbook

## Quick Diagnostics

### Check if auto-sync is enabled
```bash
echo $ENABLE_AUTO_SYNC
# Expected: "true"
```

### Check Oban queue status
```elixir
iex> Oban.check_queue(queue: :gsc_sync)
# Shows: running jobs, scheduled jobs, available workers
```

### View recent sync results
```bash
grep "auto_sync.complete" logs/gsc_audit.log | tail -5 | jq
```

## Common Issues

### Issue: "No jobs being scheduled"

**Diagnosis:**
- Check env var: `echo $ENABLE_AUTO_SYNC`
- Check startup logs for "Auto-sync ENABLED" message
- Verify Oban Cron plugin loaded: `Oban.config() |> Map.get(:plugins)`

**Resolution:**
1. Set `ENABLE_AUTO_SYNC=true`
2. Restart application
3. Verify cron plugin in Oban config

### Issue: "Jobs failing with API quota errors"

**Diagnosis:**
```bash
grep "api_quota_exceeded" logs/gsc_audit.log | wc -l
```

**Resolution:**
- Reduce sync frequency: `AUTO_SYNC_CRON="0 12 * * *"` (once daily)
- Reduce sync scope: `AUTO_SYNC_DAYS=7`
- Check GSC API quota limits in Google Cloud Console

### Issue: "Some workspaces failing, others succeeding"

**Diagnosis:**
```elixir
iex> import Ecto.Query
iex> failed_syncs = GscAnalytics.Repo.all(
       from s in GscAnalytics.Schemas.SyncDay,
       where: s.status == :failed,
       group_by: s.workspace_id,
       select: {s.workspace_id, count(s.id)}
     )
```

**Resolution:**
1. Check failed workspace property URLs
2. Verify service account has access to GSC property
3. Check workspace `active` status

## Health Check Commands

```bash
# Application health
curl http://localhost:4000/health/sync

# Database connectivity
psql -d gsc_analytics_dev -c "SELECT COUNT(*) FROM oban_jobs WHERE queue = 'gsc_sync'"

# Recent job success rate
cat logs/gsc_audit.log | jq -s '
  map(select(.event=="auto_sync.complete")) |
  {
    total: length,
    avg_success_rate: (map(.metadata.success_rate) | add / length)
  }
'
```

## Escalation

If issues persist after troubleshooting:
1. Collect logs: `grep auto_sync logs/gsc_audit.log > auto_sync_debug.log`
2. Export recent Oban jobs: SQL query on `oban_jobs` table
3. Check system resources (CPU, memory, database connections)
4. Review GSC API status page
```

## Definition of Done
- [ ] CLAUDE.md updated with comprehensive auto-sync section
- [ ] README.md updated with quick start and env vars
- [ ] All modules have proper @moduledoc and @doc
- [ ] Troubleshooting runbook created
- [ ] Example configurations provided
- [ ] Health check documentation added
- [ ] Migration guide from manual to auto-sync

## Notes
- **Keep CLAUDE.md comprehensive:** It's the main reference for Claude Code
- **Keep README.md concise:** Quick setup only, link to CLAUDE.md for details
- **Runbook format:** Step-by-step commands for operations team
- **Examples:** Real-world scenarios, not toy examples
