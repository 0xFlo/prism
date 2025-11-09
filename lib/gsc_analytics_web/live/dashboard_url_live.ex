defmodule GscAnalyticsWeb.DashboardUrlLive do
  use GscAnalyticsWeb, :live_view

  alias GscAnalytics.ContentInsights
  alias GscAnalyticsWeb.Live.AccountHelpers
  alias GscAnalyticsWeb.Live.DashboardParams
  alias GscAnalyticsWeb.Presenters.ChartDataPresenter
  alias GscAnalyticsWeb.Presenters.DashboardUrlHelpers, as: UrlHelpers

  import GscAnalyticsWeb.Dashboard.HTMLHelpers
  import GscAnalyticsWeb.Components.DashboardComponents

  @impl true
  def mount(params, _session, socket) do
    socket =
      socket
      |> assign_default_state()

    # LiveView best practice: Use assign_new/3 for safe defaults
    # This prevents runtime errors from missing assigns and makes the component more resilient
    {socket, account, _property} =
      AccountHelpers.init_account_and_property_assigns(socket, params)

    # Redirect to Settings if no workspaces exist
    if is_nil(account) do
      {:ok,
       socket
       |> put_flash(
         :info,
         "Please add a Google Search Console workspace to get started."
       )
       |> redirect(to: ~p"/users/settings")}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_params(%{"url" => url} = params, uri, socket)
      when is_binary(url) and byte_size(url) > 0 do
    socket =
      socket
      |> AccountHelpers.assign_current_account(params)
      |> AccountHelpers.assign_current_property(params, skip_reload: true)

    account_id = socket.assigns.current_account_id
    property = socket.assigns.current_property
    property_url = property && property.property_url
    chart_view = normalize_chart_view(params["view"])
    period_days = DashboardParams.parse_period(params["period"])
    visible_series = DashboardParams.parse_visible_series(params["series"])

    property_label =
      property &&
        (property.display_name || AccountHelpers.display_property_label(property.property_url))

    property_favicon_url = property && property.favicon_url

    insights =
      ContentInsights.url_insights(url, chart_view, %{
        period_days: period_days,
        account_id: account_id,
        property_url: property_url
      })

    current_path = URI.parse(uri).path || "/dashboard/url"

    # Parse sort params
    queries_sort_by = params["queries_sort"] || "clicks"
    queries_sort_dir = normalize_sort_direction(params["queries_dir"])
    backlinks_sort_by = params["backlinks_sort"] || "first_seen_at"
    backlinks_sort_dir = normalize_sort_direction(params["backlinks_dir"])

    # Sort data
    sorted_insights =
      insights
      |> UrlHelpers.sort_queries(queries_sort_by, queries_sort_dir)
      |> UrlHelpers.sort_backlinks(backlinks_sort_by, backlinks_sort_dir)

    encoded_url =
      insights
      |> Map.get(:requested_url)
      |> case do
        nil -> Map.get(insights, :url)
        value -> value
      end
      |> safe_encode_url()

    enriched_insights =
      sorted_insights
      |> Map.put(
        :time_series_json,
        ChartDataPresenter.encode_time_series(List.wrap(sorted_insights.time_series))
      )
      |> Map.put(
        :chart_events_json,
        ChartDataPresenter.encode_events(List.wrap(sorted_insights.chart_events))
      )

    links =
      UrlHelpers.dashboard_links(%{
        current_account_id: account_id,
        current_property_id: socket.assigns.current_property_id,
        chart_view: chart_view,
        period_days: period_days,
        visible_series: visible_series
      })

    {:noreply,
     socket
     |> assign(:current_path, current_path)
     |> assign(:chart_view, chart_view)
     |> assign(:period_days, period_days)
     |> assign(:period_label, DashboardParams.period_label(period_days))
     |> assign(:insights, enriched_insights)
     |> assign(:visible_series, visible_series)
     |> assign(:encoded_url, encoded_url)
     |> assign(:queries_sort_by, queries_sort_by)
     |> assign(:queries_sort_direction, queries_sort_dir)
     |> assign(:backlinks_sort_by, backlinks_sort_by)
     |> assign(:backlinks_sort_direction, backlinks_sort_dir)
     |> assign(:chart_view_label, UrlHelpers.chart_view_label(chart_view))
     |> assign(:property_label, property_label)
     |> assign(:property_favicon_url, property_favicon_url)
     |> assign(:dashboard_return_path, links.return_path)
     |> assign(:dashboard_export_path, links.export_path)}
  end

  def handle_params(_params, uri, socket) do
    socket = AccountHelpers.assign_current_account(socket, %{})
    current_path = URI.parse(uri).path || "/dashboard/url"

    {:noreply,
     socket
     |> assign(:current_path, current_path)
     |> push_navigate(to: ~p"/dashboard")}
  end

  @impl true
  def handle_event("change_chart_view", params, socket) do
    chart_view = normalize_chart_view(params["chart_view"] || params["view"])

    {:noreply,
     socket
     |> assign(:chart_view, chart_view)
     |> assign(:chart_view_label, UrlHelpers.chart_view_label(chart_view))
     |> push_url_patch(%{view: chart_view}, %{chart_view: chart_view})}
  end

  @impl true
  def handle_event("change_period", %{"period" => period}, socket) do
    period_days = DashboardParams.parse_period(period)
    params_assigns = %{period_days: period_days}

    {:noreply,
     socket
     |> assign(:period_days, period_days)
     |> assign(:period_label, DashboardParams.period_label(period_days))
     |> push_url_patch(%{period: period}, params_assigns)}
  end

  @impl true
  def handle_event("sort_queries", %{"column" => column}, socket) do
    # Toggle direction if same column, default for new column
    new_direction =
      if socket.assigns.queries_sort_by == column do
        if socket.assigns.queries_sort_direction == "asc", do: "desc", else: "asc"
      else
        if column == "position", do: "asc", else: "desc"
      end

    {:noreply, push_url_patch(socket, %{queries_sort: column, queries_dir: new_direction})}
  end

  @impl true
  def handle_event("sort_backlinks", %{"column" => column}, socket) do
    # Toggle direction if same column, default desc for new column
    new_direction =
      if socket.assigns.backlinks_sort_by == column do
        if socket.assigns.backlinks_sort_direction == "asc", do: "desc", else: "asc"
      else
        "desc"
      end

    {:noreply, push_url_patch(socket, %{backlinks_sort: column, backlinks_dir: new_direction})}
  end

  @impl true
  def handle_event("toggle_series", %{"metric" => metric_str}, socket) do
    metric = String.to_existing_atom(metric_str)
    current_series = socket.assigns.visible_series

    new_series =
      if metric in current_series do
        List.delete(current_series, metric)
      else
        [metric | current_series]
      end

    new_series = if Enum.empty?(new_series), do: [metric], else: new_series
    encoded_series = DashboardParams.encode_series(new_series)

    updated_socket = assign(socket, :visible_series, new_series)

    {:noreply, push_url_patch(updated_socket, %{series: encoded_series})}
  end

  @impl true
  def handle_event("change_account", %{"account_id" => account_id}, socket) do
    {:noreply, push_url_patch(socket, %{account_id: account_id, property_id: nil})}
  end

  @impl true
  def handle_event("switch_property", %{"property_id" => property_id}, socket) do
    {:noreply, push_url_patch(socket, %{property_id: property_id})}
  end

  defp build_url_params(socket, overrides, assign_overrides) do
    socket.assigns
    |> Map.merge(assign_overrides)
    |> DashboardParams.build_url_query(overrides)
  end

  defp push_url_patch(socket, overrides, assign_overrides \\ %{}) do
    params = build_url_params(socket, overrides, assign_overrides)
    push_patch(socket, to: ~p"/dashboard/url?#{params}")
  end

  defp normalize_chart_view("weekly"), do: "weekly"
  defp normalize_chart_view("monthly"), do: "monthly"
  defp normalize_chart_view(_), do: "daily"

  defp normalize_sort_direction("asc"), do: "asc"
  defp normalize_sort_direction("desc"), do: "desc"
  defp normalize_sort_direction(_), do: "desc"

  defp redirect_event_label(%{type: :gsc_migration}), do: "GSC migration"

  defp redirect_event_label(%{status: status}) when is_integer(status) do
    Integer.to_string(status)
  end

  defp redirect_event_label(%{status: status}) when is_binary(status) and status != "" do
    status
  end

  defp redirect_event_label(_), do: "Redirect"

  defp safe_encode_url(nil), do: ""
  defp safe_encode_url(url) when is_binary(url), do: URI.encode(url)
  defp safe_encode_url(_), do: ""

  defp assign_default_state(socket) do
    socket
    |> assign_new(:page_title, fn -> "URL Performance" end)
    |> assign_new(:insights, fn -> nil end)
    |> assign_new(:chart_view, fn -> "daily" end)
    |> assign_new(:chart_view_label, fn -> UrlHelpers.chart_view_label("daily") end)
    |> assign_new(:period_days, fn -> 30 end)
    |> assign_new(:period_label, fn -> DashboardParams.period_label(30) end)
    |> assign_new(:visible_series, fn -> [:clicks, :impressions] end)
    |> assign_new(:encoded_url, fn -> nil end)
    |> assign_new(:queries_sort_by, fn -> "clicks" end)
    |> assign_new(:queries_sort_direction, fn -> "desc" end)
    |> assign_new(:backlinks_sort_by, fn -> "first_seen_at" end)
    |> assign_new(:backlinks_sort_direction, fn -> "desc" end)
    |> assign_new(:dashboard_return_path, fn -> ~p"/dashboard" end)
    |> assign_new(:dashboard_export_path, fn -> ~p"/dashboard/export" end)
  end
end
