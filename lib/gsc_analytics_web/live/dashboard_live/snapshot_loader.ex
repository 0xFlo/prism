defmodule GscAnalyticsWeb.DashboardLive.SnapshotLoader do
  @moduledoc """
  Snapshot loading and async task handling for DashboardLive.

  This module encapsulates the logic for loading dashboard data snapshots,
  including async loading, snapshot application, and progress tracking.

  ## Async Loading Strategy

  - Initial load: Synchronous (to render page quickly)
  - Subsequent loads: Async (to keep UI responsive)
  - Force refresh: Synchronous (e.g., after sync completion)

  ## Snapshot Structure

  A snapshot contains:
  - URLs with paginated results
  - Summary statistics
  - Site trends for charting
  - Period totals for metrics
  """

  require Logger

  alias GscAnalytics.ContentInsights
  alias GscAnalytics.Analytics.{SiteTrends, SummaryStats}
  alias GscAnalytics.Dashboard.Snapshot
  alias GscAnalytics.Dashboard, as: DashboardUtils
  alias GscAnalyticsWeb.Presenters.ChartDataPresenter

  # ============================================================================
  # PUBLIC API - Snapshot Loading
  # ============================================================================

  @doc """
  Load a dashboard snapshot with smart async/sync strategy.

  ## Strategy

  1. Not connected (initial render): Sync load
  2. Force refresh: Sync load
  3. Already loading: No-op (skip duplicate requests)
  4. Otherwise: Async load

  ## Options

  - `:force?` - Force synchronous load (default: false)

  ## Examples

      iex> load_snapshot(socket, account_id, property_url, opts, force?: true)
      %Phoenix.LiveView.Socket{}
  """
  @spec load_snapshot(
          Phoenix.LiveView.Socket.t(),
          pos_integer(),
          String.t() | nil,
          map(),
          keyword()
        ) ::
          Phoenix.LiveView.Socket.t()
  def load_snapshot(socket, _account_id, nil, _opts, _opts_kw) do
    import Phoenix.Component, only: [assign: 3]

    socket
    |> assign(:snapshot_loading?, false)
    |> assign(:latest_snapshot_ref, nil)
    |> apply_snapshot(Snapshot.empty())
  end

  def load_snapshot(socket, account_id, property_url, opts, opts_kw) do
    import Phoenix.LiveView, only: [connected?: 1, start_async: 3]
    import Phoenix.Component, only: [assign: 3]

    async_enabled? = Application.get_env(:gsc_analytics, :dashboard_async_snapshots?, true)
    initial_load? = socket.assigns[:snapshot_initialized?] != true
    force? = Keyword.get(opts_kw, :force?, false) || initial_load?

    cond do
      not connected?(socket) or force? or not async_enabled? ->
        snapshot = load_dashboard_snapshot(account_id, property_url, opts)

        socket
        |> assign(:snapshot_loading?, false)
        |> assign(:latest_snapshot_ref, nil)
        |> apply_snapshot(snapshot)

      socket.assigns.snapshot_loading? ->
        socket

      true ->
        ref = make_ref()

        socket
        |> assign(:snapshot_loading?, true)
        |> assign(:latest_snapshot_ref, ref)
        |> start_async({:dashboard_snapshot, ref}, fn ->
          load_dashboard_snapshot(account_id, property_url, opts)
        end)
    end
  end

  @doc """
  Apply a loaded snapshot to socket assigns.

  Updates all dashboard state including URLs, stats, trends, and labels.

  ## Examples

      iex> apply_snapshot(socket, snapshot)
      %Phoenix.LiveView.Socket{}
  """
  @spec apply_snapshot(Phoenix.LiveView.Socket.t(), Snapshot.t()) :: Phoenix.LiveView.Socket.t()
  def apply_snapshot(socket, snapshot) do
    import Phoenix.Component, only: [assign: 2, assign: 3]

    socket
    |> assign(:urls, snapshot.urls)
    |> assign(:page, snapshot.page)
    |> assign(:total_pages, snapshot.total_pages)
    |> assign(:total_count, snapshot.total_count)
    |> assign(:stats, snapshot.stats)
    |> assign(:site_trends, snapshot.site_trends)
    |> assign(:site_trends_json, ChartDataPresenter.encode_time_series(snapshot.site_trends))
    |> assign(:chart_label, snapshot.chart_label)
    |> assign(:total_clicks, snapshot.period_totals.total_clicks)
    |> assign(:total_impressions, snapshot.period_totals.total_impressions)
    |> assign(:avg_ctr, snapshot.period_totals.avg_ctr)
    |> assign(:avg_position, snapshot.period_totals.avg_position)
    |> assign(:snapshot_loading?, false)
    |> assign(:snapshot_initialized?, true)
    |> assign_mom_indicators()
    |> assign_display_labels()
    |> assign_date_labels()
  end

  @doc """
  Handle successful async snapshot task completion.

  Checks if the task reference matches the latest request (to avoid
  race conditions) before applying the snapshot.

  ## Examples

      iex> handle_async_success(socket, ref, snapshot)
      {:noreply, %Phoenix.LiveView.Socket{}}
  """
  @spec handle_async_success(Phoenix.LiveView.Socket.t(), reference(), Snapshot.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_async_success(socket, ref, snapshot) do
    import Phoenix.Component, only: [assign: 3]

    if socket.assigns.latest_snapshot_ref == ref do
      {:noreply,
       socket
       |> assign(:latest_snapshot_ref, nil)
       |> apply_snapshot(snapshot)}
    else
      {:noreply, socket}
    end
  end

  @doc """
  Handle async snapshot task failure.

  Logs error and shows user-friendly flash message.

  ## Examples

      iex> handle_async_failure(socket, ref, reason)
      {:noreply, %Phoenix.LiveView.Socket{}}
  """
  @spec handle_async_failure(Phoenix.LiveView.Socket.t(), reference(), term()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_async_failure(socket, ref, reason) do
    import Phoenix.Component, only: [assign: 3]
    import Phoenix.LiveView, only: [put_flash: 3]

    if socket.assigns.latest_snapshot_ref == ref do
      Logger.error("Dashboard snapshot task failed: #{inspect(reason)}")

      {:noreply,
       socket
       |> assign(:snapshot_loading?, false)
       |> assign(:latest_snapshot_ref, nil)
       |> put_flash(:error, "Failed to load dashboard data. Please try again.")}
    else
      {:noreply, socket}
    end
  end

  @doc """
  Build snapshot options map from current socket assigns.

  Extracts all filter, sort, pagination, and period settings.

  ## Examples

      iex> current_snapshot_opts(socket)
      %{limit: 50, page: 1, sort_by: "clicks", ...}
  """
  @spec current_snapshot_opts(Phoenix.LiveView.Socket.t()) :: map()
  def current_snapshot_opts(socket) do
    %{
      limit: socket.assigns.limit,
      page: socket.assigns.page,
      sort_by: socket.assigns.sort_by,
      sort_direction: DashboardUtils.normalize_sort_direction(socket.assigns.sort_direction),
      search: socket.assigns.search,
      period_days: socket.assigns[:period_days] || 30,
      chart_view: socket.assigns.chart_view,
      filter_http_status: socket.assigns[:filter_http_status],
      filter_position: socket.assigns[:filter_position],
      filter_clicks: socket.assigns[:filter_clicks],
      filter_ctr: socket.assigns[:filter_ctr],
      filter_backlinks: socket.assigns[:filter_backlinks],
      filter_redirect: socket.assigns[:filter_redirect],
      filter_first_seen: socket.assigns[:filter_first_seen],
      filter_page_type: socket.assigns[:filter_page_type]
    }
  end

  # ============================================================================
  # PRIVATE HELPERS - Data Loading
  # ============================================================================

  defp load_dashboard_snapshot(_account_id, nil, _opts), do: Snapshot.empty()

  defp load_dashboard_snapshot(account_id, property_url, opts) do
    result =
      ContentInsights.list_urls(%{
        limit: opts.limit,
        page: opts.page,
        sort_by: opts.sort_by,
        sort_direction: opts.sort_direction,
        search: opts.search,
        period_days: opts.period_days,
        account_id: account_id,
        property_url: property_url,
        filter_http_status: opts[:filter_http_status],
        filter_position: opts[:filter_position],
        filter_clicks: opts[:filter_clicks],
        filter_ctr: opts[:filter_ctr],
        filter_backlinks: opts[:filter_backlinks],
        filter_redirect: opts[:filter_redirect],
        filter_first_seen: opts[:filter_first_seen],
        filter_page_type: opts[:filter_page_type]
      })

    stats = SummaryStats.fetch(%{account_id: account_id, property_url: property_url})
    first_data_date = SiteTrends.first_data_date(account_id, property_url)

    {site_trends, chart_label} =
      SiteTrends.fetch(opts.chart_view, %{
        account_id: account_id,
        property_url: property_url,
        period_days: opts.period_days,
        first_data_date: first_data_date
      })

    period_totals =
      SiteTrends.fetch_period_totals(%{
        account_id: account_id,
        property_url: property_url,
        period_days: opts.period_days,
        first_data_date: first_data_date
      })

    %Snapshot{
      urls: result.urls,
      page: result.page,
      total_pages: result.total_pages,
      total_count: result.total_count,
      stats: stats,
      site_trends: site_trends,
      chart_label: chart_label,
      period_totals: period_totals
    }
  end

  # ============================================================================
  # PRIVATE HELPERS - Display Labels
  # ============================================================================

  defp assign_display_labels(socket) do
    import Phoenix.Component, only: [assign: 3]
    alias GscAnalyticsWeb.Live.DashboardParams

    period_label_text = DashboardParams.period_label(socket.assigns.period_days)

    socket
    |> assign(:period_label, period_label_text)
    |> assign(:chart_view_label, chart_view_label(socket.assigns.chart_view))
    |> assign(:sort_label, sort_label(socket.assigns.sort_by, period_label_text))
    |> assign(:sort_direction_label, sort_direction_label(socket.assigns.sort_direction))
  end

  defp chart_view_label("weekly"), do: "Weekly trend"
  defp chart_view_label("monthly"), do: "Monthly trend"
  defp chart_view_label(_), do: "Daily trend"

  defp sort_label("clicks", period_label), do: "Clicks (#{period_label})"
  defp sort_label("impressions", period_label), do: "Impressions (#{period_label})"
  defp sort_label("ctr", period_label), do: "CTR (#{period_label})"
  defp sort_label("position", period_label), do: "Average Position (#{period_label})"
  defp sort_label("period_clicks", period_label), do: sort_label("clicks", period_label)
  defp sort_label("period_impressions", period_label), do: sort_label("impressions", period_label)
  defp sort_label("lifetime_clicks", _period_label), do: "Total Clicks (All Time)"
  defp sort_label("lifetime_avg_ctr", period_label), do: sort_label("ctr", period_label)
  defp sort_label("lifetime_avg_position", period_label), do: sort_label("position", period_label)
  defp sort_label(_, period_label), do: "Clicks (#{period_label})"

  defp sort_direction_label("asc"), do: "ascending"
  defp sort_direction_label("desc"), do: "descending"
  defp sort_direction_label(_), do: "descending"

  # ============================================================================
  # PRIVATE HELPERS - Month-over-Month Indicators
  # ============================================================================

  defp assign_mom_indicators(socket) do
    import Phoenix.Component, only: [assign: 2, assign: 3]

    mom_change = socket.assigns.stats.month_over_month_change || 0

    socket
    |> assign(:mom_change, mom_change)
    |> assign(:mom_indicator_class, mom_indicator_class(mom_change))
    |> assign(:mom_icon, mom_icon(mom_change))
    |> assign(:mom_delta_display, mom_delta_display(mom_change))
  end

  defp mom_indicator_class(change) when change > 0,
    do: "border-emerald-400/40 bg-emerald-500/10 text-emerald-200"

  defp mom_indicator_class(change) when change < 0,
    do: "border-rose-400/50 bg-rose-500/10 text-rose-200"

  defp mom_indicator_class(_), do: "border-slate-200/40 bg-slate-200/10 text-slate-200"

  defp mom_icon(change) when change > 0, do: "hero-arrow-trending-up"
  defp mom_icon(change) when change < 0, do: "hero-arrow-trending-down"
  defp mom_icon(_), do: "hero-arrows-right-left"

  defp mom_delta_display(change) when change > 0, do: "+#{Float.round(change, 1)}%"
  defp mom_delta_display(change) when change < 0, do: "#{Float.round(change, 1)}%"
  defp mom_delta_display(_), do: "0%"

  # ============================================================================
  # PRIVATE HELPERS - Date Labels
  # ============================================================================

  defp assign_date_labels(socket) do
    import Phoenix.Component, only: [assign: 3]

    stats = socket.assigns.stats

    socket
    |> assign(:earliest_all_time, format_earliest_date(stats.all_time[:earliest_date]))
    |> assign(:latest_all_time, format_latest_date(stats.all_time[:latest_date]))
    |> assign(:days_with_data, stats.all_time[:days_with_data])
  end

  defp format_earliest_date(nil), do: nil
  defp format_earliest_date(date), do: Calendar.strftime(date, "%b %Y")

  defp format_latest_date(nil), do: nil
  defp format_latest_date(date), do: Calendar.strftime(date, "%b %d, %Y")
end
