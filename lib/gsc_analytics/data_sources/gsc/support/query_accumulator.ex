defmodule GscAnalytics.DataSources.GSC.Support.QueryAccumulator do
  @moduledoc """
  Streaming accumulator that keeps only the top queries per URL.

  Instead of storing every Search Console row in memory, this accumulator
  maintains a bounded list (top 20) per URL and tracks the overall row count.
  The resulting structure is compact enough to hand off to async persistence
  tasks without blocking the coordinator.
  """

  alias GscAnalytics.DataSources.GSC.Support.DataHelpers

  @enforce_keys [:limit]
  defstruct limit: 20, urls: %{}, row_count: 0

  @type query_entry :: %{
          query: String.t(),
          clicks: number(),
          impressions: number(),
          ctr: float(),
          position: float()
        }

  @type t :: %__MODULE__{
          limit: pos_integer(),
          urls: %{optional(String.t()) => [query_entry()]},
          row_count: non_neg_integer()
        }

  @doc "Create a new accumulator with the provided per-URL limit."
  @spec new(pos_integer()) :: t()
  def new(limit \\ 20) when is_integer(limit) and limit > 0 do
    %__MODULE__{limit: limit, urls: %{}, row_count: 0}
  end

  @doc "Reset an accumulator back to an empty state."
  @spec reset(t()) :: t()
  def reset(%__MODULE__{} = acc) do
    %{acc | urls: %{}, row_count: 0}
  end

  @doc "Return the per-URL map of queries."
  @spec entries(t()) :: %{optional(String.t()) => [query_entry()]}
  def entries(%__MODULE__{urls: urls}), do: urls

  @doc "Return the total number of rows processed."
  @spec row_count(t()) :: non_neg_integer()
  def row_count(%__MODULE__{row_count: count}), do: count

  @doc "Insert a chunk of rows into the accumulator."
  @spec ingest_chunk(t(), list(map())) :: t()
  def ingest_chunk(%__MODULE__{} = acc, []), do: acc

  def ingest_chunk(%__MODULE__{} = acc, rows) when is_list(rows) do
    Enum.reduce(rows, acc, fn row, acc -> ingest_row(acc, row) end)
  end

  defp ingest_row(%__MODULE__{} = acc, %{"keys" => keys} = row) when is_list(keys) do
    url = keys |> Enum.at(0)
    query = keys |> Enum.at(1)

    if is_binary(url) and is_binary(query) do
      entry = %{
        query: query,
        clicks: row["clicks"] || 0,
        impressions: row["impressions"] || 0,
        ctr: DataHelpers.ensure_float(row["ctr"] || 0.0),
        position: DataHelpers.ensure_float(row["position"] || 0.0)
      }

      urls =
        Map.update(acc.urls, url, [entry], fn queries ->
          [entry | queries]
          |> Enum.sort_by(& &1.clicks, :desc)
          |> Enum.take(acc.limit)
        end)

      %{acc | urls: urls, row_count: acc.row_count + 1}
    else
      acc
    end
  end

  defp ingest_row(%__MODULE__{} = acc, _row), do: acc
end
