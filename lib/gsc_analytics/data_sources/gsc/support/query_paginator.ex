defmodule GscAnalytics.DataSources.GSC.Support.QueryPaginator do
  @moduledoc """
  Manages paginated query fetching with ordered result processing.

  This module consolidates pagination logic that was previously spread across
  QueryScheduler, StreamCoordinator, and Pagination modules. It handles:

  - Pagination queue management for multiple dates
  - Ordered result processing to maintain consistency
  - Streaming callbacks for real-time data processing
  - Automatic page size calculation and next page detection
  """

  require Logger
  alias MapSet

  alias GscAnalytics.DataSources.GSC.Core.Config

  alias GscAnalytics.DataSources.GSC.Support.{
    ConcurrentBatchWorker,
    QueryCoordinator,
    RateLimiter
  }

  @page_size 25_000
  @default_batch_size 8
  @agent_timeout 5_000

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Fetch all queries for multiple dates with automatic pagination.

  ## Options

    - `:batch_size` - Number of concurrent requests (default: 8)
    - `:on_complete` - Callback function for streaming results
    - `:dimensions` - Query dimensions (default: ["page", "query"])
    - `:operation` - Operation name for logging
    - `:client` - Client module to use
    - `:max_concurrency` - Number of concurrent workers (default: Config.max_concurrency/0)
    - `:max_queue_size` / `:max_in_flight` - Coordinator backpressure limits
    - `:rate_limiter` - Module implementing `check_rate/3` (default: RateLimiter)

  ## Returns

    - `{:ok, results_map, total_api_calls, http_batch_count}` - Success
    - `{:error, reason, partial_results, api_calls, batch_count}` - Failure with partial data
    - `{:halt, reason, partial_results, api_calls, batch_count}` - User-initiated halt
  """
  @spec fetch_all_queries(pos_integer(), String.t(), [Date.t()], keyword()) ::
          {:ok, map(), non_neg_integer(), non_neg_integer()}
          | {:error, term(), map(), non_neg_integer(), non_neg_integer()}
          | {:halt, term(), map(), non_neg_integer(), non_neg_integer()}
  def fetch_all_queries(account_id, site_url, dates, opts \\ [])

  def fetch_all_queries(_account_id, _site_url, [], _opts) do
    {:ok, %{}, 0, 0}
  end

  def fetch_all_queries(account_id, site_url, dates, opts) when is_list(dates) do
    opts = Keyword.put_new(opts, :batch_size, @default_batch_size)
    max_concurrency = Keyword.get(opts, :max_concurrency, Config.max_concurrency())

    if max_concurrency <= 1 do
      fetch_all_queries_sequential(account_id, site_url, dates, opts)
    else
      fetch_all_queries_concurrent(account_id, site_url, dates, opts, max_concurrency)
    end
  end

  defp fetch_all_queries_sequential(account_id, site_url, dates, opts) do
    batch_size = Keyword.fetch!(opts, :batch_size)
    client = Keyword.get(opts, :client, client_module())
    operation = Keyword.get(opts, :operation, "fetch_all_queries_batch")
    dimensions = Keyword.get(opts, :dimensions, ["page", "query"])
    on_complete = Keyword.get(opts, :on_complete)

    initial_state = %{
      queue: :queue.from_list(Enum.map(dates, &{&1, 0})),
      results:
        Map.new(dates, fn date ->
          {date,
           %{
             rows: [],
             row_chunks: [],
             api_calls: 0,
             partial?: false,
             http_batches: 0
           }}
        end),
      completed: MapSet.new(),
      total_api_calls: 0,
      http_batch_calls: 0,
      on_complete: on_complete
    }

    do_paginated_fetch(
      account_id,
      site_url,
      batch_size,
      client,
      operation,
      dimensions,
      initial_state
    )
  end

  defp fetch_all_queries_concurrent(account_id, site_url, dates, opts, max_concurrency) do
    batch_size = Keyword.fetch!(opts, :batch_size)
    client = Keyword.get(opts, :client, client_module())
    operation = Keyword.get(opts, :operation, "fetch_all_queries_batch")
    dimensions = Keyword.get(opts, :dimensions, ["page", "query"])
    on_complete = Keyword.get(opts, :on_complete)
    rate_limiter = Keyword.get(opts, :rate_limiter, RateLimiter)

    coordinator_opts = [
      account_id: account_id,
      site_url: site_url,
      dates: dates,
      on_complete: on_complete,
      max_queue_size: Keyword.get(opts, :max_queue_size, Config.max_queue_size()),
      max_in_flight: Keyword.get(opts, :max_in_flight, Config.max_in_flight())
    ]

    with {:ok, coordinator} <- QueryCoordinator.start_link(coordinator_opts) do
      worker_opts = [
        account_id: account_id,
        site_url: site_url,
        operation: operation,
        dimensions: dimensions,
        batch_size: batch_size,
        max_concurrency: max_concurrency,
        client: client,
        rate_limiter: rate_limiter
      ]

      case await_worker_tasks(ConcurrentBatchWorker.start_workers(coordinator, worker_opts)) do
        :ok ->
          finalize_concurrent(coordinator)

        {:error, reason} ->
          QueryCoordinator.halt(coordinator, {:worker_exit, reason})
          finalize_concurrent(coordinator)
      end
    else
      {:error, reason} ->
        {:error, reason, %{}, 0, 0}
    end
  end

  defp finalize_concurrent(coordinator) do
    try do
      coordinator
      |> QueryCoordinator.finalize()
      |> format_coordinator_result()
    after
      GenServer.stop(coordinator, :normal)
    end
  end

  defp await_worker_tasks(tasks) do
    try do
      Task.await_many(tasks, :infinity)
      :ok
    catch
      :exit, reason ->
        {:error, reason}
    after
      Enum.each(tasks, &Task.shutdown(&1, :brutal_kill))
    end
  end

  defp format_coordinator_result({:ok, _reason, results, total_calls, http_batches}) do
    {:ok, results, total_calls, http_batches}
  end

  defp format_coordinator_result({:halt, reason, results, total_calls, http_batches}) do
    {:halt, reason, results, total_calls, http_batches}
  end

  defp format_coordinator_result({:error, reason, results, total_calls, http_batches}) do
    {:error, reason, results, total_calls, http_batches}
  end

  @doc """
  Create a streaming callback for ordered result processing.

  This creates a callback function that:
  1. Writes query data to the database immediately
  2. Maintains proper ordering of results across dates
  3. Handles halt conditions gracefully

  ## Parameters

    - `initial_state` - Initial sync state
    - `entries` - List of entries to process
    - `context` - Sync context with account_id, site_url, finalize_fn
    - `persistence_module` - Module for data persistence

  ## Returns

    A callback function suitable for use with `fetch_all_queries/4`'s `:on_complete` option.
  """
  @spec create_streaming_callback(map(), list(), map(), module()) :: function()
  def create_streaming_callback(initial_state, entries, context, persistence_module) do
    # Start coordinator agent for ordered processing
    {:ok, coordinator} = start_coordinator(initial_state, entries)

    fn %{date: date, rows: rows, api_calls: api_calls, partial?: partial?} ->
      try do
        callback_start = System.monotonic_time(:millisecond)

        # Write to DB immediately (outside agent)
        query_count =
          persistence_module.process_queries_response(
            context.account_id,
            context.site_url,
            date,
            rows
          )

        db_write_duration = System.monotonic_time(:millisecond) - callback_start

        Logger.debug(
          "Query callback for #{date}: wrote #{query_count} rows in #{db_write_duration}ms"
        )

        # Get entry info for sync status
        entry = Map.get(entries, date)

        if entry do
          persistence_module.upsert_sync_day(
            context.account_id,
            context.site_url,
            date,
            :complete,
            url_count: entry.url_count
          )
        end

        # Coordinate ordering with agent
        agent_start = System.monotonic_time(:millisecond)

        query_info = %{
          query_count: query_count,
          api_calls: api_calls,
          partial?: partial?
        }

        result = process_completed_date(coordinator, date, query_info, context.finalize_fn)

        agent_duration = System.monotonic_time(:millisecond) - agent_start

        if agent_duration > 1_000 do
          Logger.warning("Slow agent coordination for #{date}: took #{agent_duration}ms")
        end

        case result do
          {:continue, _} -> :continue
          {:halt, reason} -> {:halt, reason}
        end
      rescue
        error ->
          Logger.error("Query callback crashed for #{date}: #{inspect(error)}")
          {:halt, {:callback_crash, Exception.message(error)}}
      after
        # Clean up coordinator if needed
        if Process.alive?(coordinator), do: Agent.stop(coordinator, :normal, 100)
      end
    end
  end

  @doc """
  Check if we need to fetch the next page of results.
  """
  @spec needs_next_page?(list()) :: boolean()
  def needs_next_page?(rows) when is_list(rows), do: length(rows) >= @page_size

  @doc """
  Calculate the next starting row offset for pagination.
  """
  @spec next_start_row(non_neg_integer()) :: non_neg_integer()
  def next_start_row(current_start_row)
      when is_integer(current_start_row) and current_start_row >= 0 do
    current_start_row + @page_size
  end

  @doc """
  Get the configured page size for GSC API requests.
  """
  @spec page_size() :: pos_integer()
  def page_size, do: @page_size

  # ============================================================================
  # Private - Pagination Loop
  # ============================================================================

  defp do_paginated_fetch(
         account_id,
         site_url,
         batch_size,
         client,
         operation,
         dimensions,
         %{queue: queue} = state
       ) do
    if :queue.is_empty(queue) do
      # All done, finalize results
      {:ok, finalize_results(state), state.total_api_calls, state.http_batch_calls}
    else
      # Get next batch of requests
      {batch, remaining_queue} = take_batch(state.queue, batch_size, state.completed, [])

      if batch == [] do
        # No more work
        {:ok, finalize_results(state), state.total_api_calls, state.http_batch_calls}
      else
        # Log pagination info
        log_batch_info(batch)

        # Build and execute batch requests
        requests = build_batch_requests(site_url, batch, operation, dimensions)

        case client.fetch_query_batch(account_id, requests, operation) do
          {:ok, responses, batch_count} ->
            updated_state = %{state | http_batch_calls: state.http_batch_calls + batch_count}

            case handle_batch_responses(batch, responses, updated_state, remaining_queue) do
              {:ok, new_state} ->
                # Continue pagination
                do_paginated_fetch(
                  account_id,
                  site_url,
                  batch_size,
                  client,
                  operation,
                  dimensions,
                  new_state
                )

              {:halt, reason, new_state} ->
                {:halt, reason, finalize_results(new_state), new_state.total_api_calls,
                 new_state.http_batch_calls}

              {:error, reason, new_state} ->
                {:error, reason, finalize_results(new_state), new_state.total_api_calls,
                 new_state.http_batch_calls}
            end

          {:error, reason} ->
            {:error, reason, finalize_results(state), state.total_api_calls,
             state.http_batch_calls}
        end
      end
    end
  end

  defp take_batch(queue, batch_size, _completed, acc) when length(acc) >= batch_size do
    {Enum.reverse(acc), queue}
  end

  defp take_batch(queue, batch_size, completed, acc) do
    case :queue.out(queue) do
      {:empty, _} ->
        {Enum.reverse(acc), queue}

      {{:value, {date, start_row}}, rest} ->
        if MapSet.member?(completed, date) do
          take_batch(rest, batch_size, completed, acc)
        else
          take_batch(rest, batch_size, completed, [{date, start_row} | acc])
        end
    end
  end

  defp build_batch_requests(site_url, batch, operation, dimensions) do
    encoded_site = URI.encode_www_form(site_url)
    path = "/webmasters/v3/sites/#{encoded_site}/searchAnalytics/query"

    Enum.map(batch, fn {date, start_row} ->
      date_string = Date.to_iso8601(date)

      %{
        id: request_id(date, start_row),
        site_url: site_url,
        method: :post,
        path: path,
        body: %{
          "startDate" => date_string,
          "endDate" => date_string,
          "dimensions" => dimensions,
          "rowLimit" => @page_size,
          "startRow" => start_row,
          "dataState" => "final"
        },
        metadata: %{date: date_string, start_row: start_row, operation: operation}
      }
    end)
  end

  defp handle_batch_responses(batch, responses, state, remaining_queue) do
    response_map = Map.new(responses, fn part -> {part.id, part} end)

    state_with_batches = increment_http_batches(state, batch)

    Enum.reduce_while(batch, {:ok, %{state_with_batches | queue: remaining_queue}}, fn {date,
                                                                                        start_row},
                                                                                       {:ok,
                                                                                        acc_state} ->
      id = request_id(date, start_row)

      case Map.fetch(response_map, id) do
        {:ok, part} ->
          if part.status >= 400 do
            {:halt,
             {:error, {:batch_response_error, date, part.status, part.raw_body}, acc_state}}
          else
            process_successful_response(date, start_row, part, acc_state)
          end

        :error ->
          {:halt, {:error, {:missing_response, id}, acc_state}}
      end
    end)
  end

  defp process_successful_response(date, start_row, part, state) do
    rows = extract_rows(part)
    needs_next = needs_next_page?(rows)
    api_calls = state.total_api_calls + 1
    result_entry = Map.fetch!(state.results, date)

    # Log pagination decision
    log_pagination_decision(date, start_row, rows, needs_next, result_entry)

    # Update result entry
    updated_entry =
      result_entry
      |> Map.update!(:row_chunks, fn chunks -> [rows | chunks] end)
      |> Map.put(:api_calls, result_entry.api_calls + 1)

    # Update queue if more pages needed
    queue =
      if needs_next do
        next = next_start_row(start_row)
        :queue.in({date, next}, state.queue)
      else
        state.queue
      end

    # Mark date as completed if no more pages
    completed =
      if needs_next do
        state.completed
      else
        MapSet.put(state.completed, date)
      end

    # Handle completion callback if date is done
    case maybe_emit_completion(state, date, updated_entry, needs_next) do
      {:continue, next_state, entry_after} ->
        {:cont,
         {:ok,
          %{
            next_state
            | results: Map.put(next_state.results, date, entry_after),
              queue: queue,
              completed: completed,
              total_api_calls: api_calls
          }}}

      {:halt, reason, next_state, entry_after} ->
        updated =
          %{
            next_state
            | results: Map.put(next_state.results, date, entry_after),
              queue: queue,
              completed: completed,
              total_api_calls: api_calls
          }

        {:halt, {:halt, reason, updated}}
    end
  end

  defp maybe_emit_completion(state, _date, entry, true = _needs_next_page) do
    {:continue, state, entry}
  end

  defp maybe_emit_completion(state, date, entry, false = _needs_next_page) do
    rows = entry.row_chunks |> Enum.reverse() |> Enum.flat_map(& &1)
    row_count = length(rows)
    entry_with_count = Map.put(entry, :row_count, row_count)

    case state.on_complete do
      nil ->
        # No callback, just finalize the entry
        finalized_entry =
          entry_with_count
          |> Map.put(:rows, rows)
          |> Map.put(:row_count, row_count)
          |> Map.put(:row_chunks, [])

        {:continue, state, finalized_entry}

      callback when is_function(callback, 1) ->
        # Invoke callback with completed data
        payload = %{
          date: date,
          rows: rows,
          api_calls: entry.api_calls,
          partial?: entry.partial?,
          row_count: row_count,
          http_batches: Map.get(entry, :http_batches, 0)
        }

        case safe_invoke_callback(callback, payload) do
          {:halt, reason} ->
            minimized_entry = minimize_entry(entry_with_count)
            {:halt, reason, state, minimized_entry}

          :continue ->
            minimized_entry = minimize_entry(entry_with_count)
            {:continue, state, minimized_entry}
        end
    end
  end

  defp safe_invoke_callback(fun, payload) do
    try do
      case fun.(payload) do
        {:halt, reason} -> {:halt, reason}
        _ -> :continue
      end
    rescue
      exception ->
        {:halt, {:callback_error, Exception.message(exception)}}
    end
  end

  defp minimize_entry(entry) do
    entry
    |> Map.put(:rows, [])
    |> Map.put(:row_chunks, [])
  end

  defp finalize_results(%{results: results}) do
    results
    |> Enum.map(fn {date, entry} ->
      rows =
        case entry do
          %{rows: rows} when rows != [] ->
            rows

          %{row_chunks: chunks} when is_list(chunks) ->
            chunks
            |> Enum.reverse()
            |> Enum.flat_map(& &1)

          _ ->
            []
        end

      sanitized =
        entry
        |> Map.put(:rows, rows)
        |> Map.delete(:row_chunks)

      {date, sanitized}
    end)
    |> Map.new()
  end

  # ============================================================================
  # Private - Coordinator Agent
  # ============================================================================

  defp start_coordinator(initial_state, entries) do
    entries_by_date = Map.new(entries, &{&1.date, &1})
    dates_in_order = Enum.map(entries, & &1.date)

    Agent.start(fn ->
      %{
        state: initial_state,
        entries: entries_by_date,
        halted?: false,
        halt_reason: nil,
        remaining_dates: dates_in_order
      }
    end)
  end

  defp process_completed_date(agent, date, query_info, finalize_fn) do
    Agent.get_and_update(
      agent,
      fn acc ->
        cond do
          # Already halted
          acc.halted? ->
            {{:halt, acc.halt_reason || :halted}, acc}

          # This is the next date in order - process it
          List.first(acc.remaining_dates) == date ->
            process_next_date_in_order(acc, date, query_info, finalize_fn)

          # Not the next date - buffer it
          true ->
            {{:continue, nil}, acc}
        end
      end,
      @agent_timeout
    )
  end

  defp process_next_date_in_order(acc, date, query_info, finalize_fn) do
    entry = Map.fetch!(acc.entries, date)

    case finalize_fn.(entry, query_info, acc.state) do
      {:ok, new_state} ->
        {{:continue, nil},
         %{
           acc
           | state: new_state,
             entries: Map.delete(acc.entries, date),
             remaining_dates: tl(acc.remaining_dates)
         }}

      {:halt, new_state} ->
        halt_reason = Map.get(new_state, :halt_reason, :halted)

        {{:halt, halt_reason},
         %{
           acc
           | state: new_state,
             entries: Map.delete(acc.entries, date),
             remaining_dates: tl(acc.remaining_dates),
             halted?: true,
             halt_reason: halt_reason
         }}
    end
  end

  # ============================================================================
  # Private - Utilities
  # ============================================================================

  defp extract_rows(%{body: %{"rows" => rows}}) when is_list(rows), do: rows
  defp extract_rows(_), do: []

  defp request_id(date, start_row) do
    Date.to_iso8601(date) <> ":" <> Integer.to_string(start_row)
  end

  defp client_module do
    Application.get_env(:gsc_analytics, :gsc_client, GscAnalytics.DataSources.GSC.Core.Client)
  end

  defp log_batch_info(batch) do
    pagination_requests = Enum.filter(batch, fn {_date, start_row} -> start_row > 0 end)

    if pagination_requests != [] do
      Logger.debug(
        "Batch includes #{length(pagination_requests)} pagination requests: #{inspect(pagination_requests)}"
      )
    end
  end

  defp log_pagination_decision(date, start_row, rows, needs_next, result_entry) do
    if needs_next do
      next_start = next_start_row(start_row)

      Logger.info(
        "Pagination triggered for #{date}: fetched #{length(rows)} rows at offset #{start_row}, " <>
          "queuing next page at offset #{next_start}"
      )
    else
      total_rows = result_entry.row_chunks |> Enum.flat_map(& &1) |> length()
      total_rows = total_rows + length(rows)

      Logger.debug(
        "Pagination complete for #{date}: fetched #{length(rows)} rows at offset #{start_row}, " <>
          "total #{total_rows} rows across #{result_entry.api_calls + 1} pages"
      )
    end
  end

  defp increment_http_batches(state, batch) do
    unique_dates =
      batch
      |> Enum.map(&elem(&1, 0))
      |> MapSet.new()

    updated_results =
      Enum.reduce(unique_dates, state.results, fn date, acc ->
        Map.update(
          acc,
          date,
          %{
            rows: [],
            row_chunks: [],
            api_calls: 0,
            partial?: false,
            http_batches: 1
          },
          fn entry ->
            Map.update(entry, :http_batches, 1, &(&1 + 1))
          end
        )
      end)

    %{state | results: updated_results}
  end
end
