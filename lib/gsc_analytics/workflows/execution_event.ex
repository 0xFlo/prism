defmodule GscAnalytics.Workflows.ExecutionEvent do
  @moduledoc """
  Immutable event log for workflow executions.

  Provides a complete audit trail of all execution activity. Events are never
  updated or deleted - they form an append-only event stream.

  This table is optimized for write-heavy workloads and timeline queries.
  Per Codex review, events are persisted alongside PubSub broadcasts to ensure
  durability across node restarts.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "workflow_execution_events" do
    field :event_type, Ecto.Enum,
      values: [
        :execution_started,
        :execution_completed,
        :execution_failed,
        :execution_paused,
        :execution_resumed,
        :execution_cancelled,
        :step_started,
        :step_completed,
        :step_failed,
        :step_skipped,
        :variable_updated,
        :human_review_requested,
        :human_review_approved,
        :human_review_rejected
      ]

    field :step_id, :string
    field :step_type, :string

    # Event-specific data (e.g., step output, error details)
    field :payload, :map

    # Duration for completed steps
    field :duration_ms, :integer

    belongs_to :execution, GscAnalytics.Workflows.Execution

    # Only inserted_at (immutable event stream)
    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Changeset for creating a new event.

  Events are immutable - no updates allowed.
  """
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:event_type, :step_id, :step_type, :payload, :duration_ms, :execution_id])
    |> validate_required([:event_type, :execution_id])
    |> foreign_key_constraint(:execution_id)
  end

  # Factory functions for common event types

  @doc """
  Creates an execution started event.
  """
  def execution_started(execution_id, metadata \\ %{}) do
    %__MODULE__{}
    |> changeset(%{
      execution_id: execution_id,
      event_type: :execution_started,
      payload: metadata
    })
  end

  @doc """
  Creates an execution completed event.
  """
  def execution_completed(execution_id, output_data, duration_ms) do
    %__MODULE__{}
    |> changeset(%{
      execution_id: execution_id,
      event_type: :execution_completed,
      payload: %{output: output_data},
      duration_ms: duration_ms
    })
  end

  @doc """
  Creates an execution failed event.
  """
  def execution_failed(execution_id, error_message, error_step_id \\ nil) do
    %__MODULE__{}
    |> changeset(%{
      execution_id: execution_id,
      event_type: :execution_failed,
      step_id: error_step_id,
      payload: %{error: error_message}
    })
  end

  @doc """
  Creates a step started event.
  """
  def step_started(execution_id, step_id, step_type) do
    %__MODULE__{}
    |> changeset(%{
      execution_id: execution_id,
      event_type: :step_started,
      step_id: step_id,
      step_type: step_type
    })
  end

  @doc """
  Creates a step completed event.
  """
  def step_completed(execution_id, step_id, step_type, output, duration_ms) do
    %__MODULE__{}
    |> changeset(%{
      execution_id: execution_id,
      event_type: :step_completed,
      step_id: step_id,
      step_type: step_type,
      payload: %{output: output},
      duration_ms: duration_ms
    })
  end

  @doc """
  Creates a step failed event.
  """
  def step_failed(execution_id, step_id, step_type, reason, duration_ms) do
    %__MODULE__{}
    |> changeset(%{
      execution_id: execution_id,
      event_type: :step_failed,
      step_id: step_id,
      step_type: step_type,
      payload: %{error: inspect(reason)},
      duration_ms: duration_ms
    })
  end

  # Query helpers

  @doc """
  Returns events for a specific execution.
  """
  def for_execution(query \\ __MODULE__, execution_id) do
    from e in query, where: e.execution_id == ^execution_id
  end

  @doc """
  Returns events of a specific type.
  """
  def of_type(query \\ __MODULE__, event_type) do
    from e in query, where: e.event_type == ^event_type
  end

  @doc """
  Orders events chronologically (oldest first).
  """
  def chronological(query \\ __MODULE__) do
    from e in query, order_by: [asc: e.inserted_at]
  end

  @doc """
  Orders events reverse chronologically (newest first).
  """
  def recent_first(query \\ __MODULE__) do
    from e in query, order_by: [desc: e.inserted_at]
  end

  @doc """
  Limits to the most recent N events.
  """
  def recent(query \\ __MODULE__, limit) do
    query
    |> recent_first()
    |> limit(^limit)
  end

  @doc """
  Returns step events only (excludes execution-level events).
  """
  def steps_only(query \\ __MODULE__) do
    from e in query,
      where:
        e.event_type in [
          :step_started,
          :step_completed,
          :step_failed,
          :step_skipped
        ]
  end
end
