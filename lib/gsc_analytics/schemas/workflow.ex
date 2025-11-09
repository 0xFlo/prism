defmodule GscAnalytics.Schemas.Workflow do
  @moduledoc """
  Workflow definition schema.

  Stores the blueprint for automated workflows including step configurations,
  connections, and input requirements.

  ## Example Definition Structure

      %{
        version: "1.0",
        steps: [
          %{
            id: "step_1",
            type: "gsc_query",
            name: "Fetch URLs",
            config: %{...},
            position: %{x: 100, y: 100}
          }
        ],
        connections: [
          %{from: "step_1", to: "step_2"}
        ]
      }
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "workflows" do
    field :name, :string
    field :description, :string
    field :status, Ecto.Enum, values: [:draft, :published, :archived], default: :draft

    # JSON field storing step graph structure
    field :definition, :map

    # Input schema definition (for validation)
    field :input_schema, :map

    # Workflow metadata
    field :tags, {:array, :string}, default: []
    field :version, :integer, default: 1
    field :published_at, :utc_datetime

    belongs_to :account, GscAnalytics.Schemas.Workspace, foreign_key: :account_id, type: :integer
    belongs_to :created_by, GscAnalytics.Auth.User, foreign_key: :created_by_id, type: :integer

    has_many :executions, GscAnalytics.Workflows.Execution

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating/updating workflows.
  """
  def changeset(workflow, attrs) do
    workflow
    |> cast(attrs, [:name, :description, :status, :definition, :input_schema, :tags, :version])
    |> validate_required([:name, :definition, :account_id])
    |> validate_length(:name, min: 3, max: 100)
    |> validate_workflow_definition()
    |> validate_input_schema()
  end

  @doc """
  Changeset for publishing a workflow.
  """
  def publish_changeset(workflow) do
    workflow
    |> change(%{
      status: :published,
      published_at: DateTime.utc_now()
    })
    |> validate_required([:definition])
    |> validate_workflow_definition()
  end

  @doc """
  Changeset for archiving a workflow.
  """
  def archive_changeset(workflow) do
    change(workflow, %{status: :archived})
  end

  # Private validation functions

  defp validate_workflow_definition(changeset) do
    case get_field(changeset, :definition) do
      nil ->
        changeset

      definition ->
        cond do
          not is_map(definition) ->
            add_error(changeset, :definition, "must be a map")

          not is_list(definition["steps"]) ->
            add_error(changeset, :definition, "must contain a 'steps' array")

          length(definition["steps"]) == 0 ->
            add_error(changeset, :definition, "must contain at least one step")

          has_circular_dependencies?(definition) ->
            add_error(changeset, :definition, "contains circular dependencies")

          has_orphaned_nodes?(definition) ->
            add_error(changeset, :definition, "contains orphaned nodes")

          has_duplicate_step_ids?(definition) ->
            add_error(changeset, :definition, "contains duplicate step IDs")

          true ->
            changeset
        end
    end
  end

  defp validate_input_schema(changeset) do
    case get_field(changeset, :input_schema) do
      nil ->
        changeset

      schema ->
        if is_map(schema) and is_list(schema["fields"]) do
          changeset
        else
          add_error(changeset, :input_schema, "must contain a 'fields' array")
        end
    end
  end

  defp has_circular_dependencies?(%{"steps" => steps, "connections" => connections})
       when is_list(connections) do
    # Build adjacency list
    graph = build_graph(connections)

    # Detect cycles using DFS
    steps
    |> Enum.map(& &1["id"])
    |> Enum.any?(fn step_id ->
      has_cycle?(graph, step_id, MapSet.new(), MapSet.new())
    end)
  end

  defp has_circular_dependencies?(_), do: false

  defp has_orphaned_nodes?(%{"steps" => steps, "connections" => connections})
       when is_list(connections) do
    step_ids = MapSet.new(steps, & &1["id"])
    connected_ids = get_connected_step_ids(connections)

    # Check if any step is not connected (except first and last)
    orphaned_count =
      MapSet.difference(step_ids, connected_ids)
      |> MapSet.size()

    # Allow at most 2 orphaned nodes (entry and exit points)
    orphaned_count > 2
  end

  defp has_orphaned_nodes?(_), do: false

  defp has_duplicate_step_ids?(%{"steps" => steps}) do
    step_ids = Enum.map(steps, & &1["id"])
    length(step_ids) != length(Enum.uniq(step_ids))
  end

  defp has_duplicate_step_ids?(_), do: false

  # Graph utilities

  defp build_graph(connections) do
    Enum.reduce(connections, %{}, fn %{"from" => from, "to" => to}, acc ->
      Map.update(acc, from, [to], &[to | &1])
    end)
  end

  defp has_cycle?(graph, node, visiting, visited) do
    cond do
      MapSet.member?(visiting, node) ->
        true

      MapSet.member?(visited, node) ->
        false

      true ->
        neighbors = Map.get(graph, node, [])
        new_visiting = MapSet.put(visiting, node)

        Enum.any?(neighbors, fn neighbor ->
          has_cycle?(graph, neighbor, new_visiting, visited)
        end)
    end
  end

  defp get_connected_step_ids(connections) do
    Enum.reduce(connections, MapSet.new(), fn conn, acc ->
      acc
      |> MapSet.put(conn["from"])
      |> MapSet.put(conn["to"])
    end)
  end

  # Query helpers

  @doc """
  Returns published workflows for an account.
  """
  def published(query \\ __MODULE__) do
    from w in query, where: w.status == :published
  end

  @doc """
  Returns workflows for a specific account.
  """
  def for_account(query \\ __MODULE__, account_id) do
    from w in query, where: w.account_id == ^account_id
  end

  @doc """
  Orders workflows by most recently updated.
  """
  def recent_first(query \\ __MODULE__) do
    from w in query, order_by: [desc: w.updated_at]
  end
end
