defmodule GscAnalytics.Workflows do
  @moduledoc """
  Context module for managing workflows.

  Handles CRUD operations and broadcasts PubSub events for real-time updates.
  """

  import Ecto.Query
  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.Workflow
  alias Phoenix.PubSub

  @pubsub GscAnalytics.PubSub
  @workflow_topic "workflows"

  ## PubSub Subscription

  @doc """
  Subscribe to workflow change events for all accounts.
  """
  def subscribe do
    PubSub.subscribe(@pubsub, @workflow_topic)
  end

  @doc """
  Subscribe to workflow change events for a specific account.
  """
  def subscribe(account_id) do
    PubSub.subscribe(@pubsub, "#{@workflow_topic}:#{account_id}")
  end

  ## CRUD Operations

  @doc """
  Creates a new workflow and broadcasts a creation event.
  """
  def create_workflow(attrs) do
    result =
      %Workflow{}
      |> Workflow.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, workflow} ->
        broadcast_workflow_event(workflow, :created)
        {:ok, workflow}

      error ->
        error
    end
  end

  @doc """
  Updates a workflow and broadcasts an update event.
  """
  def update_workflow(%Workflow{} = workflow, attrs) do
    result =
      workflow
      |> Workflow.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, updated_workflow} ->
        broadcast_workflow_event(updated_workflow, :updated)
        {:ok, updated_workflow}

      error ->
        error
    end
  end

  @doc """
  Publishes a workflow and broadcasts an update event.
  """
  def publish_workflow(%Workflow{} = workflow) do
    result =
      workflow
      |> Workflow.publish_changeset()
      |> Repo.update()

    case result do
      {:ok, updated_workflow} ->
        broadcast_workflow_event(updated_workflow, :published)
        {:ok, updated_workflow}

      error ->
        error
    end
  end

  @doc """
  Archives a workflow and broadcasts an update event.
  """
  def archive_workflow(%Workflow{} = workflow) do
    result =
      workflow
      |> Workflow.archive_changeset()
      |> Repo.update()

    case result do
      {:ok, updated_workflow} ->
        broadcast_workflow_event(updated_workflow, :archived)
        {:ok, updated_workflow}

      error ->
        error
    end
  end

  @doc """
  Deletes a workflow and broadcasts a deletion event.
  """
  def delete_workflow(%Workflow{} = workflow) do
    result = Repo.delete(workflow)

    case result do
      {:ok, deleted_workflow} ->
        broadcast_workflow_event(deleted_workflow, :deleted)
        {:ok, deleted_workflow}

      error ->
        error
    end
  end

  ## Query Functions

  @doc """
  Lists all workflows for an account.
  """
  def list_workflows(account_id, opts \\ []) do
    status_filter = Keyword.get(opts, :status, [:published, :draft])

    Workflow
    |> where([w], w.account_id == ^account_id)
    |> where([w], w.status in ^status_filter)
    |> order_by([w], desc: w.updated_at)
    |> Repo.all()
  end

  @doc """
  Gets a single workflow by ID.
  """
  def get_workflow(workflow_id) do
    Repo.get(Workflow, workflow_id)
  end

  @doc """
  Gets a single workflow by ID for a specific account.
  """
  def get_workflow(workflow_id, account_id) do
    Workflow
    |> where([w], w.id == ^workflow_id and w.account_id == ^account_id)
    |> Repo.one()
  end

  ## Private Helpers

  defp broadcast_workflow_event(workflow, event_type) do
    # Broadcast to global topic
    PubSub.broadcast(
      @pubsub,
      @workflow_topic,
      {:workflow_event, %{workflow: workflow, event: event_type}}
    )

    # Broadcast to account-specific topic
    PubSub.broadcast(
      @pubsub,
      "#{@workflow_topic}:#{workflow.account_id}",
      {:workflow_event, %{workflow: workflow, event: event_type}}
    )
  end
end
