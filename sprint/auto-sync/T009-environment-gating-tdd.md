# T009: Environment Variable Gating with TDD

**Status:** 🔵 Not Started  
**Story Points:** 2  
**Priority:** 🔥 P1 Critical  
**TDD Required:** ✅ YES - Red, Green, Refactor  
**Depends On:** T003

## Description
Move all auto-sync configuration behind a dedicated module so we can toggle behaviour via environment variables (`ENABLE_AUTO_SYNC`, `AUTO_SYNC_DAYS`, `AUTO_SYNC_CRON`). The module must be covered by tests that manipulate the environment safely (set + restore). Oban configuration (plugins + queues) should call these helpers instead of reading `System.get_env/1` inline.

## Acceptance Criteria
- [ ] `GscAnalytics.Config.AutoSync` module created with documented public API
- [ ] Module exposes `enabled?/0`, `sync_days/0`, `cron_schedule/0`, `plugins/0`, `log_status!/0`
- [ ] `config/runtime.exs` retrieves Oban config via the new module
- [ ] Tests cover enabled/disabled states, default values, and overrides without leaking env values
- [ ] Manual job enqueuing works regardless of env var
- [ ] Tests written first using helper to isolate env changes

## Module Contract

**File:** `lib/gsc_analytics/config/auto_sync.ex`

```elixir
defmodule GscAnalytics.Config.AutoSync do
  @moduledoc """
  Runtime configuration helpers for the automatic sync pipeline.
  Reads from ENV only (no Mix config) so values can change per release.
  """

  @default_days 14
  @default_cron "0 */6 * * *"

  def enabled?, do: match?("true", System.get_env("ENABLE_AUTO_SYNC"))

  def sync_days do
    System.get_env("AUTO_SYNC_DAYS", Integer.to_string(@default_days))
    |> String.to_integer()
  end

  def cron_schedule do
    System.get_env("AUTO_SYNC_CRON", @default_cron)
  end

  def plugins do
    base = [
      {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
      {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(30)}
    ]

    if enabled?() do
      cron_opts = [
        crontab: [
          {cron_schedule(), GscAnalytics.Workers.GscSyncWorker,
           queue: :gsc_sync, max_attempts: 1}
        ]
      ]

      base ++ [{Oban.Plugins.Cron, cron_opts}]
    else
      base
    end
  end

  def log_status! do
    if enabled?() do
      Logger.info(
        "Auto-sync ENABLED: schedule=#{cron_schedule()} days=#{sync_days()}",
        auto_sync: true
      )
    else
      Logger.info("Auto-sync DISABLED (set ENABLE_AUTO_SYNC=true to enable)", auto_sync: true)
    end
  end
end
```

## Runtime Config Update

**File:** `config/runtime.exs`

Replace inline Oban plugin logic with:

```elixir
auto_sync_plugins = GscAnalytics.Config.AutoSync.plugins()

config :gsc_analytics, Oban,
  repo: GscAnalytics.Repo,
  plugins: auto_sync_plugins,
  queues: [default: 10, gsc_sync: 1]
```

Call `GscAnalytics.Config.AutoSync.log_status!()` after configuration so boot logs always state whether auto-sync is enabled and why.

## TDD Cycle

### 🔴 RED: Write Failing Tests First

**File:** `test/gsc_analytics/config/auto_sync_test.exs`

```elixir
defmodule GscAnalytics.Config.AutoSyncTest do
  use ExUnit.Case, async: false

  alias GscAnalytics.Config.AutoSync

  describe "enabled?/0" do
    test "returns true when ENABLE_AUTO_SYNC=true" do
      with_env(%{"ENABLE_AUTO_SYNC" => "true"}, fn ->
        assert AutoSync.enabled?()
      end)
    end

    test "returns false for any other value" do
      with_env(%{"ENABLE_AUTO_SYNC" => "false"}, fn ->
        refute AutoSync.enabled?()
      end)
    end
  end

  describe "sync_days/0" do
    test "defaults to 14" do
      with_env(%{"AUTO_SYNC_DAYS" => nil}, fn ->
        assert AutoSync.sync_days() == 14
      end)
    end

    test "respects custom integer" do
      with_env(%{"AUTO_SYNC_DAYS" => "30"}, fn ->
        assert AutoSync.sync_days() == 30
      end)
    end
  end

  describe "cron_schedule/0" do
    test "defaults to every 6 hours" do
      with_env(%{"AUTO_SYNC_CRON" => nil}, fn ->
        assert AutoSync.cron_schedule() == "0 */6 * * *"
      end)
    end

    test "returns custom expression" do
      with_env(%{"AUTO_SYNC_CRON" => "0 8 * * *"}, fn ->
        assert AutoSync.cron_schedule() == "0 8 * * *"
      end)
    end
  end

  describe "plugins/0" do
    test "includes Cron plugin only when enabled" do
      with_env(%{"ENABLE_AUTO_SYNC" => "true"}, fn ->
        assert Enum.any?(AutoSync.plugins(), &match?({Oban.Plugins.Cron, _}, &1))
      end)

      with_env(%{"ENABLE_AUTO_SYNC" => "false"}, fn ->
        refute Enum.any?(AutoSync.plugins(), &match?({Oban.Plugins.Cron, _}, &1))
      end)
    end
  end

  defp with_env(env_map, fun) do
    original =
      for key <- Map.keys(env_map), into: %{} do
        {key, System.get_env(key)}
      end

    Enum.each(env_map, fn
      {key, nil} -> System.delete_env(key)
      {key, value} -> System.put_env(key, value)
    end)

    try do
      fun.()
    after
      Enum.each(original, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end
  end
end
```

Run the file (expect failures until implementation exists):

```bash
mix test test/gsc_analytics/config/auto_sync_test.exs
```

### 🟢 GREEN: Implement Module

- Implement the module exactly as described above.
- Ensure `log_status!/0` is called in `GscAnalytics.Application.start/2` so toggling the env variable prints a single log line.
- Update `config/runtime.exs` to call `AutoSync.plugins/0`.
- Add `config :gsc_analytics, :auto_sync_module, ...` if not already present (T006 dependency).
- Run the targeted test file until it passes, then run the full suite.

### 🔵 REFACTOR

- Extract guard clauses or private helpers (`parse_integer/2`) if desired.
- Add memoization if repeated reads become a bottleneck (optional now).
- Document the environment variables in `CLAUDE.md` / `README.md`.

## Manual Verification

```bash
# Disabled (default)
mix phx.server
# expect: "Auto-sync DISABLED..."

# Enabled with custom schedule
ENABLE_AUTO_SYNC=true AUTO_SYNC_DAYS=7 AUTO_SYNC_CRON="0 8 * * *" mix phx.server
# expect: "Auto-sync ENABLED: schedule=0 8 * * * days=7"

# Verify Oban config at runtime
iex> Application.get_env(:gsc_analytics, Oban)[:plugins]
```

## Notes
- Never rely on `Application.put_env/3` for runtime toggles—the environment is the single source of truth.
- Always reset environment variables in tests using helper like `with_env/2` to avoid cross-test leakage.
- Logging the config state at boot simplifies on-call debugging.

## 📚 Reference Documentation
- [Environment Config Research](ENVIRONMENT_CONFIG_RESEARCH.md)
- [Cron Scheduling Research](docs/cron-scheduling-research.md)
- [Oban Reference](docs/OBAN_REFERENCE.md) — Plugin usage
