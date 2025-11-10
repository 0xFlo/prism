defmodule GscAnalyticsWeb.Dashboard.Formatters do
  @moduledoc """
  Shared formatting helpers for dashboard displays.

  Provides consistent formatting of durations, rates, dates, and status badges
  across all dashboard views. This eliminates duplication and ensures consistent
  user-facing display formats.

  ## Usage

      defmodule MyDashboardLive do
        use GscAnalyticsWeb, :live_view
        import GscAnalyticsWeb.Dashboard.Formatters

        def render(assigns) do
          ~H"<span>{format_duration(@job.duration)}</span>"
        end
      end
  """

  @doc """
  Format duration in milliseconds to human-readable string.

  ## Examples

      iex> format_duration(500)
      "500ms"

      iex> format_duration(1500)
      "1.5s"

      iex> format_duration(90000)
      "1.5m"

      iex> format_duration(nil)
      "—"
  """
  @spec format_duration(integer() | nil) :: String.t()
  def format_duration(nil), do: "—"

  def format_duration(ms) when is_integer(ms) do
    cond do
      ms < 1000 -> "#{ms}ms"
      ms < 60_000 -> "#{Float.round(ms / 1000, 1)}s"
      ms < 3_600_000 -> "#{Float.round(ms / 60_000, 1)}m"
      true -> "#{Float.round(ms / 3_600_000, 1)}h"
    end
  end

  def format_duration(_), do: "—"

  @doc """
  Format rate (URLs per second) to human-readable string.

  ## Examples

      iex> format_rate(15.5)
      "15.5 URLs/sec"

      iex> format_rate(2.34)
      "2.34 URLs/sec"

      iex> format_rate(0.5)
      "30.0 URLs/min"

      iex> format_rate(nil)
      "—"
  """
  @spec format_rate(float() | nil) :: String.t()
  def format_rate(nil), do: "—"

  def format_rate(rate) when is_float(rate) or is_integer(rate) do
    cond do
      rate >= 10 -> "#{Float.round(rate * 1.0, 1)} URLs/sec"
      rate >= 1 -> "#{Float.round(rate * 1.0, 2)} URLs/sec"
      rate > 0 -> "#{Float.round(rate * 60, 1)} URLs/min"
      true -> "—"
    end
  end

  def format_rate(_), do: "—"

  @doc """
  Get CSS badge class for HTTP status code.

  ## Examples

      iex> status_badge_class(200)
      "badge badge-success"

      iex> status_badge_class(301)
      "badge badge-warning"

      iex> status_badge_class(404)
      "badge badge-error"

      iex> status_badge_class(nil)
      "badge badge-ghost"
  """
  @spec status_badge_class(integer() | nil) :: String.t()
  def status_badge_class(nil), do: "badge badge-ghost"

  def status_badge_class(code) when is_integer(code) do
    cond do
      code >= 200 and code < 300 -> "badge badge-success"
      code >= 300 and code < 400 -> "badge badge-warning"
      code >= 400 and code < 500 -> "badge badge-error"
      code >= 500 -> "badge badge-error"
      true -> "badge badge-ghost"
    end
  end

  def status_badge_class(_), do: "badge badge-ghost"

  @doc """
  Get CSS badge class for check status.

  ## Examples

      iex> check_status_badge_class("completed")
      "badge badge-success"

      iex> check_status_badge_class("running")
      "badge badge-info"

      iex> check_status_badge_class("failed")
      "badge badge-error"
  """
  @spec check_status_badge_class(String.t() | atom()) :: String.t()
  def check_status_badge_class("completed"), do: "badge badge-success"
  def check_status_badge_class(:completed), do: "badge badge-success"
  def check_status_badge_class("running"), do: "badge badge-info"
  def check_status_badge_class(:running), do: "badge badge-info"
  def check_status_badge_class("failed"), do: "badge badge-error"
  def check_status_badge_class(:failed), do: "badge badge-error"
  def check_status_badge_class("pending"), do: "badge badge-ghost"
  def check_status_badge_class(:pending), do: "badge badge-ghost"
  def check_status_badge_class(_), do: "badge badge-ghost"

  @doc """
  Format check status to display-friendly text.

  ## Examples

      iex> format_status("completed")
      "Completed"

      iex> format_status(:running)
      "Running"

      iex> format_status(nil)
      "Unknown"
  """
  @spec format_status(String.t() | atom() | nil) :: String.t()
  def format_status(nil), do: "Unknown"
  def format_status(:completed), do: "Completed"
  def format_status("completed"), do: "Completed"
  def format_status(:running), do: "Running"
  def format_status("running"), do: "Running"
  def format_status(:failed), do: "Failed"
  def format_status("failed"), do: "Failed"
  def format_status(:pending), do: "Pending"
  def format_status("pending"), do: "Pending"
  def format_status(status) when is_binary(status), do: String.capitalize(status)
  def format_status(status) when is_atom(status), do: status |> to_string() |> String.capitalize()
  def format_status(_), do: "Unknown"

  @doc """
  Get humanized label for filter values.

  ## Examples

      iex> filter_label("stale")
      "Stale URLs (unchecked or >7 days old)"

      iex> filter_label("broken")
      "Broken Links (4xx/5xx)"

      iex> filter_label("all")
      "All URLs"
  """
  @spec filter_label(String.t()) :: String.t()
  def filter_label("stale"), do: "Stale URLs (unchecked or >7 days old)"
  def filter_label("all"), do: "All URLs"
  def filter_label("broken"), do: "Broken Links (4xx/5xx)"
  def filter_label("redirected"), do: "Redirected URLs (3xx)"
  def filter_label(value) when is_binary(value), do: String.capitalize(value)
  def filter_label(_), do: "Unknown"

  @doc """
  Format milliseconds into human-readable relative time.

  ## Examples

      iex> format_relative_time(5000)
      "5 seconds"

      iex> format_relative_time(90000)
      "1 minute"

      iex> format_relative_time(3600000)
      "1 hour"
  """
  @spec format_relative_time(integer()) :: String.t()
  def format_relative_time(ms) when is_integer(ms) and ms < 60_000 do
    seconds = div(ms, 1000)

    if seconds == 1 do
      "1 second"
    else
      "#{seconds} seconds"
    end
  end

  def format_relative_time(ms) when is_integer(ms) and ms < 3_600_000 do
    minutes = div(ms, 60_000)

    if minutes == 1 do
      "1 minute"
    else
      "#{minutes} minutes"
    end
  end

  def format_relative_time(ms) when is_integer(ms) do
    hours = div(ms, 3_600_000)

    if hours == 1 do
      "1 hour"
    else
      "#{hours} hours"
    end
  end

  def format_relative_time(_), do: "—"
end
