defmodule GscAnalyticsWeb.DashboardLive do
  use GscAnalyticsWeb, :live_view
  require Logger

  alias GscAnalytics.DataSources.GSC.Support.SyncProgress
  alias GscAnalyticsWeb.Live.{AccountHelpers, DashboardParams, PaginationHelpers}
  alias GscAnalyticsWeb.Dashboard.Columns

  # Import extracted modules
  alias GscAnalyticsWeb.DashboardLive.{DisplayHelpers, EventHandlers, SnapshotLoader}

  # Import component functions for template
  import GscAnalyticsWeb.Components.DashboardControls
  import GscAnalyticsWeb.Components.DashboardFilters
  import GscAnalyticsWeb.Components.DashboardTables

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
     |> assign_new(:avg_position, fn -> 0.0 end)
     |> assign_new(:site_trends_json, fn -> "[]" end)
     |> assign_new(:snapshot_loading?, fn -> false end)
     |> assign_new(:latest_snapshot_ref, fn -> nil end)
     |> assign_new(:snapshot_initialized?, fn -> false end)}
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
    sort_direction = normalize_sort_direction(params["sort_direction"])
    view_mode = Columns.validate_view_mode(params["view_mode"] || "basic")
    chart_view = DisplayHelpers.chart_view(params["chart_view"])
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

    snapshot_opts = %{
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
    }

    base_socket =
      socket
      |> assign(:current_path, current_path)
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
      |> DisplayHelpers.assign_display_labels()

    force_snapshot? = not connected?(socket)

    {:noreply,
     SnapshotLoader.load_snapshot(base_socket, account_id, property_url, snapshot_opts,
       force?: force_snapshot?
     )}
  end

  # ============================================================================
  # Event Handlers - Delegated to EventHandlers module
  # ============================================================================

  @impl true
  def handle_event("search", params, socket) do
    EventHandlers.handle_search(params, socket)
  end

  @impl true
  def handle_event("switch_property", params, socket) do
    EventHandlers.handle_switch_property(params, socket)
  end

  @impl true
  def handle_event("change_view_mode", params, socket) do
    EventHandlers.handle_change_view_mode(params, socket)
  end

  @impl true
  def handle_event("change_period", params, socket) do
    EventHandlers.handle_change_period(params, socket)
  end

  @impl true
  def handle_event("change_chart_view", params, socket) do
    EventHandlers.handle_change_chart_view(params, socket)
  end

  @impl true
  def handle_event("toggle_series", params, socket) do
    EventHandlers.handle_toggle_series(params, socket)
  end

  @impl true
  def handle_event("sort_column", params, socket) do
    EventHandlers.handle_sort_column(params, socket)
  end

  @impl true
  def handle_event("change_limit", params, socket) do
    EventHandlers.handle_change_limit(params, socket)
  end

  @impl true
  def handle_event("filter_http_status", params, socket) do
    EventHandlers.handle_filter_http_status(params, socket)
  end

  @impl true
  def handle_event("filter_position", params, socket) do
    EventHandlers.handle_filter_position(params, socket)
  end

  @impl true
  def handle_event("filter_clicks", params, socket) do
    EventHandlers.handle_filter_clicks(params, socket)
  end

  @impl true
  def handle_event("filter_ctr", params, socket) do
    EventHandlers.handle_filter_ctr(params, socket)
  end

  @impl true
  def handle_event("filter_backlinks", params, socket) do
    EventHandlers.handle_filter_backlinks(params, socket)
  end

  @impl true
  def handle_event("filter_redirect", params, socket) do
    EventHandlers.handle_filter_redirect(params, socket)
  end

  @impl true
  def handle_event("filter_first_seen", params, socket) do
    EventHandlers.handle_filter_first_seen(params, socket)
  end

  @impl true
  def handle_event("filter_page_type", params, socket) do
    EventHandlers.handle_filter_page_type(params, socket)
  end

  @impl true
  def handle_event("clear_filters", params, socket) do
    EventHandlers.handle_clear_filters(params, socket)
  end

  @impl true
  def handle_event("goto_page", params, socket) do
    EventHandlers.handle_goto_page(params, socket)
  end

  @impl true
  def handle_event("next_page", params, socket) do
    EventHandlers.handle_next_page(params, socket)
  end

  @impl true
  def handle_event("prev_page", params, socket) do
    EventHandlers.handle_prev_page(params, socket)
  end

  # ============================================================================
  # PubSub Handlers - Sync Progress Updates
  # ============================================================================

  @impl true
  def handle_info({:sync_progress, %{type: :started, job: job}}, socket) do
    if job_matches_socket?(socket, job) do
      {:noreply, assign(socket, :sync_running, true)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:sync_progress, %{type: :step_completed, job: job}}, socket) do
    if job_matches_socket?(socket, job) do
      property_url =
        socket.assigns.current_property && socket.assigns.current_property.property_url

      {:noreply,
       SnapshotLoader.load_snapshot(
         socket,
         socket.assigns.current_account_id,
         property_url,
         SnapshotLoader.current_snapshot_opts(socket),
         force?: false
       )}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:sync_progress, %{type: :finished, job: job}}, socket) do
    socket = assign(socket, :sync_running, false)

    if job_matches_socket?(socket, job) do
      property_url =
        socket.assigns.current_property && socket.assigns.current_property.property_url

      socket =
        socket
        |> put_flash(:info, "Dashboard updated with latest sync data")
        |> SnapshotLoader.load_snapshot(
          socket.assigns.current_account_id,
          property_url,
          SnapshotLoader.current_snapshot_opts(socket),
          force?: true
        )

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:sync_progress, _event}, socket) do
    # Ignore other sync progress events (step updates, etc.)
    {:noreply, socket}
  end

  # ============================================================================
  # Async Task Handlers - Delegated to SnapshotLoader
  # ============================================================================

  @impl true
  def handle_async({:dashboard_snapshot, ref}, {:ok, snapshot}, socket) do
    SnapshotLoader.handle_async_success(socket, ref, snapshot)
  end

  @impl true
  def handle_async({:dashboard_snapshot, ref}, {:exit, reason}, socket) do
    SnapshotLoader.handle_async_failure(socket, ref, reason)
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp job_matches_socket?(socket, job) do
    property = socket.assigns.current_property

    case {property, job} do
      {nil, _} ->
        false

      {_, %{metadata: metadata}} when is_map(metadata) ->
        metadata[:account_id] == socket.assigns.current_account_id and
          metadata[:site_url] == property.property_url

      _ ->
        false
    end
  end

  # Normalize sort direction to atom for internal use
  # (DashboardParams returns strings for URL params, we need atoms for Ecto)
  defp normalize_sort_direction(nil), do: :desc
  defp normalize_sort_direction("asc"), do: :asc
  defp normalize_sort_direction(:asc), do: :asc
  defp normalize_sort_direction("desc"), do: :desc
  defp normalize_sort_direction(:desc), do: :desc
  defp normalize_sort_direction(_), do: :desc
end
