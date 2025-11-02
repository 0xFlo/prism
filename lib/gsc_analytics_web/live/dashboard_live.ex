defmodule GscAnalyticsWeb.DashboardLive do
  use GscAnalyticsWeb, :live_view

  alias GscAnalytics.ContentInsights
  alias GscAnalytics.Analytics.{SiteTrends, SummaryStats}
  alias GscAnalytics.Dashboard, as: DashboardUtils
  alias GscAnalytics.DataSources.GSC.Support.SyncProgress
  alias GscAnalyticsWeb.Live.AccountHelpers
  alias GscAnalyticsWeb.Dashboard.Columns
  alias GscAnalyticsWeb.Presenters.ChartDataPresenter

  # Import helper functions for template formatting
  import GscAnalyticsWeb.Dashboard.HTMLHelpers
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
     |> assign_new(:show_impressions, fn -> true end)
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
    property_label = property && (property.display_name || property.property_url)

    limit = DashboardUtils.normalize_limit(params["limit"])
    page = DashboardUtils.normalize_page(params["page"])
    sort_by = normalize_sort_by(params["sort_by"])
    sort_direction = DashboardUtils.normalize_sort_direction(params["sort_direction"])
    view_mode = Columns.validate_view_mode(params["view_mode"] || "basic")
    chart_view = chart_view(params["chart_view"])
    search = params["search"] || ""
    # Parse period parameter for v2 functions (default to 30 days)
    period_days = parse_period(params["period"])

    # Extract path from URI for active nav detection
    current_path = URI.parse(uri).path || "/"

    # Only fetch data if we have a property selected
    {result, stats, site_trends, chart_label, period_totals, socket} =
      if property_url do
        # Fetch data with pagination and search, filtering by property
        result =
          ContentInsights.list_urls(%{
            limit: limit,
            page: page,
            sort_by: sort_by,
            sort_direction: sort_direction,
            search: search,
            period_days: period_days,
            account_id: account_id,
            property_url: property_url
          })

        # Get summary stats filtered by property
        stats = SummaryStats.fetch(%{account_id: account_id, property_url: property_url})

        {site_trends, chart_label} =
          SiteTrends.fetch(chart_view, %{
            account_id: account_id,
            property_url: property_url,
            period_days: period_days
          })

        # Fetch aggregated totals for the selected period
        period_totals =
          SiteTrends.fetch_period_totals(%{
            account_id: account_id,
            property_url: property_url,
            period_days: period_days
          })

        {result, stats, site_trends, chart_label, period_totals, socket}
      else
        # Empty state when no property selected
        # Only show warning flash if we haven't already
        socket =
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

        empty_result = %{urls: [], page: 1, total_pages: 1, total_count: 0}

        empty_period_stats = %{
          total_urls: 0,
          total_clicks: 0,
          total_impressions: 0,
          avg_ctr: 0.0,
          avg_position: 0.0
        }

        empty_stats = %{
          current_month: empty_period_stats,
          last_month: empty_period_stats,
          all_time:
            Map.merge(empty_period_stats, %{
              earliest_date: nil,
              latest_date: nil,
              days_with_data: 0
            }),
          month_over_month_change: 0
        }

        empty_period_totals = %{
          total_clicks: 0,
          total_impressions: 0,
          avg_ctr: 0.0,
          avg_position: 0.0
        }

        {empty_result, empty_stats, [], "Date", empty_period_totals, socket}
      end

    {:noreply,
     socket
     |> assign(:current_path, current_path)
     |> assign(:urls, result.urls)
     |> assign(:page, result.page)
     |> assign(:total_pages, result.total_pages)
     |> assign(:total_count, result.total_count)
     |> assign(:stats, stats)
     |> assign(:site_trends, site_trends)
     |> assign(:site_trends_json, ChartDataPresenter.encode_time_series(site_trends))
     |> assign(:chart_label, chart_label)
     |> assign(:chart_view, chart_view)
     |> assign(:sort_by, sort_by)
     |> assign(:sort_direction, Atom.to_string(sort_direction))
     |> assign(:limit, limit)
     |> assign(:view_mode, view_mode)
     |> assign(:search, search)
     |> assign(:period_days, period_days)
     |> assign(:property_label, property_label)
     |> assign(:total_clicks, period_totals.total_clicks)
     |> assign(:total_impressions, period_totals.total_impressions)
     |> assign(:avg_ctr, period_totals.avg_ctr)
     |> assign(:avg_position, period_totals.avg_position)
     |> assign(
       :page_title,
       if(property_label,
         do: "GSC Dashboard – #{property_label}",
         else: "GSC Analytics Dashboard"
       )
     )
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
    new_period_days = parse_period(period)

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
  def handle_event("toggle_impressions", _params, socket) do
    {:noreply, assign(socket, :show_impressions, !socket.assigns.show_impressions)}
  end

  @impl true
  def handle_event("sort_column", %{"column" => column}, socket) do
    # Determine new sort direction - toggle if same column, default for new column
    # Reset to page 1 since sort order changes results
    normalized_column = normalize_sort_by(column)

    new_direction =
      if socket.assigns.sort_by == normalized_column do
        # Toggle direction for same column
        if socket.assigns.sort_direction == "asc", do: "desc", else: "asc"
      else
        # Default direction for new column - position ascending (lower is better), others descending
        if normalized_column == "position", do: "asc", else: "desc"
      end

    {:noreply,
     push_dashboard_patch(socket, %{
       sort_by: normalized_column,
       sort_direction: new_direction,
       page: 1
     })}
  end

  @impl true
  def handle_event("change_limit", %{"limit" => limit}, socket) do
    normalized_limit = DashboardUtils.normalize_limit(limit)

    {:noreply, push_dashboard_patch(socket, %{limit: normalized_limit, page: 1})}
  end

  @impl true
  def handle_event("goto_page", %{"page" => page}, socket) do
    # Navigate to specific page
    page_num = DashboardUtils.normalize_page(page)

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

    result =
      if property_url do
        ContentInsights.list_urls(%{
          limit: socket.assigns.limit,
          page: socket.assigns.page,
          sort_by: socket.assigns.sort_by,
          sort_direction: String.to_existing_atom(socket.assigns.sort_direction),
          search: socket.assigns.search,
          period_days: socket.assigns[:period_days] || 30,
          account_id: account_id,
          property_url: property_url
        })
      else
        %{urls: [], page: 1, total_pages: 1, total_count: 0}
      end

    stats =
      if property_url do
        SummaryStats.fetch(%{account_id: account_id, property_url: property_url})
      else
        # Same empty stats structure as in handle_params
        empty_period_stats = %{
          total_urls: 0,
          total_clicks: 0,
          total_impressions: 0,
          avg_ctr: 0.0,
          avg_position: 0.0
        }

        %{
          current_month: empty_period_stats,
          last_month: empty_period_stats,
          all_time:
            Map.merge(empty_period_stats, %{
              earliest_date: nil,
              latest_date: nil,
              days_with_data: 0
            }),
          month_over_month_change: 0
        }
      end

    {site_trends, chart_label} =
      if property_url do
        SiteTrends.fetch(socket.assigns.chart_view, %{
          account_id: account_id,
          property_url: property_url,
          period_days: socket.assigns.period_days
        })
      else
        {[], "Date"}
      end

    period_totals =
      if property_url do
        SiteTrends.fetch_period_totals(%{
          account_id: account_id,
          property_url: property_url,
          period_days: socket.assigns.period_days
        })
      else
        %{total_clicks: 0, total_impressions: 0, avg_ctr: 0.0, avg_position: 0.0}
      end

    {:noreply,
     socket
     |> assign(:sync_running, false)
     |> assign(:urls, result.urls)
     |> assign(:page, result.page)
     |> assign(:total_pages, result.total_pages)
     |> assign(:total_count, result.total_count)
     |> assign(:stats, stats)
     |> assign(:site_trends, site_trends)
     |> assign(:site_trends_json, ChartDataPresenter.encode_time_series(site_trends))
     |> assign(:chart_label, chart_label)
     |> assign(:total_clicks, period_totals.total_clicks)
     |> assign(:total_impressions, period_totals.total_impressions)
     |> assign(:avg_ctr, period_totals.avg_ctr)
     |> assign(:avg_position, period_totals.avg_position)
     |> put_flash(:info, "Dashboard updated with latest sync data ✨")}
  end

  @impl true
  def handle_info({:sync_progress, _event}, socket) do
    # Ignore other sync progress events (step updates, etc.)
    {:noreply, socket}
  end

  defp chart_view("weekly"), do: "weekly"
  defp chart_view("monthly"), do: "monthly"
  defp chart_view(_), do: "daily"

  defp normalize_sort_by(nil), do: "clicks"
  defp normalize_sort_by(""), do: "clicks"

  defp normalize_sort_by(sort_by) when sort_by in ["clicks", "impressions", "ctr", "position"],
    do: sort_by

  defp normalize_sort_by("lifetime_clicks"), do: "clicks"
  defp normalize_sort_by("period_clicks"), do: "clicks"
  defp normalize_sort_by("period_impressions"), do: "impressions"
  defp normalize_sort_by("lifetime_avg_ctr"), do: "ctr"
  defp normalize_sort_by("lifetime_avg_position"), do: "position"
  defp normalize_sort_by(other) when is_binary(other), do: other
  defp normalize_sort_by(_), do: "clicks"

  defp parse_period(nil), do: 30
  defp parse_period("7"), do: 7
  defp parse_period("30"), do: 30
  defp parse_period("90"), do: 90
  defp parse_period("180"), do: 180
  defp parse_period("365"), do: 365
  # Large number for "all time"
  defp parse_period("all"), do: 10000
  defp parse_period(value) when is_integer(value) and value > 0, do: value

  defp parse_period(value) when is_binary(value) do
    case Integer.parse(value) do
      {days, ""} when days > 0 -> days
      _ -> 30
    end
  end

  defp parse_period(_), do: 30

  # Display label helpers - extract inline template computations to proper assigns
  defp build_query_params(socket, overrides) do
    base = %{
      view_mode: socket.assigns.view_mode,
      sort_by: socket.assigns.sort_by,
      sort_direction: socket.assigns.sort_direction,
      limit: socket.assigns.limit,
      page: socket.assigns.page,
      chart_view: socket.assigns.chart_view,
      search: socket.assigns.search,
      period: socket.assigns.period_days,
      property_id: socket.assigns.current_property_id
    }

    base
    |> Map.merge(overrides)
    |> Enum.reject(fn
      {_key, value} when value in [nil, ""] -> true
      _ -> false
    end)
    |> Map.new()
  end

  defp push_dashboard_patch(socket, overrides) do
    params = build_query_params(socket, overrides)
    push_patch(socket, to: ~p"/dashboard?#{params}")
  end

  defp assign_display_labels(socket) do
    period_label_text = period_label(socket.assigns.period_days)

    socket
    |> assign(:period_label, period_label_text)
    |> assign(:chart_view_label, chart_view_label(socket.assigns.chart_view))
    |> assign(:sort_label, sort_label(socket.assigns.sort_by, period_label_text))
    |> assign(:sort_direction_label, sort_direction_label(socket.assigns.sort_direction))
  end

  defp period_label(7), do: "Last 7 days"
  defp period_label(30), do: "Last 30 days"
  defp period_label(90), do: "Last 90 days"
  defp period_label(180), do: "Last 6 months"
  defp period_label(10000), do: "All time"
  defp period_label(days) when is_integer(days), do: "#{days} days"
  defp period_label(value), do: to_string(value)

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
