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

    socket = assign(socket, :current_scope, nil)
    {socket, _account} = AccountHelpers.init_account_assigns(socket, params)

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
     |> assign_new(:chart_label, fn -> "Date" end)
     |> assign_new(:chart_view, fn -> "daily" end)
     |> assign_new(:sort_by, fn -> "clicks" end)
     |> assign_new(:sort_direction, fn -> "desc" end)
     |> assign_new(:limit, fn -> 50 end)
     |> assign_new(:page, fn -> 1 end)
     |> assign_new(:total_pages, fn -> 1 end)
     |> assign_new(:total_count, fn -> 0 end)
     |> assign_new(:view_mode, fn -> "basic" end)
     |> assign_new(:needs_update_filter, fn -> false end)
     |> assign_new(:search, fn -> "" end)
     |> assign_new(:page_title, fn -> "GSC Analytics Dashboard" end)}
  end

  @impl true
  def handle_params(params, uri, socket) do
    socket = AccountHelpers.assign_current_account(socket, params)
    account_id = socket.assigns.current_account_id

    limit = DashboardUtils.normalize_limit(params["limit"])
    page = DashboardUtils.normalize_page(params["page"])
    sort_by = params["sort_by"] || "lifetime_clicks"
    sort_direction = DashboardUtils.normalize_sort_direction(params["sort_direction"])
    view_mode = Columns.validate_view_mode(params["view_mode"] || "basic")
    needs_update = parse_bool(params["needs_update"])
    chart_view = chart_view(params["chart_view"])
    search = params["search"] || ""
    # Parse period parameter for v2 functions (default to 30 days)
    period_days = parse_period(params["period"])

    # Extract path from URI for active nav detection
    current_path = URI.parse(uri).path || "/"

    # Fetch data with pagination and search
    result =
      ContentInsights.list_urls(%{
        limit: limit,
        page: page,
        sort_by: sort_by,
        sort_direction: sort_direction,
        needs_update: needs_update,
        search: search,
        period_days: period_days,
        account_id: account_id
      })

    # Get summary stats showing current month, last month, all time
    stats = SummaryStats.fetch(%{account_id: account_id})
    {site_trends, chart_label} = SiteTrends.fetch(chart_view, %{account_id: account_id})

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
     |> assign(:needs_update_filter, needs_update)
     |> assign(:search, search)
     |> assign(:period_days, period_days)
     |> assign(:page_title, "GSC Analytics Dashboard")}
  end

  @impl true
  def handle_event("search", %{"search" => search_term}, socket) do
    # Update search - reset to page 1 when searching
    params = %{
      view_mode: socket.assigns.view_mode,
      needs_update: socket.assigns.needs_update_filter,
      sort_by: socket.assigns.sort_by,
      sort_direction: socket.assigns.sort_direction,
      limit: socket.assigns.limit,
      page: 1,
      chart_view: socket.assigns.chart_view,
      search: search_term,
      period: socket.assigns.period_days,
      account_id: socket.assigns.current_account_id
    }

    {:noreply, push_patch(socket, to: ~p"/dashboard?#{params}")}
  end

  @impl true
  def handle_event("change_view_mode", %{"view_mode" => view_mode}, socket) do
    # Update URL with new view mode - keep current page
    validated_mode = Columns.validate_view_mode(view_mode)

    params = %{
      view_mode: validated_mode,
      needs_update: socket.assigns.needs_update_filter,
      sort_by: socket.assigns.sort_by,
      sort_direction: socket.assigns.sort_direction,
      limit: socket.assigns.limit,
      page: socket.assigns.page,
      chart_view: socket.assigns.chart_view,
      search: socket.assigns.search,
      period: socket.assigns.period_days,
      account_id: socket.assigns.current_account_id
    }

    {:noreply, push_patch(socket, to: ~p"/dashboard?#{params}")}
  end

  @impl true
  def handle_event("toggle_needs_update", _params, socket) do
    # Toggle the current state - reset to page 1 since filtering changes results
    needs_update = !socket.assigns.needs_update_filter

    params = %{
      view_mode: socket.assigns.view_mode,
      needs_update: needs_update,
      sort_by: socket.assigns.sort_by,
      sort_direction: socket.assigns.sort_direction,
      limit: socket.assigns.limit,
      page: 1,
      chart_view: socket.assigns.chart_view,
      search: socket.assigns.search,
      period: socket.assigns.period_days,
      account_id: socket.assigns.current_account_id
    }

    {:noreply,
     socket
     |> assign(:needs_update_filter, needs_update)
     |> push_patch(to: ~p"/dashboard?#{params}")}
  end

  @impl true
  def handle_event("change_period", %{"period" => period}, socket) do
    # Update URL with new period - reset to page 1 since data changes
    params = %{
      view_mode: socket.assigns.view_mode,
      needs_update: socket.assigns.needs_update_filter,
      sort_by: socket.assigns.sort_by,
      sort_direction: socket.assigns.sort_direction,
      limit: socket.assigns.limit,
      page: 1,
      chart_view: socket.assigns.chart_view,
      search: socket.assigns.search,
      period: period,
      account_id: socket.assigns.current_account_id
    }

    {:noreply, push_patch(socket, to: ~p"/dashboard?#{params}")}
  end

  @impl true
  def handle_event("change_chart_view", %{"chart_view" => chart_view}, socket) do
    # Update URL with new chart view mode - keep current page
    params = %{
      view_mode: socket.assigns.view_mode,
      needs_update: socket.assigns.needs_update_filter,
      sort_by: socket.assigns.sort_by,
      sort_direction: socket.assigns.sort_direction,
      limit: socket.assigns.limit,
      page: socket.assigns.page,
      chart_view: chart_view,
      search: socket.assigns.search,
      period: socket.assigns.period_days,
      account_id: socket.assigns.current_account_id
    }

    {:noreply, push_patch(socket, to: ~p"/dashboard?#{params}")}
  end

  @impl true
  def handle_event("sort_column", %{"column" => column}, socket) do
    # Determine new sort direction - toggle if same column, default for new column
    # Reset to page 1 since sort order changes results
    new_direction =
      if socket.assigns.sort_by == column do
        # Toggle direction for same column
        if socket.assigns.sort_direction == "asc", do: "desc", else: "asc"
      else
        # Default direction for new column - position ascending (lower is better), others descending
        if column == "position", do: "asc", else: "desc"
      end

    params = %{
      view_mode: socket.assigns.view_mode,
      needs_update: socket.assigns.needs_update_filter,
      sort_by: column,
      sort_direction: new_direction,
      limit: socket.assigns.limit,
      page: 1,
      chart_view: socket.assigns.chart_view,
      search: socket.assigns.search,
      period: socket.assigns.period_days,
      account_id: socket.assigns.current_account_id
    }

    {:noreply, push_patch(socket, to: ~p"/dashboard?#{params}")}
  end

  @impl true
  def handle_event("apply_filters", params, socket) do
    sort_by = params["sort_by"] || socket.assigns.sort_by
    limit_param = params["limit"] || socket.assigns.limit
    search_param = params["search"] || socket.assigns.search

    # Reset to page 1 when applying filters (limit or sort changes)
    query_params = %{
      view_mode: params["view_mode"] || socket.assigns.view_mode,
      needs_update: socket.assigns.needs_update_filter,
      sort_by: sort_by,
      sort_direction: socket.assigns.sort_direction,
      limit: limit_param,
      page: 1,
      chart_view: socket.assigns.chart_view,
      search: search_param,
      period: socket.assigns.period_days,
      account_id: socket.assigns.current_account_id
    }

    {:noreply, push_patch(socket, to: ~p"/dashboard?#{query_params}")}
  end

  @impl true
  def handle_event("goto_page", %{"page" => page}, socket) do
    # Navigate to specific page
    page_num = DashboardUtils.normalize_page(page)

    # Ensure page is within valid range
    page_num = max(1, min(page_num, socket.assigns.total_pages))

    params = %{
      view_mode: socket.assigns.view_mode,
      needs_update: socket.assigns.needs_update_filter,
      sort_by: socket.assigns.sort_by,
      sort_direction: socket.assigns.sort_direction,
      limit: socket.assigns.limit,
      page: page_num,
      chart_view: socket.assigns.chart_view,
      search: socket.assigns.search,
      period: socket.assigns.period_days,
      account_id: socket.assigns.current_account_id
    }

    {:noreply, push_patch(socket, to: ~p"/dashboard?#{params}")}
  end

  @impl true
  def handle_event("next_page", _params, socket) do
    # Navigate to next page
    next_page = min(socket.assigns.page + 1, socket.assigns.total_pages)

    params = %{
      view_mode: socket.assigns.view_mode,
      needs_update: socket.assigns.needs_update_filter,
      sort_by: socket.assigns.sort_by,
      sort_direction: socket.assigns.sort_direction,
      limit: socket.assigns.limit,
      page: next_page,
      chart_view: socket.assigns.chart_view,
      search: socket.assigns.search,
      period: socket.assigns.period_days,
      account_id: socket.assigns.current_account_id
    }

    {:noreply, push_patch(socket, to: ~p"/dashboard?#{params}")}
  end

  @impl true
  def handle_event("prev_page", _params, socket) do
    # Navigate to previous page
    prev_page = max(socket.assigns.page - 1, 1)

    params = %{
      view_mode: socket.assigns.view_mode,
      needs_update: socket.assigns.needs_update_filter,
      sort_by: socket.assigns.sort_by,
      sort_direction: socket.assigns.sort_direction,
      limit: socket.assigns.limit,
      page: prev_page,
      chart_view: socket.assigns.chart_view,
      search: socket.assigns.search,
      period: socket.assigns.period_days,
      account_id: socket.assigns.current_account_id
    }

    {:noreply, push_patch(socket, to: ~p"/dashboard?#{params}")}
  end

  @impl true
  def handle_event("change_account", %{"account_id" => account_id}, socket) do
    params = %{
      view_mode: socket.assigns.view_mode,
      needs_update: socket.assigns.needs_update_filter,
      sort_by: socket.assigns.sort_by,
      sort_direction: socket.assigns.sort_direction,
      limit: socket.assigns.limit,
      page: socket.assigns.page,
      chart_view: socket.assigns.chart_view,
      search: socket.assigns.search,
      period: socket.assigns.period_days,
      account_id: account_id
    }

    {:noreply, push_patch(socket, to: ~p"/dashboard?#{params}")}
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

    result =
      ContentInsights.list_urls(%{
        limit: socket.assigns.limit,
        page: socket.assigns.page,
        sort_by: socket.assigns.sort_by,
        sort_direction: String.to_existing_atom(socket.assigns.sort_direction),
        needs_update: socket.assigns.needs_update_filter,
        search: socket.assigns.search,
        period_days: socket.assigns[:period_days] || 30,
        account_id: account_id
      })

    stats = SummaryStats.fetch(%{account_id: account_id})
    {site_trends, chart_label} = SiteTrends.fetch(socket.assigns.chart_view, %{account_id: account_id})

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

  defp parse_bool(value) when value in [true, "true", "1", 1], do: true
  defp parse_bool(_), do: false

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
end
