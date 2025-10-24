defmodule GscAnalytics.DataSources.GSC.Support.SyncProgress do
  @moduledoc """
  Tracks long running Google Search Console sync jobs and broadcasts
  real-time progress updates over `Phoenix.PubSub` so LiveViews can
  surface status to users.
  """

  use GenServer

  alias Phoenix.PubSub

  @topic "gsc_sync_progress"
  @history_limit 120

  ## Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Subscribe the caller to sync progress notifications.

  The process will receive messages in the form `{:sync_progress, event}`.
  """
  def subscribe do
    PubSub.subscribe(GscAnalytics.PubSub, @topic)
  end

  @doc """
  Returns the current job state (if any) so newly mounted LiveViews can
  render immediately without waiting for the next broadcast.
  """
  def current_state do
    GenServer.call(__MODULE__, :current_state)
  end

  @doc """
  Registers a new sync job and broadcasts a `:started` event. Returns
  the generated job id for subsequent updates.
  """
  def start_job(attrs) when is_map(attrs) do
    GenServer.call(__MODULE__, {:start_job, attrs})
  end

  @doc """
  Marks a date as actively being synced and broadcasts a `:step_started`
  event so the UI can show a loading indicator for that specific day.
  """
  def day_started(job_id, attrs) do
    GenServer.cast(__MODULE__, {:step_started, job_id, attrs})
  end

  @doc """
  Records completion (or failure) for a specific date and broadcasts a
  `:step_completed` event.
  """
  def day_completed(job_id, attrs) do
    GenServer.cast(__MODULE__, {:step_completed, job_id, attrs})
  end

  @doc """
  Finalises a job, updating its terminal status and broadcasting a
  `:finished` event.
  """
  def finish_job(job_id, attrs) do
    GenServer.cast(__MODULE__, {:finish_job, job_id, attrs})
  end

  @doc """
  Returns the pending control command for the given job, if any.
  """
  def current_command(nil), do: nil

  def current_command(job_id) do
    GenServer.call(__MODULE__, {:current_command, job_id})
  end

  @doc """
  Request the active sync job to pause on the next safe checkpoint.
  """
  def request_pause(job_id) do
    GenServer.call(__MODULE__, {:set_command, job_id, :pause})
  end

  @doc """
  Resume a previously paused sync job.
  """
  def resume_job(job_id) do
    GenServer.call(__MODULE__, {:set_command, job_id, :resume})
  end

  @doc """
  Request the active sync job to stop gracefully.
  """
  def request_stop(job_id) do
    GenServer.call(__MODULE__, {:set_command, job_id, :stop})
  end

  ## Server callbacks

  @impl true
  def init(_opts) do
    {:ok, %{current_job: nil, jobs: %{}, commands: %{}}}
  end

  @impl true
  def handle_call(:current_state, _from, state) do
    {:reply, state.current_job, state}
  end

  def handle_call({:start_job, attrs}, _from, state) do
    job_id = Map.get(attrs, :job_id, Ecto.UUID.generate())
    now = DateTime.utc_now()

    job = %{
      id: job_id,
      status: :running,
      started_at: now,
      finished_at: nil,
      total_steps: attrs[:total_steps] || 0,
      completed_steps: 0,
      metadata: Map.take(attrs, [:account_id, :site_url, :start_date, :end_date]),
      events: [],
      current_step: nil,
      current_date: nil,
      metrics: default_metrics()
    }

    jobs = Map.put(state.jobs, job_id, job)
    commands = Map.delete(state.commands, job_id)
    new_state = %{state | current_job: job, jobs: jobs, commands: commands}

    broadcast(%{type: :started, job: job})

    {:reply, job_id, new_state}
  end

  def handle_call({:current_command, job_id}, _from, state) do
    {:reply, Map.get(state.commands, job_id), state}
  end

  def handle_call({:set_command, job_id, command}, _from, state) do
    case Map.fetch(state.jobs, job_id) do
      {:ok, job} ->
        {updated_job, commands, event} = apply_command(job, state.commands, job_id, command)
        jobs = persist_job(state.jobs, updated_job)

        current_job =
          if state.current_job && state.current_job.id == job_id,
            do: updated_job,
            else: state.current_job

        if event, do: broadcast(%{type: event.type, job: updated_job, event: event})

        new_state = %{state | jobs: jobs, current_job: current_job, commands: commands}

        {:reply, :ok, new_state}

      :error ->
        {:reply, {:error, :no_job}, state}
    end
  end

  @impl true
  def handle_cast({:step_started, job_id, attrs}, state) do
    new_state =
      update_job(state, job_id, fn job ->
        event = build_event(:step_started, attrs)

        updated_job =
          job
          |> Map.put(:current_step, event.step)
          |> Map.put(:current_date, event.date)
          |> append_event(event)

        broadcast(%{type: :step_started, job: updated_job, event: event})
        updated_job
      end)

    {:noreply, new_state}
  end

  def handle_cast({:step_completed, job_id, attrs}, state) do
    new_state =
      update_job(state, job_id, fn job ->
        event = build_event(:step_completed, attrs)

        # Ensure completed steps never exceed total steps when provided
        completed_steps = max(job.completed_steps, event.step || job.completed_steps)
        completed_steps = min(completed_steps, job.total_steps || completed_steps)

        updated_job =
          job
          |> Map.merge(%{
            completed_steps: completed_steps,
            current_step: nil,
            current_date: nil
          })
          |> update_metrics(event)
          |> append_event(event)

        broadcast(%{type: :step_completed, job: updated_job, event: event})
        updated_job
      end)

    {:noreply, new_state}
  end

  def handle_cast({:finish_job, job_id, attrs}, state) do
    new_state =
      update_job(state, job_id, fn job ->
        event = build_event(:finished, attrs)
        finished_at = event.timestamp || DateTime.utc_now()
        status = attrs[:status] || :completed

        completed_steps =
          if status == :failed do
            job.completed_steps
          else
            max(job.completed_steps, job.total_steps || job.completed_steps)
          end

        updated_job =
          job
          |> Map.merge(%{
            status: status,
            finished_at: finished_at,
            summary: attrs[:summary],
            error: attrs[:error]
          })
          |> Map.put(:completed_steps, completed_steps)
          |> update_metrics(event)
          |> append_event(event)

        broadcast(%{type: :finished, job: updated_job, event: event})
        updated_job
      end)

    commands = new_state |> Map.get(:commands, %{}) |> Map.delete(job_id)
    {:noreply, Map.put(new_state, :commands, commands)}
  end

  ## Helpers

  defp update_job(state, job_id, fun) do
    case Map.fetch(state.jobs, job_id) do
      {:ok, job} ->
        updated_job = fun.(job)
        jobs = persist_job(state.jobs, updated_job)

        current_job =
          if state.current_job && state.current_job.id == job_id,
            do: updated_job,
            else: state.current_job

        %{state | jobs: jobs, current_job: current_job}

      :error ->
        state
    end
  end

  defp append_event(job, event) do
    events = [event | job.events] |> Enum.take(@history_limit)
    Map.put(job, :events, events)
  end

  defp apply_command(job, commands, job_id, :pause) do
    cond do
      job.status in [:completed, :completed_with_warnings, :failed, :cancelled] ->
        {job, commands, nil}

      Map.get(commands, job_id) in [:pause, :stop] ->
        {job, commands, nil}

      true ->
        event = build_event(:paused, %{message: "Sync paused by user"})

        updated_job =
          job
          |> Map.put(:status, :paused)
          |> append_event(event)

        {updated_job, Map.put(commands, job_id, :pause), event}
    end
  end

  defp apply_command(job, commands, job_id, :resume) do
    case Map.get(commands, job_id) do
      :pause ->
        event = build_event(:resumed, %{message: "Sync resumed"})

        updated_job =
          job
          |> Map.put(:status, :running)
          |> append_event(event)

        {updated_job, Map.delete(commands, job_id), event}

      _ ->
        {job, commands, nil}
    end
  end

  defp apply_command(job, commands, job_id, :stop) do
    if Map.get(commands, job_id) == :stop do
      {job, commands, nil}
    else
      event = build_event(:stopping, %{message: "Cancellation requested"})

      updated_job =
        job
        |> Map.put(:status, :cancelling)
        |> append_event(event)

      {updated_job, Map.put(commands, job_id, :stop), event}
    end
  end

  defp apply_command(job, commands, _job_id, _command), do: {job, commands, nil}

  defp broadcast(payload) do
    PubSub.broadcast(GscAnalytics.PubSub, @topic, {:sync_progress, payload})
  end

  defp build_event(type, attrs) do
    %{
      type: type,
      step: attrs[:step],
      date: attrs[:date],
      status: attrs[:status],
      urls: attrs[:urls] || 0,
      rows: attrs[:rows] || 0,
      query_batches: attrs[:query_batches] || 0,
      url_requests: attrs[:url_requests] || 0,
      api_calls: attrs[:api_calls] || 0,
      duration_ms: attrs[:duration_ms],
      message: attrs[:message],
      timestamp: attrs[:timestamp] || DateTime.utc_now(),
      summary: attrs[:summary],
      error: attrs[:error]
    }
  end

  defp update_metrics(job, %{type: :step_completed, status: :skipped}) do
    ensure_metrics(job)
  end

  defp update_metrics(job, %{type: :step_completed} = event) do
    metrics = job[:metrics] || default_metrics()

    urls = max(event.urls || 0, 0)
    rows = max(event.rows || 0, 0)
    query_batches = max(event.query_batches || 0, 0)
    url_requests = max(event.url_requests || 0, 0)
    api_calls = event.api_calls || query_batches + url_requests

    new_metrics =
      metrics
      |> Map.update(:total_urls, 0, &(&1 + urls))
      |> Map.update(:total_rows, 0, &(&1 + rows))
      |> Map.update(:total_query_sub_requests, 0, &(&1 + query_batches))
      |> Map.update(:total_url_requests, 0, &(&1 + url_requests))
      |> Map.update(:total_api_calls, 0, &(&1 + api_calls))

    Map.put(job, :metrics, new_metrics)
  end

  defp update_metrics(job, %{type: :finished}) do
    ensure_metrics(job)
  end

  defp update_metrics(job, _event) do
    ensure_metrics(job)
  end

  defp ensure_metrics(job) do
    Map.put_new(job, :metrics, default_metrics())
  end

  defp default_metrics do
    %{
      total_urls: 0,
      total_rows: 0,
      total_query_sub_requests: 0,
      total_query_http_batches: 0,
      total_url_requests: 0,
      total_api_calls: 0
    }
  end

  defp persist_job(jobs, %{status: status, id: id})
       when status in [:completed, :completed_with_warnings, :failed, :cancelled] do
    Map.delete(jobs, id)
  end

  defp persist_job(jobs, %{id: id} = job) do
    Map.put(jobs, id, job)
  end
end
