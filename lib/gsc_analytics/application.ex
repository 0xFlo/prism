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
        {GscAnalytics.DataSources.GSC.Support.SyncProgress, []},
        {GscAnalytics.Crawler.ProgressTracker, []},
        GscAnalyticsWeb.Endpoint
      ])

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: GscAnalytics.Supervisor]

    # Attach telemetry handlers for audit logging
    GscAnalytics.DataSources.GSC.Telemetry.AuditLogger.attach()

    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    GscAnalyticsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
