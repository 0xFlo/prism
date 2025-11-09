defmodule GscAnalytics.Workflows.Execution do
  @moduledoc """
  Workflow execution runtime instance schema.

  Tracks the state of a workflow execution including progress, context snapshots,
  and completion status.

  ## Context Snapshot vs ETS Runtime State

  The `context_snapshot` field serves as a crash recovery checkpoint. The actual
  runtime state lives in ETS (via WorkflowRuntime) and is periodically persisted
  to this field for durability.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "workflow_executions" do
    field :status, Ecto.Enum,
      values: [:queued, :running, :paused, :completed, :failed, :cancelled],
      default: :queued

    # Input data provided at execution time
    field :input_data, :map

    # Final output (populated on completion)
    field :output_data, :map

    # Current variable context (checkpoint for crash recovery)
    field :context_snapshot, :map, default: %{}

    # Runtime metrics
    field :current_step_id, :string
    field :completed_step_ids, {:array, :string}, default: []
    field :failed_step_ids, {:array, :string}, default: []

    # Timestamps
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :paused_at, :utc_datetime

    # Error tracking
    field :error_message, :string
    field :error_step_id, :string

    belongs_to :workflow, GscAnalytics.Schemas.Workflow
    belongs_to :account, GscAnalytics.Schemas.Workspace, foreign_key: :account_id, type: :integer

    belongs_to :triggered_by, GscAnalytics.Auth.User,
      foreign_key: :triggered_by_id,
      type: :integer

    has_many :events, GscAnalytics.Workflows.ExecutionEvent

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new execution.
  """
  def changeset(execution, attrs) do
    execution
    |> cast(attrs, [
      :status,
      :input_data,
      :output_data,
      :context_snapshot,
      :current_step_id,
      :workflow_id,
      :account_id,
      :triggered_by_id
    ])
    |> validate_required([:workflow_id, :account_id])
    |> validate_input_data()
    |> foreign_key_constraint(:workflow_id)
    |> foreign_key_constraint(:account_id)
  end

  @doc """
  Changeset for starting an execution.
  """
  def start_changeset(execution) do
    execution
    |> change(%{
      status: :running,
      started_at: DateTime.utc_now()
    })
  end

  @doc """
  Changeset for updating execution progress.
  """
  def progress_changeset(execution, attrs) do
    execution
    |> cast(attrs, [
      :current_step_id,
      :completed_step_ids,
      :failed_step_ids,
      :context_snapshot
    ])
  end

  @doc """
  Changeset for pausing an execution.
  """
  def pause_changeset(execution) do
    execution
    |> change(%{
      status: :paused,
      paused_at: DateTime.utc_now()
    })
  end

  @doc """
  Changeset for resuming a paused execution.
  """
  def resume_changeset(execution) do
    execution
    |> change(%{
      status: :running,
      paused_at: nil
    })
  end

  @doc """
  Changeset for completing an execution successfully.
  """
  def complete_changeset(execution, output_data) do
    execution
    |> change(%{
      status: :completed,
      output_data: output_data,
      completed_at: DateTime.utc_now()
    })
  end

  @doc """
  Changeset for marking an execution as failed.
  """
  def fail_changeset(execution, error_message, error_step_id \\ nil) do
    execution
    |> change(%{
      status: :failed,
      error_message: error_message,
      error_step_id: error_step_id,
      completed_at: DateTime.utc_now()
    })
  end

  @doc """
  Changeset for cancelling an execution.
  """
  def cancel_changeset(execution) do
    execution
    |> change(%{
      status: :cancelled,
      completed_at: DateTime.utc_now()
    })
  end

  # Private validation

  defp validate_input_data(changeset) do
    workflow_id = get_field(changeset, :workflow_id)
    input_data = get_field(changeset, :input_data)

    # If we have a workflow, validate input against schema
    if workflow_id && input_data do
      # This would be enhanced to actually validate against workflow.input_schema
      changeset
    else
      changeset
    end
  end

  # Query helpers

  @doc """
  Returns executions for a specific workflow.
  """
  def for_workflow(query \\ __MODULE__, workflow_id) do
    from e in query, where: e.workflow_id == ^workflow_id
  end

  @doc """
  Returns executions for a specific account.
  """
  def for_account(query \\ __MODULE__, account_id) do
    from e in query, where: e.account_id == ^account_id
  end

  @doc """
  Returns executions with a specific status.
  """
  def with_status(query \\ __MODULE__, status) do
    from e in query, where: e.status == ^status
  end

  @doc """
  Returns active executions (running or paused).
  """
  def active(query \\ __MODULE__) do
    from e in query, where: e.status in [:running, :paused]
  end

  @doc """
  Orders executions by most recent first.
  """
  def recent_first(query \\ __MODULE__) do
    from e in query, order_by: [desc: e.inserted_at]
  end

  @doc """
  Preloads workflow definition for execution.
  """
  def with_workflow(query \\ __MODULE__) do
    from e in query, preload: :workflow
  end
end
