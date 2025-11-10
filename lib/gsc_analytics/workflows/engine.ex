defmodule GscAnalytics.Workflows.Engine do
  @moduledoc """
  Workflow execution engine (GenServer).

  Orchestrates workflow execution with crash recovery and real-time progress tracking.
  Per Codex review:
  - Uses DynamicSupervisor for fault isolation (one supervisor per execution)
  - ETS-backed state via Runtime module (not Agent)
  - Crash recovery via Runtime.restore/1
  - Async tasks for long-running LLM/API work (don't block GenServer mailbox)
  - Registry for efficient process lookup

  ## Architecture

  ```
  EngineSupervisor (DynamicSupervisor)
    └── Engine (GenServer) - execution_id_1
    └── Engine (GenServer) - execution_id_2
  ```

  Each execution runs in its own GenServer under DynamicSupervisor for fault isolation.

  ## Usage

      # Start a new execution
      {:ok, pid} = Engine.start_execution(execution_id)

      # Execute workflow
      Engine.execute(execution_id)

      # Control execution
      Engine.pause(execution_id)
      Engine.resume(execution_id)
      Engine.stop_execution(execution_id)
  """

  use GenServer
  require Logger

  alias GscAnalytics.Repo
  alias GscAnalytics.Workflows.{Execution, Runtime, ProgressTracker}

  @type engine_state :: %{
          execution_id: binary(),
          execution: Execution.t(),
          workflow_def: map(),
          runtime_table: :ets.tid(),
          step_queue: [String.t()],
          status: :running | :paused | :cancelling | :completed | :failed
        }

  ## Client API

  @doc """
  Starts an execution engine process under DynamicSupervisor.

  The process is registered in the EngineRegistry for efficient lookup.
  """
  @spec start_execution(binary()) :: {:ok, pid()} | {:error, term()}
  def start_execution(execution_id) do
    spec = {__MODULE__, execution_id}

    case DynamicSupervisor.start_child(
           GscAnalytics.Workflows.EngineSupervisor,
           spec
         ) do
      {:ok, pid} ->
        Logger.info("Started workflow engine for execution #{execution_id}")
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        Logger.debug("Engine already running for execution #{execution_id}")
        {:ok, pid}

      error ->
        Logger.error("Failed to start engine: #{inspect(error)}")
        error
    end
  end

  @doc """
  Starts the GenServer (called by DynamicSupervisor).
  """
  def start_link(execution_id) do
    GenServer.start_link(__MODULE__, execution_id, name: via_tuple(execution_id))
  end

  @doc """
  Executes the workflow asynchronously.
  """
  @spec execute(binary()) :: :ok
  def execute(execution_id) do
    GenServer.cast(via_tuple(execution_id), :execute)
  end

  @doc """
  Pauses the workflow execution.
  """
  @spec pause(binary()) :: :ok
  def pause(execution_id) do
    GenServer.call(via_tuple(execution_id), :pause)
  end

  @doc """
  Resumes a paused workflow.
  """
  @spec resume(binary()) :: :ok
  def resume(execution_id) do
    GenServer.call(via_tuple(execution_id), :resume)
  end

  @doc """
  Stops the workflow execution (cancellation).
  """
  @spec stop_execution(binary()) :: :ok
  def stop_execution(execution_id) do
    GenServer.call(via_tuple(execution_id), :stop)
  end

  @doc """
  Gets the current engine state (for debugging).
  """
  @spec get_state(binary()) :: engine_state()
  def get_state(execution_id) do
    GenServer.call(via_tuple(execution_id), :get_state)
  end

  ## Server Callbacks

  @impl true
  def init(execution_id) do
    # Load execution from DB
    execution =
      Execution
      |> Repo.get!(execution_id)
      |> Repo.preload(:workflow)

    workflow_def = execution.workflow.definition

    # Attempt crash recovery first
    runtime_table =
      case Runtime.restore(execution_id) do
        {:ok, table} ->
          Logger.info("Recovered runtime state for execution #{execution_id}")
          table

        {:error, :not_found} ->
          # Fresh start
          Runtime.new(execution_id, execution.input_data || %{})
      end

    # Build execution plan (topological sort)
    step_queue = build_execution_plan(workflow_def)

    # Update execution status to running
    execution
    |> Execution.start_changeset()
    |> Repo.update!()

    # Publish started event
    ProgressTracker.publish_started(execution_id)

    state = %{
      execution_id: execution_id,
      execution: execution,
      workflow_def: workflow_def,
      runtime_table: runtime_table,
      step_queue: step_queue,
      status: :running
    }

    {:ok, state}
  end

  @impl true
  def handle_cast(:execute, state) do
    # Execute workflow in async task (don't block GenServer)
    Task.start(fn -> execute_workflow(state) end)

    {:noreply, state}
  end

  @impl true
  def handle_call(:pause, _from, state) do
    new_state = %{state | status: :paused}

    # Persist pause
    state.execution
    |> Execution.pause_changeset()
    |> Repo.update!()

    ProgressTracker.publish_paused(state.execution_id)

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:resume, _from, %{status: :paused} = state) do
    new_state = %{state | status: :running}

    # Resume execution
    Task.start(fn -> execute_workflow(new_state) end)

    ProgressTracker.publish_resumed(state.execution_id)

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:stop, _from, state) do
    new_state = %{state | status: :cancelling}

    state.execution
    |> Execution.cancel_changeset()
    |> Repo.update!()

    ProgressTracker.publish_cancelled(state.execution_id)

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  ## Private Functions

  defp execute_workflow(%{status: :cancelling} = state) do
    finalize_execution(state, :cancelled, nil)
  end

  defp execute_workflow(%{status: :paused}) do
    # Paused - do nothing
    :ok
  end

  defp execute_workflow(%{step_queue: []} = state) do
    # All steps completed
    output_data = Runtime.get_variables(state.runtime_table)
    finalize_execution(state, :completed, output_data)
  end

  defp execute_workflow(%{step_queue: [step_id | remaining]} = state) do
    step = find_step(state.workflow_def, step_id)

    Logger.debug("Executing step #{step_id}: #{step["name"]}")

    # Update runtime cursor
    Runtime.set_step_cursor(state.runtime_table, step_id)

    # Publish step started
    ProgressTracker.publish_step_started(
      state.execution_id,
      step_id,
      step["name"]
    )

    # TODO: Execute step via Step.Executor protocol
    # For now, simulate success
    step_output = %{simulated: true}

    # Store output in runtime state
    Runtime.store_step_output(state.runtime_table, step_id, step_output)
    Runtime.mark_step_completed(state.runtime_table, step_id)

    # Publish step completed
    ProgressTracker.publish_step_completed(
      state.execution_id,
      step_id,
      step["name"],
      :ok
    )

    # Continue with next steps
    new_state = %{state | step_queue: remaining}
    execute_workflow(new_state)
  end

  defp finalize_execution(state, status, output_or_error) do
    # Update execution record
    changeset =
      case status do
        :completed ->
          Execution.complete_changeset(state.execution, output_or_error)

        :failed ->
          Execution.fail_changeset(state.execution, output_or_error)

        :cancelled ->
          Execution.cancel_changeset(state.execution)
      end

    {:ok, _execution} = Repo.update(changeset)

    # Force final snapshot
    Runtime.force_snapshot(state.runtime_table)

    # Publish finished
    output_data = Runtime.get_variables(state.runtime_table)
    ProgressTracker.publish_finished(state.execution_id, status, output_data)

    # Cleanup runtime state
    Runtime.cleanup(state.runtime_table)

    Logger.info("Workflow execution #{state.execution_id} finished: #{status}")

    :ok
  end

  defp build_execution_plan(workflow_def) do
    # Simple implementation - return steps in order
    # TODO: Implement proper topological sort based on connections
    steps = workflow_def["steps"] || []
    Enum.map(steps, & &1["id"])
  end

  defp find_step(workflow_def, step_id) do
    steps = workflow_def["steps"] || []
    Enum.find(steps, &(&1["id"] == step_id))
  end

  defp via_tuple(execution_id) do
    {:via, Registry, {GscAnalytics.Workflows.EngineRegistry, execution_id}}
  end
end
