defmodule GscAnalytics.DataSources.GSC.Core.Sync.QueryPhase do
  @moduledoc """
  Query fetching and storage phase for sync operations.

  Coordinates with the `QueryPaginator` to stream query data, persists
  responses as they arrive, and handles error/halt scenarios by tracking
  failures in the sync state.

  ## Examples

      state =
        GscAnalytics.DataSources.GSC.Core.Sync.State.new(
          1,
          1,
          "sc-domain:example.com",
          [~D[2024-01-01]],
          []
        )

      url_results = %{~D[2024-01-01] => %{url_count: 10, success: true}}
      {query_results, api_calls, _state} =
        QueryPhase.fetch_and_store([~D[2024-01-01]], url_results, state)
  """

  require Logger

  alias GscAnalytics.DataSources.GSC.Core.{Config, Persistence}
  alias GscAnalytics.DataSources.GSC.Core.Sync.{ProgressTracker, State}
  alias GscAnalytics.DataSources.GSC.Support.QueryPaginator

  @doc """
  Fetch and store queries for the given `dates` based on `url_results`.

  Returns `{query_results, api_calls, updated_state}` where:
    * `query_results` - map of date to result metadata (rows, row_count, etc.)
    * `api_calls` - number of API calls performed
    * `updated_state` - state with failure metadata populated when errors occur
  """
  def fetch_and_store(dates, url_results, state) do
    dates_with_urls = filter_dates_with_urls(dates, url_results)

    if dates_with_urls == [] do
      {attach_query_counts(%{}, state), 0, state}
    else
      fetch_queries(dates_with_urls, state)
    end
  end

  defp filter_dates_with_urls(dates, url_results) do
    Enum.filter(dates, fn date ->
      case Map.get(url_results, date) do
        %{success: success} -> success
        _ -> false
      end
    end)
  end

  defp fetch_queries(dates, state) do
    Logger.info("Fetching queries for #{length(dates)} dates with URLs")

    callback = create_callback(state)

    case QueryPaginator.fetch_all_queries(
           state.account_id,
           state.site_url,
           dates,
           on_complete: callback,
           batch_size: Config.default_batch_size()
         ) do
      {:ok, results, api_calls, _batch_count} ->
        {attach_query_counts(results, state), api_calls, state}

      {:error, reason, partial_results, api_calls, _batch_count} ->
        handle_error(reason, dates, partial_results, api_calls, state)

      {:halt, reason, partial_results, api_calls, _batch_count} ->
        handle_halt(reason, dates, partial_results, api_calls, state)
    end
  end

  defp create_callback(state) do
    fn %{date: date, rows: rows, api_calls: api_calls} = payload ->
      http_batches = Map.get(payload, :http_batches, api_calls)

      query_count =
        Persistence.process_query_response(state.account_id, state.site_url, date, rows)

      Persistence.mark_day_complete(
        state.account_id,
        state.site_url,
        date,
        query_count: query_count
      )

      State.store_query_count(state, date, query_count)

      ProgressTracker.report_queries_complete(
        state,
        date,
        query_count,
        api_calls,
        http_batches
      )

      :continue
    end
  end

  defp handle_error(reason, dates, partial_results, api_calls, state) do
    failure_dates = identify_failed_dates(dates, partial_results)

    mark_failures(failure_dates, reason, state)

    {failure_date, error_message} = select_failure_details(failure_dates, reason)

    updated_state =
      %{
        state
        | halted?: true,
          halt_reason: {:query_fetch_failed, reason},
          halt_error_message: error_message,
          halted_on_date: failure_date || state.halted_on_date
      }
      |> State.add_query_failures(failure_dates)

    results_with_counts = attach_query_counts(partial_results, state)
    {results_with_counts, api_calls, updated_state}
  end

  defp handle_halt(reason, dates, partial_results, api_calls, state) do
    failure_dates = identify_failed_dates(dates, partial_results)

    mark_failures(failure_dates, reason, state)

    {failure_date, error_message} = select_failure_details(failure_dates, reason)

    updated_state =
      %{
        state
        | halted?: true,
          halt_reason: {:query_fetch_halted, reason},
          halt_error_message: error_message,
          halted_on_date: failure_date || state.halted_on_date
      }
      |> State.add_query_failures(failure_dates)

    results_with_counts = attach_query_counts(partial_results, state)
    {results_with_counts, api_calls, updated_state}
  end

  defp identify_failed_dates(dates, partial_results) when is_map(partial_results) do
    failure_dates =
      Enum.filter(dates, fn date ->
        case Map.get(partial_results, date) do
          nil -> true
          %{partial?: true} -> true
          _ -> false
        end
      end)

    if failure_dates == [] do
      dates
    else
      failure_dates
    end
  end

  defp mark_failures([], _reason, _state), do: :ok

  defp mark_failures(dates, reason, state) do
    error_message = format_error(reason)

    Enum.each(dates, fn date ->
      ProgressTracker.report_error(state, date, reason)

      Persistence.mark_day_failed(
        state.account_id,
        state.site_url,
        date,
        error_message
      )
    end)
  end

  defp attach_query_counts(results, state) when is_map(results) do
    counts = State.take_query_counts(state)

    Enum.reduce(counts, results, fn {date, count}, acc ->
      Map.update(acc, date, %{row_count: count}, fn entry ->
        Map.put(entry, :row_count, count)
      end)
    end)
  end

  defp select_failure_details(failure_dates, reason) do
    failure_date =
      failure_dates
      |> Enum.sort()
      |> List.first()

    {failure_date, format_error(reason)}
  end

  defp format_error(reason) when is_atom(reason), do: to_string(reason)
  defp format_error(reason) when is_binary(reason), do: reason

  defp format_error(reason) do
    reason
    |> inspect()
    |> String.slice(0, 160)
  end
end
