defmodule GscAnalytics.Crawler.ProgressTracker do
  @moduledoc """
  GenServer for tracking HTTP status check progress in real-time.

  This module maintains state for ongoing check operations and broadcasts
  progress updates via Phoenix PubSub for LiveView integration.

  ## Features
  - Real-time progress tracking
  - PubSub broadcasts for LiveView updates
  - Check history maintenance
  - Status breakdown (2xx, 3xx, 4xx, 5xx)

  ## PubSub Events

  Subscribe to `"crawler:progress"` to receive these events:

  - `{:crawler_progress, %{type: :started, job: %{...}}}`
  - `{:crawler_progress, %{type: :update, job: %{...}}}`
  - `{:crawler_progress, %{type: :finished, job: %{...}, stats: %{...}}}`
  """

  use GenServer

  require Logger

  @pubsub_topic "crawler:progress"
  @history_limit 50

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Subscribe to crawler progress events via PubSub.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(GscAnalytics.PubSub, @pubsub_topic)
  end

  @doc """
  Start a new check operation.
  """
  def start_check(total_urls) do
    GenServer.call(__MODULE__, {:start_check, total_urls})
  end

  @doc """
  Update progress with a check result.
  """
  def update_progress(result) do
    GenServer.cast(__MODULE__, {:update_progress, result})
  end

  @doc """
  Finish the current check operation.
  """
  def finish_check(stats) do
    GenServer.call(__MODULE__, {:finish_check, stats})
  end

  @doc """
  Get the current check job.
  """
  def get_current_job do
    GenServer.call(__MODULE__, :get_current_job)
  end

  @doc """
  Get check history.
  """
  def get_history do
    GenServer.call(__MODULE__, :get_history)
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    state = %{
      current_job: nil,
      history: []
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:start_check, total_urls}, _from, state) do
    job = %{
      id: generate_job_id(),
      started_at: DateTime.utc_now(),
      total_urls: total_urls,
      checked: 0,
      status_counts: %{
        "2xx" => 0,
        "3xx" => 0,
        "4xx" => 0,
        "5xx" => 0,
        "errors" => 0
      }
    }

    Logger.info("Starting crawler check: #{job.id} (#{total_urls} URLs)")

    broadcast({:started, job})

    {:reply, {:ok, job.id}, %{state | current_job: job}}
  end

  @impl true
  def handle_call({:finish_check, stats}, _from, state) do
    case state.current_job do
      nil ->
        {:reply, {:error, :no_job_running}, state}

      job ->
        finished_job = %{
          job
          | checked: stats.checked,
            status_counts: %{
              "2xx" => stats.status_2xx,
              "3xx" => stats.status_3xx,
              "4xx" => stats.status_4xx,
              "5xx" => stats.status_5xx,
              "errors" => stats.errors
            }
        }

        completed_job =
          Map.merge(finished_job, %{
            finished_at: DateTime.utc_now(),
            duration_ms: calculate_duration(job.started_at)
          })

        Logger.info("Finished crawler check: #{job.id} (#{stats.checked}/#{job.total_urls} URLs)")

        broadcast({:finished, completed_job, stats})

        # Add to history
        new_history = add_to_history(state.history, completed_job)

        {:reply, {:ok, completed_job}, %{state | current_job: nil, history: new_history}}
    end
  end

  @impl true
  def handle_call(:get_current_job, _from, state) do
    {:reply, state.current_job, state}
  end

  @impl true
  def handle_call(:get_history, _from, state) do
    {:reply, state.history, state}
  end

  @impl true
  def handle_cast({:update_progress, result}, state) do
    case state.current_job do
      nil ->
        {:noreply, state}

      job ->
        updated_job = increment_counters(job, result)
        broadcast({:update, updated_job})

        {:noreply, %{state | current_job: updated_job}}
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp generate_job_id do
    "check-#{System.system_time(:millisecond)}"
  end

  defp increment_counters(job, result) do
    job
    |> Map.update!(:checked, &(&1 + 1))
    |> update_status_counts(result)
  end

  defp update_status_counts(job, %{status: status}) when not is_nil(status) do
    key =
      cond do
        status >= 200 and status < 300 -> "2xx"
        status >= 300 and status < 400 -> "3xx"
        status >= 400 and status < 500 -> "4xx"
        status >= 500 -> "5xx"
        true -> "errors"
      end

    update_in(job.status_counts[key], &(&1 + 1))
  end

  defp update_status_counts(job, %{error: error}) when not is_nil(error) do
    update_in(job.status_counts["errors"], &(&1 + 1))
  end

  defp update_status_counts(job, _result) do
    update_in(job.status_counts["errors"], &(&1 + 1))
  end

  defp calculate_duration(started_at) do
    DateTime.diff(DateTime.utc_now(), started_at, :millisecond)
  end

  defp add_to_history(history, job) do
    [job | history]
    |> Enum.take(@history_limit)
  end

  defp broadcast(event) do
    Phoenix.PubSub.broadcast(
      GscAnalytics.PubSub,
      @pubsub_topic,
      {:crawler_progress, build_event(event)}
    )
  end

  defp build_event({:started, job}) do
    %{type: :started, job: job}
  end

  defp build_event({:update, job}) do
    %{type: :update, job: job}
  end

  defp build_event({:finished, job, stats}) do
    %{type: :finished, job: job, stats: stats}
  end
end
