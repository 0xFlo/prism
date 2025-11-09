defmodule GscAnalytics.Workflows.FoundationVerificationTest do
  @moduledoc """
  Verification tests for the workflow system foundation.

  Run these tests to verify Phase 1 is working correctly:
  - Database schema and migrations
  - Ecto models with validations
  - ETS-backed Runtime state management
  - Engine module structure

  Usage:
    mix test test/gsc_analytics/workflows/foundation_verification_test.exs
  """

  use GscAnalytics.DataCase, async: true

  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.Workflow
  alias GscAnalytics.Workflows.{Execution, ExecutionEvent, Runtime}

  describe "Phase 1: Database Schema" do
    test "workflows table exists and accepts valid data" do
      # Use the helper to create user and workspace with proper setup
      workflow =
        insert(:workflow,
          name: "Test Workflow",
          description: "Testing workflow creation"
        )

      assert workflow.id
      assert workflow.name == "Test Workflow"
      assert workflow.status == :draft
      assert length(workflow.definition["steps"]) == 1
    end

    test "workflow_executions table exists and links to workflows" do
      workflow = insert(:workflow)

      execution_attrs = %{
        workflow_id: workflow.id,
        account_id: workflow.account_id,
        input_data: %{test: "data"}
      }

      {:ok, execution} =
        %Execution{}
        |> Execution.changeset(execution_attrs)
        |> Repo.insert()

      assert execution.id
      assert execution.workflow_id == workflow.id
      assert execution.status == :queued
      assert execution.input_data == %{test: "data"}

      # Test preload
      execution_with_workflow = Repo.preload(execution, :workflow)
      assert execution_with_workflow.workflow.id == workflow.id
    end

    test "workflow_execution_events table accepts immutable events" do
      execution = insert(:execution)

      event_attrs = %{
        execution_id: execution.id,
        event_type: :execution_started,
        payload: %{metadata: "test"}
      }

      {:ok, event} =
        %ExecutionEvent{}
        |> ExecutionEvent.changeset(event_attrs)
        |> Repo.insert()

      assert event.id
      assert event.execution_id == execution.id
      assert event.event_type == :execution_started
      assert event.inserted_at
      refute Map.has_key?(event, :updated_at)
    end
  end

  describe "Phase 1: Ecto Schema Validations" do
    test "workflow rejects invalid definition (no steps)" do
      changeset =
        %Workflow{}
        |> Workflow.changeset(%{
          name: "Invalid",
          account_id: 1,
          definition: %{version: "1.0", steps: []}
        })

      refute changeset.valid?
      assert changeset.errors[:definition]
    end

    test "workflow detects circular dependencies" do
      changeset =
        %Workflow{}
        |> Workflow.changeset(%{
          name: "Circular",
          account_id: 1,
          definition: %{
            steps: [
              %{id: "step_1"},
              %{id: "step_2"}
            ],
            connections: [
              %{from: "step_1", to: "step_2"},
              %{from: "step_2", to: "step_1"}
            ]
          }
        })

      refute changeset.valid?
      assert changeset.errors[:definition]
    end

    test "workflow detects duplicate step IDs" do
      changeset =
        %Workflow{}
        |> Workflow.changeset(%{
          name: "Duplicates",
          account_id: 1,
          definition: %{
            steps: [
              %{id: "step_1"},
              %{id: "step_1"}
            ]
          }
        })

      refute changeset.valid?
      assert changeset.errors[:definition]
    end

    test "execution status transitions work" do
      execution = insert(:execution, status: :queued)

      # Start
      {:ok, execution} =
        execution
        |> Execution.start_changeset()
        |> Repo.update()

      assert execution.status == :running
      assert execution.started_at

      # Pause
      {:ok, execution} =
        execution
        |> Execution.pause_changeset()
        |> Repo.update()

      assert execution.status == :paused
      assert execution.paused_at

      # Resume
      {:ok, execution} =
        execution
        |> Execution.resume_changeset()
        |> Repo.update()

      assert execution.status == :running
      refute execution.paused_at

      # Complete
      {:ok, execution} =
        execution
        |> Execution.complete_changeset(%{result: "success"})
        |> Repo.update()

      assert execution.status == :completed
      assert execution.output_data == %{result: "success"}
      assert execution.completed_at
    end
  end

  describe "Phase 1: WorkflowRuntime ETS State" do
    test "creates ETS table with initial state" do
      execution_id = Ecto.UUID.generate()
      input_data = %{"url" => "https://example.com", "keyword" => "elixir"}

      table = Runtime.new(execution_id, input_data)

      assert is_reference(table)

      state = Runtime.get_state(table)
      assert state.execution_id == execution_id
      assert state.step_cursor == nil
      assert state.variables["input"] == input_data
      assert state.completed_steps == []
      assert state.failed_steps == []

      Runtime.cleanup(table)
    end

    test "stores and retrieves step outputs" do
      execution_id = Ecto.UUID.generate()
      table = Runtime.new(execution_id, %{})

      step_output = %{result: "success", count: 42, items: ["a", "b", "c"]}
      Runtime.store_step_output(table, "step_1", step_output)

      retrieved = Runtime.get_step_output(table, "step_1")
      assert retrieved == step_output

      # Verify in variables
      all_vars = Runtime.get_variables(table)
      assert all_vars["step_1"][:output] == step_output

      Runtime.cleanup(table)
    end

    test "tracks completed and failed steps" do
      # Create execution in DB for snapshot support
      execution = insert(:execution, input_data: %{})
      table = Runtime.new(execution.id, execution.input_data)

      Runtime.mark_step_completed(table, "step_1")
      Runtime.mark_step_completed(table, "step_2")
      Runtime.mark_step_failed(table, "step_3")

      state = Runtime.get_state(table)
      assert "step_1" in state.completed_steps
      assert "step_2" in state.completed_steps
      assert "step_3" in state.failed_steps

      Runtime.cleanup(table)
    end

    test "updates step cursor" do
      execution_id = Ecto.UUID.generate()
      table = Runtime.new(execution_id, %{})

      Runtime.set_step_cursor(table, "step_1")
      state = Runtime.get_state(table)
      assert state.step_cursor == "step_1"

      Runtime.set_step_cursor(table, "step_2")
      state = Runtime.get_state(table)
      assert state.step_cursor == "step_2"

      Runtime.cleanup(table)
    end

    test "snapshots state to database" do
      execution = insert(:execution, input_data: %{test: "data"})

      table = Runtime.new(execution.id, execution.input_data)
      Runtime.store_step_output(table, "step_1", %{result: "success"})
      Runtime.mark_step_completed(table, "step_1")
      Runtime.set_step_cursor(table, "step_2")

      # Force snapshot
      :ok = Runtime.force_snapshot(table)

      # Verify DB updated
      execution = Repo.get!(Execution, execution.id)
      assert execution.current_step_id == "step_2"
      assert "step_1" in execution.completed_step_ids
      assert execution.context_snapshot["step_1"]

      Runtime.cleanup(table)
    end

    test "restores state from database snapshot (crash recovery)" do
      execution = insert(:execution, input_data: %{test: "recovery"})

      # Create and populate runtime state
      original_table = Runtime.new(execution.id, execution.input_data)
      Runtime.store_step_output(original_table, "step_1", %{data: "important"})
      Runtime.mark_step_completed(original_table, "step_1")
      Runtime.set_step_cursor(original_table, "step_2")
      Runtime.force_snapshot(original_table)

      # Simulate crash - cleanup table
      Runtime.cleanup(original_table)

      # Restore from DB
      {:ok, restored_table} = Runtime.restore(execution.id)

      # Verify state restored correctly
      state = Runtime.get_state(restored_table)
      assert state.execution_id == execution.id
      assert state.step_cursor == "step_2"
      assert "step_1" in state.completed_steps
      # Note: After DB roundtrip, atom keys become strings in JSON
      assert Runtime.get_step_output(restored_table, "step_1") == %{"data" => "important"}

      Runtime.cleanup(restored_table)
    end
  end

  describe "Phase 1: Engine Module Structure" do
    test "Engine module loads successfully" do
      assert Code.ensure_loaded?(GscAnalytics.Workflows.Engine)
    end

    test "Engine exports expected functions" do
      functions = GscAnalytics.Workflows.Engine.__info__(:functions)

      assert {:start_execution, 1} in functions
      assert {:execute, 1} in functions
      assert {:pause, 1} in functions
      assert {:resume, 1} in functions
      assert {:stop_execution, 1} in functions
      assert {:get_state, 1} in functions
    end
  end

  # Helper to insert test data
  defp insert(schema, attrs \\ %{}) do
    case schema do
      :user ->
        %GscAnalytics.Auth.User{
          email: "test-#{System.unique_integer()}@example.com",
          hashed_password: "hashed",
          confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        }
        |> Map.merge(attrs)
        |> Repo.insert!()

      :workspace ->
        attrs_map = Enum.into(attrs, %{})

        %GscAnalytics.Schemas.Workspace{
          user_id: attrs_map[:user].id,
          google_account_email: "test@google.com",
          name: "Test Workspace"
        }
        |> Map.merge(Map.delete(attrs_map, :user))
        |> Repo.insert!()

      :workflow ->
        attrs_map = Enum.into(attrs, %{})
        user = attrs_map[:user] || insert(:user)
        workspace = attrs_map[:workspace] || insert(:workspace, user: user)

        %Workflow{
          name: "Test Workflow #{System.unique_integer()}",
          account_id: workspace.id,
          created_by_id: user.id,
          definition: %{
            "version" => "1.0",
            "steps" => [%{"id" => "step_1", "type" => "test"}],
            "connections" => []
          }
        }
        |> Map.merge(Map.drop(attrs_map, [:user, :workspace]))
        |> Repo.insert!()

      :execution ->
        attrs_map = Enum.into(attrs, %{})
        workflow = attrs_map[:workflow] || insert(:workflow)

        %Execution{
          workflow_id: workflow.id,
          account_id: workflow.account_id,
          input_data: %{}
        }
        |> Map.merge(Map.delete(attrs_map, :workflow))
        |> Repo.insert!()
    end
  end
end
