defmodule GscAnalyticsWeb.DashboardLive do
  use GscAnalyticsWeb, :live_view

  alias GscAnalytics.ContentInsights
  alias GscAnalytics.Analytics.{SiteTrends, SummaryStats}
  alias GscAnalytics.Dashboard, as: DashboardUtils
  alias GscAnalytics.Dashboard.Snapshot
  alias GscAnalytics.DataSources.GSC.Support.SyncProgress
  alias GscAnalyticsWeb.Live.AccountHelpers
  alias GscAnalyticsWeb.Live.DashboardParams
  alias GscAnalyticsWeb.Live.PaginationHelpers
  alias GscAnalyticsWeb.Dashboard.Columns
  alias GscAnalyticsWeb.Presenters.ChartDataPresenter
  alias GscAnalyticsWeb.PropertyRoutes

  # Import component functions for template
  import GscAnalyticsWeb.Components.DashboardComponents

  @impl true
  def mount(params, _session, socket) do
    # LiveView best practice: Subscribe to PubSub only on connected socket (not initial render)
    # This enables real-time dashboard updates when sync completes
    if connected?(socket), do: SyncProgress.subscribe()

    {socket, _account, _property} =
      AccountHelpers.init_account_and_property_assigns(socket, params)

    # LiveView best practice: Use assign_new/3 to prevent overwriting existing assigns
    # and provide safe defaults for all template variables
    {:ok,
     socket
     |> assign_new(:sync_running, fn -> false end)
     |> assign_new(:urls, fn -> [] end)
     |> assign_new(:stats, fn ->
       %{total_urls: 0, total_clicks: 0, total_impressions: 0, avg_ctr: 0, avg_position: 0}
     end)
     |> assign_new(:site_trends, fn -> [] end)
     |> assign_new(:visible_series, fn -> [:clicks, :impressions] end)
     |> assign_new(:chart_label, fn -> "Date" end)
     |> assign_new(:chart_view, fn -> "daily" end)
     |> assign_new(:sort_by, fn -> "clicks" end)
     |> assign_new(:sort_direction, fn -> "desc" end)
     |> assign_new(:limit, fn -> 50 end)
     |> assign_new(:page, fn -> 1 end)
     |> assign_new(:total_pages, fn -> 1 end)
     |> assign_new(:total_count, fn -> 0 end)
     |> assign_new(:view_mode, fn -> "basic" end)
     |> assign_new(:search, fn -> "" end)
     |> assign_new(:page_title, fn -> "GSC Analytics Dashboard" end)
     |> assign_new(:property_label, fn -> nil end)
     |> assign_new(:property_favicon_url, fn -> nil end)
     |> assign_new(:total_clicks, fn -> 0 end)
     |> assign_new(:total_impressions, fn -> 0 end)
     |> assign_new(:avg_ctr, fn -> 0.0 end)
     |> assign_new(:avg_position, fn -> 0.0 end)}
  end

  @impl true
  def handle_params(params, uri, socket) do
    socket = AccountHelpers.assign_current_account(socket, params)
    socket = AccountHelpers.assign_current_property(socket, params)

    account_id = socket.assigns.current_account_id
    property = socket.assigns.current_property
    property_url = property && property.property_url

    property_label =
      property &&
        (property.display_name || AccountHelpers.display_property_label(property.property_url))

    property_favicon_url = property && property.favicon_url

    limit = PaginationHelpers.parse_limit(params["limit"])
    page = PaginationHelpers.parse_page(params["page"])
    sort_by = DashboardParams.normalize_sort_column(params["sort_by"])
    sort_direction = DashboardUtils.normalize_sort_direction(params["sort_direction"])
    view_mode = Columns.validate_view_mode(params["view_mode"] || "basic")
    chart_view = chart_view(params["chart_view"])
    search = params["search"] || ""
    # Parse period parameter for v2 functions (default to 30 days)
    period_days = DashboardParams.parse_period(params["period"])
    # Parse visible series for chart (default to clicks + impressions)
    visible_series = DashboardParams.parse_visible_series(params["series"])

    # Parse filter parameters using safe whitelist validation
    filter_http_status = DashboardParams.parse_http_status(params["http_status"])
    filter_position = DashboardParams.parse_position_range(params["position"])
    filter_clicks = DashboardParams.parse_clicks_threshold(params["clicks"])
    filter_ctr = DashboardParams.parse_ctr_range(params["ctr"])
    filter_backlinks = DashboardParams.parse_backlink_count(params["backlinks"])
    filter_redirect = DashboardParams.parse_has_redirect(params["redirect"])
    filter_first_seen = DashboardParams.parse_first_seen_after(params["first_seen"])
    filter_page_type = DashboardParams.parse_page_type(params["page_type"])

    # Extract path from URI for active nav detection
    current_path = URI.parse(uri).path || "/"

    socket =
      if property_url do
        socket
      else
        if socket.assigns[:no_property_warned] != true do
          socket
          |> put_flash(
            :warning,
            "Please select a Search Console property from Settings to view data."
          )
          |> assign(:no_property_warned, true)
        else
          socket
        end
      end

    snapshot =
      load_dashboard_snapshot(account_id, property_url, %{
        limit: limit,
        page: page,
        sort_by: sort_by,
        sort_direction: sort_direction,
        search: search,
        period_days: period_days,
        chart_view: chart_view,
        filter_http_status: filter_http_status,
        filter_position: filter_position,
        filter_clicks: filter_clicks,
        filter_ctr: filter_ctr,
        filter_backlinks: filter_backlinks,
        filter_redirect: filter_redirect,
        filter_first_seen: filter_first_seen,
        filter_page_type: filter_page_type
      })

    {:noreply,
     socket
     |> assign(:current_path, current_path)
     |> assign(:urls, snapshot.urls)
     |> assign(:page, snapshot.page)
     |> assign(:total_pages, snapshot.total_pages)
     |> assign(:total_count, snapshot.total_count)
     |> assign(:stats, snapshot.stats)
     |> assign(:site_trends, snapshot.site_trends)
     |> assign(:site_trends_json, ChartDataPresenter.encode_time_series(snapshot.site_trends))
     |> assign(:chart_label, snapshot.chart_label)
     |> assign(:visible_series, visible_series)
     |> assign(:chart_view, chart_view)
     |> assign(:sort_by, sort_by)
     |> assign(:sort_direction, Atom.to_string(sort_direction))
     |> assign(:limit, limit)
     |> assign(:view_mode, view_mode)
     |> assign(:search, search)
     |> assign(:period_days, period_days)
     |> assign(:property_label, property_label)
     |> assign(:property_favicon_url, property_favicon_url)
     |> assign(:total_clicks, snapshot.period_totals.total_clicks)
     |> assign(:total_impressions, snapshot.period_totals.total_impressions)
     |> assign(:avg_ctr, snapshot.period_totals.avg_ctr)
     |> assign(:avg_position, snapshot.period_totals.avg_position)
     |> assign(
       :page_title,
       if(property_label,
         do: "GSC Dashboard – #{property_label}",
         else: "GSC Analytics Dashboard"
       )
     )
     |> assign(:filter_http_status, filter_http_status)
     |> assign(:filter_position, filter_position)
     |> assign(:filter_clicks, filter_clicks)
     |> assign(:filter_ctr, filter_ctr)
     |> assign(:filter_backlinks, filter_backlinks)
     |> assign(:filter_redirect, filter_redirect)
     |> assign(:filter_first_seen, filter_first_seen)
     |> assign(:filter_page_type, filter_page_type)
     |> assign_display_labels()
     |> assign_mom_indicators()
     |> assign_date_labels()}
  end

  @impl true
  def handle_event("search", %{"search" => search_term}, socket) do
    # Update search - reset to page 1 when searching
    {:noreply, push_dashboard_patch(socket, %{search: search_term, page: 1})}
  end

  @impl true
  def handle_event("switch_property", %{"property_id" => property_id}, socket) do
    # Switch property while preserving other params
    {:noreply, push_dashboard_patch(socket, %{property_id: property_id})}
  end

  @impl true
  def handle_event("change_view_mode", %{"view_mode" => view_mode}, socket) do
    # Update URL with new view mode - keep current page
    validated_mode = Columns.validate_view_mode(view_mode)

    {:noreply, push_dashboard_patch(socket, %{view_mode: validated_mode})}
  end

  @impl true
  def handle_event("change_period", %{"period" => period}, socket) do
    # Update local assigns for immediate visual feedback, then sync URL for data refresh
    new_period_days = DashboardParams.parse_period(period)

    new_socket =
      socket
      |> assign(:period_days, new_period_days)
      |> assign_display_labels()

    {:noreply, push_dashboard_patch(new_socket, %{period: period, page: 1})}
  end

  @impl true
  def handle_event("change_chart_view", %{"chart_view" => chart_view}, socket) do
    # Update local assigns for immediate visual feedback, then sync URL for data refresh
    new_socket =
      socket
      |> assign(:chart_view, chart_view)
      |> assign_display_labels()

    {:noreply, push_dashboard_patch(new_socket, %{chart_view: chart_view})}
  end

  @impl true
  def handle_event("toggle_series", %{"metric" => metric_str}, socket) do
    metric = String.to_existing_atom(metric_str)
    current_series = socket.assigns.visible_series

    new_series =
      if metric in current_series do
        # Remove the series
        List.delete(current_series, metric)
      else
        # Add the series
        [metric | current_series]
      end

    # Enforce at least one series visible
    new_series = if Enum.empty?(new_series), do: [metric], else: new_series

    {:noreply, push_dashboard_patch(socket, %{series: DashboardParams.encode_series(new_series)})}
  end

  @impl true
  def handle_event("sort_column", %{"column" => column}, socket) do
    # Determine new sort direction - toggle if same column, default for new column
    # Reset to page 1 since sort order changes results
    normalized_column = DashboardParams.normalize_sort_column(column)

    new_direction =
      DashboardParams.toggle_sort_direction(
        socket.assigns.sort_by,
        normalized_column,
        socket.assigns.sort_direction
      )

    {:noreply,
     push_dashboard_patch(socket, %{
       sort_by: normalized_column,
       sort_direction: new_direction,
       page: 1
     })}
  end

  @impl true
  def handle_event("change_limit", %{"limit" => limit}, socket) do
    normalized_limit = PaginationHelpers.parse_limit(limit)

    {:noreply, push_dashboard_patch(socket, %{limit: normalized_limit, page: 1})}
  end

  @impl true
  def handle_event("filter_http_status", %{"http_status" => value}, socket) do
    {:noreply, push_dashboard_patch(socket, %{http_status: value, page: 1})}
  end

  @impl true
  def handle_event("filter_position", %{"position" => value}, socket) do
    {:noreply, push_dashboard_patch(socket, %{position: value, page: 1})}
  end

  @impl true
  def handle_event("filter_clicks", %{"clicks" => value}, socket) do
    {:noreply, push_dashboard_patch(socket, %{clicks: value, page: 1})}
  end

  @impl true
  def handle_event("filter_ctr", %{"ctr" => value}, socket) do
    {:noreply, push_dashboard_patch(socket, %{ctr: value, page: 1})}
  end

  @impl true
  def handle_event("filter_backlinks", %{"backlinks" => value}, socket) do
    {:noreply, push_dashboard_patch(socket, %{backlinks: value, page: 1})}
  end

  @impl true
  def handle_event("filter_redirect", %{"redirect" => value}, socket) do
    {:noreply, push_dashboard_patch(socket, %{redirect: value, page: 1})}
  end

  @impl true
  def handle_event("filter_first_seen", %{"first_seen" => value}, socket) do
    {:noreply, push_dashboard_patch(socket, %{first_seen: value, page: 1})}
  end

  @impl true
  def handle_event("filter_page_type", %{"page_type" => value}, socket) do
    {:noreply, push_dashboard_patch(socket, %{page_type: value, page: 1})}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    {:noreply,
     push_dashboard_patch(socket, %{
       http_status: nil,
       position: nil,
       clicks: nil,
       ctr: nil,
       backlinks: nil,
       redirect: nil,
       first_seen: nil,
       page_type: nil,
       page: 1
     })}
  end

  @impl true
  def handle_event("goto_page", %{"page" => page}, socket) do
    # Navigate to specific page
    page_num = PaginationHelpers.parse_page(page)

    # Ensure page is within valid range
    page_num = max(1, min(page_num, socket.assigns.total_pages))

    {:noreply, push_dashboard_patch(socket, %{page: page_num})}
  end

  @impl true
  def handle_event("next_page", _params, socket) do
    # Navigate to next page
    next_page = min(socket.assigns.page + 1, socket.assigns.total_pages)

    {:noreply, push_dashboard_patch(socket, %{page: next_page})}
  end

  @impl true
  def handle_event("prev_page", _params, socket) do
    # Navigate to previous page
    prev_page = max(socket.assigns.page - 1, 1)

    {:noreply, push_dashboard_patch(socket, %{page: prev_page})}
  end

  @impl true
  def handle_info({:sync_progress, %{type: :started}}, socket) do
    # Mark sync as running to show indicator
    {:noreply, assign(socket, :sync_running, true)}
  end

  @impl true
  def handle_info({:sync_progress, %{type: :finished, job: _job}}, socket) do
    # Sync completed - refresh all dashboard data
    account_id = socket.assigns.current_account_id
    property = socket.assigns.current_property
    property_url = property && property.property_url
    sort_direction = DashboardUtils.normalize_sort_direction(socket.assigns.sort_direction)

    snapshot =
      load_dashboard_snapshot(account_id, property_url, %{
        limit: socket.assigns.limit,
        page: socket.assigns.page,
        sort_by: socket.assigns.sort_by,
        sort_direction: sort_direction,
        search: socket.assigns.search,
        period_days: socket.assigns[:period_days] || 30,
        chart_view: socket.assigns.chart_view
      })

    {:noreply,
     socket
     |> assign(:sync_running, false)
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
     |> put_flash(:info, "Dashboard updated with latest sync data ✨")}
  end

  @impl true
  def handle_info({:sync_progress, _event}, socket) do
    # Ignore other sync progress events (step updates, etc.)
    {:noreply, socket}
  end

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

  defp chart_view("weekly"), do: "weekly"
  defp chart_view("monthly"), do: "monthly"
  defp chart_view(_), do: "daily"

  defp push_dashboard_patch(socket, overrides) do
    property_override = Map.get(overrides, :property_id)
    sanitized_overrides = Map.delete(overrides, :property_id)

    params =
      socket.assigns
      |> DashboardParams.build_dashboard_query(sanitized_overrides)

    property_id = property_override || socket.assigns.current_property_id

    push_patch(socket, to: PropertyRoutes.dashboard_path(property_id, params))
  end

  # Display label helpers - extract inline template computations to proper assigns

  defp assign_display_labels(socket) do
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

  # Month-over-month indicator helpers
  defp assign_mom_indicators(socket) do
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

  # Date label helpers
  defp assign_date_labels(socket) do
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
