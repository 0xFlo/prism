defmodule GscAnalytics.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    authenticator_children =
      if Application.get_env(:gsc_analytics, :start_authenticator, true) do
        [
          {GscAnalytics.DataSources.GSC.Support.Authenticator,
           name: GscAnalytics.DataSources.GSC.Support.Authenticator}
        ]
      else
        []
      end

    children =
      [
        GscAnalyticsWeb.Telemetry,
        GscAnalytics.Vault,
        GscAnalytics.Repo,
        {Oban, Application.fetch_env!(:gsc_analytics, Oban)},
        {DNSCluster, query: Application.get_env(:gsc_analytics, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: GscAnalytics.PubSub},
        {Finch,
         name: GscAnalytics.Finch,
         pools: %{
           default: [
             size: 70,
             pool_max_idle_time: 60_000
           ]
         }}
      ]
      |> Kernel.++(authenticator_children)
      |> Kernel.++([
        # Task Supervisor for background jobs (HTTP checks, etc.)
        {Task.Supervisor, name: GscAnalytics.TaskSupervisor},
        # Workflow execution infrastructure
        {Registry, keys: :unique, name: GscAnalytics.Workflows.EngineRegistry},
        {DynamicSupervisor,
         strategy: :one_for_one, name: GscAnalytics.Workflows.EngineSupervisor},
        {GscAnalytics.Workflows.ProgressTracker, []},
        # GSC and Crawler progress tracking
        {GscAnalytics.DataSources.GSC.Support.SyncProgress, []},
        {GscAnalytics.Crawler.ProgressTracker, []},
        GscAnalyticsWeb.Endpoint
      ])

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: GscAnalytics.Supervisor]

    # Attach telemetry handlers for audit logging
    GscAnalytics.DataSources.GSC.Telemetry.AuditLogger.attach()

    case Supervisor.start_link(children, opts) do
      {:ok, _pid} = result ->
        # Schedule initial GSC sync on startup if auto-sync is enabled
        schedule_initial_sync()
        result

      error ->
        error
    end
  end

  @doc false
  # Schedules an initial GSC sync job to run immediately after server startup
  # Only runs if ENABLE_AUTO_SYNC is true and not in test environment
  defp schedule_initial_sync do
    if GscAnalytics.Config.AutoSync.enabled?() and Mix.env() != :test do
      require Logger

      # Insert job with schedule_in: 0 to run immediately
      case GscAnalytics.Workers.GscSyncWorker.new(%{}, schedule_in: 0) |> Oban.insert() do
        {:ok, _job} ->
          Logger.info("Scheduled initial GSC sync to run immediately on startup")

        {:error, reason} ->
          Logger.warning(
            "Failed to schedule initial GSC sync on startup: #{inspect(reason)}"
          )
      end
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    GscAnalyticsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
