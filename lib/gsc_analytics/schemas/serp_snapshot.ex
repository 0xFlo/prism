defmodule GscAnalytics.Schemas.SerpSnapshot do
  @moduledoc """
  Ecto schema for SERP (Search Engine Results Page) snapshots.

  The schema stores both the raw ScrapFly response (via the built-in `JSON`
  module) and normalized analytics fields:

    * top-10 competitors with `title`, `url`, `domain`, `content_type`, and `position`
    * detected SERP features and AI Overview details
    * derived metadata (`content_types_present`, `scrapfly_mentioned_in_ao`, etc.)

  Competitor entries are versioned (`schema_version`) so future migrations can
  upgrade old rows without breaking queries.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @competitor_schema_version 2
  @default_content_type "website"
  @content_type_whitelist [
    "ai_overview",
    "forum",
    "paa",
    "reddit",
    "website",
    "youtube"
  ]

  schema "serp_snapshots" do
    # Multi-tenancy and property identification
    field :account_id, :integer
    field :property_url, :string

    # URL being checked
    field :url, :string

    belongs_to :serp_check_run, GscAnalytics.Schemas.SerpCheckRun, type: :binary_id

    # SERP Data
    field :keyword, :string
    field :position, :integer
    field :serp_features, {:array, :string}, default: []
    field :competitors, {:array, :map}, default: []
    field :content_types_present, {:array, :string}, default: []
    field :raw_response, :map

    # AI Overview data
    field :ai_overview_present, :boolean, default: false
    field :ai_overview_text, :string
    field :ai_overview_citations, {:array, :map}, default: []
    field :scrapfly_mentioned_in_ao, :boolean, default: false
    field :scrapfly_citation_position, :integer

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
    :error_message,
    :ai_overview_present,
    :ai_overview_text,
    :ai_overview_citations,
    :content_types_present,
    :scrapfly_mentioned_in_ao,
    :scrapfly_citation_position,
    :serp_check_run_id
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
    |> sanitize_raw_response()
    |> normalize_competitors()
    |> normalize_content_types()
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

  # Data Helpers

  @doc """
  Returns the current competitor map schema version.
  """
  def competitor_schema_version, do: @competitor_schema_version

  @doc """
  Normalizes competitor entries into the persisted structure.
  """
  def migrate_competitors(nil), do: []

  def migrate_competitors(competitors) when is_list(competitors) do
    competitors
    |> Enum.with_index(1)
    |> Enum.map(fn {entry, fallback_position} ->
      normalize_competitor_entry(entry, fallback_position)
    end)
    |> Enum.reject(&is_nil/1)
  end

  def migrate_competitors(_), do: []

  @doc """
  Extracts the unique content types contained in a competitor collection.
  """
  def content_types_from_competitors(competitors) when is_list(competitors) do
    competitors
    |> Enum.map(fn competitor ->
      competitor["content_type"] || competitor[:content_type]
    end)
    |> Enum.map(&normalize_content_type_value/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  def content_types_from_competitors(_), do: []

  @doc """
  Returns whether ScrapFly is cited inside AI Overview results and the position.
  """
  @spec scrapfly_citation_stats(list() | nil) :: {boolean(), integer() | nil}
  def scrapfly_citation_stats(nil), do: {false, nil}

  def scrapfly_citation_stats(citations) when is_list(citations) do
    citations
    |> Enum.find(fn citation ->
      domain =
        citation
        |> fetch_value(:domain)
        |> safe_downcase()

      domain != "" and String.contains?(domain, "scrapfly")
    end)
    |> case do
      nil ->
        {false, nil}

      citation ->
        position = citation |> fetch_value(:position) |> normalize_position(nil)
        {true, position}
    end
  end

  def scrapfly_citation_stats(_), do: {false, nil}

  # Private Helpers

  defp sanitize_raw_response(changeset) do
    case get_change(changeset, :raw_response) do
      nil ->
        changeset

      raw_response when is_map(raw_response) ->
        sanitized = sanitize_map_strings(raw_response)
        put_change(changeset, :raw_response, sanitized)
    end
  end

  defp normalize_competitors(changeset) do
    case get_change(changeset, :competitors) do
      nil ->
        changeset

      competitors ->
        put_change(changeset, :competitors, migrate_competitors(competitors))
    end
  end

  defp normalize_content_types(changeset) do
    case get_change(changeset, :content_types_present) do
      nil ->
        changeset

      content_types when is_list(content_types) ->
        normalized =
          content_types
          |> Enum.map(&normalize_content_type_value/1)
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()

        put_change(changeset, :content_types_present, normalized)
    end
  end

  defp normalize_competitor_entry(entry, fallback_position) when is_map(entry) do
    url = entry |> fetch_value(:url) |> normalize_url_value()

    if url in [nil, ""] do
      nil
    else
      %{
        "position" => entry |> fetch_value(:position) |> normalize_position(fallback_position),
        "title" => entry |> fetch_value(:title) |> safe_trimmed_string(),
        "url" => url,
        "domain" => entry |> fetch_value(:domain) |> normalize_domain_value(url),
        "content_type" => entry |> fetch_value(:content_type) |> normalize_content_type_value(),
        "schema_version" => @competitor_schema_version
      }
    end
  end

  defp normalize_competitor_entry(_entry, _fallback_position), do: nil

  defp normalize_url_value(nil), do: nil

  defp normalize_url_value(url) do
    url
    |> to_string()
    |> String.trim()
  end

  defp normalize_domain_value(nil, url), do: derive_domain_from_url(url)

  defp normalize_domain_value(domain, _url) do
    domain
    |> to_string()
    |> String.trim()
    |> String.replace(~r{^https?://}, "")
    |> String.replace(~r{^www\.}, "")
    |> String.split("/")
    |> List.first()
    |> safe_downcase()
  end

  defp derive_domain_from_url(nil), do: ""

  defp derive_domain_from_url(url) do
    url
    |> normalize_domain_value(nil)
  end

  defp normalize_position(nil, fallback_position), do: fallback_position

  defp normalize_position(position, _fallback_position) when is_integer(position) do
    position
  end

  defp normalize_position(position, fallback_position) do
    case Integer.parse(to_string(position || "")) do
      {value, _} -> value
      :error -> fallback_position
    end
  end

  defp normalize_content_type_value(nil), do: @default_content_type

  defp normalize_content_type_value(type) do
    type =
      type
      |> to_string()
      |> safe_downcase()

    if type in @content_type_whitelist do
      type
    else
      @default_content_type
    end
  end

  defp safe_trimmed_string(nil), do: nil

  defp safe_trimmed_string(value) do
    value
    |> to_string()
    |> String.trim()
  end

  defp safe_downcase(nil), do: ""

  defp safe_downcase(value) do
    value
    |> to_string()
    |> String.downcase()
  end

  defp fetch_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  defp fetch_value(_, _), do: nil

  defp sanitize_map_strings(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      {sanitize_value(key), sanitize_value(value)}
    end)
  end

  defp sanitize_value(value) when is_binary(value) do
    # Remove null bytes (\u0000) which PostgreSQL cannot store in text/jsonb
    String.replace(value, <<0>>, "")
  end

  defp sanitize_value(value) when is_map(value) do
    sanitize_map_strings(value)
  end

  defp sanitize_value(value) when is_list(value) do
    Enum.map(value, &sanitize_value/1)
  end

  defp sanitize_value(value), do: value

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
