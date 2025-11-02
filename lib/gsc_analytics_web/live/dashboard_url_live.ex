defmodule GscAnalyticsWeb.DashboardUrlLive do
  use GscAnalyticsWeb, :live_view

  alias GscAnalytics.ContentInsights
  alias GscAnalyticsWeb.Live.AccountHelpers
  alias GscAnalyticsWeb.Presenters.ChartDataPresenter

  import GscAnalyticsWeb.Dashboard.HTMLHelpers
  import GscAnalyticsWeb.Components.DashboardComponents

  @impl true
  def mount(params, _session, socket) do
    # LiveView best practice: Use assign_new/3 for safe defaults
    # This prevents runtime errors from missing assigns and makes the component more resilient
    {socket, account} = AccountHelpers.init_account_assigns(socket, params)

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
      {:ok,
       socket
       |> assign_new(:page_title, fn -> "URL Performance" end)
       |> assign_new(:insights, fn -> nil end)
       |> assign_new(:view_mode, fn -> "daily" end)
       |> assign_new(:period_days, fn -> 30 end)
       |> assign_new(:encoded_url, fn -> nil end)
       |> assign_new(:queries_sort_by, fn -> "clicks" end)
       |> assign_new(:queries_sort_direction, fn -> "desc" end)
       |> assign_new(:backlinks_sort_by, fn -> "first_seen_at" end)
       |> assign_new(:backlinks_sort_direction, fn -> "desc" end)}
    end
  end

  @impl true
  def handle_params(%{"url" => url} = params, uri, socket)
      when is_binary(url) and byte_size(url) > 0 do
    socket = AccountHelpers.assign_current_account(socket, params)
    account_id = socket.assigns.current_account_id
    view_mode = normalize_view_mode(params["view"])
    period_days = parse_period(params["period"])

    insights =
      ContentInsights.url_insights(url, view_mode, %{
        period_days: period_days,
        account_id: account_id
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
      |> sort_queries(queries_sort_by, queries_sort_dir)
      |> sort_backlinks(backlinks_sort_by, backlinks_sort_dir)

    enriched_insights =
      sorted_insights
      |> Map.put(
        :time_series_json,
        ChartDataPresenter.encode_time_series(sorted_insights.time_series || [])
      )
      |> Map.put(
        :chart_events_json,
        ChartDataPresenter.encode_events(sorted_insights.chart_events || [])
      )

    {:noreply,
     socket
     |> assign(:current_path, current_path)
     |> assign(:view_mode, view_mode)
     |> assign(:period_days, period_days)
     |> assign(:insights, enriched_insights)
     |> assign(:encoded_url, URI.encode(insights.requested_url || insights.url || ""))
     |> assign(:queries_sort_by, queries_sort_by)
     |> assign(:queries_sort_direction, queries_sort_dir)
     |> assign(:backlinks_sort_by, backlinks_sort_by)
     |> assign(:backlinks_sort_direction, backlinks_sort_dir)}
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
  def handle_event("change_view", %{"view" => view}, socket) do
    view_mode = normalize_view_mode(view)
    params = build_params(socket, %{view: view_mode})
    {:noreply, push_patch(socket, to: ~p"/dashboard/url?#{params}")}
  end

  @impl true
  def handle_event("change_period", %{"period" => period}, socket) do
    period_days = parse_period(period)
    params = build_params(socket, %{period: period})

    {:noreply,
     socket
     |> assign(:period_days, period_days)
     |> push_patch(to: ~p"/dashboard/url?#{params}")}
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

    params =
      build_params(socket, %{queries_sort: column, queries_dir: new_direction})

    {:noreply, push_patch(socket, to: ~p"/dashboard/url?#{params}")}
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

    params =
      build_params(socket, %{backlinks_sort: column, backlinks_dir: new_direction})

    {:noreply, push_patch(socket, to: ~p"/dashboard/url?#{params}")}
  end

  @impl true
  def handle_event("change_account", %{"account_id" => account_id}, socket) do
    params = build_params(socket, %{account_id: account_id})
    {:noreply, push_patch(socket, to: ~p"/dashboard/url?#{params}")}
  end

  # Helper to build URL params preserving current state
  defp build_params(socket, overrides) do
    %{
      url: socket.assigns[:encoded_url] || "",
      view: Map.get(overrides, :view, socket.assigns.view_mode),
      period: Map.get(overrides, :period, socket.assigns.period_days),
      queries_sort: Map.get(overrides, :queries_sort, socket.assigns.queries_sort_by),
      queries_dir: Map.get(overrides, :queries_dir, socket.assigns.queries_sort_direction),
      backlinks_sort: Map.get(overrides, :backlinks_sort, socket.assigns.backlinks_sort_by),
      backlinks_dir: Map.get(overrides, :backlinks_dir, socket.assigns.backlinks_sort_direction),
      account_id: Map.get(overrides, :account_id, socket.assigns.current_account_id)
    }
  end

  defp normalize_view_mode("weekly"), do: "weekly"
  defp normalize_view_mode("monthly"), do: "monthly"
  defp normalize_view_mode(_), do: "daily"

  defp parse_period(nil), do: 30
  defp parse_period("7"), do: 7
  defp parse_period("30"), do: 30
  defp parse_period("90"), do: 90
  defp parse_period("180"), do: 180
  defp parse_period("365"), do: 365
  defp parse_period("all"), do: 10000
  defp parse_period(value) when is_integer(value) and value > 0, do: value

  defp parse_period(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} when int > 0 -> int
      _ -> 30
    end
  end

  defp parse_period(_), do: 30

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

  # Sort queries by specified field
  defp sort_queries(%{top_queries: queries} = insights, sort_by, direction)
       when is_list(queries) do
    sorted =
      Enum.sort_by(
        queries,
        fn query ->
          case sort_by do
            "query" -> query.query
            "clicks" -> query.clicks
            "impressions" -> query.impressions
            "ctr" -> query.ctr
            "position" -> query.position
            _ -> query.clicks
          end
        end,
        if(direction == "asc", do: :asc, else: :desc)
      )

    %{insights | top_queries: sorted}
  end

  defp sort_queries(insights, _sort_by, _direction), do: insights

  # Sort backlinks by specified field
  defp sort_backlinks(%{backlinks: backlinks} = insights, sort_by, direction)
       when is_list(backlinks) do
    sorted =
      Enum.sort_by(
        backlinks,
        fn backlink ->
          case sort_by do
            "source_domain" -> backlink.source_domain || backlink.source_url
            "anchor_text" -> backlink.anchor_text || ""
            "domain_rating" -> backlink.domain_rating || 0
            "domain_traffic" -> backlink.domain_traffic || 0
            "first_seen_at" -> backlink.first_seen_at || ~U[1970-01-01 00:00:00Z]
            "data_source" -> backlink.data_source
            _ -> backlink.first_seen_at || ~U[1970-01-01 00:00:00Z]
          end
        end,
        if(direction == "asc", do: :asc, else: :desc)
      )

    %{insights | backlinks: sorted}
  end

  defp sort_backlinks(insights, _sort_by, _direction), do: insights
end
