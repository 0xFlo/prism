# T010: End-to-End Integration Tests with TDD

**Status:** 🔵 Not Started  
**Story Points:** 3  
**Priority:** 🔥 P1 Critical  
**TDD Required:** ✅ YES - Red, Green, Refactor  
**Depends On:** T006, T009

## Description
Write deterministic integration tests that execute the entire auto-sync pipeline: Oban worker → workspace iterator → persistence + telemetry. Tests must avoid runtime patching libraries (`:meck`/`:mock`) by relying on the configurable `:gsc_client` and deterministic fake implementations.

## Acceptance Criteria
- [ ] Integration test module covers happy path, multi-workspace flow, telemetry, failure handling, and cron configuration
- [ ] Tests use deterministic fake GSC client module registered via `Application.put_env/3`
- [ ] No random data or `:rand.uniform/1` in fixtures
- [ ] Tests clean up env overrides and ETS/state on exit
- [ ] Coverage includes verification of DB artifacts (`TimeSeries`, `SyncDay`, `Performance`)

## Test Support Module

**File:** `test/support/gsc_fake_client.ex`

```elixir
defmodule GscAnalytics.GscFakeClient do
  @moduledoc false

  @deterministic_rows [
    %{
      "keys" => ["https://example.com/page-1"],
      "clicks" => 100,
      "impressions" => 1_000,
      "ctr" => 0.1,
      "position" => 9.5
    },
    %{
      "keys" => ["https://example.com/page-2"],
      "clicks" => 50,
      "impressions" => 500,
      "ctr" => 0.1,
      "position" => 12.0
    }
  ]

  def fetch_all_urls_for_date(_account_id, site_url, date, _opts) do
    case failing_site?(site_url) do
      true -> {:error, :api_quota_exceeded}
      false -> {:ok, %{"rows" => annotate(@deterministic_rows, date)}}
    end
  end

  def fetch_query_batch(_account_id, requests, _operation) do
    {:ok,
     Enum.map(requests, fn _ ->
       {:ok,
        %{
          "rows" => [
            %{
              "keys" => ["sample query"],
              "clicks" => 10,
              "impressions" => 100,
              "ctr" => 0.1,
              "position" => 8.0
            }
          ]
        }}
     end)}
  end

  # Add other functions used by the sync pipeline as needed (no-ops are fine for unused APIs).

  defp annotate(rows, date) do
    Enum.map(rows, fn row ->
      Map.put(row, "date", Date.to_iso8601(date))
    end)
  end

  defp failing_site?(site_url), do: String.contains?(site_url, "failing")
end
```

Register the fake module in `test/test_helper.exs`:

```elixir
Application.put_env(:gsc_analytics, :gsc_client, GscAnalytics.GscFakeClient)
```

Individual tests can temporarily override this env key if they need custom behaviour.

## TDD Cycle

### 🔴 RED: Write Failing Integration Tests

**File:** `test/gsc_analytics/integration/auto_sync_integration_test.exs`

