defmodule GscAnalytics.Analytics.MigrationDetector do
  @moduledoc """
  Detects when a known redirect pair swapped in Google Search Console.

  The redirect crawler determines `old_url` → `new_url` relationships. This
  module does **not** discover successors; instead, it marks the first day the
  new URL records impressions and treats that as the migration date. The signal
  is intentionally lightweight—when GSC shows the new URL, we assume the
  migration happened.
  """

  import Ecto.Query

  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.TimeSeries

  @type t :: %{
          old_url: String.t(),
          new_url: String.t(),
          migration_date: Date.t(),
          new_first_impression_on: Date.t(),
          old_last_seen_on: Date.t() | nil,
          confidence: :high
        }

  @doc """
  Return the first-impression migration date for a known redirect pair.

  When the new URL has not appeared in GSC yet, `nil` is returned.
  """
  @spec detect(String.t(), String.t(), integer()) :: t() | nil
  def detect(old_url, new_url, account_id)
      when is_binary(old_url) and is_binary(new_url) and is_integer(account_id) do
    case first_impression_date(new_url, account_id) do
      {:ok, migration_date} ->
        %{
          old_url: old_url,
          new_url: new_url,
          migration_date: migration_date,
          new_first_impression_on: migration_date,
          old_last_seen_on: last_seen_before(old_url, account_id, migration_date),
          confidence: :high
        }

      :error ->
        nil
    end
  end

  defp first_impression_date(url, account_id) do
    query =
      from(ts in TimeSeries,
        where: ts.account_id == ^account_id,
        where: ts.url == ^url,
        where: ts.impressions > 0,
        order_by: [asc: ts.date],
        select: ts.date,
        limit: 1
      )

    case Repo.one(query) do
      nil -> :error
      date -> {:ok, date}
    end
  end

  defp last_seen_before(url, account_id, migration_date) do
    query =
      from(ts in TimeSeries,
        where: ts.account_id == ^account_id,
        where: ts.url == ^url,
        where: ts.date <= ^migration_date,
        where: ts.impressions > 0 or ts.clicks > 0,
        order_by: [desc: ts.date],
        select: ts.date,
        limit: 1
      )

    Repo.one(query)
  end
end
