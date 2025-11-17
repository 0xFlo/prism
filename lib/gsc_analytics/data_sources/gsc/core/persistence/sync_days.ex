defmodule GscAnalytics.DataSources.GSC.Core.Persistence.SyncDays do
  @moduledoc false

  import Ecto.Query
  require Logger

  alias GscAnalytics.DateTime, as: AppDateTime
  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.SyncDay

  @doc """
  Check if a specific day has already been synced successfully.
  """
  def day_already_synced?(account_id, site_url, date) do
    Repo.exists?(
      from sd in SyncDay,
        where:
          sd.account_id == ^account_id and
            sd.site_url == ^site_url and
            sd.date == ^date and
            sd.status == :complete
    )
  end

  @doc """
  Mark a sync day as running.
  """
  def mark_day_running(account_id, site_url, date) do
    upsert_sync_day(account_id, site_url, date, :running)
  end

  @doc """
  Mark a sync day as complete, optionally updating counters.
  """
  def mark_day_complete(account_id, site_url, date, opts \\ []) do
    upsert_sync_day(account_id, site_url, date, :complete, opts)
  end

  @doc """
  Mark a sync day as failed with the provided error message.
  """
  def mark_day_failed(account_id, site_url, date, error) do
    upsert_sync_day(account_id, site_url, date, :failed, error: error)
  end

  defp upsert_sync_day(account_id, site_url, date, status, opts \\ []) do
    timestamp = AppDateTime.utc_now()

    update_fields =
      [status: status, last_synced_at: timestamp]
      |> maybe_add(:url_count, opts[:url_count])
      |> maybe_add(:query_count, opts[:query_count])
      |> maybe_add(:error, opts[:error])

    attrs =
      %{
        account_id: account_id,
        site_url: site_url,
        date: date,
        status: status,
        last_synced_at: timestamp
      }
      |> maybe_put(:url_count, opts[:url_count])
      |> maybe_put(:query_count, opts[:query_count])
      |> maybe_put(:error, opts[:error])

    changeset = SyncDay.changeset(%SyncDay{}, attrs)

    case Repo.insert(
           changeset,
           on_conflict: [set: update_fields],
           conflict_target: [:account_id, :site_url, :date]
         ) do
      {:ok, sync_day} ->
        {:ok, sync_day}

      {:error, changeset} ->
        Logger.error("Failed to upsert SyncDay: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_add(list, _key, nil), do: list
  defp maybe_add(list, key, value), do: list ++ [{key, value}]
end
