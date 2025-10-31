defmodule GscAnalyticsWeb.HealthController do
  use GscAnalyticsWeb, :controller

  alias GscAnalytics.Repo

  def show(conn, _params) do
    checks = %{
      database: database_status(),
      authenticator: service_status(GscAnalytics.DataSources.GSC.Support.Authenticator),
      sync_progress: service_status(GscAnalytics.DataSources.GSC.Support.SyncProgress)
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
end
