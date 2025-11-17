defmodule GscAnalyticsWeb.ChartComponents do
  @moduledoc """
  Reusable canvas-based chart components for GSC analytics visualization.

  ## Data Encoding Strategy

  This component accepts both raw data and pre-encoded JSON for time series and events.
  The pre-encoded JSON attributes (`time_series_json`, `events_json`) take precedence
  when provided. Use `ChartDataPresenter` to encode data consistently.

  ## Recommended Usage

      # In LiveView - use ChartDataPresenter for encoding
      alias GscAnalyticsWeb.Presenters.ChartDataPresenter

      socket
      |> assign(:time_series, data)
      |> assign(:time_series_json, ChartDataPresenter.encode_time_series(data))

      # In template
      <.performance_chart
        id="myChart"
        time_series={@time_series}
        time_series_json={@time_series_json}
        visible_series={@visible_series}
      />
  """
  use Phoenix.Component

  @doc """
  Renders a multi-series line chart for clicks, impressions, and CTR.

  ## Attributes

    * `id` - Unique ID for the chart canvas (required)
    * `time_series` - List of time series data with clicks, impressions, ctr, position (required).
      Used for empty check. Can be empty list `[]` if you know data exists.
    * `time_series_json` - Pre-encoded JSON string of time series data.
      When provided, this is used directly (no encoding overhead). Prefer this approach.
    * `events` - List of event objects with date and label (default: [])
    * `events_json` - Pre-encoded JSON string of events. When provided, takes precedence.
    * `x_label` - Label for x-axis (default: "Date")
    * `visible_series` - List of metric atoms to show (default: [:clicks, :impressions])
    * `wrapper_class` - CSS classes for wrapper div (default: "relative h-96")

  ## Performance Note

  Pre-encoding data using `ChartDataPresenter` is recommended as it avoids
  re-encoding on every render and provides consistent JSON serialization.
  """
  attr :id, :string, required: true
  attr :time_series, :list, required: true
  attr :x_label, :string, default: "Date"
  attr :events, :list, default: []
  attr :time_series_json, :string, default: nil
  attr :events_json, :string, default: nil
  attr :visible_series, :list, default: [:clicks, :impressions]
  attr :wrapper_class, :string, default: "relative h-96"

  def performance_chart(assigns) do
    ~H"""
    <%= if has_data?(@time_series, @time_series_json) do %>
      <div
        id={"#{@id}-wrapper"}
        phx-hook="PerformanceChart"
        data-chart-id={@id}
        data-x-label={@x_label}
        data-time-series={resolve_time_series_json(@time_series, @time_series_json)}
        data-events={resolve_events_json(@events, @events_json)}
        data-visible-series={encode_visible_series(@visible_series)}
        class={@wrapper_class}
      >
        <canvas id={@id} class="absolute inset-0 w-full h-full"></canvas>
      </div>
    <% else %>
      <div class="flex items-center justify-center h-48 text-gray-500">
        <div class="text-center">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="h-12 w-12 mx-auto mb-4 opacity-50"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"
            />
          </svg>
          <p>No time series data available</p>
        </div>
      </div>
    <% end %>
    """
  end

  # Check if data exists - prefer JSON string check when available
  defp has_data?(_time_series, time_series_json) when is_binary(time_series_json) do
    # JSON check: not empty array
    time_series_json != "[]" and time_series_json != ""
  end

  defp has_data?(time_series, _json), do: length(time_series) > 0

  # Resolve time series JSON - prefer pre-encoded when available
  defp resolve_time_series_json(_series, json) when is_binary(json) and json != "", do: json

  defp resolve_time_series_json(series, _json) do
    # Fallback encoding for backwards compatibility
    # Prefer using ChartDataPresenter.encode_time_series/1 in the LiveView instead
    series
    |> Enum.map(fn ts ->
      base = %{
        date: Date.to_string(ts.date),
        clicks: ts.clicks,
        impressions: ts.impressions,
        ctr: ts.ctr,
        position: ts.position
      }

      if Map.has_key?(ts, :period_end) and not is_nil(ts.period_end) do
        Map.put(base, :period_end, Date.to_string(ts.period_end))
      else
        base
      end
    end)
    |> JSON.encode!()
  end

  # Resolve events JSON - prefer pre-encoded when available
  defp resolve_events_json(_events, json) when is_binary(json) and json != "", do: json
  defp resolve_events_json(events, _json), do: JSON.encode!(events)

  defp encode_visible_series(series) when is_list(series) do
    series
    |> Enum.map(&Atom.to_string/1)
    |> JSON.encode!()
  end
end
