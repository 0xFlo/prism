# T004: Add Oban to Supervision Tree

**Status:** 🔵 Not Started
**Story Points:** 1
**Priority:** 🔥 P1 Critical
**TDD Required:** No (supervision tree)
**Depends On:** T003

## Description
Add Oban to the application supervision tree so it starts automatically when the Phoenix app boots.

## Acceptance Criteria
- [ ] Oban added to supervision tree in `application.ex`
- [ ] Oban starts successfully on app boot
- [ ] Proper child spec format used: `{Oban, Application.fetch_env!(:gsc_analytics, Oban)}`
- [ ] Application starts without errors

## Implementation Steps

### 1. Edit `lib/gsc_analytics/application.ex`

**Location:** After `GscAnalytics.Repo`, before `Phoenix.PubSub`

```elixir
def start(_type, _args) do
  children = [
    GscAnalyticsWeb.Telemetry,
    GscAnalytics.Repo,

    # Add Oban here
    {Oban, Application.fetch_env!(:gsc_analytics, Oban)},

    {Phoenix.PubSub, name: GscAnalytics.PubSub},

    # GSC Services
    {GscAnalytics.DataSources.GSC.Support.Authenticator,
     name: GscAnalytics.DataSources.GSC.Support.Authenticator},
    {GscAnalytics.DataSources.GSC.Support.SyncProgress, []},

    GscAnalyticsWeb.Endpoint
  ]

  opts = [strategy: :one_for_one, name: GscAnalytics.Supervisor]
  Supervisor.start_link(children, opts)
end
```

### 2. Verify Supervision Tree

```bash
# Start the application
iex -S mix phx.server

# Check supervision tree
iex> Supervisor.which_children(GscAnalytics.Supervisor)
# Should show Oban in the list

# Check Oban is running
iex> Oban.config()
# Should return Oban configuration

# Check scheduled jobs (if ENABLE_AUTO_SYNC=true)
iex> Oban.check_queue(queue: :gsc_sync)
# Should show queue info
```

### 3. Test Restart Behavior

```bash
# In IEx, kill Oban and verify it restarts
iex> pid = Process.whereis(Oban)
iex> Process.exit(pid, :kill)
iex> Process.sleep(100)
iex> Process.whereis(Oban)
# Should return new PID (supervisor restarted it)
```

## Testing
- Manual verification via IEx
- Ensure app starts successfully with and without `ENABLE_AUTO_SYNC`

## Definition of Done
- [ ] Oban added to supervision tree
- [ ] Application starts without errors
- [ ] Oban process is running
- [ ] Supervisor restarts Oban if it crashes
- [ ] Works in both test and dev environments

## Notes
- **Position matters:** Oban should start AFTER Repo (needs database) but BEFORE Endpoint
- **Tuple format:** Use `{Oban, config}` not bare `Oban` to pass configuration
- **Crash tolerance:** `:one_for_one` strategy means Oban crash won't bring down other services
- **Test environment:** Oban will start but won't process jobs (disabled in config/test.exs)

## Rollback Plan
If Oban causes startup issues, comment out the line and restart the app.
