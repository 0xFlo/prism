defmodule GscAnalytics.DataSources.GSC.Core.Sync do
  @moduledoc """
  GSC data synchronization orchestrator.

  Provides high-level API for syncing Google Search Console data with
  the local database. Delegates execution to pipeline architecture:

  - `State` - Explicit state management with Agent-based metrics
  - `Pipeline` - Chunk processing and phase coordination
  - `URLPhase` - URL fetching and storage
  - `QueryPhase` - Query fetching and storage with pagination
  - `ProgressTracker` - Centralized progress reporting

  ## Usage

      # Sync specific date range
      Sync.sync_date_range("sc-domain:example.com", ~D[2024-01-01], ~D[2024-01-31])

      # Sync yesterday's data
      Sync.sync_yesterday()

      # Sync last 30 days
      Sync.sync_last_n_days("sc-domain:example.com", 30)

      # Sync full history (stops at empty threshold)
      Sync.sync_full_history("sc-domain:example.com")

  ## Architecture

  The sync process follows a pipeline architecture:

  1. **State Initialization** - Create SyncState with job tracking
  2. **Pipeline Execution** - Process dates in chunks
     - URL Phase: Fetch and store URLs
     - Query Phase: Fetch and store queries with pagination
     - Progress Tracking: Report real-time progress
     - Halt Checking: Stop on empty threshold or errors
  3. **Finalization** - Audit logging and cleanup

  Each phase is independently testable and maintains backwards
  compatibility with existing tests and behavior.

  ## Process Flow

  ```
  sync_date_range
    ↓
  State.new (initialize with Agent)
    ↓
  Pipeline.execute
    ↓
  ┌─────────────────────────────┐
  │ For each chunk of dates:    │
  │  1. Check pause/stop        │
  │  2. URLPhase.fetch_and_store│
  │  3. QueryPhase.fetch_and... │
  │  4. Update metrics          │
  │  5. Check halt conditions   │
  └─────────────────────────────┘
    ↓
  finalize_sync (audit log + cleanup)
  ```

  ## Error Handling

  - URL fetch failures: Mark day as failed, continue with other dates
  - Query fetch failures: Return partial results, halt sync
  - User stop command: Graceful shutdown with partial results
  - Empty threshold: Stop when configured consecutive empty days reached
  """

  require Logger

  alias GscAnalytics.Accounts
  alias GscAnalytics.DataSources.GSC.Core.Config
  alias GscAnalytics.DataSources.GSC.Core.Sync.{Pipeline, ProgressTracker}
  alias GscAnalytics.DataSources.GSC.Core.Sync.State, as: SyncState
  alias GscAnalytics.DataSources.GSC.Telemetry.AuditLogger

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Sync GSC data for a date range.

  ## Options
    - `:account_id` - Account ID (default: 1)
    - `:force?` - Force resync even if data exists
    - `:stop_on_empty?` - Stop when empty results threshold reached
    - `:empty_threshold` - Number of empty days before stopping
    - `:leading_empty_grace_days` - Grace period for leading empty results

  ## Examples

      sync_date_range("sc-domain:example.com", ~D[2024-01-01], ~D[2024-01-31])
  """
  def sync_date_range(site_url, start_date, end_date, opts \\ []) do
    account_id = opts[:account_id] || Config.default_account_id()
    start_time = System.monotonic_time(:millisecond)

    Logger.info("Starting GSC sync for #{site_url} from #{start_date} to #{end_date}")

    # Prepare dates (newest first)
    dates =
      start_date
      |> Date.range(end_date)
      |> Enum.to_list()
      |> Enum.reverse()

    # Start progress tracking
    job_id = ProgressTracker.start_job(account_id, site_url, start_date, end_date, length(dates))

    # Initialize sync state
    state = SyncState.new(job_id, account_id, site_url, dates, opts)

    # Execute sync
    final_state = execute_sync(state)

    # Calculate duration and finalize
    duration_ms = System.monotonic_time(:millisecond) - start_time
    finalize_sync(final_state, duration_ms)
  end

  @doc """
  Sync yesterday's GSC data. Useful for daily cron jobs.
  """
  def sync_yesterday(site_url \\ nil, opts \\ []) do
    account_id = opts[:account_id] || Config.default_account_id()
    site_url = site_url || get_default_site_url(account_id)
    target_date = Date.add(Date.utc_today(), -Config.data_delay_days())

    result =
      sync_date_range(
        site_url,
        target_date,
        target_date,
        Keyword.put(opts, :account_id, account_id)
      )

    normalize_sync_result(result)
  end

  @doc """
  Sync the last N days of GSC data.
  """
  def sync_last_n_days(site_url, days, opts \\ []) when is_integer(days) and days > 0 do
    account_id = opts[:account_id] || Config.default_account_id()
    site_url = site_url || get_default_site_url(account_id)

    end_date = Date.add(Date.utc_today(), -Config.data_delay_days())
    start_date = Date.add(end_date, -(days - 1))

    sync_date_range(site_url, start_date, end_date, Keyword.put(opts, :account_id, account_id))
  end

  @doc """
  Sync as much history as the API will provide.
  Stops when reaching sustained empty results.
  """
  def sync_full_history(site_url, opts \\ []) do
    account_id = opts[:account_id] || Config.default_account_id()
    site_url = site_url || get_default_site_url(account_id)

    end_date = Date.add(Date.utc_today(), -Config.data_delay_days())
    max_days = Keyword.get(opts, :max_days, Config.full_history_days())
    start_date = Date.add(end_date, -(max_days - 1))

    opts =
      opts
      |> Keyword.put(:stop_on_empty?, true)
      |> Keyword.put_new(:empty_threshold, Config.empty_result_limit())
      |> Keyword.put_new(:leading_empty_grace_days, Config.leading_empty_grace_days())

    sync_date_range(site_url, start_date, end_date, Keyword.put(opts, :account_id, account_id))
  end

  @doc """
  Sync all enabled workspaces across all users.

  This function is used by the automatic sync worker to process all active
  workspaces in the system. It iterates through enabled workspaces and syncs
  each one, collecting successes and failures.

  ## Parameters

    - `days` - Number of days of historical data to sync (default: 14)

  ## Returns

    - `{:ok, result}` where result is a map with:
      - `:total_workspaces` - Total number of workspaces processed
      - `:successes` - List of `{workspace, summary}` tuples for successful syncs
      - `:failures` - List of `{workspace, reason}` tuples for failed syncs

  ## Examples

      {:ok, result} = Sync.sync_all_workspaces(14)
      # => %{
      #      total_workspaces: 3,
      #      successes: [{workspace1, summary1}, {workspace2, summary2}],
      #      failures: [{workspace3, :api_timeout}]
      #    }

  ## Telemetry

  Emits a `[:gsc_analytics, :sync_all, :complete]` event with:
    - `measurements`: duration_ms, total_workspaces, successes, failures
    - `metadata`: sync_days
  """
  @spec sync_all_workspaces(pos_integer()) :: {:ok, map()}
  def sync_all_workspaces(days \\ 14) do
    start_time = System.monotonic_time(:millisecond)

    # Get the workspace sync runner (behaviour-based for testing)
    runner = Application.get_env(:gsc_analytics, :workspace_sync_runner, __MODULE__)

    # Fetch all enabled workspaces
    workspaces = GscAnalytics.Workspaces.list_all_enabled_workspaces()

    Logger.info("Starting sync for #{length(workspaces)} enabled workspace(s)")

    # Sync each workspace, collecting results
    {successes, failures} =
      Enum.reduce(workspaces, {[], []}, fn workspace, {succ, fail} ->
        case runner.sync_workspace(workspace, days) do
          {:ok, summary} ->
            Logger.info("Workspace #{workspace.id} synced successfully")
            {[{workspace, summary} | succ], fail}

          {:error, reason} ->
            Logger.error("Workspace #{workspace.id} failed: #{inspect(reason)}")
            {succ, [{workspace, reason} | fail]}
        end
      end)

    duration_ms = System.monotonic_time(:millisecond) - start_time

    result = %{
      total_workspaces: length(workspaces),
      successes: Enum.reverse(successes),
      failures: Enum.reverse(failures)
    }

    # Emit telemetry
    :telemetry.execute(
      [:gsc_analytics, :sync_all, :complete],
      %{
        duration_ms: duration_ms,
        total_workspaces: result.total_workspaces,
        successes: length(result.successes),
        failures: length(result.failures)
      },
      %{sync_days: days}
    )

    Logger.info(
      "Sync completed: #{result.total_workspaces} workspaces, " <>
        "#{length(result.successes)} succeeded, #{length(result.failures)} failed"
    )

    {:ok, result}
  end

  @doc """
  Sync a single workspace by fetching its active property and syncing the last N days.

  This is the default implementation used by `sync_all_workspaces/1`. It can be
  overridden in tests using Mox.

  ## Parameters

    - `workspace` - The workspace struct to sync
    - `days` - Number of days to sync

  ## Returns

    - `{:ok, summary}` on success
    - `{:error, reason}` on failure
  """
  @spec sync_workspace(GscAnalytics.Schemas.Workspace.t(), pos_integer()) ::
          {:ok, map()} | {:error, any()}
  def sync_workspace(workspace, days) do
    account_id = workspace.id

    case Accounts.get_active_property(account_id) do
      nil ->
        {:error, :no_active_property}

      property ->
        sync_fun = sync_last_n_days_fun()

        {:ok, result} =
          sync_fun.(property.property_url, days, account_id: account_id)

        {:ok, %{urls_synced: result.total_urls, api_calls: result.api_calls}}
    end
  end

  # ============================================================================
  # Private - Sync Execution
  # ============================================================================

  defp execute_sync(state), do: Pipeline.execute(state)

  defp finalize_sync(state, duration_ms) do
    # Log audit event
    AuditLogger.log_sync_complete(
      %{
        total_api_calls: state.api_calls,
        total_urls: state.total_urls,
        total_query_rows: state.total_queries,
        duration_ms: duration_ms
      },
      %{
        site_url: state.site_url,
        start_date: List.last(state.dates) |> Date.to_iso8601(),
        end_date: List.first(state.dates) |> Date.to_iso8601()
      }
    )

    {_status, summary} = ProgressTracker.finish_job(state, duration_ms)
    SyncState.cleanup(state)

    {:ok, summary}
  end

  # ============================================================================
  # Private - Utilities
  # ============================================================================

  defp get_default_site_url(account_id) do
    case Accounts.get_active_property_url(account_id) do
      {:ok, url} -> url
      {:error, _} -> raise "No active property set for account #{account_id}"
    end
  end

  defp normalize_sync_result(result) do
    case result do
      {:ok, summary} ->
        case summary[:halt_reason] do
          {:query_fetch_failed, reason} ->
            {:error, reason, failure_metrics(summary)}

          {:query_fetch_halted, reason} ->
            {:error, reason, failure_metrics(summary)}

          :stopped_by_user ->
            {:error, :stopped_by_user, failure_metrics(summary)}

          _ ->
            result
        end

      _ ->
        result
    end
  end

  defp failure_metrics(summary) do
    %{
      url_count: Map.get(summary, :total_urls, 0),
      api_calls: Map.get(summary, :api_calls, 0)
    }
  end

  defp sync_last_n_days_fun do
    Application.get_env(:gsc_analytics, :sync_last_n_days_fun, &__MODULE__.sync_last_n_days/3)
  end
end
