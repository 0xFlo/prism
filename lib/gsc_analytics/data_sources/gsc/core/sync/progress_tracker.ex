defmodule GscAnalytics.DataSources.GSC.Core.Sync.ProgressTracker do
  @moduledoc """
  Centralized progress tracking for sync operations.

  Wraps `SyncProgress` with consistent step lookup based on `SyncState`
  and provides helpers to report day-level events and build the final
  summary payload.

  ## Examples

      job_id =
        ProgressTracker.start_job(
          1,
          "sc-domain:example.com",
          ~D[2024-01-01],
          ~D[2024-01-07],
          7
        )

      state = SyncState.new(job_id, 1, "sc-domain:example.com", [~D[2024-01-01]], [])
      ProgressTracker.report_started(state, ~D[2024-01-01])
      ProgressTracker.report_urls_complete(state, ~D[2024-01-01], 50, 1)
      ProgressTracker.report_queries_complete(state, ~D[2024-01-01], 120, 2, 1)
      summary = ProgressTracker.finish_job(state, 1_250)
  """

  alias GscAnalytics.DataSources.GSC.Core.Sync.State, as: SyncState
  alias GscAnalytics.DataSources.GSC.Support.SyncProgress

  @doc "Start a new sync job and return the job identifier."
  def start_job(account_id, site_url, start_date, end_date, total_steps) do
    SyncProgress.start_job(%{
      account_id: account_id,
      site_url: site_url,
      start_date: start_date,
      end_date: end_date,
      total_steps: total_steps
    })
  end

  @doc "Report that a day's processing has started."
  def report_started(state, date) do
    step = SyncState.get_step(state, date)

    SyncProgress.day_started(state.job_id, %{
      date: date,
      step: step
    })
  end

  @doc "Report URL fetch completion for a day."
  def report_urls_complete(state, date, url_count, api_calls) do
    step = SyncState.get_step(state, date)

    SyncProgress.day_completed(state.job_id, %{
      date: date,
      step: step,
      status: :ok,
      urls: url_count,
      rows: 0,
      query_batches: 0,
      query_sub_requests: 0,
      url_requests: api_calls,
      api_calls: api_calls
    })
  end

  @doc "Report query fetch completion for a day."
  def report_queries_complete(state, date, query_count, api_calls, http_batches) do
    step = SyncState.get_step(state, date)

    SyncProgress.day_completed(state.job_id, %{
      date: date,
      step: step,
      status: :ok,
      urls: 0,
      rows: query_count,
      query_batches: http_batches,
      query_sub_requests: api_calls,
      url_requests: 0,
      api_calls: api_calls
    })
  end

  @doc "Report an error for a day."
  def report_error(state, date, reason) do
    step = SyncState.get_step(state, date)

    SyncProgress.day_completed(state.job_id, %{
      date: date,
      step: step,
      status: :error,
      message: format_error(reason)
    })
  end

  @doc "Report that a day was skipped."
  def report_skipped(state, date) do
    step = SyncState.get_step(state, date)

    SyncProgress.day_completed(state.job_id, %{
      date: date,
      step: step,
      status: :skipped
    })
  end

  @doc """
  Finish the sync job and return the summary that was reported.
  """
  def finish_job(state, duration_ms) do
    status = determine_status(state)
    {halt_reason, halt_on_from_reason} = extract_halt_details(state.halt_reason)
    halt_on = halt_on_from_reason || state.halted_on_date
    error_message = select_error_message(status, state)
    failed_on = if status == :failed, do: halt_on, else: nil

    processed_days = count_processed_days(state, halt_on)

    summary = %{
      days_processed: processed_days,
      total_urls: state.total_urls,
      total_queries: state.total_queries,
      total_rows: state.total_queries,
      total_query_http_batches: state.total_query_http_batches,
      total_query_sub_requests: state.total_query_sub_requests,
      api_calls: state.api_calls,
      duration_ms: duration_ms,
      halt_reason: halt_reason,
      halt_on: halt_on,
      failed_on: failed_on,
      error: error_message
    }

    SyncProgress.finish_job(state.job_id, %{
      status: status,
      summary: summary,
      error: error_message
    })

    {status, summary}
  end

  defp determine_status(state) do
    cond do
      state.halt_reason == :stopped_by_user -> :cancelled
      match?({:query_fetch_failed, _}, state.halt_reason) -> :failed
      state.halt_reason -> :completed_with_warnings
      true -> :completed
    end
  end

  defp extract_halt_details({:empty_threshold, date}), do: {:empty_threshold, date}
  defp extract_halt_details(reason), do: {reason, nil}

  defp select_error_message(:failed, state) do
    state.halt_error_message || format_error(state.halt_reason)
  end

  defp select_error_message(_status, _state), do: nil

  defp format_error(reason) when is_atom(reason), do: to_string(reason)
  defp format_error(reason) when is_binary(reason), do: reason

  defp format_error(reason) do
    reason
    |> inspect()
    |> String.slice(0, 160)
  end

  defp count_processed_days(state, halt_on) do
    cond do
      match?({:empty_threshold, _}, state.halt_reason) and halt_on ->
        state.dates
        |> Enum.reduce_while(0, fn date, acc ->
          acc = if Map.has_key?(state.results, date), do: acc + 1, else: acc

          if Date.compare(date, halt_on) == :eq do
            {:halt, acc}
          else
            {:cont, acc}
          end
        end)

      true ->
        map_size(state.results)
    end
  end
end
