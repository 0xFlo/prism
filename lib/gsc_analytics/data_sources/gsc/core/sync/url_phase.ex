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

  alias GscAnalytics.DataSources.GSC.Core.{Client, Config, Persistence}
  alias GscAnalytics.DataSources.GSC.Core.Sync.ProgressTracker
  alias GscAnalytics.DataSources.GSC.Support.{PipelineRetry, URLPipeline}
  alias GscAnalytics.DataSources.GSC.Support.SyncProgress

  @pause_poll_interval 500

  @doc """
  Fetch and store URLs for the provided `dates`.

  Returns `{url_results, api_calls, updated_state}` where:
    * `url_results` - map of date to %{url_count: integer, success: boolean}
    * `api_calls` - number of API calls executed
    * `updated_state` - state with the current step advanced
  """
  def fetch_and_store([], state), do: {%{}, 0, state}

  def fetch_and_store(dates, state) do
    maybe_notify_batch(dates)

    client = Application.get_env(:gsc_analytics, :gsc_client, Client)

    max_concurrency =
      [
        Config.max_concurrency(),
        Config.url_phase_max_concurrency(),
        length(dates)
      ]
      |> Enum.min()
      |> max(1)

    {results, api_calls, updated_state} =
      URLPipeline.run(dates,
        state: state,
        client: client,
        max_concurrency: max_concurrency
      )

    {results, api_calls, updated_state}
  end

  @doc false
  def skip_date?(date, state) do
    force? = force_option(state.opts)

    not force? and Persistence.day_already_synced?(state.account_id, state.site_url, date)
  end

  defp force_option(opts) when is_list(opts), do: Keyword.get(opts, :force?, false)
  defp force_option(%{} = opts), do: Map.get(opts, :force?, false)
  defp force_option(_), do: false

  @doc false
  def advance_step_with_skip(state, date) do
    step = state.current_step + 1
    ProgressTracker.report_skipped(state, date)
    %{state | current_step: step}
  end

  @doc false
  def fetch_url_for_date(client, date, state) do
    step = state.current_step + 1
    ProgressTracker.report_started(state, date)

    fetch_fun = fn ->
      client.fetch_all_urls_for_date(state.account_id, state.site_url, date)
    end

    case PipelineRetry.retry(fetch_fun, Config.max_retries(), Config.retry_delay()) do
      {:ok, response} ->
        result = handle_success(date, response, state)
        {:ok, {result, %{state | current_step: step}}}

      {:error, reason} ->
        result = handle_error(date, reason, state)
        {:error, reason, {result, %{state | current_step: step}}}
    end
  end

  defp handle_success(date, response, state) do
    # Use defer_refresh to collect URLs for batch processing later
    {url_count, urls} =
      case Persistence.process_url_response(
             state.account_id,
             state.site_url,
             date,
             response,
             defer_refresh: true
           ) do
        {count, url_list} when is_integer(count) and is_list(url_list) ->
          {count, url_list}

        count when is_integer(count) ->
          # Backward compatibility if defer_refresh is not supported
          {count, []}
      end

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

    {date, %{url_count: url_count, success: true, urls: urls}}
  end

  defp handle_error(date, reason, state) do
    Logger.error("Failed to fetch URLs for #{date}: #{inspect(reason)}")
    ProgressTracker.report_error(state, date, reason)
    {date, %{url_count: 0, success: false}}
  end

  @doc false
  def command_status(job_id) do
    case SyncProgress.current_command(job_id) do
      :stop -> :stop
      :pause -> :pause
      _ -> :continue
    end
  end

  @doc false
  def wait_for_resume(job_id) do
    Process.sleep(@pause_poll_interval)

    case SyncProgress.current_command(job_id) do
      :pause -> wait_for_resume(job_id)
      :stop -> :stop
      _ -> :continue
    end
  end

  @doc false
  def mark_stopped(state) do
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
