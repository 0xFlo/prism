defmodule GscAnalytics.DataSources.GSC.Core.Sync.URLPhase do
  @moduledoc """
  URL fetching and storage phase for sync operations.

  Responsible for filtering already-synced dates, fetching URLs from the
  GSC API, persisting responses, and reporting progress.

  ## Examples

      state =
        GscAnalytics.DataSources.GSC.Core.Sync.State.new(
          1,
          1,
          "sc-domain:example.com",
          [~D[2024-01-01]],
          []
        )
      {results, api_calls, updated_state} =
        URLPhase.fetch_and_store([~D[2024-01-01]], state)
  """

  require Logger

  alias GscAnalytics.DataSources.GSC.Core.{Client, Persistence}
  alias GscAnalytics.DataSources.GSC.Core.Sync.ProgressTracker
  alias GscAnalytics.DataSources.GSC.Support.SyncProgress

  @pause_poll_interval 500

  @doc """
  Fetch and store URLs for the provided `dates`.

  Returns `{url_results, api_calls, updated_state}` where:
    * `url_results` - map of date to %{url_count: integer, success: boolean}
    * `api_calls` - number of API calls executed
    * `updated_state` - state with the current step advanced
  """
  def fetch_and_store(dates, state) do
    maybe_notify_batch(dates)

    client = Application.get_env(:gsc_analytics, :gsc_client, Client)

    Enum.reduce_while(dates, {%{}, 0, state}, fn date, {results_acc, api_acc, state_acc} ->
      case command_status(state_acc.job_id) do
        :stop ->
          {:halt, {results_acc, api_acc, mark_stopped(state_acc)}}

        :pause ->
          case wait_for_resume(state_acc.job_id) do
            :stop ->
              {:halt, {results_acc, api_acc, mark_stopped(state_acc)}}

            :continue ->
              {:cont, {results_acc, api_acc, state_acc}}
          end

        :continue ->
          if skip_date?(date, state_acc) do
            new_state = advance_step_with_skip(state_acc, date)
            {:cont, {results_acc, api_acc, new_state}}
          else
            {result, new_state} = fetch_url_for_date(client, date, state_acc)
            updated_results = Map.put(results_acc, elem(result, 0), elem(result, 1))
            {:cont, {updated_results, api_acc + 1, new_state}}
          end
      end
    end)
    |> case do
      {results, api_calls, updated_state} -> {results, api_calls, updated_state}
      {:halt, {results, api_calls, updated_state}} -> {results, api_calls, updated_state}
    end
  end

  defp skip_date?(date, state) do
    force? = force_option(state.opts)

    not force? and Persistence.day_already_synced?(state.account_id, state.site_url, date)
  end

  defp force_option(opts) when is_list(opts), do: Keyword.get(opts, :force?, false)
  defp force_option(%{} = opts), do: Map.get(opts, :force?, false)
  defp force_option(_), do: false

  defp advance_step_with_skip(state, date) do
    step = state.current_step + 1
    ProgressTracker.report_skipped(state, date)
    %{state | current_step: step}
  end

  defp fetch_url_for_date(client, date, state) do
    step = state.current_step + 1
    ProgressTracker.report_started(state, date)

    result =
      case client.fetch_all_urls_for_date(state.account_id, state.site_url, date) do
        {:ok, response} ->
          handle_success(date, response, state)

        {:error, reason} ->
          handle_error(date, reason, state)
      end

    {result, %{state | current_step: step}}
  end

  defp handle_success(date, response, state) do
    url_count =
      Persistence.process_url_response(
        state.account_id,
        state.site_url,
        date,
        response
      )

    if url_count == 0 do
      Persistence.mark_day_complete(
        state.account_id,
        state.site_url,
        date,
        url_count: 0,
        query_count: 0
      )
    end

    ProgressTracker.report_urls_complete(state, date, url_count, 1)

    {date, %{url_count: url_count, success: true}}
  end

  defp handle_error(date, reason, state) do
    Logger.error("Failed to fetch URLs for #{date}: #{inspect(reason)}")
    ProgressTracker.report_error(state, date, reason)
    {date, %{url_count: 0, success: false}}
  end

  defp command_status(job_id) do
    case SyncProgress.current_command(job_id) do
      :stop -> :stop
      :pause -> :pause
      _ -> :continue
    end
  end

  defp wait_for_resume(job_id) do
    Process.sleep(@pause_poll_interval)

    case SyncProgress.current_command(job_id) do
      :pause -> wait_for_resume(job_id)
      :stop -> :stop
      _ -> :continue
    end
  end

  defp mark_stopped(state) do
    %{
      state
      | halted?: true,
        halt_reason: :stopped_by_user,
        halt_error_message: nil
    }
  end

  defp maybe_notify_batch(dates) do
    case Application.get_env(:gsc_analytics, :fake_client_pid) do
      pid when is_pid(pid) ->
        payload = Enum.map(dates, &{&1, 0})
        send(pid, {:batch, payload})
        :ok

      _ ->
        :ok
    end
  end
end
