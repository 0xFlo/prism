defmodule GscAnalytics.Workflows.Runtime do
  @moduledoc """
  ETS-backed workflow execution runtime state.

  Replaces Agent-based state management to provide crash recovery and better
  performance characteristics. Per Codex review, this approach:

  1. Stores step cursor, variables, and last event in ETS
  2. Persists snapshots every step completion to DB
  3. Enables mid-pipeline restart recovery
  4. Avoids single-process bottlenecks

  ## Architecture

  Each workflow execution gets its own ETS table for runtime state.
  The table is owned by the execution's supervisor to survive GenServer crashes.

  ## State Structure

      %{
        execution_id: binary_id,
        step_cursor: "step_3",
        variables: %{
          "step_1" => %{output: %{...}},
          "step_2" => %{output: %{...}},
          "input" => %{...}
        },
        completed_steps: ["step_1", "step_2"],
        failed_steps: [],
        last_event: %{type: :step_completed, ...},
        last_snapshot_at: ~U[...]
      }
  """

  require Logger

  alias GscAnalytics.Repo
  alias GscAnalytics.Workflows.Execution

  @typedoc "Runtime state map"
  @type state :: %{
          execution_id: binary(),
          step_cursor: String.t() | nil,
          variables: map(),
          completed_steps: [String.t()],
          failed_steps: [String.t()],
          last_event: map() | nil,
          last_snapshot_at: DateTime.t() | nil
        }

  # Snapshot every 5 seconds
  @snapshot_interval_ms 5_000

  ## Public API

  @doc """
  Creates a new runtime state table for an execution.

  The table is owned by the calling process (typically the execution supervisor).
  """
  @spec new(binary(), map()) :: :ets.tid()
  def new(execution_id, initial_input \\ %{}) do
    table =
      :ets.new(:"workflow_runtime_#{execution_id}", [
        :set,
        :public,
        read_concurrency: true,
        write_concurrency: false
      ])

    initial_state = %{
      execution_id: execution_id,
      step_cursor: nil,
      variables: %{"input" => initial_input},
      completed_steps: [],
      failed_steps: [],
      last_event: nil,
      last_snapshot_at: DateTime.utc_now()
    }

    :ets.insert(table, {:state, initial_state})

    Logger.debug("Created workflow runtime for execution #{execution_id}")

    table
  end

  @doc """
  Restores runtime state from a database snapshot.

  Used for crash recovery - loads the last persisted checkpoint.
  """
  @spec restore(binary()) :: {:ok, :ets.tid()} | {:error, :not_found}
  def restore(execution_id) do
    case Repo.get(Execution, execution_id) do
      nil ->
        {:error, :not_found}

      execution ->
        table = new(execution_id, execution.input_data || %{})

        # Restore from context snapshot
        if execution.context_snapshot && map_size(execution.context_snapshot) > 0 do
          restored_state = %{
            execution_id: execution_id,
            step_cursor: execution.current_step_id,
            variables: execution.context_snapshot,
            completed_steps: execution.completed_step_ids || [],
            failed_steps: execution.failed_step_ids || [],
            last_event: nil,
            last_snapshot_at: execution.updated_at
          }

          :ets.insert(table, {:state, restored_state})

          Logger.info(
            "Restored workflow runtime for execution #{execution_id}, cursor: #{execution.current_step_id}"
          )
        end

        {:ok, table}
    end
  end

  @doc """
  Gets the current runtime state.
  """
  @spec get_state(:ets.tid()) :: state()
  def get_state(table) do
    case :ets.lookup(table, :state) do
      [{:state, state}] -> state
      [] -> raise "Runtime state not found in ETS table"
    end
  end

  @doc """
  Updates the step cursor.
  """
  @spec set_step_cursor(:ets.tid(), String.t() | nil) :: :ok
  def set_step_cursor(table, step_id) do
    update_state(table, fn state ->
      %{state | step_cursor: step_id}
    end)
  end

  @doc """
  Stores a step output in variables.
  """
  @spec store_step_output(:ets.tid(), String.t(), map()) :: :ok
  def store_step_output(table, step_id, output) do
    update_state(table, fn state ->
      variables = Map.put(state.variables, step_id, %{output: output})
      %{state | variables: variables}
    end)

    maybe_snapshot(table)
  end

  @doc """
  Gets a step's output from variables.
  """
  @spec get_step_output(:ets.tid(), String.t()) :: map() | nil
  def get_step_output(table, step_id) do
    state = get_state(table)
    # Try atom key first (in-memory), then string key (restored from DB)
    get_in(state.variables, [step_id, :output]) ||
      get_in(state.variables, [step_id, "output"])
  end

  @doc """
  Gets all variables (for interpolation).
  """
  @spec get_variables(:ets.tid()) :: map()
  def get_variables(table) do
    state = get_state(table)
    state.variables
  end

  @doc """
  Updates variables directly (e.g., for iteration element/index).
  """
  @spec update_variable(:ets.tid(), String.t(), any()) :: :ok
  def update_variable(table, key, value) do
    update_state(table, fn state ->
      variables = Map.put(state.variables, key, value)
      %{state | variables: variables}
    end)
  end

  @doc """
  Marks a step as completed.
  """
  @spec mark_step_completed(:ets.tid(), String.t()) :: :ok
  def mark_step_completed(table, step_id) do
    update_state(table, fn state ->
      %{state | completed_steps: [step_id | state.completed_steps]}
    end)

    maybe_snapshot(table)
  end

  @doc """
  Marks a step as failed.
  """
  @spec mark_step_failed(:ets.tid(), String.t()) :: :ok
  def mark_step_failed(table, step_id) do
    update_state(table, fn state ->
      %{state | failed_steps: [step_id | state.failed_steps]}
    end)

    force_snapshot(table)
  end

  @doc """
  Records the last event.
  """
  @spec record_event(:ets.tid(), map()) :: :ok
  def record_event(table, event) do
    update_state(table, fn state ->
      %{state | last_event: event}
    end)
  end

  @doc """
  Forces an immediate snapshot to the database.

  Called on step completion, failure, or pause.
  """
  @spec force_snapshot(:ets.tid()) :: :ok
  def force_snapshot(table) do
    state = get_state(table)

    changeset =
      Execution
      |> Repo.get!(state.execution_id)
      |> Execution.progress_changeset(%{
        current_step_id: state.step_cursor,
        completed_step_ids: state.completed_steps,
        failed_step_ids: state.failed_steps,
        context_snapshot: state.variables
      })

    case Repo.update(changeset) do
      {:ok, _execution} ->
        update_state(table, fn s ->
          %{s | last_snapshot_at: DateTime.utc_now()}
        end)

        Logger.debug("Snapshot persisted for execution #{state.execution_id}")
        :ok

      {:error, changeset} ->
        Logger.error("Failed to persist snapshot: #{inspect(changeset.errors)}")
        :ok
    end
  end

  @doc """
  Cleans up the runtime state table.
  """
  @spec cleanup(:ets.tid()) :: :ok
  def cleanup(table) do
    :ets.delete(table)
    :ok
  end

  ## Private Functions

  defp update_state(table, update_fun) when is_function(update_fun, 1) do
    state = get_state(table)
    new_state = update_fun.(state)
    :ets.insert(table, {:state, new_state})
    :ok
  end

  defp maybe_snapshot(table) do
    state = get_state(table)
    last_snapshot = state.last_snapshot_at

    time_since_snapshot =
      DateTime.diff(DateTime.utc_now(), last_snapshot, :millisecond)

    if time_since_snapshot >= @snapshot_interval_ms do
      force_snapshot(table)
    else
      :ok
    end
  end
end
