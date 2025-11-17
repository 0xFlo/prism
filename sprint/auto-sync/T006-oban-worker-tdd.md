# T006: Create Oban Worker with TDD

**Status:** 🔵 Not Started  
**Story Points:** 3  
**Priority:** 🔥 P1 Critical  
**TDD Required:** ✅ YES - Red, Green, Refactor  
**Depends On:** T005

## Description
Add an Oban worker (`GscAnalytics.Workers.GscSyncWorker`) that schedules the fully automated sync every six hours. The worker must call the workspace iterator from T005, emit telemetry, and expose retry/timeout configuration. Implementation must follow strict TDD with behaviour-driven injection so we can use Mox instead of runtime patching.

## Acceptance Criteria
- [ ] Worker defined at `lib/gsc_analytics/workers/gsc_sync_worker.ex`
- [ ] Uses `Oban.Worker` with queue `:gsc_sync`, priority `1`, timeout `10m`, `max_attempts >= 3`
- [ ] Invokes configurable auto-sync service (behaviour) with `days: 14`
- [ ] Emits telemetry for success/failure and logs structured summary
- [ ] Returns `:ok` for partial failures but propagates fatal errors
- [ ] Tests written first using `Oban.Testing` + Mox

## Pre-work: Auto-Sync Behaviour

1. **Behaviour definition**  
   **File:** `lib/gsc_analytics/auto_sync.ex`

   ```elixir
   defmodule GscAnalytics.AutoSync do
     @moduledoc """
     Behaviour for running the full workspace sync. Allows Mox stubs in tests
     without touching the production `Sync` module.
     """

     @type summary :: %{
             total_workspaces: non_neg_integer(),
             successes: list(),
             failures: list()
           }

     @callback sync_all(keyword()) :: {:ok, summary()} | {:error, term()}
   end
   ```

2. **Live implementation**  
   **File:** `lib/gsc_analytics/auto_sync/live.ex`

   ```elixir
   defmodule GscAnalytics.AutoSync.Live do
     @behaviour GscAnalytics.AutoSync
     alias GscAnalytics.DataSources.GSC.Core.Sync

     @impl true
     def sync_all(opts), do: Sync.sync_all_workspaces(opts)
   end
   ```

3. **Configuration**  
   **File:** `config/config.exs`

   ```elixir
   config :gsc_analytics, :auto_sync_module, GscAnalytics.AutoSync.Live
   ```

4. **Mox mock**  
   **File:** `test/test_helper.exs`

   ```elixir
   Mox.defmock(GscAnalytics.AutoSyncMock, for: GscAnalytics.AutoSync)
   ```

## TDD Cycle

### 🔴 RED: Write Failing Tests First

**File:** `test/gsc_analytics/workers/gsc_sync_worker_test.exs`

```elixir
defmodule GscAnalytics.Workers.GscSyncWorkerTest do
  use GscAnalytics.DataCase, async: true
  use Oban.Testing, repo: GscAnalytics.Repo

  import Mox
  alias GscAnalytics.Workers.GscSyncWorker
  alias GscAnalytics.AutoSyncMock

  setup :verify_on_exit!

  setup do
    original = Application.get_env(:gsc_analytics, :auto_sync_module)
    Application.put_env(:gsc_analytics, :auto_sync_module, AutoSyncMock)

    on_exit(fn -> Application.put_env(:gsc_analytics, :auto_sync_module, original) end)
    :ok
  end

  describe "perform/1" do
    test "runs the auto-sync service with 14-day window" do
      expect(AutoSyncMock, :sync_all, fn opts ->
        assert Keyword.get(opts, :days) == 14
        {:ok, %{total_workspaces: 1, successes: [:ok], failures: []}}
      end)

      assert :ok = perform_job(GscSyncWorker, %{})
    end

    test "propagates fatal errors" do
      expect(AutoSyncMock, :sync_all, fn _ -> {:error, :database_down} end)

      assert {:error, :database_down} = perform_job(GscSyncWorker, %{})
    end

    test "emits telemetry on success" do
      expect(AutoSyncMock, :sync_all, fn _ ->
        {:ok,
         %{
           total_workspaces: 2,
           successes: [:ws1],
           failures: [:ws2]
         }}
      end)

      test_pid = self()

      :telemetry.attach(
        "auto-sync-worker-success",
        [:gsc_analytics, :auto_sync, :complete],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      assert :ok = perform_job(GscSyncWorker, %{})

      assert_receive {
        :telemetry,
        [:gsc_analytics, :auto_sync, :complete],
        %{successes: 1, failures: 1, total_workspaces: 2, duration_ms: duration},
        %{results: %{successes: [:ws1], failures: [:ws2]}}
      }

      assert is_integer(duration) and duration >= 0

      :telemetry.detach("auto-sync-worker-success")
    end

    test "returns :ok even with partial failures" do
      expect(AutoSyncMock, :sync_all, fn _ ->
        {:ok, %{total_workspaces: 2, successes: [:ws1], failures: [:ws2]}}
      end)

      assert :ok = perform_job(GscSyncWorker, %{})
    end
  end

  describe "configuration" do
    test "enqueues onto gsc_sync queue" do
      {:ok, job} = GscSyncWorker.new(%{}) |> Oban.insert()
      assert job.queue == "gsc_sync"
      assert job.priority == 1
    end

    test "exposes retry + timeout settings" do
      job = GscSyncWorker.new(%{})
      assert job.max_attempts >= 3
      assert GscSyncWorker.timeout_ms() == :timer.minutes(10)
    end
  end
end
```

