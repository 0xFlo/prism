defmodule GscAnalytics.DataSources.SERP.Core.Persistence do
  @moduledoc """
  Database operations for SERP snapshots.

  Handles storage and retrieval of SERP position data.
  """

  import Ecto.Query

  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.SerpSnapshot

  @doc """
  Save a new SERP snapshot to the database.

  ## Parameters
  - `attrs` - Map of snapshot attributes (account_id, property_url, url, keyword, etc.)

  ## Returns
  - `{:ok, %SerpSnapshot{}}` on success
  - `{:error, %Ecto.Changeset{}}` on validation/database errors

  ## Example
      iex> save_snapshot(%{
      ...>   account_id: 1,
      ...>   property_url: "sc-domain:example.com",
      ...>   url: "https://example.com",
      ...>   keyword: "test",
      ...>   position: 3,
      ...>   checked_at: DateTime.utc_now()
      ...> })
      {:ok, %SerpSnapshot{}}
  """
  def save_snapshot(attrs) do
    %SerpSnapshot{}
    |> SerpSnapshot.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Get the most recent SERP snapshot for a specific URL.

  ## Parameters
  - `account_id` - Account ID
  - `property_url` - Property URL (e.g., "sc-domain:example.com")
  - `url` - The URL to find

  ## Returns
  - `%SerpSnapshot{}` - The most recent snapshot
  - `nil` - If no snapshot exists

  ## Example
      iex> latest_for_url(1, "sc-domain:example.com", "https://example.com")
      %SerpSnapshot{position: 3, checked_at: ~U[...]}
  """
  def latest_for_url(account_id, property_url, url) do
    SerpSnapshot.latest_for_url(account_id, property_url, url)
    |> Repo.one()
  end

  @doc """
  Get SERP snapshots for a property with optional filtering.

  Returns snapshots that have a position (excludes URL-not-found records),
  ordered by most recent first.

  ## Parameters
  - `account_id` - Account ID
  - `property_url` - Property URL
  - `opts` - Keyword list options:
    - `:limit` - Max results (default: 100)

  ## Returns
  - List of `%SerpSnapshot{}`

  ## Example
      iex> snapshots_for_property(1, "sc-domain:example.com", limit: 10)
      [%SerpSnapshot{}, ...]
  """
  def snapshots_for_property(account_id, property_url, opts \\ []) do
    limit = opts[:limit] || 100

    SerpSnapshot.for_account_and_property(account_id, property_url)
    |> SerpSnapshot.with_position()
    |> order_by([s], desc: s.checked_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Delete SERP snapshots older than the specified number of days.

  Used for data pruning to keep database size manageable.

  ## Parameters
  - `days` - Delete snapshots older than this many days (default: 7)

  ## Returns
  - `{deleted_count, nil}` - Tuple with number of deleted records

  ## Example
      iex> delete_old_snapshots(7)
      {15, nil}  # Deleted 15 old snapshots
  """
  def delete_old_snapshots(days \\ 7) do
    SerpSnapshot.older_than(days)
    |> Repo.delete_all()
  end
end
