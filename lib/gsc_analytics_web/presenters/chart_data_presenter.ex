defmodule GscAnalyticsWeb.Presenters.ChartDataPresenter do
  @moduledoc """
  Centralized presentation logic for preparing chart data for frontend consumption.

  Single source of truth for:
  - JSON encoding of time series data
  - Event data preparation
  - Chart configuration and metadata

  Eliminates duplicate encoding logic across LiveViews (DashboardLive, DashboardUrlLive).

  ## Design Decision

  This module uses `TimeSeriesData.to_json_map/1` for consistent transformation
  from domain types to JSON-serializable maps. This ensures all charts receive
  identically formatted data regardless of which LiveView is rendering them.

  ## Usage

      alias GscAnalyticsWeb.Presenters.ChartDataPresenter

      # In LiveView handle_params
      chart_data = ChartDataPresenter.prepare_chart_data(time_series, events)

      socket
      |> assign(:time_series_json, chart_data.time_series_json)
      |> assign(:events_json, chart_data.events_json)
      |> assign(:has_data, chart_data.has_data)
  """

  alias GscAnalytics.Analytics.TimeSeriesData

  @doc """
  Prepare complete chart data package for frontend rendering.

  Returns a map with all necessary data for chart rendering, including
  JSON-encoded strings and metadata about the dataset.

  ## Parameters
    - `time_series`: List of `TimeSeriesData` structs (or compatible maps)
    - `events`: List of event maps (default: [])

  ## Returns
    Map with keys:
    - `:time_series_json` - JSON string of time series data
    - `:events_json` - JSON string of events data
    - `:has_data` - Boolean indicating if time series has data
    - `:data_points` - Count of time series data points

  ## Examples

      iex> time_series = [%TimeSeriesData{date: ~D[2025-01-15], clicks: 100, ...}]
      iex> ChartDataPresenter.prepare_chart_data(time_series, [])
      %{
        time_series_json: "[{\"date\":\"2025-01-15\",\"clicks\":100,...}]",
        events_json: "[]",
        has_data: true,
        data_points: 1
      }

      iex> ChartDataPresenter.prepare_chart_data([], [])
      %{
        time_series_json: "[]",
        events_json: "[]",
        has_data: false,
        data_points: 0
      }
  """
  @spec prepare_chart_data(list(), list()) :: map()
  def prepare_chart_data(time_series, events \\ []) do
    %{
      time_series_json: encode_time_series(time_series),
      events_json: encode_events(events),
      has_data: length(time_series) > 0,
      data_points: length(time_series)
    }
  end

  @doc """
  Encode time series data to JSON string.

  Uses `TimeSeriesData.to_json_map/1` for consistent transformation from
  domain types to JSON-serializable maps. This ensures:
  - Dates are formatted as ISO 8601 strings
  - period_end is included when present
  - All numeric fields are preserved

  Includes error handling for malformed data - returns empty array on encoding failure
  to prevent LiveView crashes.

  ## Parameters
    - `series`: List of `TimeSeriesData` structs or compatible maps

  ## Returns
    JSON string representation of the time series data, or "[]" on encoding error

  ## Examples

      iex> time_series = [
      ...>   %TimeSeriesData{
      ...>     date: ~D[2025-01-15],
      ...>     clicks: 100,
      ...>     impressions: 1000,
      ...>     ctr: 0.1,
      ...>     position: 5.0,
      ...>     period_end: nil
      ...>   }
      ...> ]
      iex> ChartDataPresenter.encode_time_series(time_series)
      "[{\"date\":\"2025-01-15\",\"clicks\":100,\"impressions\":1000,\"ctr\":0.1,\"position\":5.0}]"

      iex> ChartDataPresenter.encode_time_series([])
      "[]"
  """
  @spec encode_time_series(list(TimeSeriesData.t() | map())) :: String.t()
  def encode_time_series(series) when is_list(series) do
    series
    |> Enum.map(&TimeSeriesData.to_json_map/1)
    |> JSON.encode!()
  rescue
    e ->
      require Logger

      Logger.error(
        "Failed to encode time series data: #{inspect(e)}. " <>
          "Data preview: #{inspect(Enum.take(series, 3))}"
      )

      "[]"
  end

  @doc """
  Encode event data to JSON string.

  Events are typically chart annotations or markers indicating significant
  occurrences (e.g., URL changes, content updates, algorithm updates).

  Includes error handling for malformed data - returns empty array on encoding failure
  to prevent LiveView crashes.

  ## Parameters
    - `events`: List of event maps

  ## Returns
    JSON string representation of events, or "[]" on encoding error

  ## Examples

      iex> events = [%{type: "url_changes", date: ~D[2025-01-15], count: 5}]
      iex> result = ChartDataPresenter.encode_events(events)
      iex> is_binary(result)
      true

      iex> ChartDataPresenter.encode_events([])
      "[]"
  """
  @spec encode_events(list(map())) :: String.t()
  def encode_events(events) when is_list(events) do
    JSON.encode!(events)
  rescue
    e ->
      require Logger

      Logger.error(
        "Failed to encode events data: #{inspect(e)}. " <>
          "Data preview: #{inspect(Enum.take(events, 3))}"
      )

      "[]"
  end
end
