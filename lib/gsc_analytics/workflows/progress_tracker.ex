defmodule GscAnalytics.Workflows.ProgressTracker do
  @moduledoc """
  Tracks workflow execution progress and broadcasts real-time updates.

  Implements dual persistence pattern:
  1. PubSub broadcasts for real-time LiveView updates
  2. Database persistence to workflow_execution_events for durability

  This enables:
  - Real-time progress updates in LiveViews
  - Crash recovery (read events from DB)
  - Reconnection recovery (LiveView can catch up)
  - Audit trail of all execution activity
  """

  use GenServer
  require Logger

  alias Phoenix.PubSub
  alias GscAnalytics.Repo
  alias GscAnalytics.Workflows.ExecutionEvent

  @topic "workflow_progress"

  ## Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Subscribe the caller to workflow progress notifications.

  The process will receive messages in the form `{:workflow_progress, event}`.
  """
  def subscribe do
    PubSub.subscribe(GscAnalytics.PubSub, @topic)
  end

  @doc """
  Subscribe to a specific execution's progress.
  """
  def subscribe(execution_id) do
    PubSub.subscribe(GscAnalytics.PubSub, "#{@topic}:#{execution_id}")
  end

  @doc """
  Publishes execution started event.
  """
  def publish_started(execution_id) do
    GenServer.cast(__MODULE__, {:publish, execution_id, :execution_started, %{}})
  end

  @doc """
  Publishes execution paused event.
  """
  def publish_paused(execution_id) do
    GenServer.cast(__MODULE__, {:publish, execution_id, :execution_paused, %{}})
  end

  @doc """
  Publishes execution resumed event.
  """
  def publish_resumed(execution_id) do
    GenServer.cast(__MODULE__, {:publish, execution_id, :execution_resumed, %{}})
  end

  @doc """
  Publishes execution cancelled event.
  """
  def publish_cancelled(execution_id) do
    GenServer.cast(__MODULE__, {:publish, execution_id, :execution_cancelled, %{}})
  end

  @doc """
  Publishes step started event.
  """
  def publish_step_started(execution_id, step_id, step_name) do
    GenServer.cast(
      __MODULE__,
      {:publish, execution_id, :step_started, %{step_id: step_id, step_name: step_name}}
    )
  end

  @doc """
  Publishes step completed event.
  """
  def publish_step_completed(execution_id, step_id, step_name, status) do
    GenServer.cast(
      __MODULE__,
      {:publish, execution_id, :step_completed,
       %{step_id: step_id, step_name: step_name, status: status}}
    )
  end

  @doc """
  Publishes step failed event.
  """
  def publish_step_failed(execution_id, step_id, step_name, reason) do
    GenServer.cast(
      __MODULE__,
      {:publish, execution_id, :step_failed,
       %{step_id: step_id, step_name: step_name, reason: inspect(reason)}}
    )
  end

  @doc """
  Publishes awaiting review event (human-in-the-loop).
  """
  def publish_awaiting_review(execution_id, step_id, review_id) do
    GenServer.cast(
      __MODULE__,
      {:publish, execution_id, :awaiting_review, %{step_id: step_id, review_id: review_id}}
    )
  end

  @doc """
  Publishes execution finished event.
  """
  def publish_finished(execution_id, status, output_data) do
    GenServer.cast(
      __MODULE__,
      {:publish, execution_id, :execution_finished, %{status: status, output_data: output_data}}
    )
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:publish, execution_id, event_type, payload}, state) do
    # Dual persistence: PubSub broadcast + DB write
    broadcast_event(execution_id, event_type, payload)
    persist_event(execution_id, event_type, payload)

    {:noreply, state}
  end

  ## Private Functions

  defp broadcast_event(execution_id, event_type, payload) do
    event = %{
      execution_id: execution_id,
      event_type: event_type,
      payload: payload,
      timestamp: DateTime.utc_now()
    }

    # Broadcast to global topic
    PubSub.broadcast(GscAnalytics.PubSub, @topic, {:workflow_progress, event})

    # Broadcast to execution-specific topic
    PubSub.broadcast(
      GscAnalytics.PubSub,
      "#{@topic}:#{execution_id}",
      {:workflow_progress, event}
    )
  end

  defp persist_event(execution_id, event_type, payload) do
    # Use factory functions from ExecutionEvent schema where available
    changeset =
      case event_type do
        :execution_started ->
          ExecutionEvent.execution_started(execution_id, payload)

        :step_started ->
          ExecutionEvent.step_started(
            execution_id,
            payload.step_id,
            payload[:step_type] || "unknown"
          )

        :step_completed ->
          ExecutionEvent.step_completed(
            execution_id,
            payload.step_id,
            payload[:step_type] || "unknown",
            payload,
            payload[:duration_ms] || 0
          )

        :step_failed ->
          ExecutionEvent.step_failed(
            execution_id,
            payload.step_id,
            payload[:step_type] || "unknown",
            payload[:reason] || "Unknown error",
            payload[:duration_ms] || 0
          )

        # For events without factory functions, use generic changeset
        _ ->
          %ExecutionEvent{}
          |> ExecutionEvent.changeset(%{
            execution_id: execution_id,
            event_type: event_type,
            step_id: payload[:step_id],
            step_type: payload[:step_type],
            payload: payload
          })
      end

    case Repo.insert(changeset) do
      {:ok, _event} ->
        :ok

      {:error, changeset} ->
        Logger.error(
          "Failed to persist workflow event: #{inspect(changeset.errors)}, execution_id: #{execution_id}, event_type: #{event_type}"
        )

        :error
    end
  end
end
