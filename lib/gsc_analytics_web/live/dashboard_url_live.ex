defmodule GscAnalyticsWeb.DashboardUrlLive do
  use GscAnalyticsWeb, :live_view

  alias GscAnalytics.ContentInsights
  alias GscAnalytics.DataSources.SERP.Core.Persistence, as: SerpPersistence
  alias GscAnalytics.SerpChecks
  alias GscAnalyticsWeb.Live.AccountHelpers
  alias GscAnalyticsWeb.Live.ChartHelpers
  alias GscAnalyticsWeb.Live.DashboardParams
  alias GscAnalyticsWeb.Presenters.ChartDataPresenter
  alias GscAnalyticsWeb.Presenters.DashboardUrlHelpers, as: UrlHelpers
  alias GscAnalyticsWeb.PropertyRoutes
  alias Phoenix.PubSub

  import GscAnalyticsWeb.Dashboard.HTMLHelpers
  import GscAnalyticsWeb.Components.DashboardControls
  import GscAnalyticsWeb.Components.DashboardTables

  @serp_keyword_limit Application.compile_env(:gsc_analytics, :serp_bulk_keyword_limit, 7)
  @serp_credit_cost Application.compile_env(:gsc_analytics, :serp_scrapfly_credit_cost, 36)
  @serp_timeout_ms 120_000

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

    # Load latest SERP snapshot for this URL
    serp_snapshot = SerpPersistence.latest_for_url(account_id, property_url, url)

    latest_run =
      if account_id && property_url && url do
        SerpChecks.latest_run(account_id, property_url, url)
      else
        nil
      end

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
     |> assign(:dashboard_export_path, links.export_path)
     |> assign(:serp_snapshot, serp_snapshot)
     |> assign_serp_run(latest_run)}
  end

  def handle_params(_params, uri, socket) do
    socket =
      socket
      |> AccountHelpers.assign_current_account(%{})
      |> AccountHelpers.assign_current_property(%{})

    current_path = URI.parse(uri).path || "/dashboard/url"

    {:noreply,
     socket
     |> assign(:current_path, current_path)
     |> push_navigate(to: PropertyRoutes.dashboard_path(socket.assigns.current_property_id))}
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
      DashboardParams.toggle_sort_direction(
        socket.assigns.queries_sort_by,
        column,
        socket.assigns.queries_sort_direction
      )

    {:noreply, push_url_patch(socket, %{queries_sort: column, queries_dir: new_direction})}
  end

  @impl true
  def handle_event("sort_backlinks", %{"column" => column}, socket) do
    # Toggle direction if same column, default desc for new column
    new_direction =
      DashboardParams.toggle_sort_direction(
        socket.assigns.backlinks_sort_by,
        column,
        socket.assigns.backlinks_sort_direction
      )

    {:noreply, push_url_patch(socket, %{backlinks_sort: column, backlinks_dir: new_direction})}
  end

  @impl true
  def handle_event("toggle_series", %{"metric" => metric_str}, socket) do
    new_series = ChartHelpers.toggle_chart_series(metric_str, socket.assigns.visible_series)
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

  @impl true
  def handle_info({:serp_check_progress, %{run: run}}, socket) do
    topic = SerpChecks.topic(run.id)

    socket =
      if socket.assigns.serp_run_topic == topic do
        socket
        |> assign(:serp_run, run)
        |> maybe_reset_timeout(run)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info(:serp_run_timeout, socket) do
    {:noreply, assign(socket, :serp_timeout_reached?, true)}
  end

  @impl true
  def handle_event("check_top_keywords", _params, socket) do
    cond do
      serp_run_active?(socket.assigns.serp_run) ->
        {:noreply, socket}

      is_nil(socket.assigns.current_property) ->
        {:noreply, put_flash(socket, :error, "Select a property before running SERP checks.")}

      true ->
        url = socket.assigns.insights.url
        property_url = socket.assigns.current_property.property_url

        case SerpChecks.start_bulk_check(
               socket.assigns.current_scope,
               socket.assigns.current_account_id,
               property_url,
               url,
               %{keyword_limit: @serp_keyword_limit}
             ) do
          {:ok, run} ->
            socket =
              socket
              |> assign(:serp_timeout_reached?, false)
              |> assign(:serp_run, run)
              |> subscribe_to_run(run)
              |> schedule_serp_timeout(run)

            message =
              "Checking #{run.keyword_count} keywords (~#{run.estimated_cost} credits). We'll keep you updated."

            {:noreply, put_flash(socket, :info, message)}

          {:error, :no_keywords} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "Could not find recent top queries for this URL. Try expanding the date range."
             )}

          {:error, :invalid_url} ->
            {:noreply, put_flash(socket, :error, "Invalid URL – please refresh and try again.")}

          {:error, :unauthorized_account} ->
            {:noreply,
             put_flash(socket, :error, "You are not authorized to run checks for this workspace.")}

          {:error, reason} ->
            {:noreply,
             put_flash(socket, :error, "Failed to start bulk SERP checks: #{inspect(reason)}")}
        end
    end
  end

  defp build_url_params(socket, overrides, assign_overrides) do
    property_override =
      case Map.fetch(overrides, :property_id) do
        {:ok, value} -> value
        :error -> :no_override
      end

    sanitized_overrides = Map.delete(overrides, :property_id)

    params =
      socket.assigns
      |> Map.merge(assign_overrides)
      |> DashboardParams.build_url_query(sanitized_overrides)

    property_id =
      case property_override do
        :no_override -> socket.assigns.current_property_id
        value -> value
      end

    {params, property_id}
  end

  defp push_url_patch(socket, overrides, assign_overrides \\ %{}) do
    {params, property_id} = build_url_params(socket, overrides, assign_overrides)

    push_patch(
      socket,
      to: PropertyRoutes.url_path(property_id, params)
    )
  end

  defp assign_serp_run(socket, nil) do
    socket
    |> cancel_serp_timeout()
    |> maybe_unsubscribe_run()
    |> assign(:serp_run, nil)
    |> assign(:serp_run_topic, nil)
    |> assign(:serp_timeout_reached?, false)
  end

  defp assign_serp_run(socket, run) do
    socket
    |> subscribe_to_run(run)
    |> assign(:serp_run, run)
    |> assign(:serp_timeout_reached?, false)
    |> schedule_serp_timeout(run)
  end

  defp subscribe_to_run(socket, nil), do: socket

  defp subscribe_to_run(socket, %{id: run_id}) do
    topic = SerpChecks.topic(run_id)

    socket =
      if socket.assigns[:serp_run_topic] && socket.assigns.serp_run_topic != topic do
        maybe_unsubscribe_run(socket)
      else
        socket
      end

    if connected?(socket) && socket.assigns[:serp_run_topic] != topic do
      SerpChecks.subscribe(run_id)
    end

    assign(socket, :serp_run_topic, topic)
  end

  defp maybe_unsubscribe_run(%{assigns: %{serp_run_topic: topic}} = socket)
       when is_binary(topic) do
    PubSub.unsubscribe(GscAnalytics.PubSub, topic)
    assign(socket, :serp_run_topic, nil)
  end

  defp maybe_unsubscribe_run(socket), do: socket

  defp schedule_serp_timeout(socket, %{status: status}) when status in [:running] do
    socket = cancel_serp_timeout(socket)
    ref = Process.send_after(self(), :serp_run_timeout, @serp_timeout_ms)
    assign(socket, :serp_timeout_ref, ref)
  end

  defp schedule_serp_timeout(socket, _run), do: cancel_serp_timeout(socket)

  defp maybe_reset_timeout(socket, %{status: status} = run) do
    if status == :running do
      schedule_serp_timeout(socket, run)
    else
      cancel_serp_timeout(socket)
      |> assign(:serp_timeout_reached?, false)
    end
  end

  defp cancel_serp_timeout(socket) do
    if ref = socket.assigns[:serp_timeout_ref] do
      Process.cancel_timer(ref)
    end

    assign(socket, :serp_timeout_ref, nil)
  end

  defp serp_run_active?(nil), do: false
  defp serp_run_active?(%{status: status}) when status in [:pending, :running], do: true
  defp serp_run_active?(_), do: false

  defp serp_keyword_limit, do: @serp_keyword_limit
  defp serp_credit_cost, do: @serp_credit_cost
  defp serp_cost_estimate, do: @serp_keyword_limit * @serp_credit_cost

  defp serp_run_status_label(nil), do: "Not run yet"
  defp serp_run_status_label(%{status: :running}), do: "Running"
  defp serp_run_status_label(%{status: :complete}), do: "Complete"
  defp serp_run_status_label(%{status: :partial}), do: "Partial"
  defp serp_run_status_label(%{status: :failed}), do: "Failed"
  defp serp_run_status_label(_), do: "Queued"

  defp serp_run_status_class(%{status: :running}), do: "bg-amber-100 text-amber-800"
  defp serp_run_status_class(%{status: :complete}), do: "bg-emerald-100 text-emerald-700"
  defp serp_run_status_class(%{status: :partial}), do: "bg-amber-100 text-amber-800"
  defp serp_run_status_class(%{status: :failed}), do: "bg-rose-100 text-rose-700"
  defp serp_run_status_class(_), do: "bg-slate-100 text-slate-600"

  defp keyword_status_label(%{status: :pending}), do: "Pending"
  defp keyword_status_label(%{status: :running}), do: "Running"
  defp keyword_status_label(%{status: :success}), do: "Done"
  defp keyword_status_label(%{status: :failed}), do: "Failed"
  defp keyword_status_label(_), do: "Unknown"

  defp keyword_status_badge(%{status: :pending}), do: "bg-slate-100 text-slate-700"
  defp keyword_status_badge(%{status: :running}), do: "bg-amber-100 text-amber-700"
  defp keyword_status_badge(%{status: :success}), do: "bg-emerald-100 text-emerald-700"
  defp keyword_status_badge(%{status: :failed}), do: "bg-rose-100 text-rose-700"
  defp keyword_status_badge(_), do: "bg-slate-100 text-slate-700"

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
    |> assign_new(:serp_snapshot, fn -> nil end)
    |> assign_new(:serp_run, fn -> nil end)
    |> assign_new(:serp_run_topic, fn -> nil end)
    |> assign_new(:serp_timeout_ref, fn -> nil end)
    |> assign_new(:serp_timeout_reached?, fn -> false end)
  end
end
