defmodule GscAnalytics.Workers.GscPropertySyncWorker do
  @moduledoc """
  Oban worker for syncing individual GSC properties.

  This worker handles the actual sync of a single property, allowing for
  controlled concurrency across multiple properties via Oban queue limits.

  ## Configuration

  - **Queue**: `:gsc_property_sync` - Dedicated queue with configurable concurrency
  - **Priority**: 2 - Standard priority (lower than HTTP checks)
  - **Max Attempts**: 3 - Retry up to 3 times on failure
  - **Unique**: Prevents duplicate jobs for the same property

  ## Args

  - `workspace_id` - The workspace (account) ID
  - `property_url` - The GSC property URL (e.g., "sc-domain:example.com")
  - `days` - Number of days to sync

  ## Telemetry Events

  1. `[:gsc_analytics, :property_sync, :started]`
     - `measurements`: `%{system_time: integer()}`
     - `metadata`: `%{workspace_id: integer(), property_url: string(), days: integer()}`

  2. `[:gsc_analytics, :property_sync, :complete]`
     - `measurements`: `%{duration_ms: integer(), urls_synced: integer(), api_calls: integer()}`
     - `metadata`: `%{workspace_id: integer(), property_url: string(), days: integer()}`

  3. `[:gsc_analytics, :property_sync, :failure]`
     - `measurements`: `%{duration_ms: integer()}`
     - `metadata`: `%{workspace_id: integer(), property_url: string(), error: any()}`

  ## Manual Triggering

      # In IEx console
      GscAnalytics.Workers.GscPropertySyncWorker.new(%{
        workspace_id: 4,
        property_url: "https://insighttimer.com/",
        days: 14
      }) |> Oban.insert()
  """

  use Oban.Worker,
    queue: :gsc_property_sync,
    priority: 2,
    max_attempts: 3,
    unique: [
      period: 3600,
      states: [:available, :scheduled, :executing],
      keys: [:workspace_id, :property_url]
    ]

  require Logger

  alias GscAnalytics.DataSources.GSC.Core.Sync

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    workspace_id = args["workspace_id"]
    property_url = args["property_url"]
    days = args["days"] || 14

    start_time = System.monotonic_time(:millisecond)

    Logger.info(
      "Starting property sync: workspace=#{workspace_id}, property=#{property_url}, days=#{days}"
    )

    # Emit start telemetry
    :telemetry.execute(
      [:gsc_analytics, :property_sync, :started],
      %{system_time: System.system_time()},
      %{workspace_id: workspace_id, property_url: property_url, days: days}
    )

    # Perform the sync
    result = sync_property(workspace_id, property_url, days)

    duration_ms = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, summary} ->
        # Emit success telemetry
        :telemetry.execute(
          [:gsc_analytics, :property_sync, :complete],
          %{
            duration_ms: duration_ms,
            urls_synced: summary[:total_urls] || 0,
            api_calls: summary[:api_calls] || 0
          },
          %{workspace_id: workspace_id, property_url: property_url, days: days}
        )

        Logger.info(
          "Property sync completed: workspace=#{workspace_id}, property=#{property_url}, " <>
            "urls=#{summary[:total_urls] || 0}, api_calls=#{summary[:api_calls] || 0}, " <>
            "duration=#{duration_ms}ms"
        )

        :ok

      {:error, reason} = error ->
        # Emit failure telemetry
        :telemetry.execute(
          [:gsc_analytics, :property_sync, :failure],
          %{duration_ms: duration_ms},
          %{workspace_id: workspace_id, property_url: property_url, error: reason}
        )

        Logger.error(
          "Property sync failed: workspace=#{workspace_id}, property=#{property_url}, " <>
            "error=#{inspect(reason)}, duration=#{duration_ms}ms"
        )

        error
    end
  end

  defp sync_property(workspace_id, property_url, days) do
    try do
      Sync.sync_last_n_days(property_url, days, account_id: workspace_id)
    rescue
      exception ->
        {:error, Exception.message(exception)}
    end
  end
end
