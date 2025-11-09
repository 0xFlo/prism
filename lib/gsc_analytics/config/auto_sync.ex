defmodule GscAnalytics.Config.AutoSync do
  @moduledoc """
  Configuration module for automatic GSC data synchronization.

  Manages environment-based configuration for background sync jobs, including:
  - Enable/disable flag via `ENABLE_AUTO_SYNC` env var
  - Sync window (days of data to fetch) via `AUTO_SYNC_DAYS` env var
  - Cron schedule for sync frequency via `AUTO_SYNC_CRON` env var

  ## Environment Variables

  - `ENABLE_AUTO_SYNC` - Set to "true" or "1" to enable automatic syncing (default: false)
  - `AUTO_SYNC_DAYS` - Number of days of historical data to sync each run (default: 14)
  - `AUTO_SYNC_CRON` - Cron schedule for sync frequency (default: "0 */6 * * *" - every 6 hours)

  ## Examples

      # Check if auto-sync is enabled
      iex> System.put_env("ENABLE_AUTO_SYNC", "true")
      iex> GscAnalytics.Config.AutoSync.enabled?()
      true

      # Get configured sync window
      iex> System.put_env("AUTO_SYNC_DAYS", "30")
      iex> GscAnalytics.Config.AutoSync.sync_days()
      30

      # Get Oban plugins configuration
      iex> GscAnalytics.Config.AutoSync.plugins()
      [
        {Oban.Plugins.Pruner, max_age: 604800},
        {Oban.Plugins.Lifeline, rescue_after: 1800000},
        {Oban.Plugins.Cron, crontab: [{"0 */6 * * *", GscAnalytics.Workers.GscSyncWorker}]}
      ]
  """

  require Logger

  @default_sync_days 14
  @default_cron_schedule "0 */6 * * *"

  @doc """
  Returns true if automatic syncing is enabled via environment variable.

  Auto-sync is enabled when `ENABLE_AUTO_SYNC` is set to "true" or "1".
  Defaults to false for safety.
  """
  @spec enabled?() :: boolean()
  def enabled? do
    System.get_env("ENABLE_AUTO_SYNC") in ["true", "1"]
  end

  @doc """
  Returns the number of days of historical data to sync each run.

  Reads from `AUTO_SYNC_DAYS` environment variable, defaults to 14.
  Returns default if the value is invalid or negative.
  """
  @spec sync_days() :: pos_integer()
  def sync_days do
    case System.get_env("AUTO_SYNC_DAYS") do
      nil ->
        @default_sync_days

      value ->
        case Integer.parse(value) do
          {days, ""} when days > 0 -> days
          _ -> @default_sync_days
        end
    end
  end

  @doc """
  Returns the cron schedule for automatic syncing.

  Reads from `AUTO_SYNC_CRON` environment variable.
  Defaults to "0 */6 * * *" (every 6 hours at minute 0).

  ## Common Schedules

  - `"0 */6 * * *"` - Every 6 hours (00:00, 06:00, 12:00, 18:00 UTC)
  - `"0 4 * * *"` - Daily at 4am UTC
  - `"0 */12 * * *"` - Every 12 hours (00:00, 12:00 UTC)
  """
  @spec cron_schedule() :: String.t()
  def cron_schedule do
    System.get_env("AUTO_SYNC_CRON") || @default_cron_schedule
  end

  @doc """
  Returns Oban plugin configuration based on auto-sync enabled state.

  Always includes:
  - `Oban.Plugins.Pruner` - Removes completed jobs after 7 days

  When auto-sync is enabled, also includes:
  - `Oban.Plugins.Lifeline` - Rescues orphaned jobs after 30 minutes
  - `Oban.Plugins.Cron` - Schedules periodic sync jobs

  ## Examples

      # When disabled
      iex> System.delete_env("ENABLE_AUTO_SYNC")
      iex> AutoSync.plugins()
      [{Oban.Plugins.Pruner, max_age: 604800}]

      # When enabled
      iex> System.put_env("ENABLE_AUTO_SYNC", "true")
      iex> AutoSync.plugins()
      [
        {Oban.Plugins.Pruner, max_age: 604800},
        {Oban.Plugins.Lifeline, rescue_after: 1800000},
        {Oban.Plugins.Cron, crontab: [...]}
      ]
  """
  @spec plugins() :: [tuple()]
  def plugins do
    base_plugins = [
      # Prune completed jobs after 7 days
      {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7}
    ]

    # SERP pruning and HTTP rechecking cron - always enabled (independent of auto-sync)
    always_on_cron =
      {Oban.Plugins.Cron,
       crontab: [
         # Prune old SERP snapshots daily at 2 AM
         {"0 2 * * *", GscAnalytics.Workers.SerpPruningWorker},
         # Re-check stale HTTP status codes daily at 3 AM
         {"0 3 * * *", GscAnalytics.Workers.HttpStatusRecheckWorker}
       ]}

    if enabled?() do
      base_plugins ++
        [
          # Rescue orphaned jobs after 30 minutes
          {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(30)},
          # Schedule periodic sync jobs + SERP pruning + HTTP rechecking
          {Oban.Plugins.Cron,
           crontab: [
             {cron_schedule(), GscAnalytics.Workers.GscSyncWorker},
             # Prune old SERP snapshots daily at 2 AM
             {"0 2 * * *", GscAnalytics.Workers.SerpPruningWorker},
             # Re-check stale HTTP status codes daily at 3 AM
             {"0 3 * * *", GscAnalytics.Workers.HttpStatusRecheckWorker}
           ]}
        ]
    else
      base_plugins ++ [always_on_cron]
    end
  end

  @doc """
  Logs the current auto-sync configuration status.

  Call this during application startup to make configuration visible in logs.

  ## Examples

      iex> System.put_env("ENABLE_AUTO_SYNC", "true")
      iex> AutoSync.log_status!()
      # Logs: "Auto-sync: ENABLED (sync last 14 days every 0 */6 * * *)"
      :ok

      iex> System.delete_env("ENABLE_AUTO_SYNC")
      iex> AutoSync.log_status!()
      # Logs: "Auto-sync: DISABLED"
      :ok
  """
  @spec log_status!() :: :ok
  def log_status! do
    if enabled?() do
      Logger.info("Auto-sync: ENABLED (sync last #{sync_days()} days every #{cron_schedule()})")
    else
      Logger.info("Auto-sync: DISABLED")
    end

    :ok
  end
end
