defmodule GscAnalyticsWeb.Dashboard.HTMLHelpers do
  @moduledoc """
  Shared formatting helpers for the dashboard views.
  """
  use GscAnalyticsWeb, :html

  alias GscAnalyticsWeb.Dashboard.Columns

  @doc """
  Get columns visible for current view mode
  """
  def visible_columns(view_mode) do
    Columns.visible_columns(view_mode)
  end

  @doc """
  Check if a specific column is visible in current view mode
  """
  def column_visible?(column_key, view_mode) do
    valid_mode = Columns.validate_view_mode(view_mode)
    mode_atom = String.to_existing_atom(valid_mode)
    column = Enum.find(Columns.columns(), &(&1.key == column_key))
    column && mode_atom in column.visible_in
  end

  @doc """
  Format large numbers with commas for display
  """
  def format_number(nil), do: "0"
  def format_number(%Decimal{} = num), do: num |> Decimal.to_integer() |> format_number()
  def format_number(num) when is_float(num), do: format_number(trunc(num))

  def format_number(num) when is_integer(num) do
    num
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end

  @doc """
  Format percentage values
  """
  def format_percentage(nil), do: "0%"
  def format_percentage(%Decimal{} = num), do: num |> Decimal.to_float() |> format_percentage()
  def format_percentage(num) when is_float(num), do: "#{Float.round(num, 2)}%"
  def format_percentage(num), do: "#{num}%"

  @doc """
  Format position with one decimal place
  """
  def format_position(nil), do: "—"
  def format_position(%Decimal{} = pos), do: pos |> Decimal.to_float() |> format_position()
  def format_position(pos) when is_float(pos), do: Float.round(pos, 1)
  def format_position(pos), do: pos

  @doc """
  Truncate URL for display
  """
  def truncate_url(url, max_length \\ 60) do
    if String.length(url) > max_length do
      String.slice(url, 0, max_length - 3) <> "..."
    else
      url
    end
  end

  @doc """
  Get badge color based on value
  """
  def get_badge_color(value, type) do
    case type do
      :ctr ->
        cond do
          value > 5.0 -> "badge-success"
          value > 2.0 -> "badge-warning"
          true -> "badge-error"
        end

      :position ->
        cond do
          value <= 3 -> "badge-success"
          value <= 10 -> "badge-warning"
          true -> "badge-error"
        end

      :growth ->
        cond do
          value > 10 -> "badge-success"
          value > -10 -> "badge-warning"
          true -> "badge-error"
        end

      _ ->
        "badge-ghost"
    end
  end

  @doc """
  Format date for display
  """
  def format_date(nil), do: "—"

  def format_date(date) do
    Calendar.strftime(date, "%b %d, %Y")
  end

  @doc """
  Calculate days ago from date
  """
  def days_ago(nil), do: "—"

  def days_ago(date) do
    days = Date.diff(Date.utc_today(), date)

    case days do
      0 -> "Today"
      1 -> "Yesterday"
      n when n < 7 -> "#{n} days ago"
      n when n < 30 -> "#{div(n, 7)} weeks ago"
      n -> "#{div(n, 30)} months ago"
    end
  end

  @doc """
  Get badge class for content category
  """
  def content_category_badge(category) do
    case category do
      "Fresh" -> "badge badge-success badge-sm"
      "Recent" -> "badge badge-info badge-sm"
      "Aging" -> "badge badge-warning badge-sm"
      "Stale" -> "badge badge-error badge-sm"
      _ -> "badge badge-ghost badge-sm"
    end
  end

  @doc """
  Get badge class for priority level
  """
  def priority_badge(priority) do
    case priority do
      "High" -> "badge badge-error badge-sm"
      "Medium" -> "badge badge-warning badge-sm"
      "Low" -> "badge badge-info badge-sm"
      _ -> "badge badge-ghost badge-sm"
    end
  end

  @doc """
  Check if backlinks data is stale (>90 days old).

  Returns true if data is stale or missing.
  """
  def stale_backlinks?(nil), do: true

  def stale_backlinks?(last_imported) when is_struct(last_imported, DateTime) do
    days_old = DateTime.diff(DateTime.utc_now(), last_imported, :day)
    days_old > 90
  end

  @doc """
  Get badge class for backlink data source.
  """
  def badge_class_for_source("vendor"), do: "badge badge-success badge-sm"
  def badge_class_for_source("ahrefs"), do: "badge badge-info badge-sm"
  def badge_class_for_source(_), do: "badge badge-ghost badge-sm"

  @doc """
  Get badge class for HTTP status code.
  Returns appropriate DaisyUI badge class based on status code range.
  """
  def http_status_badge_class(nil), do: "badge badge-ghost badge-sm"

  def http_status_badge_class(status) when status >= 200 and status < 300,
    do: "badge badge-success badge-sm"

  def http_status_badge_class(status) when status >= 300 and status < 400,
    do: "badge badge-warning badge-sm"

  def http_status_badge_class(status) when status >= 400 and status < 500,
    do: "badge badge-error badge-sm"

  def http_status_badge_class(status) when status >= 500, do: "badge badge-error badge-sm"
  def http_status_badge_class(_), do: "badge badge-ghost badge-sm"

  @doc """
  Format datetime with UTC timezone.
  """
  def format_datetime(nil), do: "Unknown"

  def format_datetime(datetime) when is_struct(datetime, DateTime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M UTC")
  end

  @doc """
  Get sort indicator icon for sortable column headers.
  Returns appropriate Heroicon based on sort state.
  """
  def sort_icon(column, current_sort, current_direction) do
    cond do
      column == current_sort and current_direction == "asc" ->
        "hero-chevron-up"

      column == current_sort and current_direction == "desc" ->
        "hero-chevron-down"

      true ->
        "hero-chevron-up-down"
    end
  end

  @doc """
  Get CSS classes for sortable column header.
  Highlights active sort column.
  """
  def sort_header_class(column, current_sort) do
    base = "cursor-pointer hover:bg-base-300 transition-colors select-none"

    if column == current_sort do
      "#{base} text-primary font-bold"
    else
      base
    end
  end
end
