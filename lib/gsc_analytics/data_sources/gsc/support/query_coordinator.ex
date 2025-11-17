defmodule GscAnalytics.DataSources.GSC.Support.QueryCoordinator do
  @moduledoc """
  GenServer that coordinates concurrent query pagination.

  The coordinator owns the pagination queue, enforces backpressure via
  configurable queue and in-flight limits, and ensures ordered result
  processing by invoking the `:on_complete` callback exactly once per date.
  """

  use GenServer

  require Logger

  alias GscAnalytics.DataSources.GSC.Core.Config
  alias GscAnalytics.DataSources.GSC.Support.{
    DataHelpers,
    QueryAccumulator,
    QueryPaginator,
    StreamingCallbacks
  }

  @type batch_item :: {Date.t(), non_neg_integer()}

  @type batch_entry ::
          {:ok, Date.t(), non_neg_integer(), map()}
          | {:error, Date.t(), non_neg_integer(), term()}

  @default_queue_size 1_000
  @default_in_flight 10

  defstruct [
    :account_id,
    :site_url,
    :mode,
    :queue,
    :results,
    :completed,
    :total_api_calls,
    :http_batch_calls,
    :callbacks,
    :writer_supervisor,
    :writer_refs,
    :pending_writes,
    :writer_pending_limit,
    :writer_max_concurrency,
    :finalize_from,
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

  Changed to async (cast) to prevent workers from blocking on result submission.
  This significantly improves concurrent performance.
  """
  @spec submit_results(GenServer.server(), %{
          entries: [batch_entry()],
          http_batches: non_neg_integer()
        }) ::
          :ok
  def submit_results(server, %{entries: _entries} = payload) do
    GenServer.cast(server, {:submit_results, payload})
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
    callbacks =
      opts
      |> Keyword.get(:on_complete)
      |> StreamingCallbacks.normalize()

    mode = callbacks.mode
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
        |> Keyword.get_lazy(:results, fn -> build_initial_results(dates, mode) end)

      {writer_supervisor, writer_refs, pending_writes} = start_writer_supervisor(callbacks)
      writer_pending_limit = writer_pending_limit(callbacks.mode)
      writer_max_concurrency = writer_max_concurrency(callbacks.mode)

      {:ok,
       %__MODULE__{
         account_id: account_id,
         site_url: site_url,
         queue: queue,
         results: results,
         completed: MapSet.new(),
         total_api_calls: :atomics.new(1, []),
         http_batch_calls: :atomics.new(1, []),
         mode: mode,
         callbacks: callbacks,
         writer_supervisor: writer_supervisor,
         writer_refs: writer_refs,
         pending_writes: pending_writes,
         writer_pending_limit: writer_pending_limit,
         writer_max_concurrency: writer_max_concurrency,
         finalize_from: nil,
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

      pending_writer_backlog?(state) ->
        reply_with_metrics({:backpressure, :writer_backlog}, state)

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
  def handle_call(:finalize, from, state) do
    if pending_writers?(state) do
      {:noreply, %{state | finalize_from: from}}
    else
      reply = finalize_reply_payload(state)
      emit_metrics(state)
      {:reply, reply, state}
    end
  end

  @impl true
  def handle_cast({:submit_results, payload}, state) do
    entries = Map.get(payload, :entries, [])
    http_batches = Map.get(payload, :http_batches, 0)

    updated_state =
      if entries == [] do
        increment_http_batches(state, http_batches)
      else
        :atomics.add(state.total_api_calls, 1, length(entries))
        :atomics.add(state.http_batch_calls, 1, http_batches)

        entries
        |> Enum.reduce(state, &process_entry/2)
        |> clear_in_flight(entries)
      end

    {:noreply, updated_state}
  end

  @impl true
  def handle_info({:writer_complete, pid, _date, result}, state) do
    {meta, writer_refs} = Map.pop(state.writer_refs, pid)

    if meta do
      Process.demonitor(meta.monitor_ref, [:flush])
    end

    updated_state =
      state
      |> Map.put(:writer_refs, writer_refs)
      |> handle_writer_result(result)
      |> maybe_start_pending_writer()
      |> maybe_reply_finalize()

    {:noreply, updated_state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    case Map.pop(state.writer_refs, pid) do
      {nil, writer_refs} ->
        {:noreply, %{state | writer_refs: writer_refs}}

      {%{monitor_ref: ^ref} = _meta, writer_refs} ->
        new_state =
          state
          |> Map.put(:writer_refs, writer_refs)
          |> handle_writer_down(reason)
          |> maybe_start_pending_writer()
          |> maybe_reply_finalize()

        {:noreply, new_state}
    end
  end

  # ===========================================================================
  # Internal helpers
  # ===========================================================================

  defp build_initial_queue(dates) do
    dates
    |> Enum.map(&{&1, 0})
    |> :queue.from_list()
  end

  defp start_writer_supervisor(%StreamingCallbacks{mode: :streaming}) do
    {:ok, supervisor} = Task.Supervisor.start_link()
    {supervisor, %{}, :queue.new()}
  end

  defp start_writer_supervisor(_callbacks), do: {nil, %{}, :queue.new()}

  defp writer_pending_limit(:streaming), do: Config.query_writer_pending_limit()
  defp writer_pending_limit(_mode), do: 0

  defp writer_max_concurrency(:streaming), do: Config.query_writer_max_concurrency()
  defp writer_max_concurrency(_mode), do: 0

  defp pending_writer_backlog?(%{writer_pending_limit: limit}) when limit <= 0, do: false

  defp pending_writer_backlog?(state) do
    :queue.len(state.pending_writes) >= state.writer_pending_limit
  end

  defp build_initial_results(dates, mode) do
    Enum.reduce(dates, %{}, fn date, acc ->
      Map.put(acc, date, new_result_entry(mode))
    end)
  end

  defp new_result_entry(:legacy) do
    %{
      rows: [],
      row_chunks: [],
      api_calls: 0,
      partial?: false,
      http_batches: 0,
      row_count: 0,
      accumulator: nil
    }
  end

  defp new_result_entry(:streaming) do
    %{
      rows: [],
      row_chunks: nil,
      api_calls: 0,
      partial?: false,
      http_batches: 0,
      row_count: 0,
      accumulator: QueryAccumulator.new()
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

  defp maybe_store_chunk(entry, _rows, :streaming), do: entry

  defp maybe_store_chunk(%{row_chunks: nil} = entry, _rows, _mode), do: entry

  defp maybe_store_chunk(%{row_chunks: chunks} = entry, rows, _mode) do
    %{entry | row_chunks: [rows | chunks]}
  end

  defp maybe_accumulate(entry, _rows, mode) when mode in [:legacy, :none], do: entry

  defp maybe_accumulate(%{accumulator: nil} = entry, _rows, _mode), do: entry

  defp maybe_accumulate(%{accumulator: acc} = entry, rows, _mode) do
    %{entry | accumulator: QueryAccumulator.ingest_chunk(acc, rows)}
  end

  defp process_entry({:ok, date, start_row, part}, state) do
    rows = extract_rows(part)
    needs_next? = QueryPaginator.needs_next_page?(rows)

    result_entry = Map.get(state.results, date, new_result_entry(state.mode))

    updated_entry =
      result_entry
      |> maybe_store_chunk(rows, state.mode)
      |> maybe_accumulate(rows, state.mode)
      |> Map.update!(:api_calls, &(&1 + 1))
      |> Map.update!(:http_batches, &(&1 + 1))
      |> Map.update!(:row_count, &(&1 + length(rows)))

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
      |> Map.get(date, new_result_entry(state.mode))
      |> Map.put(:partial?, true)

    %{
      state
      | results: Map.put(state.results, date, entry),
        halt_reason: state.halt_reason || {:error, reason}
    }
  end

  defp handle_completion(state, date, entry) do
    {payload, minimized_entry} = build_completion_payload(entry, date, state.mode)
    control_payload = Map.drop(payload, [:accumulator])

    case invoke_control(state.callbacks.control, control_payload) do
      {:halt, reason} ->
        {%{state | halt_reason: state.halt_reason || {:halt, reason}}, minimized_entry}

      :continue ->
        updated_state = maybe_start_writer(state, payload)
        {updated_state, minimized_entry}
    end
  end

  defp build_completion_payload(entry, date, :streaming) do
    acc = entry.accumulator || QueryAccumulator.new()
    row_count = entry.row_count

    payload = %{
      date: date,
      accumulator: acc,
      api_calls: entry.api_calls,
      partial?: entry.partial?,
      row_count: row_count,
      http_batches: entry.http_batches
    }

    {payload, minimize_entry(entry, row_count, :streaming)}
  end

  defp build_completion_payload(entry, date, _mode) do
    rows = DataHelpers.flatten_row_chunks(entry.row_chunks || [])
    row_count = length(rows)

    payload = %{
      date: date,
      rows: rows,
      api_calls: entry.api_calls,
      partial?: entry.partial?,
      row_count: row_count,
      http_batches: entry.http_batches
    }

    {payload, minimize_entry(entry, row_count, :legacy)}
  end

  defp minimize_entry(entry, row_count, :streaming) do
    reset_acc =
      case entry.accumulator do
        nil -> QueryAccumulator.new()
        acc -> QueryAccumulator.reset(acc)
      end

    entry
    |> Map.put(:rows, [])
    |> Map.put(:row_chunks, nil)
    |> Map.put(:accumulator, reset_acc)
    |> Map.put(:row_count, row_count)
  end

  defp minimize_entry(entry, row_count, :legacy) do
    entry
    |> Map.put(:rows, [])
    |> Map.put(:row_chunks, [])
    |> Map.put(:row_count, row_count)
  end

  defp minimize_entry(entry, row_count, _mode) do
    minimize_entry(entry, row_count, :legacy)
  end

  defp invoke_control(nil, _payload), do: :continue

  defp invoke_control(callback, payload) when is_function(callback, 1) do
    try do
      case callback.(payload) do
        {:halt, reason} -> {:halt, reason}
        _ -> :continue
      end
    rescue
      exception ->
        Logger.error(
          "Query control callback crashed for #{payload.date}: #{Exception.message(exception)}"
        )

        {:halt, {:callback_error, Exception.message(exception)}}
    end
  end

  defp invoke_control(_, _payload), do: :continue

  defp maybe_start_writer(
         %{callbacks: %StreamingCallbacks{mode: :streaming, writer: writer}} = state,
         payload
       )
       when is_function(writer, 1) and not is_nil(state.writer_supervisor) do
    if state.writer_max_concurrency > 0 and
         map_size(state.writer_refs) >= state.writer_max_concurrency do
      # Queue the payload for later processing when a writer slot frees up
      %{state | pending_writes: :queue.in(payload, state.pending_writes)}
    else
      spawn_writer(state, payload)
    end
  end

  defp maybe_start_writer(state, _payload), do: state

  defp spawn_writer(state, payload) do
    parent = self()
    writer = state.callbacks.writer

    {:ok, pid} =
      Task.Supervisor.start_child(state.writer_supervisor, fn ->
        result = safe_run_writer(writer, payload)
        send(parent, {:writer_complete, self(), payload.date, result})
      end)

    ref = Process.monitor(pid)

    %{
      state
      | writer_refs: Map.put(state.writer_refs, pid, %{monitor_ref: ref, date: payload.date})
    }
  end

  defp maybe_start_pending_writer(state) do
    case :queue.out(state.pending_writes) do
      {:empty, _} ->
        state

      {{:value, payload}, remaining} ->
        state
        |> Map.put(:pending_writes, remaining)
        |> spawn_writer(payload)
    end
  end

  defp safe_run_writer(writer, payload) when is_function(writer, 1) do
    try do
      case writer.(payload) do
        {:halt, reason} -> {:halt, reason}
        {:error, reason} -> {:error, reason}
        {:ok, meta} -> {:ok, meta}
        other -> {:ok, other}
      end
    rescue
      exception ->
        Logger.error(
          "Query writer crashed for #{payload.date}: #{Exception.message(exception)}"
        )

        {:error, {:writer_error, Exception.message(exception)}}
    end
  end

  defp safe_run_writer(_, _payload), do: :ok

  defp finalize_results(results) do
    Enum.into(results, %{}, fn {date, entry} ->
      rows =
        cond do
          entry.rows != [] -> entry.rows
          is_list(entry.row_chunks) -> DataHelpers.flatten_row_chunks(entry.row_chunks)
          true -> []
        end

      sanitized =
        entry
        |> Map.put(:rows, rows)
        |> Map.delete(:row_chunks)
        |> Map.delete(:accumulator)

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

  defp handle_writer_result(state, {:halt, reason}) do
    %{state | halt_reason: state.halt_reason || {:halt, reason}}
  end

  defp handle_writer_result(state, {:error, reason}) do
    %{state | halt_reason: state.halt_reason || {:error, reason}}
  end

  defp handle_writer_result(state, {:ok, _meta}), do: state
  defp handle_writer_result(state, _), do: state

  defp handle_writer_down(state, reason) when reason in [:normal, :shutdown, {:shutdown, :normal}],
    do: state

  defp handle_writer_down(state, reason) do
    %{state | halt_reason: state.halt_reason || {:writer_exit, reason}}
  end

  defp pending_writers?(%{writer_refs: refs}) when is_map(refs) do
    map_size(refs) > 0
  end

  defp pending_writers?(_state), do: false

  defp maybe_reply_finalize(%{finalize_from: nil} = state), do: state

  defp maybe_reply_finalize(%{finalize_from: from} = state) do
    if pending_writers?(state) do
      state
    else
      reply = finalize_reply_payload(state)
      emit_metrics(state)
      GenServer.reply(from, reply)
      %{state | finalize_from: nil}
    end
  end

  defp finalize_reply_payload(state) do
    results = finalize_results(state.results)
    total_api_calls = :atomics.get(state.total_api_calls, 1)
    http_batch_calls = :atomics.get(state.http_batch_calls, 1)

    case state.halt_reason do
      nil -> {:ok, nil, results, total_api_calls, http_batch_calls}
      {:halt, reason} -> {:halt, reason, results, total_api_calls, http_batch_calls}
      {:error, reason} -> {:error, reason, results, total_api_calls, http_batch_calls}
    end
  end
end
