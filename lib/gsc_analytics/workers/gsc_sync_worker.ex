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
  alias GscAnalytics.Accounts
  alias GscAnalytics.Workers.GscPropertySyncWorker

  @doc """
  Orchestrates sync jobs by enqueuing individual property sync workers.

  Instead of syncing all properties sequentially in one job, this worker
  enqueues separate jobs for each active property. This allows for:
  - Controlled concurrency via Oban queue limits
  - Individual retries per property
  - Better observability and scaling

  ## Args

  - `args` - Job arguments map (currently unused, reserved for future use)

  ## Returns

  - `:ok` on success (jobs enqueued successfully)
  - `{:error, reason}` on catastrophic failure
  """
  @impl Oban.Worker
  def perform(_job) do
    start_time = System.monotonic_time(:millisecond)
    sync_days = AutoSync.sync_days()

    Logger.info("Starting automatic GSC sync orchestrator (#{sync_days} days)")

    # Emit start telemetry
    :telemetry.execute(
      [:gsc_analytics, :auto_sync, :started],
      %{system_time: System.system_time()},
      %{sync_days: sync_days}
    )

    # Fetch all active properties across all enabled workspaces
    properties = Accounts.list_all_active_properties()

    Logger.info("Enqueueing sync jobs for #{length(properties)} active properties")

    # Enqueue individual property sync jobs
    {successes, failures} =
      properties
      |> Enum.map(fn property ->
        job =
          GscPropertySyncWorker.new(%{
            workspace_id: property.workspace_id,
            property_url: property.property_url,
            days: sync_days
          })

        case Oban.insert(job) do
          {:ok, _job} -> {:ok, property}
          {:error, reason} -> {:error, property, reason}
        end
      end)
      |> Enum.split_with(fn
        {:ok, _} -> true
        _ -> false
      end)

    duration_ms = System.monotonic_time(:millisecond) - start_time

    # Emit completion telemetry
    :telemetry.execute(
      [:gsc_analytics, :auto_sync, :complete],
      %{
        duration_ms: duration_ms,
        total_properties: length(properties),
        jobs_enqueued: length(successes),
        enqueue_failures: length(failures)
      },
      %{sync_days: sync_days}
    )

    if failures != [] do
      Logger.warning(
        "Auto-sync orchestrator: #{length(failures)} jobs failed to enqueue: " <>
          inspect(Enum.map(failures, fn {:error, p, r} -> {p.property_url, r} end))
      )
    end

    Logger.info(
      "Auto-sync orchestrator completed: #{length(successes)} jobs enqueued, " <>
        "#{length(failures)} failed to enqueue in #{duration_ms}ms"
    )

    :ok
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
