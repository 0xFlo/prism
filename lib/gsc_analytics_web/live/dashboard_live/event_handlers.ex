defmodule GscAnalyticsWeb.DashboardLive.EventHandlers do
  @moduledoc """
  Event handlers for DashboardLive.

  This module contains all `handle_event/3` callbacks for the dashboard,
  including search, filtering, sorting, pagination, and view mode changes.

  All functions accept a socket and return `{:noreply, socket}` following
  Phoenix LiveView conventions.
  """

  alias GscAnalyticsWeb.Live.{DashboardParams, PaginationHelpers}
  alias GscAnalyticsWeb.Dashboard.Columns
  alias GscAnalyticsWeb.Live.ChartHelpers
  alias GscAnalyticsWeb.PropertyRoutes

  # ============================================================================
  # PUBLIC API - Event Handlers
  # ============================================================================

  @doc """
  Handle search form submission.

  Updates the search term and resets pagination to page 1.

  ## Examples

      iex> handle_search(%{"search" => "blog"}, socket)
      {:noreply, updated_socket}
  """
  @spec handle_search(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_search(%{"search" => search_term}, socket) do
    {:noreply, push_dashboard_patch(socket, %{search: search_term, page: 1})}
  end

  @doc """
  Handle property switcher dropdown selection.

  Switches to a different GSC property while preserving other URL params.

  ## Examples

      iex> handle_switch_property(%{"property_id" => "123"}, socket)
      {:noreply, updated_socket}
  """
  @spec handle_switch_property(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_switch_property(%{"property_id" => property_id}, socket) do
    {:noreply, push_dashboard_patch(socket, %{property_id: property_id})}
  end

  @doc """
  Handle view mode toggle (basic/advanced/full).

  Updates the view mode and keeps current page.

  ## Examples

      iex> handle_change_view_mode(%{"view_mode" => "advanced"}, socket)
      {:noreply, updated_socket}
  """
  @spec handle_change_view_mode(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_change_view_mode(%{"view_mode" => view_mode}, socket) do
    validated_mode = Columns.validate_view_mode(view_mode)
    {:noreply, push_dashboard_patch(socket, %{view_mode: validated_mode})}
  end

  @doc """
  Handle period selector change (7/30/90 days).

  Updates local assigns for immediate visual feedback, then syncs URL
  for data refresh. Resets to page 1.

  ## Examples

      iex> handle_change_period(%{"period" => "30"}, socket)
      {:noreply, updated_socket}
  """
  @spec handle_change_period(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_change_period(%{"period" => period}, socket) do
    import Phoenix.Component, only: [assign: 3]

    new_period_days = DashboardParams.parse_period(period)

    new_socket =
      socket
      |> assign(:period_days, new_period_days)
      |> assign_display_labels()

    {:noreply, push_dashboard_patch(new_socket, %{period: period, page: 1})}
  end

  @doc """
  Handle chart view toggle (daily/weekly/monthly).

  Updates local assigns for immediate visual feedback, then syncs URL
  for data refresh.

  ## Examples

      iex> handle_change_chart_view(%{"chart_view" => "weekly"}, socket)
      {:noreply, updated_socket}
  """
  @spec handle_change_chart_view(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_change_chart_view(%{"chart_view" => chart_view}, socket) do
    import Phoenix.Component, only: [assign: 3]

    new_socket =
      socket
      |> assign(:chart_view, chart_view)
      |> assign_display_labels()

    {:noreply, push_dashboard_patch(new_socket, %{chart_view: chart_view})}
  end

  @doc """
  Handle chart series toggle (clicks/impressions/ctr/position).

  Toggles visibility of a metric in the chart and updates URL params.

  ## Examples

      iex> handle_toggle_series(%{"metric" => "ctr"}, socket)
      {:noreply, updated_socket}
  """
  @spec handle_toggle_series(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_toggle_series(%{"metric" => metric_str}, socket) do
    new_series = ChartHelpers.toggle_chart_series(metric_str, socket.assigns.visible_series)
    {:noreply, push_dashboard_patch(socket, %{series: DashboardParams.encode_series(new_series)})}
  end

  @doc """
  Handle column header click for sorting.

  Determines new sort direction - toggles if same column, uses default for new column.
  Resets to page 1 since sort order changes results.

  ## Examples

      iex> handle_sort_column(%{"column" => "clicks"}, socket)
      {:noreply, updated_socket}
  """
  @spec handle_sort_column(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_sort_column(%{"column" => column}, socket) do
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

  @doc """
  Handle page size dropdown change.

  Updates limit and resets to page 1.

  ## Examples

      iex> handle_change_limit(%{"limit" => "100"}, socket)
      {:noreply, updated_socket}
  """
  @spec handle_change_limit(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_change_limit(%{"limit" => limit}, socket) do
    normalized_limit = PaginationHelpers.parse_limit(limit)
    {:noreply, push_dashboard_patch(socket, %{limit: normalized_limit, page: 1})}
  end

  @doc """
  Handle HTTP status filter change.

  Filters URLs by HTTP status (ok/broken/redirect/unchecked). Resets to page 1.

  ## Examples

      iex> handle_filter_http_status(%{"http_status" => "broken"}, socket)
      {:noreply, updated_socket}
  """
  @spec handle_filter_http_status(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_filter_http_status(%{"http_status" => value}, socket) do
    {:noreply, push_dashboard_patch(socket, %{http_status: value, page: 1})}
  end

  @doc """
  Handle position range filter change.

  Filters URLs by position range (top3/top10/page1/page2/poor/unranked). Resets to page 1.

  ## Examples

      iex> handle_filter_position(%{"position" => "top10"}, socket)
      {:noreply, updated_socket}
  """
  @spec handle_filter_position(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_filter_position(%{"position" => value}, socket) do
    {:noreply, push_dashboard_patch(socket, %{position: value, page: 1})}
  end

  @doc """
  Handle clicks threshold filter change.

  Filters URLs by minimum clicks (10+/100+/1000+/none). Resets to page 1.

  ## Examples

      iex> handle_filter_clicks(%{"clicks" => "100+"}, socket)
      {:noreply, updated_socket}
  """
  @spec handle_filter_clicks(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_filter_clicks(%{"clicks" => value}, socket) do
    {:noreply, push_dashboard_patch(socket, %{clicks: value, page: 1})}
  end

  @doc """
  Handle CTR range filter change.

  Filters URLs by CTR range (high/good/average/low). Resets to page 1.

  ## Examples

      iex> handle_filter_ctr(%{"ctr" => "high"}, socket)
      {:noreply, updated_socket}
  """
  @spec handle_filter_ctr(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_filter_ctr(%{"ctr" => value}, socket) do
    {:noreply, push_dashboard_patch(socket, %{ctr: value, page: 1})}
  end

  @doc """
  Handle backlinks filter change.

  Filters URLs by backlink count (any/none/10+/100+). Resets to page 1.

  ## Examples

      iex> handle_filter_backlinks(%{"backlinks" => "10+"}, socket)
      {:noreply, updated_socket}
  """
  @spec handle_filter_backlinks(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_filter_backlinks(%{"backlinks" => value}, socket) do
    {:noreply, push_dashboard_patch(socket, %{backlinks: value, page: 1})}
  end

  @doc """
  Handle redirect filter change.

  Filters URLs by redirect status (yes/no). Resets to page 1.

  ## Examples

      iex> handle_filter_redirect(%{"redirect" => "yes"}, socket)
      {:noreply, updated_socket}
  """
  @spec handle_filter_redirect(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_filter_redirect(%{"redirect" => value}, socket) do
    {:noreply, push_dashboard_patch(socket, %{redirect: value, page: 1})}
  end

  @doc """
  Handle first seen date filter change.

  Filters URLs by first seen date (7d/30d/90d or ISO date). Resets to page 1.

  ## Examples

      iex> handle_filter_first_seen(%{"first_seen" => "30d"}, socket)
      {:noreply, updated_socket}
  """
  @spec handle_filter_first_seen(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_filter_first_seen(%{"first_seen" => value}, socket) do
    {:noreply, push_dashboard_patch(socket, %{first_seen: value, page: 1})}
  end

  @doc """
  Handle page type filter change.

  Filters URLs by page type (blog/documentation/product/etc). Resets to page 1.

  ## Examples

      iex> handle_filter_page_type(%{"page_type" => "blog"}, socket)
      {:noreply, updated_socket}
  """
  @spec handle_filter_page_type(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_filter_page_type(%{"page_type" => value}, socket) do
    {:noreply, push_dashboard_patch(socket, %{page_type: value, page: 1})}
  end

  @doc """
  Handle clear all filters button click.

  Resets all filter parameters to nil and returns to page 1.

  ## Examples

      iex> handle_clear_filters(%{}, socket)
      {:noreply, updated_socket}
  """
  @spec handle_clear_filters(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_clear_filters(_params, socket) do
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

  @doc """
  Handle goto page input submission.

  Navigates to a specific page number within valid range.

  ## Examples

      iex> handle_goto_page(%{"page" => "5"}, socket)
      {:noreply, updated_socket}
  """
  @spec handle_goto_page(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_goto_page(%{"page" => page}, socket) do
    page_num = PaginationHelpers.parse_page(page)
    # Ensure page is within valid range
    page_num = max(1, min(page_num, socket.assigns.total_pages))
    {:noreply, push_dashboard_patch(socket, %{page: page_num})}
  end

  @doc """
  Handle next page button click.

  Navigates to the next page, capped at total_pages.

  ## Examples

      iex> handle_next_page(%{}, socket)
      {:noreply, updated_socket}
  """
  @spec handle_next_page(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_next_page(_params, socket) do
    next_page = min(socket.assigns.page + 1, socket.assigns.total_pages)
    {:noreply, push_dashboard_patch(socket, %{page: next_page})}
  end

  @doc """
  Handle previous page button click.

  Navigates to the previous page, minimum page 1.

  ## Examples

      iex> handle_prev_page(%{}, socket)
      {:noreply, updated_socket}
  """
  @spec handle_prev_page(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_prev_page(_params, socket) do
    prev_page = max(socket.assigns.page - 1, 1)
    {:noreply, push_dashboard_patch(socket, %{page: prev_page})}
  end

  # ============================================================================
  # PRIVATE HELPERS
  # ============================================================================

  defp push_dashboard_patch(socket, overrides) do
    import Phoenix.LiveView, only: [push_patch: 2]

    property_override = Map.get(overrides, :property_id)
    sanitized_overrides = Map.delete(overrides, :property_id)

    params =
      socket.assigns
      |> DashboardParams.build_dashboard_query(sanitized_overrides)

    property_id = property_override || socket.assigns.current_property_id

    push_patch(socket, to: PropertyRoutes.dashboard_path(property_id, params))
  end

  defp assign_display_labels(socket) do
    import Phoenix.Component, only: [assign: 3]

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
end
