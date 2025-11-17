defmodule GscAnalytics.ContentInsights.UrlPerformance do
  @moduledoc """
  Provides the main dashboard URL listing with lifetime + period metrics, enriched
  metadata, and pagination. This is a straight extraction of the legacy
  `Dashboard.list_urls/1` logic so behaviour remains identical.

  This module serves as a high-level orchestrator that delegates to:
  - `QueryBuilder` for Ecto query construction and filtering
  - `Enrichment` for WoW growth calculations and content tagging
  - `Filters` for composable filter application

  ## Architecture

  The module follows a clean separation of concerns:

  1. **Input normalization** - Uses shared `QueryParams` utilities
  2. **Query building** - Delegates to `QueryBuilder`
  3. **Data enrichment** - Delegates to `Enrichment`
  4. **Pagination** - Calculates page metadata

  This design makes the code easier to test, maintain, and extend.
  """

  import Ecto.Query

  alias GscAnalytics.Accounts
  alias GscAnalytics.ContentInsights.Filters
  alias GscAnalytics.ContentInsights.UrlPerformance.{Enrichment, QueryBuilder}
  alias GscAnalytics.QueryParams
  alias GscAnalytics.Repo

  @doc """
  List URLs with combined lifetime and recent-period metrics.

  ## Parameters

  Accepts either a keyword list or map with the following options:

  - `account_id` - Account ID (optional, resolved from opts)
  - `property_url` - GSC property URL (required)
  - `limit` - Items per page (default: 100, max: 1000)
  - `page` - Page number (default: 1)
  - `period_days` - Days of recent period (default: 30, >= 10,000 means lifetime)
  - `search` - URL search term
  - `sort_by` - Column to sort by
  - `sort_direction` - `:asc` or `:desc` (default: `:desc`)
  - `filter_*` - Various filter options (see `Filters` module)

  ## Returns

  Map with pagination metadata and enriched URL data:

      %{
        urls: [%{url: "...", clicks: 100, ...}],
        total_count: 1234,
        page: 1,
        per_page: 100,
        total_pages: 13
      }
  """
  @spec list(map() | keyword()) :: map()
  def list(opts \\ %{})

  def list(opts) when is_list(opts) do
    opts
    |> Enum.into(%{})
    |> list()
  end

  def list(opts) when is_map(opts) do
    # Normalize input parameters using shared utilities
    account_id = Accounts.resolve_account_id(opts)
    property_url = Map.get(opts, :property_url) || raise ArgumentError, "property_url is required"
    limit = QueryParams.normalize_limit(Map.get(opts, :limit))
    page = QueryParams.normalize_page(Map.get(opts, :page))
    sort_direction = QueryParams.normalize_sort_direction(Map.get(opts, :sort_direction))
    period_days = Map.get(opts, :period_days, 30)
    search = Map.get(opts, :search)
    search_pattern = QueryBuilder.build_search_pattern(search)

    # Extract filter parameters
    filters = %{
      http_status: Map.get(opts, :filter_http_status),
      position: Map.get(opts, :filter_position),
      clicks: Map.get(opts, :filter_clicks),
      ctr: Map.get(opts, :filter_ctr),
      backlinks: Map.get(opts, :filter_backlinks),
      redirect: Map.get(opts, :filter_redirect),
      first_seen: Map.get(opts, :filter_first_seen),
      page_type: Map.get(opts, :filter_page_type)
    }

    offset = (page - 1) * limit

    # Build query using QueryBuilder
    query =
      account_id
      |> QueryBuilder.build_base_query(property_url, period_days, search_pattern)
      |> QueryBuilder.apply_search_filter(search_pattern)
      |> apply_filters(filters)

    total_count = QueryBuilder.count_urls(query)

    # Execute query with sorting and pagination
    urls =
      query
      |> QueryBuilder.apply_sort(Map.get(opts, :sort_by), sort_direction, period_days)
      |> limit(^limit)
      |> offset(^offset)
      |> Repo.all()

    # Enrich results with WoW growth and tagging
    enriched_urls = Enrichment.enrich_urls(urls, account_id, property_url, period_days)

    total_pages =
      total_count
      |> Kernel./(limit)
      |> Float.ceil()
      |> trunc()
      |> max(1)

    %{
      urls: enriched_urls,
      total_count: total_count,
      page: page,
      per_page: limit,
      total_pages: total_pages
    }
  end

  # ============================================================================
  # PRIVATE HELPERS
  # ============================================================================

  # Apply all filters from the filters map to the query.
  # Uses the composable Filters module to apply each filter in sequence.
  # All filter functions are nil-safe (no-op when filter value is nil).
  defp apply_filters(query, filters) do
    query
    |> Filters.apply_http_status(filters.http_status)
    |> Filters.apply_position_range(filters.position)
    |> Filters.apply_clicks_threshold(filters.clicks)
    |> Filters.apply_ctr_range(filters.ctr)
    |> Filters.apply_backlink_count(filters.backlinks)
    |> Filters.apply_has_redirect(filters.redirect)
    |> Filters.apply_first_seen_after(filters.first_seen)
    |> Filters.apply_page_type(filters.page_type)
  end
end
