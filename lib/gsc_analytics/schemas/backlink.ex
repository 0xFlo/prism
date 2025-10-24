defmodule GscAnalytics.Schemas.Backlink do
  @moduledoc """
  Ecto schema for backlink data from external sources.

  ## ⚠️  MANUAL EXTERNAL DATA SOURCE

  This schema stores backlink data that is **manually imported** from external
  tools and vendors. Unlike GSC data which syncs automatically via API, backlinks
  require human intervention to import CSV reports.

  **Data freshness depends on manual import frequency.**

  ## Data Sources

  - `vendor`: Purchased links from link building campaigns
  - `ahrefs`: Backlinks discovered via Ahrefs Site Explorer
  - Future: `moz`, `semrush`, `majestic`, `manual`

  ## Fields

  - `target_url` - The Scrapfly URL receiving the backlink
  - `source_url` - The referring page URL containing the link
  - `source_domain` - Domain extracted from source_url
  - `anchor_text` - Text used for the link
  - `first_seen_at` - When the link was first discovered/published

  ## Data Provenance (External Data Tracking)

  - `data_source` - **REQUIRED** - Which tool/vendor provided this data
  - `import_batch_id` - UUID for the import run that created this record
  - `imported_at` - Timestamp of manual import (not automated sync)
  - `import_metadata` - JSON: `%{file: "report.csv", row: 123, warnings: []}`

  ## Usage

      # via Content.Backlink context
      Content.Backlink.import_vendor_csv("scrapfly/backlinks-report.csv")
      Content.Backlink.list_for_url("https://scrapfly.io/blog/...")
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_data_sources ~w(vendor ahrefs moz semrush majestic manual)

  schema "backlinks" do
    # Core backlink data
    field :target_url, :string
    field :source_url, :string
    field :source_domain, :string
    field :anchor_text, :string
    field :first_seen_at, :utc_datetime

    # SEO metrics (from Ahrefs, prioritized over vendor data)
    field :domain_rating, :integer
    field :domain_traffic, :integer

    # External data provenance
    field :data_source, :string
    field :import_batch_id, :string
    field :imported_at, :utc_datetime
    field :import_metadata, :map

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating backlinks from imports.

  Validates required fields and extracts source_domain from source_url.
  """
  def changeset(backlink, attrs) do
    backlink
    |> cast(attrs, [
      :target_url,
      :source_url,
      :source_domain,
      :anchor_text,
      :first_seen_at,
      :domain_rating,
      :domain_traffic,
      :data_source,
      :import_batch_id,
      :imported_at,
      :import_metadata
    ])
    |> validate_required([:target_url, :source_url, :data_source])
    |> validate_inclusion(:data_source, @valid_data_sources,
      message: "must be one of: #{Enum.join(@valid_data_sources, ", ")}"
    )
    |> validate_url_format(:target_url)
    |> validate_url_format(:source_url)
    |> extract_source_domain()
    |> unique_constraint([:source_url, :target_url],
      name: :backlinks_unique_link,
      message: "backlink already exists"
    )
  end

  @doc """
  Import changeset with default values for batch import operations.
  Automatically sets imported_at to now if not provided.
  """
  def import_changeset(backlink, attrs, batch_id) do
    attrs_with_defaults =
      attrs
      |> Map.put(:import_batch_id, batch_id)
      |> Map.put_new(:imported_at, DateTime.utc_now())

    changeset(backlink, attrs_with_defaults)
  end

  # Private functions

  defp validate_url_format(changeset, field) do
    validate_change(changeset, field, fn _, url ->
      case URI.parse(url) do
        %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and not is_nil(host) ->
          []

        _ ->
          [{field, "must be a valid HTTP(S) URL"}]
      end
    end)
  end

  defp extract_source_domain(changeset) do
    case get_change(changeset, :source_url) do
      nil ->
        changeset

      source_url ->
        domain =
          source_url
          |> URI.parse()
          |> Map.get(:host)

        put_change(changeset, :source_domain, domain)
    end
  end
end
