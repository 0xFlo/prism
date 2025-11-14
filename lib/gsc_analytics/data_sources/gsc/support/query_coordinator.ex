defmodule GscAnalytics.DataSources.GSC.Support.QueryCoordinator do
  @moduledoc """
  GenServer that coordinates concurrent query pagination.

  The coordinator owns the pagination queue, enforces backpressure via
  configurable queue and in-flight limits, and ensures ordered result
  processing by invoking the `:on_complete` callback exactly once per date.
  """

  use GenServer

  require Logger

  alias GscAnalytics.DataSources.GSC.Support.{DataHelpers, QueryPaginator}

  @type batch_item :: {Date.t(), non_neg_integer()}

  @type batch_entry ::
          {:ok, Date.t(), non_neg_integer(), map()}
          | {:error, Date.t(), non_neg_integer(), term()}

  @default_queue_size 1_000
  @default_in_flight 10

  defstruct [
    :account_id,
    :site_url,
    :queue,
    :results,
    :completed,
    :total_api_calls,
    :http_batch_calls,
    :on_complete,
    :max_queue_size,
    :max_in_flight,
    :in_flight,
    :inflight_table,
    :halt_reason,
    :page_size,
    :telemetry_prefix
  ]

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Starts the coordinator.

  Required options:
    * `:account_id`
    * `:site_url`
    * `:dates` – list of dates being paginated
    * `:on_complete` – callback invoked when a date finishes (may be nil)

  Optional options:
    * `:max_queue_size` (default: 1_000)
    * `:max_in_flight` (default: 10)
    * `:telemetry_prefix`
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name))
  end

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :transient,
      shutdown: 5_000
    }
  end

  @doc """
  Returns the next batch of work respecting in-flight limits.
  """
  @spec take_batch(GenServer.server(), pos_integer()) ::
          {:ok, [batch_item()]}
          | {:backpressure, :max_in_flight}
          | {:halted, term()}
          | :pending
          | :no_more_work
  def take_batch(server, batch_size) when batch_size > 0 do
    GenServer.call(server, {:take_batch, batch_size}, :infinity)
  end

  @doc """
  Accepts results for one HTTP batch.
  """
  @spec submit_results(GenServer.server(), %{
          entries: [batch_entry()],
          http_batches: non_neg_integer()
        }) ::
          :ok
  def submit_results(server, %{entries: _entries} = payload) do
    GenServer.call(server, {:submit_results, payload}, :infinity)
  end

  @doc """
  Re-enqueues the provided batch items (e.g. when rate limited).
  """
  @spec requeue_batch(GenServer.server(), [batch_item()]) ::
          :ok | {:error, :queue_full}
  def requeue_batch(server, batch_items) do
    GenServer.call(server, {:requeue_batch, batch_items}, :infinity)
  end

  @doc """
  Forces the coordinator into a halted state.
  """
  @spec halt(GenServer.server(), term()) :: :ok
  def halt(server, reason) do
    GenServer.call(server, {:halt, reason}, :infinity)
  end

  @doc """
  Returns true if the coordinator has been halted.
  """
  @spec halted?(GenServer.server()) :: boolean()
  def halted?(server) do
    GenServer.call(server, :halted?, :infinity)
  end

  @doc """
  Finalizes results and reports final counters.
  """
  @spec finalize(GenServer.server()) ::
          {:ok | :halt | :error, term() | nil, map(), non_neg_integer(), non_neg_integer()}
  def finalize(server) do
    GenServer.call(server, :finalize, :infinity)
  end

  @doc """
  Returns queue depth and in-flight counts for telemetry.
  """
  @spec stats(GenServer.server()) :: %{
          queue_depth: non_neg_integer(),
          in_flight: non_neg_integer()
        }
  def stats(server) do
    GenServer.call(server, :stats, :infinity)
  end

  # ===========================================================================
  # GenServer callbacks
  # ===========================================================================

  @impl true
  def init(opts) do
    account_id = Keyword.fetch!(opts, :account_id)
    site_url = Keyword.fetch!(opts, :site_url)
    dates = Keyword.get(opts, :dates, [])
    on_complete = Keyword.get(opts, :on_complete)
    max_queue_size = Keyword.get(opts, :max_queue_size, @default_queue_size)
    max_in_flight = Keyword.get(opts, :max_in_flight, @default_in_flight)
    telemetry_prefix = Keyword.get(opts, :telemetry_prefix, [:gsc_analytics, :coordinator])

    queue =
      opts
      |> Keyword.get_lazy(:queue, fn -> build_initial_queue(dates) end)

    if :queue.len(queue) > max_queue_size do
      {:stop, {:queue_overflow, :initial}}
    else
      results =
        opts
        |> Keyword.get_lazy(:results, fn -> build_initial_results(dates) end)

      {:ok,
       %__MODULE__{
         account_id: account_id,
         site_url: site_url,
         queue: queue,
         results: results,
         completed: MapSet.new(),
         total_api_calls: :atomics.new(1, []),
         http_batch_calls: :atomics.new(1, []),
         on_complete: on_complete,
         max_queue_size: max_queue_size,
         max_in_flight: max_in_flight,
         in_flight: MapSet.new(),
         inflight_table:
           Keyword.get_lazy(opts, :inflight_table, fn ->
             :ets.new(__MODULE__, [:set, :public, read_concurrency: true])
           end),
         halt_reason: nil,
         telemetry_prefix: telemetry_prefix
       }}
    end
  end

  @impl true
  def handle_call({:take_batch, batch_size}, _from, state) do
    cond do
      state.halt_reason != nil ->
        reply_with_metrics({:halted, state.halt_reason}, state)

      MapSet.size(state.in_flight) >= state.max_in_flight ->
        reply_with_metrics({:backpressure, :max_in_flight}, state)

      true ->
        {batch, remaining_queue} = take_batch(state.queue, batch_size, state.completed, [])

        case batch do
          [] ->
            if MapSet.size(state.in_flight) == 0 do
              reply_with_metrics(:no_more_work, %{state | queue: remaining_queue})
            else
              reply_with_metrics(:pending, %{state | queue: remaining_queue})
            end

          _ ->
            in_flight = mark_in_flight(state.in_flight, batch, state.inflight_table)

            reply_with_metrics({:ok, batch}, %{
              state
              | queue: remaining_queue,
                in_flight: in_flight
            })
        end
    end
  end

  @impl true
  def handle_call({:submit_results, payload}, _from, state) do
    entries = Map.get(payload, :entries, [])
    http_batches = Map.get(payload, :http_batches, 0)

    if entries == [] do
      reply_with_metrics(:ok, increment_http_batches(state, http_batches))
    else
      :atomics.add(state.total_api_calls, 1, length(entries))
      :atomics.add(state.http_batch_calls, 1, http_batches)

      updated_state =
        entries
        |> Enum.reduce(state, &process_entry/2)
        |> clear_in_flight(entries)

      reply_with_metrics(:ok, updated_state)
    end
  end

  @impl true
  def handle_call({:requeue_batch, batch_items}, _from, state) do
    cond do
      batch_items == [] ->
        reply_with_metrics(:ok, state)

      :queue.len(state.queue) + length(batch_items) > state.max_queue_size ->
        reply_with_metrics({:error, :queue_full}, state)

      true ->
        queue =
          Enum.reduce(batch_items, state.queue, fn item, acc -> :queue.in_r(item, acc) end)

        in_flight =
          Enum.reduce(batch_items, state.in_flight, fn key, acc ->
            :ets.delete(state.inflight_table, key)
            MapSet.delete(acc, key)
          end)

        reply_with_metrics(:ok, %{state | queue: queue, in_flight: in_flight})
    end
  end

  @impl true
  def handle_call({:halt, reason}, _from, state) do
    reply_with_metrics(:ok, %{state | halt_reason: {:halt, reason}})
  end

  @impl true
  def handle_call(:halted?, _from, state) do
    reply_with_metrics(state.halt_reason != nil, state)
  end

  @impl true
  def handle_call(:stats, _from, state) do
    reply_with_metrics(
      %{queue_depth: :queue.len(state.queue), in_flight: MapSet.size(state.in_flight)},
      state
    )
  end

  @impl true
  def handle_call(:finalize, _from, state) do
    results = finalize_results(state.results)
    total_api_calls = :atomics.get(state.total_api_calls, 1)
    http_batch_calls = :atomics.get(state.http_batch_calls, 1)

    reply =
      case state.halt_reason do
        nil -> {:ok, nil, results, total_api_calls, http_batch_calls}
        {:halt, reason} -> {:halt, reason, results, total_api_calls, http_batch_calls}
        {:error, reason} -> {:error, reason, results, total_api_calls, http_batch_calls}
      end

    reply_with_metrics(reply, state)
  end

  # ===========================================================================
  # Internal helpers
  # ===========================================================================

  defp build_initial_queue(dates) do
    dates
    |> Enum.map(&{&1, 0})
    |> :queue.from_list()
  end

  defp build_initial_results(dates) do
    Enum.reduce(dates, %{}, fn date, acc ->
      Map.put(acc, date, new_result_entry())
    end)
  end

  defp new_result_entry do
    %{
      rows: [],
      row_chunks: [],
      api_calls: 0,
      partial?: false,
      http_batches: 0
    }
  end

  defp take_batch(queue, batch_size, _completed, acc) when length(acc) >= batch_size do
    {Enum.reverse(acc), queue}
  end

  defp take_batch(queue, batch_size, completed, acc) do
    case :queue.out(queue) do
      {:empty, queue} ->
        {Enum.reverse(acc), queue}

      {{:value, {date, _start_row} = item}, rest} ->
        if MapSet.member?(completed, date) do
          take_batch(rest, batch_size, completed, acc)
        else
          take_batch(rest, batch_size, completed, [item | acc])
        end
    end
  end

  defp mark_in_flight(in_flight, batch, inflight_table) do
    Enum.reduce(batch, in_flight, fn key, acc ->
      :ets.insert(inflight_table, {key, System.monotonic_time()})
      MapSet.put(acc, key)
    end)
  end

  defp clear_in_flight(state, entries) do
    keys =
      entries
      |> Enum.map(fn
        {status, date, start_row, _} when status in [:ok, :error] -> {date, start_row}
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)

    in_flight =
      Enum.reduce(keys, state.in_flight, fn key, acc ->
        :ets.delete(state.inflight_table, key)
        MapSet.delete(acc, key)
      end)

    %{state | in_flight: in_flight}
  end

  defp process_entry({:ok, date, start_row, part}, state) do
    rows = extract_rows(part)
    needs_next? = QueryPaginator.needs_next_page?(rows)

    result_entry = Map.get(state.results, date, new_result_entry())

    updated_entry =
      result_entry
      |> Map.update!(:row_chunks, fn chunks -> [rows | chunks] end)
      |> Map.update!(:api_calls, &(&1 + 1))
      |> Map.update!(:http_batches, &(&1 + 1))

    {queue, overflow?} =
      if needs_next? do
        next_row = start_row + length(rows)
        enqueue_with_limit(state.queue, {date, next_row}, state.max_queue_size)
      else
        {state.queue, false}
      end

    state =
      if overflow? do
        %{state | halt_reason: state.halt_reason || {:error, :queue_overflow}}
      else
        state
      end

    completed =
      if needs_next? do
        state.completed
      else
        MapSet.put(state.completed, date)
      end

    {next_state, entry_after_callback} =
      if needs_next? do
        {%{state | queue: queue, results: Map.put(state.results, date, updated_entry)},
         updated_entry}
      else
        handle_completion(%{state | queue: queue}, date, updated_entry)
      end

    %{
      next_state
      | completed: completed,
        results: Map.put(next_state.results, date, entry_after_callback)
    }
  end

  defp process_entry({:error, date, _start_row, reason}, state) do
    entry =
      state.results
      |> Map.get(date, new_result_entry())
      |> Map.put(:partial?, true)

    %{
      state
      | results: Map.put(state.results, date, entry),
        halt_reason: state.halt_reason || {:error, reason}
    }
  end

  defp handle_completion(state, date, entry) do
    rows = DataHelpers.flatten_row_chunks(entry.row_chunks)
    row_count = length(rows)

    payload = %{
      date: date,
      rows: rows,
      api_calls: entry.api_calls,
      partial?: entry.partial?,
      row_count: row_count,
      http_batches: entry.http_batches
    }

    case safe_invoke_callback(state.on_complete, payload) do
      {:halt, reason} ->
        {%{state | halt_reason: state.halt_reason || {:halt, reason}},
         minimize_entry(entry, row_count)}

      :continue ->
        {state, minimize_entry(entry, row_count)}
    end
  end

  defp safe_invoke_callback(nil, _payload), do: :continue

  defp safe_invoke_callback(callback, payload) when is_function(callback, 1) do
    try do
      case callback.(payload) do
        {:halt, reason} -> {:halt, reason}
        _ -> :continue
      end
    rescue
      exception ->
        Logger.error(
          "Query callback crashed for #{payload.date}: #{Exception.message(exception)}"
        )

        {:halt, {:callback_error, Exception.message(exception)}}
    end
  end

  defp safe_invoke_callback(_, _payload), do: :continue

  defp minimize_entry(entry, row_count) do
    entry
    |> Map.put(:rows, [])
    |> Map.put(:row_chunks, [])
    |> Map.put(:row_count, row_count)
  end

  defp finalize_results(results) do
    Enum.into(results, %{}, fn {date, entry} ->
      rows =
        cond do
          entry.rows != [] -> entry.rows
          true -> DataHelpers.flatten_row_chunks(Map.get(entry, :row_chunks, []))
        end

      sanitized =
        entry
        |> Map.put(:rows, rows)
        |> Map.delete(:row_chunks)

      {date, sanitized}
    end)
  end

  defp extract_rows(%{body: %{"rows" => rows}}) when is_list(rows), do: rows
  defp extract_rows(_), do: []

  defp increment_http_batches(state, amount) do
    :atomics.add(state.http_batch_calls, 1, amount)
    state
  end

  defp enqueue_with_limit(queue, item, max_limit) do
    if :queue.len(queue) >= max_limit do
      {queue, true}
    else
      {:queue.in(item, queue), false}
    end
  end

  defp reply_with_metrics(reply, state) do
    emit_metrics(state)
    {:reply, reply, state}
  end

  defp emit_metrics(state) do
    metadata = %{account_id: state.account_id, site_url: state.site_url}
    prefix = state.telemetry_prefix

    :telemetry.execute(prefix ++ [:queue_size], %{size: :queue.len(state.queue)}, metadata)
    :telemetry.execute(prefix ++ [:in_flight], %{count: MapSet.size(state.in_flight)}, metadata)
  end
end
