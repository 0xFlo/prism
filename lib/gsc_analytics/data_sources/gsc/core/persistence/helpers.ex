defmodule GscAnalytics.DataSources.GSC.Core.Persistence.Helpers do
  @moduledoc false

  require Logger

  # Ensure a value is a float (handles integers and strings from API)
  def ensure_float(value) when is_float(value), do: value
  def ensure_float(value) when is_integer(value), do: value / 1.0

  def ensure_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> float
      :error -> 0.0
    end
  end

  def ensure_float(_), do: 0.0

  # Safely truncate strings to avoid database length constraint errors.
  def safe_truncate(nil, _max_length), do: nil

  def safe_truncate(string, max_length) when is_binary(string) do
    if String.length(string) > max_length do
      truncated = String.slice(string, 0, max_length)

      Logger.warning(
        "Truncated overly long string from #{String.length(string)} to #{max_length} characters: #{String.slice(string, 0, 100)}..."
      )

      truncated
    else
      string
    end
  end

  def safe_truncate(value, _max_length), do: value
end
