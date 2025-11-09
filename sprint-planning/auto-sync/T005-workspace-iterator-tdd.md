# T005: Implement Workspace Iterator with TDD

**Status:** 🔵 Not Started  
**Story Points:** 3  
**Priority:** 🔥 P1 Critical  
**TDD Required:** ✅ YES - Red, Green, Refactor  
**Depends On:** T004

## Description
Add a `sync_all_workspaces/1` function that walks every active workspace and invokes the existing `Sync.sync_last_n_days/3`. The implementation must be fully covered by tests written first and must rely on behaviour-driven dependency injection so we can use Mox safely.

## Acceptance Criteria
- [ ] `GscAnalytics.DataSources.GSC.Core.Sync.sync_all_workspaces/1` implemented
- [ ] Only active workspaces (`active: true`) are processed
- [ ] Default range is 14 days but overrideable via option
- [ ] Summaries include total processed, successes, and failures (with reasons)
- [ ] Workspace sync runner extracted behind a behaviour and configured via `Application.get_env/3`
- [ ] Tests written before production code using Mox expectations

## Pre-work: Behaviour + Config

1. **Behaviour definition**  
   **File:** `lib/gsc_analytics/data_sources/gsc/core/workspace_sync.ex`

   ```elixir
   defmodule GscAnalytics.DataSources.GSC.Core.WorkspaceSync do
     @moduledoc """
     Behaviour for syncing a single workspace. Extracted so tests can stub
     `sync_last_n_days/3` via Mox without patching modules at runtime.
     """

     @callback sync_workspace(GscAnalytics.Accounts.Workspace.t(), keyword()) ::
                 {:ok, map()} | {:error, term(), map()}
   end
   ```

2. **Live implementation**  
   **File:** `lib/gsc_analytics/data_sources/gsc/core/workspace_sync/live.ex`

   ```elixir
   defmodule GscAnalytics.DataSources.GSC.Core.WorkspaceSync.Live do
     @behaviour GscAnalytics.DataSources.GSC.Core.WorkspaceSync
     alias GscAnalytics.DataSources.GSC.Core.Sync

     @impl true
     def sync_workspace(workspace, opts) do
       days = Keyword.fetch!(opts, :days)

       Sync.sync_last_n_days(
         workspace.property_url,
         days,
         Keyword.put(opts, :account_id, workspace.account_id)
       )
     end
   end
   ```

3. **Configuration**  
   **File:** `config/config.exs`

   ```elixir
   config :gsc_analytics, :workspace_sync_runner,
     GscAnalytics.DataSources.GSC.Core.WorkspaceSync.Live
   ```

   Tests can override this env key with a mock module.

4. **Mox mock**  
   **File:** `test/test_helper.exs`

   ```elixir
   Mox.defmock(GscAnalytics.WorkspaceSyncMock,
     for: GscAnalytics.DataSources.GSC.Core.WorkspaceSync
   )
   ```

## TDD Cycle

### 🔴 RED: Write Failing Tests First

**File:** `test/gsc_analytics/data_sources/gsc/core/sync_test.exs`

```elixir
defmodule GscAnalytics.DataSources.GSC.Core.SyncTest do
  use GscAnalytics.DataCase, async: true

  import Mox
  import GscAnalytics.{AccountsFixtures, WorkspacesFixtures}

  alias GscAnalytics.DataSources.GSC.Core.Sync
  alias GscAnalytics.WorkspaceSyncMock

  setup :verify_on_exit!

  setup do
    original_runner = Application.get_env(:gsc_analytics, :workspace_sync_runner)
    Application.put_env(:gsc_analytics, :workspace_sync_runner, WorkspaceSyncMock)

    on_exit(fn ->
      Application.put_env(:gsc_analytics, :workspace_sync_runner, original_runner)
    end)

    :ok
  end

  describe "sync_all_workspaces/1" do
    test "syncs only active workspaces" do
      account = account_fixture()
      active = workspace_fixture(%{account_id: account.id, active: true})
      _inactive = workspace_fixture(%{account_id: account.id, active: false})

      expect(WorkspaceSyncMock, :sync_workspace, fn workspace, opts ->
        assert workspace.id == active.id
        assert Keyword.fetch!(opts, :days) == 14
        {:ok, %{total_urls: 120, total_queries: 55}}
      end)

      {:ok, summary} = Sync.sync_all_workspaces(days: 14)

      assert summary.total_workspaces == 2
      assert [{ws, _}] = summary.successes
      assert ws.id == active.id
      assert summary.failures == []
    end

    test "defaults to 14 days when option omitted" do
      account = account_fixture()
      workspace = workspace_fixture(%{account_id: account.id, active: true})

      expect(WorkspaceSyncMock, :sync_workspace, fn ^workspace, opts ->
        assert Keyword.fetch!(opts, :days) == 14
        {:ok, %{total_urls: 80}}
      end)

      assert {:ok, _summary} = Sync.sync_all_workspaces()
    end

    test "continues after failure and records reason" do
      account = account_fixture()
      ws1 = workspace_fixture(%{account_id: account.id, active: true, name: "WS1"})
      ws2 = workspace_fixture(%{account_id: account.id, active: true, name: "WS2"})

      expect(WorkspaceSyncMock, :sync_workspace, 2, fn workspace, _opts ->
        case workspace.id do
          id when id == ws1.id -> {:ok, %{total_urls: 40}}
          _ -> {:error, :api_failure, %{api_calls: 5}}
        end
      end)

      {:ok, summary} = Sync.sync_all_workspaces(days: 7)

      assert Enum.count(summary.successes) == 1
      assert Enum.count(summary.failures) == 1
      assert Enum.any?(summary.failures, fn {ws, reason} ->
               ws.id == ws2.id and reason == :api_failure
             end)
    end

    test "returns complete summary structure" do
      account = account_fixture()
      workspace = workspace_fixture(%{account_id: account.id, active: true})

      expect(WorkspaceSyncMock, :sync_workspace, fn ^workspace, _opts ->
        {:ok, %{total_urls: 150, total_queries: 75, api_calls: 10}}
      end)

      {:ok, summary} = Sync.sync_all_workspaces(days: 3)

      assert summary.total_workspaces == 1
      assert summary.successes == [{workspace, %{total_urls: 150, total_queries: 75, api_calls: 10}}]
      assert summary.failures == []
    end
  end
end
```

