defmodule GscAnalytics.ContentInsights.UrlInsights do
  @moduledoc """
  Fetches comprehensive insights for a single URL including:
  - Canonical group resolution (redirect chains)
  - Time-series metrics in daily/weekly/monthly views
  - Aggregated performance summary
  - Top search queries
  - Backlink data
  - Chart annotations for redirects
  """

  import Ecto.Query

  alias GscAnalytics.Accounts
  alias GscAnalytics.Analytics.TimeSeriesAggregator
  alias GscAnalytics.DataSources.Backlinks.Backlink, as: BacklinkContext
  alias GscAnalytics.Presentation.ChartPresenter
  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.{Performance, TimeSeries}
  alias GscAnalytics.UrlGroups

  @default_period_days 365

  @doc """
  Fetch the enriched insight payload for the given URL and view mode.
  """
  def fetch(url, view_mode, opts \\ %{}) when is_binary(url) do
    account_id = Accounts.resolve_account_id(opts)
    period_days = resolve_period_days(Map.get(opts, :period_days))
    decoded_url = URI.decode(url)

    url_group = UrlGroups.resolve(decoded_url, %{account_id: account_id})

    period_end = resolve_period_end(url_group, Map.get(opts, :period_end))
    selection_start = resolve_selection_start(url_group, period_days, period_end)
    data_start = clamp_selection_to_coverage(selection_start, url_group.earliest_date)

    {time_series, label, coverage} =
      build_time_series_for_view(view_mode, url_group, account_id, %{
        period_start: data_start,
        period_end: period_end
      })

    selection_summary = build_selection_summary(view_mode, selection_start, period_end)

    performance =
      calculate_performance_from_time_series(
        time_series,
        url_group.canonical_url || decoded_url,
        account_id,
        %{
          range_start: coverage.range_start,
          range_end: coverage.range_end,
          selection_start: selection_start,
          selection_end: period_end,
          coverage_summary: coverage.summary
        }
      )

    backlink_target = url_group.canonical_url || decoded_url
    backlinks = BacklinkContext.list_for_url(backlink_target)

    effective_range =
      resolve_effective_query_range(
        selection_start,
        period_end,
        coverage.range_start,
        coverage.range_end
      )

    top_queries =
      fetch_top_queries(
        url_group.urls || [],
        account_id,
        Map.get(effective_range, :start_date),
        Map.get(effective_range, :end_date)
      )

    %{
      url: url_group.canonical_url || decoded_url,
      requested_url: url_group.requested_url,
      url_group: url_group,
      performance: performance,
      time_series: time_series,
      label: label,
      range_summary: selection_summary,
      data_coverage_summary: coverage.summary,
      data_range_start: coverage.range_start,
      data_range_end: coverage.range_end,
      period_start: selection_start,
      period_end: period_end,
      chart_events: ChartPresenter.build_chart_events(view_mode, url_group.redirect_events),
      top_queries: top_queries,
      backlinks: backlinks,
      backlink_count: length(backlinks)
    }
  end

  defp calculate_performance_from_time_series([], _url, _account_id, _opts), do: nil

  defp calculate_performance_from_time_series(time_series, url, account_id, opts) do
    total_clicks = Enum.reduce(time_series, 0, fn ts, acc -> acc + (ts.clicks || 0) end)
    total_impressions = Enum.reduce(time_series, 0, fn ts, acc -> acc + (ts.impressions || 0) end)

    total_weighted_position =
      Enum.reduce(time_series, 0.0, fn ts, acc ->
        acc + (ts.position || 0.0) * (ts.impressions || 0)
      end)

    avg_position =
      if total_impressions > 0, do: total_weighted_position / total_impressions, else: 0.0

    avg_ctr = if total_impressions > 0, do: total_clicks / total_impressions, else: 0.0

    dates = Enum.map(time_series, & &1.date)
    end_dates = Enum.map(time_series, fn ts -> Map.get(ts, :period_end, ts.date) end)

    http_data =
      from(p in Performance,
        where: p.url == ^url and p.account_id == ^account_id,
        select: %{
          http_status: p.http_status,
          redirect_url: p.redirect_url,
          http_checked_at: p.http_checked_at
        },
        limit: 1
      )
      |> Repo.one()

    {data_range_start, data_range_end} =
      case {Map.get(opts, :range_start), Map.get(opts, :range_end)} do
        {nil, nil} -> normalize_date_range(Enum.min(dates), Enum.max(end_dates))
        {start, finish} -> normalize_date_range(start, finish)
      end

    {selection_start, selection_end} =
      case {Map.get(opts, :selection_start), Map.get(opts, :selection_end)} do
        {nil, nil} ->
          {data_range_start, data_range_end}

        {start, finish} ->
          normalize_date_range(start || data_range_start, finish || data_range_end)
      end

    fetched_at =
      case selection_end do
        %Date{} = date -> date
        _ -> Date.utc_today()
      end

    %{
      url: url,
      account_id: account_id,
      clicks: total_clicks,
      impressions: total_impressions,
      ctr: avg_ctr,
      position: avg_position,
      date_range_start: selection_start,
      date_range_end: selection_end,
      data_range_start: data_range_start,
      data_range_end: data_range_end,
      data_coverage_summary: Map.get(opts, :coverage_summary),
      data_available: total_clicks > 0 || total_impressions > 0,
      fetched_at: fetched_at,
      http_status: if(http_data, do: http_data.http_status),
      redirect_url: if(http_data, do: http_data.redirect_url),
      http_checked_at: if(http_data, do: http_data.http_checked_at)
    }
  end

  defp build_time_series_for_view(
         view_mode,
         %{urls: urls, earliest_date: earliest},
         account_id,
         %{period_start: period_start, period_end: period_end}
       ) do
    label = view_label(view_mode)

    cond do
      urls == [] ->
        {[], label, %{summary: "No data", range_start: nil, range_end: nil}}

      is_nil(earliest) ->
        {[], label, %{summary: "No data", range_start: nil, range_end: nil}}

      is_nil(period_start) ->
        {[], label, %{summary: "No data", range_start: nil, range_end: nil}}

      true ->
        query_opts = %{account_id: account_id, start_date: period_start}

        time_series =
          case view_mode do
            "weekly" -> TimeSeriesAggregator.aggregate_group_by_week(urls, query_opts)
            "monthly" -> TimeSeriesAggregator.aggregate_group_by_month(urls, query_opts)
            _ -> TimeSeriesAggregator.aggregate_group_by_day(urls, query_opts)
          end
          |> maybe_filter_series_by_end(period_end)

        coverage = build_coverage_details(view_mode, time_series)

        {time_series, label, coverage}
    end
  end

  defp view_label("weekly"), do: "Week Starting"
  defp view_label("monthly"), do: "Month"
  defp view_label(_), do: "Date"

  defp build_coverage_details(_view_mode, []),
    do: %{summary: "No data", range_start: nil, range_end: nil}

  defp build_coverage_details(view_mode, time_series) do
    date_values =
      time_series
      |> Enum.map(&extract_primary_date/1)
      |> Enum.filter(& &1)

    end_values =
      time_series
      |> Enum.map(&extract_comparison_date/1)
      |> Enum.filter(& &1)

    if date_values == [] or end_values == [] do
      %{summary: "No data", range_start: nil, range_end: nil}
    else
      start_date = Enum.min(date_values)
      end_date = Enum.max(end_values)

      {range_start, range_end} = normalize_date_range(start_date, end_date)

      summary =
        case view_mode do
          "weekly" ->
            pluralize(length(time_series), "week")

          "monthly" ->
            pluralize(length(time_series), "month")

          _ ->
            days =
              range_end
              |> Date.diff(range_start)
              |> Kernel.+(1)
              |> max(1)

            pluralize(days, "day")
        end

      %{summary: summary, range_start: range_start, range_end: range_end}
    end
  end

  defp build_selection_summary(_view_mode, nil, nil), do: "No range"
  defp build_selection_summary(_view_mode, nil, _finish), do: "No range"
  defp build_selection_summary(_view_mode, _start, nil), do: "No range"

  defp build_selection_summary(view_mode, start, finish) do
    {range_start, range_end} = normalize_date_range(start, finish)

    case view_mode do
      "weekly" ->
        weeks =
          range_end
          |> Date.diff(range_start)
          |> Kernel.+(1)
          |> Kernel./(7)
          |> Float.ceil()
          |> trunc()

        pluralize(max(weeks, 1), "week")

      "monthly" ->
        months = months_between(range_start, range_end)
        pluralize(max(months, 1), "month")

      _ ->
        days =
          range_end
          |> Date.diff(range_start)
          |> Kernel.+(1)
          |> max(1)

        pluralize(days, "day")
    end
  end

  defp months_between(%Date{} = start, %Date{} = finish) do
    (finish.year - start.year) * 12 + (finish.month - start.month) + 1
  end

  defp resolve_effective_query_range(_period_start, _period_end, nil, _coverage_end),
    do: %{start_date: nil, end_date: nil}

  defp resolve_effective_query_range(_period_start, _period_end, _coverage_start, nil),
    do: %{start_date: nil, end_date: nil}

  defp resolve_effective_query_range(period_start, period_end, coverage_start, coverage_end) do
    start_date =
      case {period_start, coverage_start} do
        {%Date{} = p, %Date{} = c} -> max_date(p, c)
        {%Date{} = p, _} -> p
        {_, %Date{} = c} -> c
        _ -> coverage_start
      end

    end_date =
      case {period_end, coverage_end} do
        {%Date{} = p, %Date{} = c} -> min_date(p, c)
        {%Date{} = p, _} -> p
        {_, %Date{} = c} -> c
        _ -> coverage_end
      end

    if is_nil(start_date) or is_nil(end_date) or Date.compare(start_date, end_date) == :gt do
      %{start_date: nil, end_date: nil}
    else
      %{start_date: start_date, end_date: end_date}
    end
  end

  defp normalize_date_range(nil, nil), do: {nil, nil}
  defp normalize_date_range(nil, finish), do: {finish, finish}
  defp normalize_date_range(start, nil), do: {start, start}

  defp normalize_date_range(start, finish) do
    case Date.compare(start, finish) do
      :gt -> {finish, start}
      _ -> {start, finish}
    end
  end

  defp pluralize(value, singular) when value == 1 do
    "1 #{singular}"
  end

  defp pluralize(value, singular) do
    "#{value} #{singular}s"
  end

  defp fetch_top_queries(urls, _account_id, _start_date, _end_date) when urls in [nil, []],
    do: []

  defp fetch_top_queries(_urls, _account_id, nil, _end_date), do: []
  defp fetch_top_queries(_urls, _account_id, _start_date, nil), do: []

  defp fetch_top_queries(urls, account_id, start_date, end_date) do
    urls = urls |> Enum.uniq() |> Enum.reject(&is_nil/1)

    if urls == [] do
      []
    else
      from(ts in TimeSeries,
        where: ts.account_id == ^account_id,
        where: ts.url in ^urls,
        where: ts.date >= ^start_date and ts.date <= ^end_date,
        where: fragment("array_length(?, 1) > 0", ts.top_queries),
        cross_join: q in fragment("unnest(?)", ts.top_queries),
        group_by: fragment("LOWER(TRIM(COALESCE(?->>'query', '')))", q),
        order_by: [desc: fragment("SUM((?->>'clicks')::bigint)", q)],
        limit: 50,
        select: %{
          display_query: fragment("MIN(TRIM(COALESCE(?->>'query', '')))", q),
          normalized_query: fragment("LOWER(TRIM(COALESCE(?->>'query', '')))", q),
          clicks: fragment("SUM((?->>'clicks')::bigint)", q),
          impressions: fragment("SUM((?->>'impressions')::bigint)", q),
          ctr:
            fragment(
              "COALESCE(SUM((?->>'clicks')::bigint)::float / NULLIF(SUM((?->>'impressions')::bigint), 0), 0)",
              q,
              q
            ),
          position:
            fragment(
              "COALESCE(SUM((?->>'position')::float * (?->>'impressions')::bigint) / NULLIF(SUM((?->>'impressions')::bigint), 0), 0)",
              q,
              q,
              q
            )
        }
      )
      |> Repo.all()
      |> Enum.map(&normalize_query_row/1)
    end
  end

  defp normalize_query_row(row) do
    query =
      row
      |> Map.get(:display_query, "")
      |> to_string()
      |> String.trim()
      |> presentable_query()

    %{
      query: query,
      clicks: normalize_integer(Map.get(row, :clicks)),
      impressions: normalize_integer(Map.get(row, :impressions)),
      ctr: normalize_float(Map.get(row, :ctr)),
      position: normalize_float(Map.get(row, :position))
    }
  end

  defp maybe_filter_series_by_end(series, nil), do: series

  defp maybe_filter_series_by_end(series, %Date{} = period_end) do
    Enum.filter(series, fn row ->
      case extract_comparison_date(row) do
        nil -> true
        comparison_date -> Date.compare(comparison_date, period_end) != :gt
      end
    end)
  end

  defp extract_comparison_date(%{period_end: %Date{} = period_end}), do: period_end
  defp extract_comparison_date(%{date: %Date{} = date}), do: date
  defp extract_comparison_date(%{period_end: nil, date: nil}), do: nil

  defp extract_comparison_date(%{period_end: period_end}) when is_binary(period_end) do
    Date.from_iso8601!(period_end)
  rescue
    _ -> nil
  end

  defp extract_comparison_date(%{date: date}) when is_binary(date) do
    Date.from_iso8601!(date)
  rescue
    _ -> nil
  end

  defp extract_comparison_date(_), do: nil

  defp extract_primary_date(%{date: %Date{} = date}), do: date

  defp extract_primary_date(%{date: date}) when is_binary(date) do
    Date.from_iso8601!(date)
  rescue
    _ -> nil
  end

  defp extract_primary_date(_), do: nil

  defp resolve_period_days(nil), do: @default_period_days
  defp resolve_period_days(:all), do: :all

  defp resolve_period_days(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> resolve_period_days(int)
      :error -> @default_period_days
    end
  end

  defp resolve_period_days(value) when is_integer(value) and value >= 10000, do: :all
  defp resolve_period_days(value) when is_integer(value) and value > 0, do: value
  defp resolve_period_days(_), do: @default_period_days

  defp resolve_period_end(%{latest_date: nil}, explicit_end) do
    candidate = explicit_end || Date.utc_today()
    min_date(candidate, Date.utc_today())
  end

  defp resolve_period_end(%{latest_date: latest}, explicit_end) do
    candidate = explicit_end || latest

    candidate
    |> min_date(latest)
    |> min_date(Date.utc_today())
  end

  defp resolve_selection_start(%{earliest_date: earliest}, :all, _period_end)
       when not is_nil(earliest),
       do: earliest

  defp resolve_selection_start(_url_group, :all, %Date{} = period_end), do: period_end

  defp resolve_selection_start(_url_group, period_days, %Date{} = period_end)
       when is_integer(period_days) and period_days > 0 do
    days_back = max(period_days - 1, 0)
    Date.add(period_end, -days_back)
  end

  defp resolve_selection_start(url_group, period_days, nil) when is_integer(period_days) do
    resolve_selection_start(url_group, period_days, Date.utc_today())
  end

  defp resolve_selection_start(_url_group, _period_days, _period_end), do: nil

  defp clamp_selection_to_coverage(nil, _earliest), do: nil
  defp clamp_selection_to_coverage(_selection_start, nil), do: nil

  defp clamp_selection_to_coverage(%Date{} = selection_start, %Date{} = earliest) do
    case Date.compare(selection_start, earliest) do
      :lt -> earliest
      _ -> selection_start
    end
  end

  defp presentable_query(""), do: ""
  defp presentable_query(value), do: value

  defp min_date(nil, other), do: other
  defp min_date(other, nil), do: other

  defp min_date(a, b) do
    case Date.compare(a, b) do
      :gt -> b
      _ -> a
    end
  end

  defp max_date(a, b) do
    case Date.compare(a, b) do
      :lt -> b
      _ -> a
    end
  end

  defp normalize_integer(nil), do: 0
  defp normalize_integer(%Decimal{} = value), do: Decimal.to_integer(value)
  defp normalize_integer(value) when is_integer(value), do: value
  defp normalize_integer(value) when is_float(value), do: trunc(value)
  defp normalize_integer(_), do: 0

  defp normalize_float(nil), do: 0.0
  defp normalize_float(%Decimal{} = value), do: Decimal.to_float(value)
  defp normalize_float(value) when is_float(value), do: value
  defp normalize_float(value) when is_integer(value), do: value * 1.0
  defp normalize_float(_), do: 0.0
end
