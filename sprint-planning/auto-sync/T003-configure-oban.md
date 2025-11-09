# T003: Configure Oban in Application Config

**Status:** 🔵 Not Started
**Story Points:** 2
**Priority:** 🔥 P1 Critical
**TDD Required:** No (configuration)
**Depends On:** T002

## Description
Configure Oban in application config files with proper settings for dev, test, and production environments.

## Acceptance Criteria
- [ ] Base Oban config added to `config/config.exs`
- [ ] Runtime config added to `config/runtime.exs` with environment gating
- [ ] Test config disables Oban plugins and queues
- [ ] Cron job configured for every 6 hours
- [ ] Environment variable `ENABLE_AUTO_SYNC` controls scheduling

## Implementation Steps

### 1. Base Config (`config/config.exs`)
```elixir
# Configure Oban
config :gsc_analytics, Oban,
  repo: GscAnalytics.Repo,
  plugins: [],  # Will be set in runtime.exs based on environment
  queues: [default: 10, gsc_sync: 1]  # gsc_sync queue runs one job at a time
```

### 2. Runtime Config (`config/runtime.exs`)
```elixir
# Inside the config_env? block
alias GscAnalytics.Config.AutoSync

auto_sync_plugins = AutoSync.plugins()

config :gsc_analytics, Oban,
  repo: GscAnalytics.Repo,
  plugins: auto_sync_plugins,
  queues: [default: 10, gsc_sync: 1]

AutoSync.log_status!()
```

### 3. Test Config (`config/test.exs`)
```elixir
# Disable Oban in tests (use Oban.Testing for manual job execution)
config :gsc_analytics, Oban,
  repo: GscAnalytics.Repo,
  plugins: false,  # Disable all plugins
  queues: false    # Disable queue processing
```

### 4. Verify Configuration
```bash
# Enabled
ENABLE_AUTO_SYNC=true iex -S mix
iex> GscAnalytics.Config.AutoSync.enabled?()
true
iex> Application.get_env(:gsc_analytics, Oban)[:plugins]
# Includes Cron plugin

# Disabled
ENABLE_AUTO_SYNC=false iex -S mix
iex> GscAnalytics.Config.AutoSync.enabled?()
false
iex> Application.get_env(:gsc_analytics, Oban)[:plugins]
# Only pruner + lifeline plugins present
```

## Testing
- Manual verification with different `ENABLE_AUTO_SYNC` values
- Check that test environment doesn't process jobs automatically

## Definition of Done
- [ ] Config files updated with Oban settings
- [ ] Cron schedule set to `"0 */6 * * *"` (every 6 hours)
- [ ] Environment variable gating works
- [ ] Test environment disables Oban processing
- [ ] Configuration compiles without errors

## Notes
- **Cron format:** `"0 */6 * * *"` = Every 6 hours at minute 0 (midnight, 6am, noon, 6pm UTC)
- **Queue strategy:** `gsc_sync: 1` ensures only one sync runs at a time (prevents overlap)
- **Pruner:** Keeps job history for 7 days for debugging
- **Test mode:** `plugins: false, queues: false` prevents automatic job execution in tests

## 📚 Reference Documentation
- **Primary:** [Oban Reference](/Users/flor/Developer/prism/docs/OBAN_REFERENCE.md) - Configuration & Cron Plugin sections
- **Secondary:** [Environment Config Research](/Users/flor/Developer/prism/ENVIRONMENT_CONFIG_RESEARCH.md) - Runtime configuration patterns
- **Tertiary:** [Cron Scheduling Research](/Users/flor/Developer/prism/docs/cron-scheduling-research.md) - Cron syntax and best practices
- **Official:** https://hexdocs.pm/oban/Oban.Plugins.Cron.html
- **Index:** [Documentation Index](docs/DOCUMENTATION_INDEX.md)
