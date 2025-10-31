defmodule GscAnalytics.DataSources.GSC.Core.Sync do
  @moduledoc """
  Simplified GSC data synchronization orchestrator.

  This module coordinates the sync process, delegating heavy lifting to:
  - QueryPaginator for pagination management
  - Persistence for data storage
  - SyncProgress for progress tracking

  The sync process fetches data day by day, discovering URLs and their query performance.
  """

  require Logger

  alias GscAnalytics.DataSources.GSC.Core.{Client, Persistence, Config}
  alias GscAnalytics.DataSources.GSC.Support.{QueryPaginator, SyncProgress}
  alias GscAnalytics.DataSources.GSC.Telemetry.AuditLogger

  @pause_poll_interval 500

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Sync GSC data for a date range.

  ## Options
    - `:account_id` - Account ID (default: 1)
    - `:force?` - Force resync even if data exists
    - `:stop_on_empty?` - Stop when empty results threshold reached
    - `:empty_threshold` - Number of empty days before stopping
    - `:leading_empty_grace_days` - Grace period for leading empty results

  ## Examples

      sync_date_range("sc-domain:example.com", ~D[2024-01-01], ~D[2024-01-31])
  """
  def sync_date_range(site_url, start_date, end_date, opts \\ []) do
    account_id = opts[:account_id] || Config.default_account_id()
    start_time = System.monotonic_time(:millisecond)

    Logger.info("Starting GSC sync for #{site_url} from #{start_date} to #{end_date}")

    # Prepare dates (newest first)
    dates =
      start_date
      |> Date.range(end_date)
      |> Enum.to_list()
      |> Enum.reverse()

    # Start progress tracking
    job_id = start_sync_job(account_id, site_url, start_date, end_date, length(dates))

    # Initialize sync state
    state = %{
      job_id: job_id,
      account_id: account_id,
      site_url: site_url,
      dates: dates,
      results: %{},
      empty_streak: 0,
      has_seen_data?: false,
      total_urls: 0,
      total_queries: 0,
      api_calls: 0,
      halted?: false,
      halt_reason: nil,
      current_step: 0,
      total_steps: length(dates),
      opts: opts
    }

    # Execute sync
    final_state = execute_sync(state)

    # Calculate duration and finalize
    duration_ms = System.monotonic_time(:millisecond) - start_time
    finalize_sync(final_state, duration_ms)
  end

  @doc """
  Sync yesterday's GSC data. Useful for daily cron jobs.
  """
  def sync_yesterday(site_url \\ nil, opts \\ []) do
    account_id = opts[:account_id] || Config.default_account_id()
    site_url = site_url || get_default_site_url(account_id)
    target_date = Date.add(Date.utc_today(), -Config.data_delay_days())

    sync_date_range(
      site_url,
      target_date,
      target_date,
      Keyword.put(opts, :account_id, account_id)
    )
  end

  @doc """
  Sync the last N days of GSC data.
  """
  def sync_last_n_days(site_url, days, opts \\ []) when is_integer(days) and days > 0 do
    account_id = opts[:account_id] || Config.default_account_id()
    site_url = site_url || get_default_site_url(account_id)

    end_date = Date.add(Date.utc_today(), -Config.data_delay_days())
    start_date = Date.add(end_date, -(days - 1))

    sync_date_range(site_url, start_date, end_date, Keyword.put(opts, :account_id, account_id))
  end

  @doc """
  Sync as much history as the API will provide.
  Stops when reaching sustained empty results.
  """
  def sync_full_history(site_url, opts \\ []) do
    account_id = opts[:account_id] || Config.default_account_id()
    site_url = site_url || get_default_site_url(account_id)

    end_date = Date.add(Date.utc_today(), -Config.data_delay_days())
    max_days = Keyword.get(opts, :max_days, Config.full_history_days())
    start_date = Date.add(end_date, -(max_days - 1))

    opts =
      opts
      |> Keyword.put(:stop_on_empty?, true)
      |> Keyword.put_new(:empty_threshold, Config.empty_result_limit())
      |> Keyword.put_new(:leading_empty_grace_days, Config.leading_empty_grace_days())

    sync_date_range(site_url, start_date, end_date, Keyword.put(opts, :account_id, account_id))
  end

  # ============================================================================
  # Private - Sync Execution
  # ============================================================================

  defp execute_sync(state) do
    # Process dates in chunks for better progress visibility
    chunk_size = Config.query_scheduler_chunk_size()

    state.dates
    |> Enum.chunk_every(chunk_size, chunk_size, [])
    |> Enum.reduce_while(state, fn chunk, acc ->
      case process_date_chunk(chunk, acc) do
        {:halt, new_state} -> {:halt, new_state}
        {:cont, new_state} -> {:cont, new_state}
      end
    end)
  end

  defp process_date_chunk([], state), do: {:cont, state}

  defp process_date_chunk(dates, state) do
    # Check for user commands (pause/stop)
    case await_continue(state.job_id) do
      :stop ->
        {:halt, %{state | halted?: true, halt_reason: :stopped_by_user}}

      :continue ->
        # Batch fetch URLs for all dates in chunk
        {url_results, url_api_calls, state_after_urls} = batch_fetch_urls(dates, state)

        # Process queries for dates with URLs
        {query_results, query_api_calls} =
          batch_fetch_queries(dates, url_results, state_after_urls)

        # Update state and check halt conditions
        new_state =
          state_after_urls
          |> update_sync_metrics(url_results, query_results, url_api_calls + query_api_calls)
          |> Map.update(:results, %{}, &Map.merge(&1, url_results))
          |> check_empty_threshold(dates)

        if new_state.halted? do
          {:halt, new_state}
        else
          {:cont, new_state}
        end
    end
  end

  defp batch_fetch_urls(dates, state) do
    # Filter dates that need syncing
    dates_to_fetch =
      if state.opts[:force?] do
        dates
      else
        Enum.reject(dates, &Persistence.day_already_synced?(state.account_id, state.site_url, &1))
      end

    if dates_to_fetch == [] do
      # Skip already-synced dates but still track progress
      updated_state =
        Enum.reduce(dates, state, fn date, acc ->
          step = acc.current_step + 1
          report_day_skipped(acc.job_id, date, step)
          %{acc | current_step: step}
        end)

      {%{}, 0, updated_state}
    else
      Logger.info("Fetching URLs for #{length(dates_to_fetch)} dates")

      # Use Client to fetch URLs
      client = Application.get_env(:gsc_analytics, :gsc_client, Client)

      {results, updated_state} =
        dates_to_fetch
        |> Enum.reduce({%{}, state}, fn date, {results_acc, state_acc} ->
          step = state_acc.current_step + 1

          # Notify that we're starting this day
          report_day_started(state_acc.job_id, date, step)

          result =
            case client.fetch_all_urls_for_date(state_acc.account_id, state_acc.site_url, date) do
              {:ok, response} ->
                url_count =
                  Persistence.process_url_response(
                    state_acc.account_id,
                    state_acc.site_url,
                    date,
                    response
                  )

                report_day_progress(state_acc.job_id, date, step, :urls, url_count, 1)
                {date, %{url_count: url_count, success: true}}

              {:error, reason} ->
                Logger.error("Failed to fetch URLs for #{date}: #{inspect(reason)}")
                report_day_error(state_acc.job_id, date, step, reason)
                {date, %{url_count: 0, success: false}}
            end

          new_state = %{state_acc | current_step: step}
          {Map.put(results_acc, elem(result, 0), elem(result, 1)), new_state}
        end)

      api_calls = length(dates_to_fetch)
      {results, api_calls, updated_state}
    end
  end

  defp batch_fetch_queries(_dates, url_results, state) do
    # Only fetch queries for dates with successful URL fetches
    dates_with_urls =
      url_results
      |> Enum.filter(fn {_date, result} -> result.success and result.url_count > 0 end)
      |> Enum.map(&elem(&1, 0))

    if dates_with_urls == [] do
      {%{}, 0}
    else
      Logger.info("Fetching queries for #{length(dates_with_urls)} dates with URLs")

      # Build a date->step mapping for the callback
      date_to_step =
        dates_with_urls
        |> Enum.reduce(%{}, fn date, acc ->
          # Find this date's position in the original dates list
          step =
            Enum.find_index(state.dates, &(&1 == date))
            |> case do
              nil -> state.current_step
              index -> index + 1
            end

          Map.put(acc, date, step)
        end)

      # Create streaming callback for real-time processing
      callback = create_query_callback(state, date_to_step)

      # Use QueryPaginator for paginated fetching
      case QueryPaginator.fetch_all_queries(
             state.account_id,
             state.site_url,
             dates_with_urls,
             on_complete: callback,
             batch_size: Config.default_batch_size()
           ) do
        {:ok, results, api_calls, _batch_count} ->
          {results, api_calls}

        {:error, _reason, partial_results, api_calls, _batch_count} ->
          {partial_results, api_calls}

        {:halt, _reason, partial_results, api_calls, _batch_count} ->
          {partial_results, api_calls}
      end
    end
  end

  defp create_query_callback(state, date_to_step) do
    fn %{date: date, rows: rows, api_calls: api_calls} ->
      # Process queries immediately
      query_count =
        Persistence.process_query_response(state.account_id, state.site_url, date, rows)

      # Update sync day status
      Persistence.mark_day_complete(state.account_id, state.site_url, date)

      # Report progress with step number
      step = Map.get(date_to_step, date, 0)
      report_day_progress(state.job_id, date, step, :queries, query_count, api_calls)

      :continue
    end
  end

  defp update_sync_metrics(state, url_results, query_results, api_calls) do
    total_urls =
      url_results
      |> Map.values()
      |> Enum.map(& &1.url_count)
      |> Enum.sum()

    total_queries =
      query_results
      |> Map.values()
      |> Enum.map(&length(&1.rows || []))
      |> Enum.sum()

    %{
      state
      | total_urls: state.total_urls + total_urls,
        total_queries: state.total_queries + total_queries,
        api_calls: state.api_calls + api_calls,
        has_seen_data?: state.has_seen_data? or total_urls > 0
    }
  end

  defp check_empty_threshold(state, dates) do
    # Track consecutive empty dates, finding the date where we hit the threshold
    # Dates are processed newest-first in the list
    {new_streak, threshold_date} =
      Enum.reduce(dates, {state.empty_streak, nil}, fn date, {streak, threshold_acc} ->
        url_result = Map.get(state.results, date, %{url_count: 0})

        if url_result.url_count == 0 do
          # Empty date: increment streak
          new_streak_val = streak + 1
          empty_threshold = Keyword.get(state.opts, :empty_threshold, 0)

          # Track the date where we first hit the threshold (if not already set)
          new_threshold_date =
            if threshold_acc == nil and new_streak_val >= empty_threshold and empty_threshold > 0 do
              date
            else
              threshold_acc
            end

          {new_streak_val, new_threshold_date}
        else
          # Date with data: reset streak
          {0, nil}
        end
      end)

    # Check if we should halt (after processing all dates in chunk)
    should_halt? =
      Keyword.get(state.opts, :stop_on_empty?, false) and
        new_streak >= Keyword.get(state.opts, :empty_threshold, 0) and
        (state.has_seen_data? or
           map_size(state.results) >= Keyword.get(state.opts, :leading_empty_grace_days, 0))

    if should_halt? do
      %{
        state
        | empty_streak: new_streak,
          halted?: true,
          halt_reason: {:empty_threshold, threshold_date || List.last(dates)}
      }
    else
      %{state | empty_streak: new_streak}
    end
  end

  defp await_continue(job_id) do
    case SyncProgress.current_command(job_id) do
      :stop ->
        :stop

      :pause ->
        Process.sleep(@pause_poll_interval)
        await_continue(job_id)

      _ ->
        :continue
    end
  end

  # ============================================================================
  # Private - Progress Tracking
  # ============================================================================

  defp start_sync_job(account_id, site_url, start_date, end_date, total_steps) do
    SyncProgress.start_job(%{
      account_id: account_id,
      site_url: site_url,
      start_date: start_date,
      end_date: end_date,
      total_steps: total_steps
    })
  end

  defp report_day_started(job_id, date, step) do
    SyncProgress.day_started(job_id, %{
      date: date,
      step: step
    })
  end

  defp report_day_progress(job_id, date, step, type, count, api_calls) do
    SyncProgress.day_completed(job_id, %{
      date: date,
      step: step,
      status: :ok,
      urls: if(type == :urls, do: count, else: 0),
      rows: if(type == :queries, do: count, else: 0),
      query_batches: if(type == :queries, do: api_calls, else: 0),
      url_requests: if(type == :urls, do: api_calls, else: 0),
      api_calls: api_calls
    })
  end

  defp report_day_error(job_id, date, step, reason) do
    SyncProgress.day_completed(job_id, %{
      date: date,
      step: step,
      status: :error,
      message: format_error(reason)
    })
  end

  defp report_day_skipped(job_id, date, step) do
    SyncProgress.day_completed(job_id, %{
      date: date,
      step: step,
      status: :skipped
    })
  end

  defp finalize_sync(state, duration_ms) do
    status =
      cond do
        state.halt_reason == :stopped_by_user -> :cancelled
        state.halt_reason -> :completed_with_warnings
        true -> :completed
      end

    # Extract halt_reason and halt_on from tuple if present
    {halt_reason, halt_on} =
      case state.halt_reason do
        {:empty_threshold, date} -> {:empty_threshold, date}
        other -> {other, nil}
      end

    summary = %{
      days_processed: map_size(state.results),
      total_urls: state.total_urls,
      total_queries: state.total_queries,
      api_calls: state.api_calls,
      duration_ms: duration_ms,
      halt_reason: halt_reason,
      halt_on: halt_on
    }

    # Log audit event
    AuditLogger.log_sync_complete(
      %{
        total_api_calls: state.api_calls,
        total_urls: state.total_urls,
        total_query_rows: state.total_queries,
        duration_ms: duration_ms
      },
      %{
        site_url: state.site_url,
        start_date: List.last(state.dates) |> Date.to_iso8601(),
        end_date: List.first(state.dates) |> Date.to_iso8601()
      }
    )

    # Update progress tracker
    SyncProgress.finish_job(state.job_id, %{
      status: status,
      summary: summary
    })

    {:ok, summary}
  end

  # ============================================================================
  # Private - Utilities
  # ============================================================================

  defp get_default_site_url(account_id) do
    case GscAnalytics.DataSources.GSC.Accounts.default_property(account_id) do
      {:ok, property} ->
        property

      {:error, reason} ->
        Logger.warning(
          "Falling back to example.com for account #{account_id}; missing property (#{inspect(reason)})"
        )

        "sc-domain:example.com"
    end
  end

  defp format_error(reason) when is_atom(reason), do: to_string(reason)
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason) |> String.slice(0, 160)
end
