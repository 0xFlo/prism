defmodule GscAnalytics.DataSources.Backlinks.Backlink do
  @moduledoc """
  Context module for backlink data management.

  ## ⚠️  MANUAL EXTERNAL DATA SOURCE

  Unlike GSC data which syncs automatically via API, backlinks come from:
  - **Vendor reports** (purchased link campaigns)
  - **Ahrefs exports** (backlink discovery tool)
  - **Manual CSV imports** (human-initiated, not automated)

  **Data freshness depends on when reports are manually imported.**

  ## Import Sources

  - `vendor`: Purchased links from link building campaigns
  - `ahrefs`: Discovered backlinks from Ahrefs Site Explorer

  Future sources: Moz, Semrush, Majestic, manual additions

  ## Usage Examples

      # Import vendor CSV
      Backlink.import_vendor_csv("scrapfly/backlinks-report.csv")

      # Import Ahrefs CSV
      Backlink.import_ahrefs_csv("scrapfly/ahrefs-backlink-report.csv")

      # Get backlink count for dashboard
      Backlink.count_by_url("https://scrapfly.io/blog/...")

      # List all backlinks for URL detail view
      Backlink.list_for_url("https://scrapfly.io/blog/...")

      # Check data staleness
      Backlink.data_staleness("https://scrapfly.io/blog/...")
  """

  import Ecto.Query
  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.Backlink, as: BacklinkSchema

  @doc """
  Count backlinks for a specific target URL.

  Returns the count of distinct backlinks pointing to the URL.
  Used in dashboard table aggregation.

  ## Examples

      iex> count_by_url("https://scrapfly.io/blog/web-scraping-with-scrapy/")
      42
  """
  def count_by_url(url) when is_binary(url) do
    from(b in BacklinkSchema, where: b.target_url == ^url, select: count(b.id))
    |> Repo.one()
  end

  @doc """
  List all backlinks for a specific target URL.

  Returns backlinks ordered by first_seen_at (newest first).
  Includes source_url, source_domain, anchor_text, first_seen_at, data_source.

  Used in URL detail view to display complete backlink list.

  ## Examples

      iex> list_for_url("https://scrapfly.io/blog/...")
      [
        %{source_domain: "example.com", anchor_text: "web scraping", ...},
        ...
      ]
  """
  def list_for_url(url) when is_binary(url) do
    from(b in BacklinkSchema,
      where: b.target_url == ^url,
      order_by: [desc: b.first_seen_at],
      select: %{
        id: b.id,
        source_url: b.source_url,
        source_domain: b.source_domain,
        anchor_text: b.anchor_text,
        first_seen_at: b.first_seen_at,
        domain_rating: b.domain_rating,
        domain_traffic: b.domain_traffic,
        data_source: b.data_source,
        imported_at: b.imported_at
      }
    )
    |> Repo.all()
  end

  @doc """
  Get aggregated backlink counts per URL for dashboard display.

  Returns map of %{url => %{count: N, last_imported: datetime}}.

  ## Examples

      iex> aggregate_counts_by_url(["https://scrapfly.io/blog/..."])
      %{"https://scrapfly.io/blog/..." => %{count: 5, last_imported: ~U[...]}}
  """
  def aggregate_counts_by_url(urls) when is_list(urls) do
    from(b in BacklinkSchema,
      where: b.target_url in ^urls,
      group_by: b.target_url,
      select: {b.target_url, %{count: count(b.id), last_imported: max(b.imported_at)}}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Check data staleness for a URL.

  Returns number of days since last import, or nil if no backlinks found.
  Data is considered stale if >90 days old.

  ## Examples

      iex> data_staleness("https://scrapfly.io/blog/...")
      {:ok, 15}  # 15 days old

      iex> data_staleness("https://scrapfly.io/blog/no-backlinks")
      {:error, :no_data}
  """
  def data_staleness(url) when is_binary(url) do
    query =
      from(b in BacklinkSchema,
        where: b.target_url == ^url,
        select: max(b.imported_at)
      )

    case Repo.one(query) do
      nil ->
        {:error, :no_data}

      last_import ->
        days_old = DateTime.diff(DateTime.utc_now(), last_import, :day)
        {:ok, days_old}
    end
  end

  @doc """
  Check if backlink data is stale (>90 days old).

  ## Examples

      iex> stale?("https://scrapfly.io/blog/...")
      false

      iex> stale?(~U[2024-01-01 00:00:00Z])
      true
  """
  def stale?(url) when is_binary(url) do
    case data_staleness(url) do
      {:ok, days} -> days > 90
      {:error, :no_data} -> true
    end
  end

  def stale?(%DateTime{} = last_imported_at) do
    days_old = DateTime.diff(DateTime.utc_now(), last_imported_at, :day)
    days_old > 90
  end

  def stale?(nil), do: true

  @doc """
  Import vendor CSV report.

  Delegates to VendorCSV importer module.
  See `GscAnalytics.DataSources.Backlinks.Importers.VendorCSV` for details.
  """
  def import_vendor_csv(path) do
    GscAnalytics.DataSources.Backlinks.Importers.VendorCSV.import(path)
  end

  @doc """
  Import Ahrefs CSV export.

  Delegates to AhrefsCSV importer module.
  See `GscAnalytics.DataSources.Backlinks.Importers.AhrefsCSV` for details.
  """
  def import_ahrefs_csv(path) do
    GscAnalytics.DataSources.Backlinks.Importers.AhrefsCSV.import(path)
  end

  @doc """
  Get last import timestamp across all backlinks.

  Returns the most recent imported_at datetime, or nil if no backlinks.
  Useful for dashboard warnings about data freshness.
  """
  def last_import_timestamp do
    from(b in BacklinkSchema, select: max(b.imported_at))
    |> Repo.one()
  end

  @doc """
  Get summary statistics for all backlinks.

  Returns:
  - total_backlinks: Total count
  - unique_targets: Unique Scrapfly URLs with backlinks
  - unique_sources: Unique referring domains
  - last_import: Most recent import timestamp
  - data_sources: Count per source type

  ## Examples

      iex> summary_stats()
      %{
        total_backlinks: 921,
        unique_targets: 145,
        unique_sources: 412,
        last_import: ~U[...],
        data_sources: %{"vendor" => 466, "ahrefs" => 455}
      }
  """
  def summary_stats do
    # Total and uniques
    totals_query =
      from(b in BacklinkSchema,
        select: %{
          total: count(b.id),
          unique_targets: count(b.target_url, :distinct),
          unique_sources: count(b.source_domain, :distinct),
          last_import: max(b.imported_at)
        }
      )

    # Counts per data source
    source_counts_query =
      from(b in BacklinkSchema,
        group_by: b.data_source,
        select: {b.data_source, count(b.id)}
      )

    totals = Repo.one(totals_query)
    source_counts = Repo.all(source_counts_query) |> Map.new()

    %{
      total_backlinks: totals.total,
      unique_targets: totals.unique_targets,
      unique_sources: totals.unique_sources,
      last_import: totals.last_import,
      data_sources: source_counts
    }
  end
end
