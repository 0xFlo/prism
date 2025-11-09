defmodule GscAnalytics.Schemas.SerpSnapshot do
  @moduledoc """
  Ecto schema for SERP (Search Engine Results Page) snapshots.

  Stores real-time SERP position data from ScrapFly API, enabling
  validation of Google Search Console ranking data against actual
  search results.

  ## Fields

  - `account_id` - Multi-tenancy identifier
  - `property_url` - GSC property URL (e.g., "sc-domain:example.com")
  - `url` - The URL being checked in SERP
  - `keyword` - Search query/keyword
  - `position` - Ranking position in SERP (1-100)
  - `serp_features` - List of SERP features (e.g., ["featured_snippet", "people_also_ask"])
  - `competitors` - List of competing URLs with their positions
  - `raw_response` - Full JSON response from ScrapFly for debugging
  - `geo` - Geographic location for search (default: "us")
  - `checked_at` - When the SERP check was performed
  - `api_cost` - ScrapFly API credits used for this query
  - `error_message` - Error details if check failed
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "serp_snapshots" do
    # Multi-tenancy and property identification
    field :account_id, :integer
    field :property_url, :string

    # URL being checked
    field :url, :string

    # SERP Data
    field :keyword, :string
    field :position, :integer
    field :serp_features, {:array, :string}, default: []
    field :competitors, {:array, :map}, default: []
    field :raw_response, :map

    # Metadata
    field :geo, :string, default: "us"
    field :checked_at, :utc_datetime
    field :api_cost, :decimal
    field :error_message, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @required_fields [:account_id, :property_url, :url, :keyword, :checked_at]
  @optional_fields [
    :position,
    :serp_features,
    :competitors,
    :raw_response,
    :geo,
    :api_cost,
    :error_message
  ]

  @doc """
  Creates a changeset for SERP snapshot data.

  ## Examples

      iex> changeset(%SerpSnapshot{}, %{
      ...>   account_id: 1,
      ...>   property_url: "sc-domain:example.com",
      ...>   url: "https://example.com/page",
      ...>   keyword: "elixir phoenix",
      ...>   checked_at: DateTime.utc_now()
      ...> })
      %Ecto.Changeset{valid?: true}

  """
  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_url(:url)
    |> validate_number(:position, greater_than: 0, less_than_or_equal_to: 100)
    |> validate_length(:keyword, min: 1, max: 500)
    |> validate_geo()
  end

  # Query Helpers

  @doc """
  Filters snapshots by property URL.

  ## Examples

      iex> SerpSnapshot.for_property("sc-domain:example.com")
      #Ecto.Query<...>

  """
  def for_property(query \\ __MODULE__, property_url) do
    from(s in query, where: s.property_url == ^property_url)
  end

  @doc """
  Filters snapshots by account and property.
  """
  def for_account_and_property(query \\ __MODULE__, account_id, property_url) do
    from(s in query,
      where: s.account_id == ^account_id and s.property_url == ^property_url
    )
  end

  @doc """
  Filters snapshots by URL.
  """
  def for_url(query \\ __MODULE__, url) do
    from(s in query, where: s.url == ^url)
  end

  @doc """
  Returns the latest snapshot for a given URL and keyword.

  ## Examples

      iex> SerpSnapshot.latest_for_url(1, "sc-domain:example.com", "https://example.com")
      #Ecto.Query<...>

  """
  def latest_for_url(query \\ __MODULE__, account_id, property_url, url) do
    query
    |> for_account_and_property(account_id, property_url)
    |> for_url(url)
    |> order_by([s], desc: s.checked_at)
    |> limit(1)
  end

  @doc """
  Filters snapshots that have a valid position (not nil).
  """
  def with_position(query \\ __MODULE__) do
    from(s in query, where: not is_nil(s.position))
  end

  @doc """
  Filters snapshots checked within the last N days.

  ## Examples

      iex> SerpSnapshot.recent(7)
      #Ecto.Query<...>

  """
  def recent(query \\ __MODULE__, days) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days, :day)
    from(s in query, where: s.checked_at >= ^cutoff)
  end

  @doc """
  Filters snapshots older than N days (for pruning).
  """
  def older_than(query \\ __MODULE__, days) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days, :day)
    from(s in query, where: s.checked_at < ^cutoff)
  end

  # Private Helpers

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn _, url ->
      case URI.parse(url) do
        %URI{scheme: scheme} when scheme in ["http", "https"] ->
          []

        _ ->
          [{field, "must be a valid HTTP(S) URL"}]
      end
    end)
  end

  defp validate_geo(changeset) do
    valid_geos = ["us", "uk", "ca", "au", "de", "fr", "es", "it", "jp", "br"]

    validate_change(changeset, :geo, fn _, geo ->
      if geo in valid_geos do
        []
      else
        [geo: "must be one of: #{Enum.join(valid_geos, ", ")}"]
      end
    end)
  end
end
