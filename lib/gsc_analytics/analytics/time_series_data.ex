defmodule GscAnalytics.Analytics.TimeSeriesData do
  @moduledoc """
  Domain type for time series data with guaranteed sorting and structure.

  This module serves as the single source of truth for time series data structure,
  ensuring all time series data is consistently structured, validated, and sorted
  chronologically. Prevents the entire class of bugs related to incorrect date handling.

  ## Examples

      iex> raw = [
      ...>   %{date: ~D[2025-01-15], clicks: 100, impressions: 1000, ctr: 0.1, position: 5.5},
      ...>   %{date: ~D[2025-01-14], clicks: 90, impressions: 900, ctr: 0.1, position: 6.0}
      ...> ]
      iex> TimeSeriesData.from_raw_data(raw)
      [
        %TimeSeriesData{date: ~D[2025-01-14], clicks: 90, ...},
        %TimeSeriesData{date: ~D[2025-01-15], clicks: 100, ...}
      ]
  """

  @enforce_keys [:date, :clicks, :impressions, :ctr, :position]
  defstruct [
    :date,
    :period_end,
    :clicks,
    :impressions,
    :ctr,
    :position
  ]

  @type t :: %__MODULE__{
          date: Date.t(),
          period_end: Date.t() | nil,
          clicks: integer(),
          impressions: integer(),
          ctr: float(),
          position: float()
        }

  @doc """
  Convert raw data to structured time series, ensuring proper sorting.

  Single point of entry for creating time series data. Automatically validates
  required fields and sorts data chronologically.

  ## Parameters

    - data: List of maps containing time series data

  ## Returns

    List of TimeSeriesData structs, sorted chronologically by date

  ## Examples

      iex> raw = [
      ...>   %{date: ~D[2025-01-15], clicks: 100, impressions: 1000, ctr: 0.1, position: 5.5},
      ...>   %{date: ~D[2025-01-14], clicks: 90, impressions: 900, ctr: 0.1, position: 6.0}
      ...> ]
      iex> result = TimeSeriesData.from_raw_data(raw)
      iex> Enum.map(result, & &1.date)
      [~D[2025-01-14], ~D[2025-01-15]]
  """
  @spec from_raw_data([map()]) :: [t()]
  def from_raw_data(data) when is_list(data) do
    start_time = System.monotonic_time()

    result =
      data
      |> Enum.map(&to_struct/1)
      |> sort_chronologically()

    end_time = System.monotonic_time()
    duration = System.convert_time_unit(end_time - start_time, :native, :millisecond)

    :telemetry.execute(
      [:gsc_analytics, :time_series_data, :from_raw_data],
      %{duration_ms: duration, count: length(data)},
      %{}
    )

    result
  end

  @doc """
  Always sort chronologically using Date module.

  Replaces all scattered sorting calls across the codebase with a single,
  consistent implementation that uses the Date module for proper date comparison.

  ## Parameters

    - series: List of TimeSeriesData structs

  ## Returns

    List of TimeSeriesData structs sorted chronologically (earliest to latest)

  ## Examples

      iex> unsorted = [
      ...>   %TimeSeriesData{date: ~D[2025-01-15], clicks: 100, impressions: 1000, ctr: 0.1, position: 5.5},
      ...>   %TimeSeriesData{date: ~D[2025-01-14], clicks: 90, impressions: 900, ctr: 0.1, position: 6.0}
      ...> ]
      iex> sorted = TimeSeriesData.sort_chronologically(unsorted)
      iex> Enum.map(sorted, & &1.date)
      [~D[2025-01-14], ~D[2025-01-15]]
  """
  @spec sort_chronologically([t()]) :: [t()]
  def sort_chronologically(series) when is_list(series) do
    Enum.sort_by(series, & &1.date, Date)
  end

  @doc """
  Convert to JSON-ready map for frontend consumption.

  Single source of truth for time series serialization. Converts Date structs
  to ISO8601 strings and handles optional period_end field.

  ## Parameters

    - ts: TimeSeriesData struct

  ## Returns

    Map with string keys ready for JSON encoding

  ## Examples

      iex> ts = %TimeSeriesData{
      ...>   date: ~D[2025-01-15],
      ...>   clicks: 100,
      ...>   impressions: 1000,
      ...>   ctr: 0.1,
      ...>   position: 5.5,
      ...>   period_end: nil
      ...> }
      iex> result = TimeSeriesData.to_json_map(ts)
      iex> result.date
      "2025-01-15"
      iex> Map.has_key?(result, :period_end)
      false
  """
  @spec to_json_map(t() | map()) :: map()
  def to_json_map(%__MODULE__{} = ts) do
    base = %{
      date: Date.to_string(ts.date),
      clicks: ts.clicks,
      impressions: ts.impressions,
      ctr: ts.ctr,
      position: ts.position
    }

    if ts.period_end do
      Map.put(base, :period_end, Date.to_string(ts.period_end))
    else
      base
    end
  end

  # Handle plain maps for backward compatibility (used in tests)
  def to_json_map(%{date: date} = map) when is_map(map) do
    base = %{
      date: Date.to_string(date),
      clicks: Map.fetch!(map, :clicks),
      impressions: Map.fetch!(map, :impressions),
      ctr: Map.fetch!(map, :ctr),
      position: Map.fetch!(map, :position)
    }

    case Map.get(map, :period_end) do
      nil -> base
      period_end -> Map.put(base, :period_end, Date.to_string(period_end))
    end
  end

  # Private functions

  @doc false
  defp to_struct(%{} = attrs) do
    %__MODULE__{
      date: attrs |> Map.fetch!(:date) |> normalize_to_date!(),
      period_end: attrs |> Map.get(:period_end) |> normalize_optional_date(),
      clicks: Map.fetch!(attrs, :clicks),
      impressions: Map.fetch!(attrs, :impressions),
      ctr: Map.fetch!(attrs, :ctr),
      position: Map.fetch!(attrs, :position)
    }
  end

  @doc false
  defp normalize_to_date!(%Date{} = date), do: date
  defp normalize_to_date!(date) when is_binary(date), do: Date.from_iso8601!(date)

  @doc false
  defp normalize_optional_date(nil), do: nil
  defp normalize_optional_date(%Date{} = date), do: date

  defp normalize_optional_date(date) when is_binary(date),
    do: Date.from_iso8601!(date)
end