Run the file to see expected failures:

```bash
mix test test/gsc_analytics/workers/gsc_sync_worker_test.exs
```

### 🟢 GREEN: Implement Minimum Code to Pass

1. **Worker module**  
   **File:** `lib/gsc_analytics/workers/gsc_sync_worker.ex`

   ```elixir
defmodule GscAnalytics.Workers.GscSyncWorker do
  use Oban.Worker,
    queue: :gsc_sync,
    priority: 1,
    max_attempts: 3,
    timeout: :timer.minutes(10)

  require Logger
  @sync_days 14
  @timeout_ms :timer.minutes(10)

  def timeout_ms, do: @timeout_ms

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
       sync_module =
         Application.get_env(:gsc_analytics, :auto_sync_module, GscAnalytics.AutoSync.Live)

       started_at = System.monotonic_time(:millisecond)

       case sync_module.sync_all(days: @sync_days) do
         {:ok, results} ->
           duration = System.monotonic_time(:millisecond) - started_at
           emit_telemetry(results, duration)
           log_success(results, duration)
           :ok

         {:error, reason} ->
           Logger.error("Auto-sync failed: #{inspect(reason)}")
           {:error, reason}
       end
     end
   end
   ```

2. **Helper functions**
   - `emit_telemetry/2` publishes `[:gsc_analytics, :auto_sync, :complete]` with measurement keys `:total_workspaces`, `:successes`, `:failures`, `:duration_ms`.
   - `log_success/2` writes structured multi-line info log and warns when failures exist.

3. **Logging on failure** should include `reason` and use `Logger.error/2`.

Re-run the worker test file until green.

### 🔵 REFACTOR: Clean Up

- Extract `auto_sync_module/0` helper to keep `perform/1` concise.
- Format log output using `Logger.info/2` with metadata (`auto_sync: true`).
- Add `handle_success/2` private function for readability.
- Consider instrumentation for additional metrics (e.g., URLs per second) but keep tests updated.

## Testing Checklist
- [ ] `perform/1` happy path returns `:ok`
- [ ] Fatal errors propagate
- [ ] Telemetry event emitted with counts + duration
- [ ] Partial failures still return `:ok`
- [ ] Worker enqueues on `:gsc_sync`
- [ ] Timeout/retry configuration asserted
- [ ] Oban job can be inserted manually

## Definition of Done
- [ ] Behaviour + mock in place
- [ ] Worker implemented with logging + telemetry
- [ ] Tests written first and all pass
- [ ] Ready for cron scheduling (T003/T009)

## Notes
- **Mox:** Always call `setup :verify_on_exit!` so expectations must be met.
- **Telemetry:** Use `:telemetry.attach/4` only inside tests and clean up with `:telemetry.detach/1`.
- **Oban.Testing:** Provides `perform_job/2` and `assert_enqueued/1`; leverage it if you extend tests later.
- **No meck:** Runtime patching breaks async tests—stick to behaviours for every external dependency.

## 📚 Reference Documentation
- [Oban Reference](docs/OBAN_REFERENCE.md) — Worker config + Oban.Testing
- [Error Handling Research](docs/elixir_error_handling_research.md) — Retry strategies
- [Testing Quick Reference](docs/testing-quick-reference.md) — Mox patterns
- [Telemetry Guide](docs/elixir-tdd-research.md#telemetry) — Emitting custom events
