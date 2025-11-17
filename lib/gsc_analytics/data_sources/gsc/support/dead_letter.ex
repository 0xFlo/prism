defmodule GscAnalytics.DataSources.GSC.Support.DeadLetter do
  @moduledoc """
  In-memory dead-letter queue for capturing pipeline failures.
  """

  use GenServer

  @table __MODULE__

  # Client API ---------------------------------------------------------------

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Stores a dead-letter entry tagged by pipeline.
  """
  def put(pipeline, payload) do
    entry = %{
      pipeline: pipeline,
      payload: payload,
      inserted_at: DateTime.utc_now()
    }

    :ets.insert(@table, {System.unique_integer([:positive]), entry})
    :ok
  end

  @doc """
  Returns all dead-letter entries.
  """
  def all do
    :ets.tab2list(@table)
    |> Enum.map(fn {_id, entry} -> entry end)
  end

  @doc """
  Clears all entries from the dead-letter queue.
  """
  def clear do
    :ets.delete_all_objects(@table)
    :ok
  end

  # Server callbacks ---------------------------------------------------------

  @impl true
  def init(state) do
    table =
      :ets.new(@table, [
        :set,
        :named_table,
        :public,
        read_concurrency: true,
        write_concurrency: true
      ])

    {:ok, Map.put(state, :table, table)}
  end
end
