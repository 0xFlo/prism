defmodule GscAnalytics.DataSources.GSC.Support.DataHelpers do
  @moduledoc """
  Common data transformation and utility functions for GSC data processing.

  Consolidates utility functions that were duplicated or could be shared
  across multiple modules.
  """

  @doc """
  Conditionally add a key-value pair to a map if the value is not nil.

  ## Examples

      iex> maybe_put(%{a: 1}, :b, nil)
      %{a: 1}

      iex> maybe_put(%{a: 1}, :b, 2)
      %{a: 1, b: 2}
  """
  @spec maybe_put(map(), any(), any()) :: map()
  def maybe_put(map, _key, nil), do: map
  def maybe_put(map, key, value), do: Map.put(map, key, value)

  @doc """
  Conditionally append a key-value tuple to a keyword list if the value is not nil.

  ## Examples

      iex> maybe_add([a: 1], :b, nil)
      [a: 1]

      iex> maybe_add([a: 1], :b, 2)
      [a: 1, b: 2]
  """
  @spec maybe_add(keyword(), any(), any()) :: keyword()
  def maybe_add(list, _key, nil), do: list
  def maybe_add(list, key, value), do: list ++ [{key, value}]

  @doc """
  Ensure a value is a float, converting from integer or string if needed.

  ## Examples

      iex> ensure_float(1.5)
      1.5

      iex> ensure_float(2)
      2.0

      iex> ensure_float("3.14")
      3.14

      iex> ensure_float("invalid")
      0.0

      iex> ensure_float(nil)
      0.0
  """
  @spec ensure_float(any()) :: float()
  def ensure_float(value) when is_float(value), do: value
  def ensure_float(value) when is_integer(value), do: value / 1.0

  def ensure_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> float
      :error -> 0.0
    end
  end

  def ensure_float(_), do: 0.0

  @doc """
  Flatten a list of row chunks in the correct order.

  Used by QueryPaginator to flatten accumulated result chunks.

  ## Examples

      iex> flatten_row_chunks([[3, 4], [1, 2]])
      [1, 2, 3, 4]
  """
  @spec flatten_row_chunks(list(list())) :: list()
  def flatten_row_chunks(chunks) do
    chunks
    |> Enum.reverse()
    |> Enum.flat_map(& &1)
  end

  @doc """
  Build a unique batch boundary string for multipart requests.
  """
  @spec build_batch_boundary() :: String.t()
  def build_batch_boundary do
    "batch_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end

  @doc """
  Normalize an ID value to a string for consistent map keys.

  ## Examples

      iex> normalize_id(:atom_id)
      "atom_id"

      iex> normalize_id("string_id")
      "string_id"
  """
  @spec normalize_id(atom() | String.t()) :: String.t()
  def normalize_id(id) when is_atom(id), do: Atom.to_string(id)
  def normalize_id(id) when is_binary(id), do: id

  @doc """
  Extract row count from a GSC API response body.

  ## Examples

      iex> extract_row_count(%{"rows" => [1, 2, 3]})
      3

      iex> extract_row_count(%{"error" => "something"})
      0

      iex> extract_row_count(nil)
      0
  """
  @spec extract_row_count(map() | nil) :: non_neg_integer()
  def extract_row_count(%{"rows" => rows}) when is_list(rows), do: length(rows)
  def extract_row_count(_), do: 0

  @doc """
  Check if a date is within the GSC data availability window.

  GSC data has a 2-3 day processing lag.
  """
  @spec date_available?(Date.t()) :: boolean()
  def date_available?(date) do
    today = Date.utc_today()
    # GSC data is typically available with 3 day lag
    earliest_available = Date.add(today, -3)
    Date.compare(date, earliest_available) != :gt
  end
end