```elixir
defmodule GscAnalytics.Integration.AutoSyncIntegrationTest do
  use GscAnalytics.DataCase, async: false
  use Oban.Testing, repo: GscAnalytics.Repo

  alias GscAnalytics.Workers.GscSyncWorker
  alias GscAnalytics.{Repo, Accounts}
  alias GscAnalytics.Schemas.{Performance, TimeSeries, SyncDay}

  import Ecto.Query
  import GscAnalytics.{AccountsFixtures, WorkspacesFixtures}

  setup do
    # Ensure fake client is active
    original = Application.get_env(:gsc_analytics, :gsc_client)
    Application.put_env(:gsc_analytics, :gsc_client, GscAnalytics.GscFakeClient)

    on_exit(fn -> Application.put_env(:gsc_analytics, :gsc_client, original) end)

    :ok
  end

  describe "full auto-sync flow" do
    test "syncs a single workspace and persists metrics" do
      account = account_fixture()
      workspace = workspace_fixture(%{account_id: account.id, active: true})

      assert :ok = perform_job(GscSyncWorker, %{})

      assert Repo.aggregate(TimeSeries, :count, :id) > 0
      assert Repo.aggregate(Performance, :count, :id) > 0

      sync_days =
        Repo.all(
          from s in SyncDay,
            where: s.workspace_id == ^workspace.id,
            select: s.status
        )

      assert Enum.all?(sync_days, &(&1 == :complete))
    end

    test "handles multiple workspaces deterministically" do
      account = account_fixture()
      ws1 = workspace_fixture(%{account_id: account.id, active: true, property_url: "sc-domain:site-a.com"})
      ws2 = workspace_fixture(%{account_id: account.id, active: true, property_url: "sc-domain:site-b.com"})
      _inactive = workspace_fixture(%{account_id: account.id, active: false})

      assert :ok = perform_job(GscSyncWorker, %{})

      assert Repo.aggregate(from(s in SyncDay, where: s.workspace_id == ^ws1.id), :count, :id) > 0
      assert Repo.aggregate(from(s in SyncDay, where: s.workspace_id == ^ws2.id), :count, :id) > 0
    end

    test "records partial failures without stopping other workspaces" do
      account = account_fixture()

      workspace_fixture(%{account_id: account.id, active: true, property_url: "sc-domain:working.com"})
      workspace_fixture(%{account_id: account.id, active: true, property_url: "sc-domain:failing.com"})

      assert :ok = perform_job(GscSyncWorker, %{})

      failures =
        Repo.all(
          from s in SyncDay,
            where: s.status == :failed,
            select: {s.workspace_id, s.error_reason}
        )

      assert Enum.any?(failures, fn {_id, reason} -> reason == ":api_quota_exceeded" end)
    end

    test "emits telemetry" do
      test_pid = self()

      :telemetry.attach(
        "auto-sync-integration",
        [[:gsc_analytics, :auto_sync, :started], [:gsc_analytics, :auto_sync, :complete]],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      perform_job(GscSyncWorker, %{})

      assert_receive {:telemetry, [:gsc_analytics, :auto_sync, :started], _m, %{total_workspaces: total}}
      assert total > 0

      assert_receive {:telemetry, [:gsc_analytics, :auto_sync, :complete], measurements, _meta}
      assert measurements.duration_ms >= 0

      :telemetry.detach("auto-sync-integration")
    end
  end

  describe "cron configuration" do
    test "configures cron plugin when ENABLE_AUTO_SYNC=true" do
      System.put_env("ENABLE_AUTO_SYNC", "true")
      on_exit(fn -> System.delete_env("ENABLE_AUTO_SYNC") end)

      plugins = GscAnalytics.Config.AutoSync.plugins()

      assert Enum.any?(plugins, &match?({Oban.Plugins.Cron, _}, &1))
      cron_opts = plugins |> Enum.find_value(fn {mod, opts} -> mod == Oban.Plugins.Cron && opts end)
      assert Enum.any?(cron_opts[:crontab], fn {_, worker, _} -> worker == GscAnalytics.Workers.GscSyncWorker end)
    end
  end
end
```

Run the test file (expect failures).

```bash
mix test test/gsc_analytics/integration/auto_sync_integration_test.exs
```

### 🟢 GREEN: Make Tests Pass

Most implementation already exists from previous tickets. Ensure:

- `GscAnalytics.GscFakeClient` implements every function the sync pipeline calls.
- `GscSyncWorker` emits telemetry (T006) and uses `AutoSync` module.
- `GscAnalytics.Config.AutoSync.plugins/0` (T009) drives Oban configuration.

Run `mix test` for the integration file until it passes.

### 🔵 REFACTOR

- Extract shared helper functions (e.g., `count_sync_days/1`) at bottom of test file.
- Use `assert_enqueued/1` for cron scheduling if desired.
- Keep fake client deterministic: no random numbers, use fixed lists so failures are reproducible.

## Testing Checklist
- [ ] Single workspace happy path
- [ ] Multiple workspaces + inactive filtering
- [ ] Partial failure recorded without halting job
- [ ] Telemetry events emitted
- [ ] Cron plugin configuration verified
- [ ] Environment restored after each test

## Notes
- Always `on_exit/1` env changes and `:telemetry` handlers to prevent leakage across tests.
- Deterministic data speeds up debugging and removes flaky comparisons.
- Avoid `:meck`/`:mock`; fake modules + config injection provide the same flexibility without patching beam code.

## 📚 Reference Documentation
- [Testing Quick Reference](docs/testing-quick-reference.md) — Integration patterns
- [Oban Reference](docs/OBAN_REFERENCE.md) — Oban.Testing helpers
- [Elixir TDD Research](docs/elixir-tdd-research.md) — Strategy for large integration specs
