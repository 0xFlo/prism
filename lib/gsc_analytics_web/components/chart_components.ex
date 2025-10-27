defmodule GscAnalyticsWeb.ChartComponents do
  @moduledoc """
  Reusable canvas-based chart components for GSC analytics visualization.
  """
  use Phoenix.Component

  @doc """
  Renders a dual-axis line chart for clicks and impressions.

  ## Attributes
    * `id` - Unique ID for the chart canvas (required)
    * `time_series` - List of time series data with clicks, impressions, ctr, position (required)
    * `x_label` - Label for x-axis (default: "Date")
  """
  attr :id, :string, required: true
  attr :time_series, :list, required: true
  attr :x_label, :string, default: "Date"
  attr :events, :list, default: []
  attr :time_series_json, :string, default: nil
  attr :events_json, :string, default: nil
  attr :show_impressions, :boolean, default: true

  def performance_chart(assigns) do
    ~H"""
    <%= if length(@time_series) > 0 do %>
      <div
        id={"#{@id}-wrapper"}
        phx-hook="PerformanceChart"
        data-chart-id={@id}
        data-x-label={@x_label}
        data-time-series={encoded_time_series(@time_series, @time_series_json)}
        data-events={encoded_events(@events, @events_json)}
        data-show-impressions={if @show_impressions, do: "true", else: "false"}
        class="relative h-96"
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

  defp encoded_time_series(_series, json) when is_binary(json), do: json

  defp encoded_time_series(series, _json) do
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

  defp encoded_events(_events, json) when is_binary(json), do: json
  defp encoded_events(events, _json), do: JSON.encode!(events)
end
