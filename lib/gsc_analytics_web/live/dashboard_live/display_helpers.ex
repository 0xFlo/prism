defmodule GscAnalyticsWeb.DashboardLive.DisplayHelpers do
  @moduledoc """
  Display formatting helpers for DashboardLive.

  This module provides pure functions for formatting labels, dates,
  and other display values used in the dashboard UI.

  All functions are stateless and easily testable.
  """

  alias GscAnalyticsWeb.Live.DashboardParams

  # ============================================================================
  # PUBLIC API - Display Label Helpers
  # ============================================================================

  @doc """
  Assign all display labels to socket assigns.

  This is a convenience function that calls all label assignment helpers.

  ## Examples

      iex> assign_display_labels(socket)
      %Phoenix.LiveView.Socket{}
  """
  @spec assign_display_labels(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def assign_display_labels(socket) do
    import Phoenix.Component, only: [assign: 3]

    period_label_text = DashboardParams.period_label(socket.assigns.period_days)

    socket
    |> assign(:period_label, period_label_text)
    |> assign(:chart_view_label, chart_view_label(socket.assigns.chart_view))
    |> assign(:sort_label, sort_label(socket.assigns.sort_by, period_label_text))
    |> assign(:sort_direction_label, sort_direction_label(socket.assigns.sort_direction))
  end

  @doc """
  Get human-readable label for chart view mode.

  ## Examples

      iex> chart_view_label("weekly")
      "Weekly trend"

      iex> chart_view_label("daily")
      "Daily trend"
  """
  @spec chart_view_label(String.t()) :: String.t()
  def chart_view_label("weekly"), do: "Weekly trend"
  def chart_view_label("monthly"), do: "Monthly trend"
  def chart_view_label(_), do: "Daily trend"

  @doc """
  Get human-readable label for sort column.

  Combines column name with period context for clarity.

  ## Examples

      iex> sort_label("clicks", "Last 30 days")
      "Clicks (Last 30 days)"

      iex> sort_label("position", "Last 7 days")
      "Average Position (Last 7 days)"

      iex> sort_label("lifetime_clicks", "Last 30 days")
      "Total Clicks (All Time)"
  """
  @spec sort_label(String.t(), String.t()) :: String.t()
  def sort_label("clicks", period_label), do: "Clicks (#{period_label})"
  def sort_label("impressions", period_label), do: "Impressions (#{period_label})"
  def sort_label("ctr", period_label), do: "CTR (#{period_label})"
  def sort_label("position", period_label), do: "Average Position (#{period_label})"
  def sort_label("period_clicks", period_label), do: sort_label("clicks", period_label)

  def sort_label("period_impressions", period_label),
    do: sort_label("impressions", period_label)

  def sort_label("lifetime_clicks", _period_label), do: "Total Clicks (All Time)"
  def sort_label("lifetime_avg_ctr", period_label), do: sort_label("ctr", period_label)

  def sort_label("lifetime_avg_position", period_label),
    do: sort_label("position", period_label)

  def sort_label(_, period_label), do: "Clicks (#{period_label})"

  @doc """
  Get human-readable label for sort direction.

  ## Examples

      iex> sort_direction_label("asc")
      "ascending"

      iex> sort_direction_label("desc")
      "descending"
  """
  @spec sort_direction_label(String.t()) :: String.t()
  def sort_direction_label("asc"), do: "ascending"
  def sort_direction_label("desc"), do: "descending"
  def sort_direction_label(_), do: "descending"

  # ============================================================================
  # PUBLIC API - Month-over-Month Indicator Helpers
  # ============================================================================

  @doc """
  Assign month-over-month indicator assigns to socket.

  Extracts MoM change from stats and calculates display properties:
  - CSS classes for color coding
  - Icon name for trend direction
  - Formatted delta display (e.g., "+12.5%")

  ## Examples

      iex> assign_mom_indicators(socket)
      %Phoenix.LiveView.Socket{}
  """
  @spec assign_mom_indicators(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def assign_mom_indicators(socket) do
    import Phoenix.Component, only: [assign: 2, assign: 3]

    mom_change = socket.assigns.stats.month_over_month_change || 0

    socket
    |> assign(:mom_change, mom_change)
    |> assign(:mom_indicator_class, mom_indicator_class(mom_change))
    |> assign(:mom_icon, mom_icon(mom_change))
    |> assign(:mom_delta_display, mom_delta_display(mom_change))
  end

  @doc """
  Get CSS classes for month-over-month indicator.

  Returns color-coded classes based on positive/negative/neutral change.

  ## Examples

      iex> mom_indicator_class(15.5)
      "border-emerald-400/40 bg-emerald-500/10 text-emerald-200"

      iex> mom_indicator_class(-8.2)
      "border-rose-400/50 bg-rose-500/10 text-rose-200"

      iex> mom_indicator_class(0)
      "border-slate-200/40 bg-slate-200/10 text-slate-200"
  """
  @spec mom_indicator_class(float()) :: String.t()
  def mom_indicator_class(change) when change > 0,
    do: "border-emerald-400/40 bg-emerald-500/10 text-emerald-200"

  def mom_indicator_class(change) when change < 0,
    do: "border-rose-400/50 bg-rose-500/10 text-rose-200"

  def mom_indicator_class(_), do: "border-slate-200/40 bg-slate-200/10 text-slate-200"

  @doc """
  Get Heroicon name for month-over-month trend.

  ## Examples

      iex> mom_icon(12.5)
      "hero-arrow-trending-up"

      iex> mom_icon(-5.3)
      "hero-arrow-trending-down"

      iex> mom_icon(0)
      "hero-arrows-right-left"
  """
  @spec mom_icon(float()) :: String.t()
  def mom_icon(change) when change > 0, do: "hero-arrow-trending-up"
  def mom_icon(change) when change < 0, do: "hero-arrow-trending-down"
  def mom_icon(_), do: "hero-arrows-right-left"

  @doc """
  Format month-over-month change as display string.

  ## Examples

      iex> mom_delta_display(12.5)
      "+12.5%"

      iex> mom_delta_display(-8.2)
      "-8.2%"

      iex> mom_delta_display(0)
      "0%"
  """
  @spec mom_delta_display(float()) :: String.t()
  def mom_delta_display(change) when change > 0, do: "+#{Float.round(change, 1)}%"
  def mom_delta_display(change) when change < 0, do: "#{Float.round(change, 1)}%"
  def mom_delta_display(_), do: "0%"

  # ============================================================================
  # PUBLIC API - Date Label Helpers
  # ============================================================================

  @doc """
  Assign date labels to socket assigns.

  Extracts date metadata from stats and formats for display.

  ## Examples

      iex> assign_date_labels(socket)
      %Phoenix.LiveView.Socket{}
  """
  @spec assign_date_labels(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def assign_date_labels(socket) do
    import Phoenix.Component, only: [assign: 3]

    stats = socket.assigns.stats

    socket
    |> assign(:earliest_all_time, format_earliest_date(stats.all_time[:earliest_date]))
    |> assign(:latest_all_time, format_latest_date(stats.all_time[:latest_date]))
    |> assign(:days_with_data, stats.all_time[:days_with_data])
  end

  @doc """
  Format earliest date (typically for "since" labels).

  Returns month and year (e.g., "Jan 2024").

  ## Examples

      iex> format_earliest_date(~D[2024-01-15])
      "Jan 2024"

      iex> format_earliest_date(nil)
      nil
  """
  @spec format_earliest_date(Date.t() | nil) :: String.t() | nil
  def format_earliest_date(nil), do: nil
  def format_earliest_date(date), do: Calendar.strftime(date, "%b %Y")

  @doc """
  Format latest date (typically for "as of" labels).

  Returns full date (e.g., "Jan 15, 2024").

  ## Examples

      iex> format_latest_date(~D[2024-01-15])
      "Jan 15, 2024"

      iex> format_latest_date(nil)
      nil
  """
  @spec format_latest_date(Date.t() | nil) :: String.t() | nil
  def format_latest_date(nil), do: nil
  def format_latest_date(date), do: Calendar.strftime(date, "%b %d, %Y")

  # ============================================================================
  # PUBLIC API - Chart View Parsing
  # ============================================================================

  @doc """
  Normalize chart view parameter to valid value.

  ## Examples

      iex> chart_view("weekly")
      "weekly"

      iex> chart_view("invalid")
      "daily"

      iex> chart_view(nil)
      "daily"
  """
  @spec chart_view(String.t() | nil) :: String.t()
  def chart_view("weekly"), do: "weekly"
  def chart_view("monthly"), do: "monthly"
  def chart_view(_), do: "daily"
end