Run the focused test file and confirm failures until the production code exists:

```bash
mix test test/gsc_analytics/data_sources/gsc/core/sync_test.exs
```

### 🟢 GREEN: Implement Minimum Code to Pass

**File:** `lib/gsc_analytics/data_sources/gsc/core/sync.ex`

Key steps:

1. Fetch the configured runner module:

   ```elixir
   runner =
     Application.get_env(
       :gsc_analytics,
       :workspace_sync_runner,
       GscAnalytics.DataSources.GSC.Core.WorkspaceSync.Live
     )
   ```

2. Load active workspaces via `GscAnalytics.Accounts.list_active_workspaces/0`.
3. For each workspace call `runner.sync_workspace(workspace, days: days)`.
4. Accumulate tuples:

   ```elixir
   case runner.sync_workspace(workspace, days: days) do
     {:ok, summary} -> {:success, workspace, summary}
     {:error, reason, _metrics} -> {:failure, workspace, reason}
   end
   ```

5. Return

   ```elixir
   {:ok,
     %{
       total_workspaces: length(workspaces),
       successes: successes,
       failures: failures
     }}
   ```

6. Emit telemetry inside `sync_workspace/2` helper so future tickets (T007/T008) can attach handlers:

   ```elixir
   :telemetry.execute(
     [:gsc_analytics, :workspace_sync, status],
     %{workspace_id: workspace.id},
     %{summary: summary_or_reason}
   )
   ```

7. Add `@spec` declarations plus guards for empty workspace lists.

8. Add `GscAnalytics.Accounts.list_active_workspaces/0` if it does not already exist.

Re-run the test file until it passes.

### 🔵 REFACTOR: Clean Up and Optimize

After the minimal implementation is green:

1. Extract `sync_workspace/3` and `build_summary/2` helpers for clarity.
2. Add instrumentation helper that calculates success/failure counts once.
3. Wrap logging with context-rich metadata (workspace id, property URL).
4. Consider streaming enumerations for large workspace sets (`Enum.reduce` instead of building intermediate lists).

Re-run tests to ensure behaviour is unchanged.

## Testing Checklist
- [ ] Sync skips inactive workspaces
- [ ] Default days is 14
- [ ] Failures do not stop iteration
- [ ] Summary structure matches contract
- [ ] Telemetry events emitted for success/failure
- [ ] Returns empty summary gracefully when there are no workspaces

## Definition of Done
- [ ] Behaviour + live runner implemented and configured
- [ ] Tests written first and executed via `mix test`
- [ ] `sync_all_workspaces/1` returns deterministic summaries
- [ ] Telemetry + logging in place for downstream tickets
- [ ] Ready for worker integration (T006)

## Notes
- **Mox over Meck:** Behaviour-based injection keeps tests async-safe and aligns with the company-wide standard outlined in `docs/testing-quick-reference.md`.
- **Env hygiene:** Always reset `:workspace_sync_runner` and any other config overrides in `on_exit/1`.
- **Workspaces fixtures:** Prefer `workspace_fixture/1` to guarantee consistent data and reduce manual inserts.

## 📚 Reference Documentation
- [Elixir TDD Research](docs/elixir-tdd-research.md) — Red/Green/Refactor workflow
- [Testing Quick Reference](docs/testing-quick-reference.md) — Mox + fixture helpers
- [Phoenix & Ecto Patterns](docs/phoenix-ecto-research.md) — Context/query structure
- [Mox Documentation](https://hexdocs.pm/mox/Mox.html)
*** End Patch***
