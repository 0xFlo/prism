defmodule GscAnalytics.ContentInsights.UrlPerformance do
  @moduledoc """
  Provides the main dashboard URL listing with lifetime + period metrics, enriched
  metadata, and pagination. This is a straight extraction of the legacy
  `Dashboard.list_urls/1` logic so behaviour remains identical.
  """

  import Ecto.Query

  alias GscAnalytics.Accounts
  alias GscAnalytics.Analytics.TimeSeriesAggregator
  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.{Backlink, Performance, TimeSeries}

  @default_limit 100

  @doc """
  List URLs with combined lifetime and recent-period metrics.
  """
  def list(opts \\ %{})

  def list(opts) when is_list(opts) do
    opts
    |> Enum.into(%{})
    |> list()
  end

  def list(opts) when is_map(opts) do
    account_id = Accounts.resolve_account_id(opts)
    property_url = Map.get(opts, :property_url) || raise ArgumentError, "property_url is required"
    limit = normalize_limit(Map.get(opts, :limit))
    page = normalize_page(Map.get(opts, :page))
    period_days = Map.get(opts, :period_days, 30)
    search = Map.get(opts, :search)
    search_pattern = build_search_pattern(search)

    offset = (page - 1) * limit

    query =
      account_id
      |> build_hybrid_query(property_url, period_days, search_pattern)
      |> apply_search_filter(search_pattern)

    total_count = count_urls(query)

    urls =
      query
      |> apply_sort(Map.get(opts, :sort_by), Map.get(opts, :sort_direction), period_days)
      |> limit(^limit)
      |> offset(^offset)
      |> Repo.all()

    enriched_urls = enrich_urls(urls, account_id, period_days)

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

  defp build_hybrid_query(account_id, property_url, period_days, search_pattern) do
    period_start = Date.add(Date.utc_today(), -period_days)

    period_query =
      TimeSeries
      |> where(
        [ts],
        ts.account_id == ^account_id and ts.property_url == ^property_url and
          ts.date >= ^period_start
      )
      |> maybe_filter_time_series(search_pattern)
      |> group_by([ts], ts.url)
      |> select([ts], %{
        url: ts.url,
        period_clicks: sum(ts.clicks),
        period_impressions: sum(ts.impressions),
        period_position:
          fragment(
            "SUM(? * ?) / NULLIF(SUM(?), 0)",
            ts.position,
            ts.impressions,
            ts.impressions
          ),
        period_ctr: fragment("SUM(?)::float / NULLIF(SUM(?), 0)", ts.clicks, ts.impressions)
      })

    backlink_query =
      Backlink
      |> maybe_filter_backlinks(search_pattern)
      |> group_by([b], b.target_url)
      |> select([b], %{
        target_url: b.target_url,
        backlink_count: count(b.id),
        backlinks_last_imported: max(b.imported_at)
      })

    from(ls in "url_lifetime_stats")
    |> where([ls], ls.account_id == ^account_id and ls.property_url == ^property_url)
    |> join(:left, [ls], pm in subquery(period_query), on: pm.url == ls.url)
    |> join(:left, [ls, pm], bl in subquery(backlink_query), on: bl.target_url == ls.url)
    |> join(:left, [ls, pm, bl], p in Performance,
      on: p.url == ls.url and p.account_id == ^account_id and p.property_url == ^property_url
    )
    |> maybe_filter_lifetime_stats(search_pattern)
    |> select([ls, pm, bl, p], %{
      url: ls.url,
      lifetime_clicks: ls.lifetime_clicks,
      lifetime_impressions: ls.lifetime_impressions,
      lifetime_avg_position: ls.avg_position,
      lifetime_avg_ctr: ls.avg_ctr,
      first_seen_date: ls.first_seen_date,
      last_seen_date: ls.last_seen_date,
      days_with_data: ls.days_with_data,
      period_clicks: coalesce(pm.period_clicks, 0),
      period_impressions: coalesce(pm.period_impressions, 0),
      period_position: coalesce(pm.period_position, 0.0),
      period_ctr: coalesce(pm.period_ctr, 0.0),
      backlink_count: coalesce(bl.backlink_count, 0),
      backlinks_last_imported: bl.backlinks_last_imported,
      http_status: p.http_status,
      redirect_url: p.redirect_url,
      http_checked_at: p.http_checked_at,
      data_available:
        fragment(
          "(? > 0 OR ? > 0)",
          ls.lifetime_clicks,
          ls.lifetime_impressions
        )
    })
  end

  defp apply_search_filter(query, nil), do: query

  defp apply_search_filter(query, pattern) do
    from row in query,
      where: ilike(row.url, ^pattern)
  end

  defp build_search_pattern(search) when is_binary(search) do
    search
    |> String.trim()
    |> case do
      "" -> nil
      term -> "%#{term}%"
    end
  end

  defp build_search_pattern(_), do: nil

  defp maybe_filter_time_series(query, nil), do: query

  defp maybe_filter_time_series(query, pattern) do
    where(query, [ts], ilike(ts.url, ^pattern))
  end

  defp maybe_filter_backlinks(query, nil), do: query

  defp maybe_filter_backlinks(query, pattern) do
    where(query, [b], ilike(b.target_url, ^pattern))
  end

  defp maybe_filter_lifetime_stats(query, nil), do: query

  defp maybe_filter_lifetime_stats(query, pattern) do
    where(query, [ls, _pm, _bl, _p], ilike(ls.url, ^pattern))
  end

  defp apply_sort(query, sort_by, sort_direction, period_days) do
    direction = normalize_sort_direction(sort_direction)
    use_lifetime = lifetime_window?(period_days)

    order_by_clause =
      case sort_by do
        "clicks" ->
          if use_lifetime do
            [{direction, dynamic([ls], ls.lifetime_clicks)}]
          else
            [{direction, dynamic([ls, pm], coalesce(pm.period_clicks, 0))}]
          end

        "impressions" ->
          if use_lifetime do
            [{direction, dynamic([ls], ls.lifetime_impressions)}]
          else
            [{direction, dynamic([ls, pm], coalesce(pm.period_impressions, 0))}]
          end

        "ctr" ->
          if use_lifetime do
            [{direction, dynamic([ls], ls.avg_ctr)}]
          else
            [{direction, dynamic([ls, pm], coalesce(pm.period_ctr, 0.0))}]
          end

        "position" ->
          if use_lifetime do
            [{direction, dynamic([ls], ls.avg_position)}]
          else
            [{direction, dynamic([ls, pm], coalesce(pm.period_position, 0.0))}]
          end

        "lifetime_clicks" ->
          [{direction, dynamic([ls], ls.lifetime_clicks)}]

        "lifetime_impressions" ->
          [{direction, dynamic([ls], ls.lifetime_impressions)}]

        "lifetime_ctr" ->
          [{direction, dynamic([ls], ls.avg_ctr)}]

        "lifetime_position" ->
          [{direction, dynamic([ls], ls.avg_position)}]

        "period_clicks" ->
          [{direction, dynamic([ls, pm], coalesce(pm.period_clicks, 0))}]

        "period_impressions" ->
          [{direction, dynamic([ls, pm], coalesce(pm.period_impressions, 0))}]

        "period_ctr" ->
          [{direction, dynamic([ls, pm], coalesce(pm.period_ctr, 0.0))}]

        "period_position" ->
          [{direction, dynamic([ls, pm], coalesce(pm.period_position, 0.0))}]

        "backlinks" ->
          [{direction, dynamic([ls, pm, bl], coalesce(bl.backlink_count, 0))}]

        "http_status" ->
          [{direction, dynamic([ls, pm, bl, p], coalesce(p.http_status, 999))}]

        "first_seen_date" ->
          [{direction, dynamic([ls], ls.first_seen_date)}]

        _ ->
          if use_lifetime do
            [{direction, dynamic([ls], ls.lifetime_clicks)}]
          else
            [{direction, dynamic([ls, pm], coalesce(pm.period_clicks, 0))}]
          end
      end

    from row in query, order_by: ^order_by_clause
  end

  defp lifetime_window?(period_days) when is_integer(period_days) and period_days >= 10_000,
    do: true

  defp lifetime_window?(_), do: false

  defp enrich_urls(urls, account_id, period_days) do
    url_list = Enum.map(urls, & &1.url)

    # Use window function implementation for 20x performance improvement
    # Fetches last 8 weeks (4 weeks recent + 4 weeks prior for comparison)
    start_date = Date.add(Date.utc_today(), -8 * 7)

    wow_growth_results =
      TimeSeriesAggregator.batch_calculate_wow_growth(
        url_list,
        %{start_date: start_date, account_id: account_id, weeks_back: 1}
      )

    # Convert list of weekly results to map of url => latest WoW growth
    # We take the most recent week's growth for each URL
    wow_growth_map =
      wow_growth_results
      |> Enum.group_by(& &1.url)
      |> Enum.map(fn {url, weeks} ->
        # Get the most recent week that has growth data
        latest_growth =
          weeks
          |> Enum.reject(&is_nil(&1.wow_growth_pct))
          |> Enum.max_by(& &1.week_start, Date, fn -> nil end)

        growth_value = if latest_growth, do: latest_growth.wow_growth_pct, else: 0.0
        {url, growth_value}
      end)
      |> Map.new()

    Enum.map(urls, fn url_data ->
      wow_growth = Map.get(wow_growth_map, url_data.url, 0.0)

      use_lifetime = lifetime_window?(period_days)

      selected_clicks =
        if use_lifetime do
          url_data.lifetime_clicks || 0
        else
          url_data.period_clicks || url_data.lifetime_clicks || 0
        end

      selected_impressions =
        if use_lifetime do
          url_data.lifetime_impressions || 0
        else
          url_data.period_impressions || url_data.lifetime_impressions || 0
        end

      selected_ctr =
        if use_lifetime do
          url_data.lifetime_avg_ctr
        else
          url_data.period_ctr || url_data.lifetime_avg_ctr
        end

      selected_position =
        if use_lifetime do
          url_data.lifetime_avg_position
        else
          url_data.period_position || url_data.lifetime_avg_position
        end

      selected_ctr_pct = Float.round((selected_ctr || 0.0) * 100, 2)

      url_data
      |> Map.merge(%{
        wow_growth_last4w: wow_growth,
        lifetime_ctr_pct: Float.round((url_data.lifetime_avg_ctr || 0.0) * 100, 2),
        period_ctr_pct: Float.round((url_data.period_ctr || 0.0) * 100, 2),
        selected_clicks: selected_clicks,
        selected_impressions: selected_impressions,
        selected_ctr: selected_ctr,
        selected_ctr_pct: selected_ctr_pct,
        selected_position: selected_position,
        selected_metrics_source: if(use_lifetime, do: :lifetime, else: :period),
        type: nil,
        content_category: nil
      })
      |> tag_update_status(wow_growth)
    end)
  end

  defp tag_update_status(url_data, wow_growth) do
    position =
      Map.get(url_data, :selected_position) ||
        Map.get(url_data, :period_position) ||
        Map.get(url_data, :lifetime_avg_position)

    clicks =
      Map.get(url_data, :selected_clicks) ||
        Map.get(url_data, :period_clicks) ||
        Map.get(url_data, :lifetime_clicks, 0)

    needs_update =
      cond do
        wow_growth < -20 -> true
        position && position > 10 -> true
        url_data[:content_category] == "Stale" -> true
        true -> false
      end

    Map.merge(url_data, %{
      needs_update: needs_update,
      update_reason:
        if needs_update do
          cond do
            wow_growth < -20 -> "Traffic drop #{wow_growth}%"
            position && position > 10 -> "Low ranking (position #{Float.round(position, 1)})"
            url_data[:content_category] == "Stale" -> "Content is stale"
            true -> "Review needed"
          end
        end,
      update_priority:
        if needs_update do
          cond do
            clicks > 1_000 -> "High"
            clicks > 100 -> "Medium"
            true -> "Low"
          end
        end
    })
  end

  defp count_urls(query) do
    query
    |> exclude(:select)
    |> exclude(:order_by)
    |> exclude(:limit)
    |> select([row], count(row.url))
    |> Repo.one()
  end

  defp normalize_limit(nil), do: @default_limit

  defp normalize_limit(limit) when is_binary(limit) do
    case Integer.parse(limit) do
      {value, ""} -> normalize_limit(value)
      _ -> @default_limit
    end
  end

  defp normalize_limit(limit) when is_integer(limit) and limit > 0 do
    limit |> min(1000) |> max(1)
  end

  defp normalize_limit(_), do: @default_limit

  defp normalize_page(nil), do: 1

  defp normalize_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {value, ""} -> normalize_page(value)
      _ -> 1
    end
  end

  defp normalize_page(page) when is_integer(page) and page > 0, do: page
  defp normalize_page(_), do: 1

  defp normalize_sort_direction(nil), do: :desc
  defp normalize_sort_direction("asc"), do: :asc
  defp normalize_sort_direction(:asc), do: :asc
  defp normalize_sort_direction("desc"), do: :desc
  defp normalize_sort_direction(:desc), do: :desc
  defp normalize_sort_direction(_), do: :desc
end
