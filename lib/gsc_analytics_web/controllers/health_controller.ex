defmodule GscAnalyticsWeb.HealthController do
  @moduledoc """
  Health check endpoints for monitoring application status.
  """

  use GscAnalyticsWeb, :controller

  import Ecto.Query
  alias GscAnalytics.{Repo, Config.AutoSync}

  @doc """
  Overall application health check.
  """
  def show(conn, _params) do
    checks = %{
      database: database_status(),
      authenticator: service_status(GscAnalytics.DataSources.GSC.Support.Authenticator),
      sync_progress: service_status(GscAnalytics.DataSources.GSC.Support.SyncProgress),
      oban: service_status(Oban)
    }

    overall =
      if Enum.all?(checks, fn {_key, status} -> status == :ok end) do
        :ok
      else
        :service_unavailable
      end

    conn
    |> put_status(overall)
    |> json(%{
      status: status_label(overall),
      checks: Map.new(checks, fn {key, value} -> {key, status_label(value)} end)
    })
  end

  @doc """
  Auto-sync health check - returns detailed status of background sync jobs.

  Returns:
  - Auto-sync enabled status
  - Sync configuration (days, schedule)
  - Recent job statistics (last 24 hours)
  - Queue status
  - Last successful sync timestamp

  ## Examples

      GET /health/sync
      => 200 OK
  """
  def sync(conn, _params) do
    enabled = AutoSync.enabled?()

    health_data = %{
      enabled: enabled,
      sync_days: AutoSync.sync_days(),
      cron_schedule: AutoSync.cron_schedule(),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    health_data =
      if enabled do
        Map.merge(health_data, %{
          recent_jobs: get_recent_job_stats(),
          queue_status: get_queue_status()
        })
      else
        health_data
      end

    json(conn, health_data)
  end

  defp database_status do
    case Repo.query("SELECT 1") do
      {:ok, _result} -> :ok
      {:error, _reason} -> :error
    end
  rescue
    _ -> :error
  end

  defp service_status(module) when is_atom(module) do
    case Process.whereis(module) do
      pid when is_pid(pid) -> :ok
      _ -> :error
    end
  end

  defp status_label(:ok), do: "ok"
  defp status_label(_), do: "error"

  # Auto-sync specific helpers

  defp get_recent_job_stats do
    twenty_four_hours_ago = DateTime.utc_now() |> DateTime.add(-24, :hour)

    query =
      from j in Oban.Job,
        where: j.worker == "GscAnalytics.Workers.GscSyncWorker",
        where: j.inserted_at >= ^twenty_four_hours_ago,
        select: %{
          state: j.state,
          inserted_at: j.inserted_at,
          completed_at: j.completed_at,
          errors: j.errors
        },
        order_by: [desc: j.inserted_at],
        limit: 10

    jobs = Repo.all(query)

    # Count by state
    state_counts =
      Enum.reduce(jobs, %{}, fn job, acc ->
        Map.update(acc, Atom.to_string(job.state), 1, &(&1 + 1))
      end)

    # Get last successful job
    last_success = Enum.find(jobs, fn j -> j.state == :completed end)

    %{
      total_last_24h: length(jobs),
      by_state: state_counts,
      last_success_at: last_success && DateTime.to_iso8601(last_success.completed_at),
      recent_jobs:
        Enum.map(jobs, fn j ->
          %{
            state: Atom.to_string(j.state),
            inserted_at: DateTime.to_iso8601(j.inserted_at),
            completed_at: j.completed_at && DateTime.to_iso8601(j.completed_at)
          }
        end)
    }
  end

  defp get_queue_status do
    # Check gsc_sync queue
    case Oban.check_queue(queue: :gsc_sync) do
      %{} = status ->
        %{
          limit: status[:limit],
          paused: status[:paused],
          running: status[:running] || [],
          node: status[:node]
        }

      nil ->
        %{error: "Queue not running on this node"}
    end
  end
end
