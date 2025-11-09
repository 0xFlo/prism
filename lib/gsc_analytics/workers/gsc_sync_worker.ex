defmodule GscAnalytics.Workers.GscSyncWorker do
  @moduledoc """
  Oban worker for automatic GSC data synchronization.

  This worker runs periodically (configured via Oban.Plugins.Cron) to sync
  Google Search Console data for all enabled workspaces in the system.

  ## Configuration

  The worker's behavior is controlled by environment variables via
  `GscAnalytics.Config.AutoSync`:

  - `ENABLE_AUTO_SYNC` - Must be "true" or "1" to enable (default: false)
  - `AUTO_SYNC_DAYS` - Number of days to sync per run (default: 14)
  - `AUTO_SYNC_CRON` - Cron schedule for sync frequency (default: "0 */6 * * *")

  ## Worker Configuration

  - **Queue**: `:gsc_sync` - Dedicated queue with concurrency of 1
  - **Priority**: 1 - High priority background job
  - **Max Attempts**: 3 - Retry up to 3 times on failure
  - **Timeout**: 10 minutes - Long-running job for multiple workspaces

  ## Telemetry Events

  Emits three telemetry events:

  1. `[:gsc_analytics, :auto_sync, :started]`
     - `measurements`: `%{system_time: integer()}`
     - `metadata`: `%{sync_days: integer()}`

  2. `[:gsc_analytics, :auto_sync, :complete]`
     - `measurements`: `%{duration_ms: integer(), total_workspaces: integer(), successes: integer(), failures: integer()}`
     - `metadata`: `%{sync_days: integer()}`

  3. `[:gsc_analytics, :auto_sync, :failure]`
     - `measurements`: `%{duration_ms: integer()}`
     - `metadata`: `%{error: any(), sync_days: integer()}`

  ## Manual Triggering

  To manually trigger a sync job:

      # In IEx console
      GscAnalytics.Workers.GscSyncWorker.new(%{}) |> Oban.insert()

      # Or with custom days
      GscAnalytics.Workers.GscSyncWorker.new(%{days: 30}) |> Oban.insert()

  ## Testing

  In tests, use `Oban.Testing.perform_job/2`:

      test "worker syncs all workspaces" do
        perform_job(GscSyncWorker, %{})
      end
  """

  use Oban.Worker,
    queue: :gsc_sync,
    priority: 1,
    max_attempts: 3

  require Logger

  alias GscAnalytics.Config.AutoSync

  @doc """
  Performs the sync job for all enabled workspaces.

  ## Args

  - `args` - Job arguments map (currently unused, reserved for future use)

  ## Returns

  - `:ok` on success (even if some workspaces fail - failures are logged)
  - `{:error, reason}` on catastrophic failure
  """
  @impl Oban.Worker
  def perform(_job) do
    start_time = System.monotonic_time(:millisecond)
    sync_days = AutoSync.sync_days()

    Logger.info("Starting automatic GSC sync for all enabled workspaces (#{sync_days} days)")

    # Emit start telemetry
    :telemetry.execute(
      [:gsc_analytics, :auto_sync, :started],
      %{system_time: System.system_time()},
      %{sync_days: sync_days}
    )

    # Get the auto-sync module (behaviour-based for testing)
    auto_sync =
      Application.get_env(
        :gsc_analytics,
        :auto_sync_module,
        GscAnalytics.DataSources.GSC.Core.Sync
      )

    # Perform the sync
    result = auto_sync.sync_all_workspaces(sync_days)

    duration_ms = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, summary} ->
        # Emit success telemetry
        :telemetry.execute(
          [:gsc_analytics, :auto_sync, :complete],
          %{
            duration_ms: duration_ms,
            total_workspaces: summary.total_workspaces,
            successes: length(summary.successes),
            failures: length(summary.failures)
          },
          %{sync_days: sync_days}
        )

        Logger.info(
          "Auto-sync completed: #{summary.total_workspaces} workspaces, " <>
            "#{length(summary.successes)} succeeded, #{length(summary.failures)} failed " <>
            "in #{duration_ms}ms"
        )

        :ok

      {:error, reason} = error ->
        # Emit failure telemetry
        :telemetry.execute(
          [:gsc_analytics, :auto_sync, :failure],
          %{duration_ms: duration_ms},
          %{error: reason, sync_days: sync_days}
        )

        Logger.error("Auto-sync failed after #{duration_ms}ms: #{inspect(reason)}")

        error
    end
  end

  @doc """
  Returns the worker configuration for inspection/testing.

  This is a convenience function for tests to verify worker configuration.
  """
  def worker_config do
    %{
      queue: :gsc_sync,
      priority: 1,
      max_attempts: 3
    }
  end
end
