# Workflow System Testing Guide

**Status**: Foundation Phase Complete
**Last Updated**: 2025-01-09

## Quick Start - Testing What's Built

### Phase 1: Database & Schema Verification ✅

**1. Verify Migrations Applied**
```bash
# Check migration status
mix ecto.migrations

# Expected output should show:
# up     20251109141727  create_workflows.exs
```

**2. Test Database Schema in IEx**
```elixir
# Start IEx
iex -S mix

# Verify tables exist
GscAnalytics.Repo.__adapter__().execute(
  GscAnalytics.Repo,
  "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_name LIKE 'workflow%'",
  []
)

# Expected: workflows, workflow_executions, workflow_execution_events, workflow_review_queue
```

**3. Test Ecto Schemas**
```elixir
# In IEx
alias GscAnalytics.Schemas.Workflow
alias GscAnalytics.Workflows.{Execution, ExecutionEvent}
alias GscAnalytics.Repo

# Create a test workflow
{:ok, workflow} = %Workflow{}
|> Workflow.changeset(%{
  name: "Test Workflow",
  description: "Simple test",
  account_id: 1,  # Use your actual workspace ID
  created_by_id: 1,  # Use your actual user ID
  definition: %{
    version: "1.0",
    steps: [
      %{id: "step_1", type: "test", name: "Test Step", config: %{}}
    ],
    connections: []
  }
})
|> Repo.insert()

# Verify workflow saved
Repo.get!(Workflow, workflow.id)

# Create a test execution
{:ok, execution} = %Execution{}
|> Execution.changeset(%{
  workflow_id: workflow.id,
  account_id: 1,
  input_data: %{test: "data"}
})
|> Repo.insert()

# Verify execution saved
Repo.get!(Execution, execution.id) |> Repo.preload(:workflow)

# Create a test event
{:ok, event} = ExecutionEvent.execution_started(execution.id, %{test: true})
|> Repo.insert()

# Verify event saved
Repo.get!(ExecutionEvent, event.id)

# Cleanup
Repo.delete!(event)
Repo.delete!(execution)
Repo.delete!(workflow)
```

### Phase 2: WorkflowRuntime ETS Testing ✅

**Test ETS-backed State Management**
```elixir
# In IEx
alias GscAnalytics.Workflows.Runtime

# Create a new runtime state
execution_id = Ecto.UUID.generate()
input_data = %{"url" => "https://example.com", "keyword" => "elixir"}

table = Runtime.new(execution_id, input_data)

# Verify state created
state = Runtime.get_state(table)
IO.inspect(state, label: "Initial State")
# Expected: %{execution_id: ..., step_cursor: nil, variables: %{"input" => ...}}

# Test storing step output
Runtime.store_step_output(table, "step_1", %{result: "success", count: 42})

# Verify output stored
output = Runtime.get_step_output(table, "step_1")
IO.inspect(output, label: "Step 1 Output")
# Expected: %{result: "success", count: 42}

# Test marking step completed
Runtime.mark_step_completed(table, "step_1")

# Verify completion tracked
state = Runtime.get_state(table)
IO.inspect(state.completed_steps, label: "Completed Steps")
# Expected: ["step_1"]

# Test variable access
all_vars = Runtime.get_variables(table)
IO.inspect(all_vars, label: "All Variables")
# Expected: %{"input" => ..., "step_1" => %{output: ...}}

# Cleanup
Runtime.cleanup(table)
```

**Test Crash Recovery**
```elixir
# In IEx
alias GscAnalytics.Workflows.{Runtime, Execution}
alias GscAnalytics.Repo

# Create a real execution in DB
{:ok, workflow} = %GscAnalytics.Schemas.Workflow{}
|> GscAnalytics.Schemas.Workflow.changeset(%{
  name: "Recovery Test",
  account_id: 1,
  created_by_id: 1,
  definition: %{steps: [%{id: "step_1", type: "test"}]}
})
|> Repo.insert()

{:ok, execution} = %Execution{}
|> Execution.changeset(%{
  workflow_id: workflow.id,
  account_id: 1,
  input_data: %{test: "recovery"}
})
|> Repo.insert()

# Create runtime and store some state
table = Runtime.new(execution.id, execution.input_data)
Runtime.store_step_output(table, "step_1", %{data: "important"})
Runtime.mark_step_completed(table, "step_1")

# Force snapshot to DB
Runtime.force_snapshot(table)

# Simulate crash - cleanup table
Runtime.cleanup(table)

# Restore from DB snapshot
{:ok, restored_table} = Runtime.restore(execution.id)

# Verify state restored
restored_state = Runtime.get_state(restored_table)
IO.inspect(restored_state.completed_steps, label: "Restored Completed Steps")
# Expected: ["step_1"]

output = Runtime.get_step_output(restored_table, "step_1")
IO.inspect(output, label: "Restored Step Output")
# Expected: %{data: "important"}

# Cleanup
Runtime.cleanup(restored_table)
Repo.delete!(execution)
Repo.delete!(workflow)
```

### Phase 3: Engine Testing (Partial - Missing Dependencies)

**Note**: The Engine requires ProgressTracker and Step Executors to be fully functional. Here's what you can test now:

**Test Engine Module Loading**
```elixir
# In IEx
alias GscAnalytics.Workflows.Engine

# Verify module loads
Code.ensure_loaded?(Engine)
# Expected: true

# Check exported functions
Engine.__info__(:functions)
# Expected: [start_execution: 1, start_link: 1, execute: 1, pause: 1, resume: 1, ...]
```

**Test Registry Setup** (when EngineSupervisor is added)
```elixir
# This will work after adding to supervision tree
Registry.lookup(GscAnalytics.Workflows.EngineRegistry, "test-id")
# Expected: [] (empty until engine started)
```

## Phase 2: Testing After Next Components

### After EngineSupervisor + ProgressTracker

**Full Engine Test**
```elixir
# In IEx
alias GscAnalytics.Workflows.{Engine, ProgressTracker}
alias GscAnalytics.Repo

# Subscribe to progress updates
ProgressTracker.subscribe()

# Create workflow and execution
{:ok, workflow} = # ... create workflow
{:ok, execution} = # ... create execution

# Start engine
{:ok, pid} = Engine.start_execution(execution.id)

# Execute workflow
Engine.execute(execution.id)

# Listen for progress messages
flush()
# Expected: {:workflow_progress, {:step_started, ...}}

# Check execution status
execution = Repo.get!(Execution, execution.id)
execution.status
# Expected: :running or :completed

# Test pause
Engine.pause(execution.id)
execution = Repo.get!(Execution, execution.id)
execution.status
# Expected: :paused

# Test resume
Engine.resume(execution.id)

# Test stop
Engine.stop_execution(execution.id)
execution = Repo.get!(Execution, execution.id)
execution.status
# Expected: :cancelled
```

### After Variable System

**Template Compilation Test**
```elixir
# In IEx
alias GscAnalytics.Workflows.Variables

context = %{
  "step_1" => %{output: %{"url" => "https://example.com", "score" => 8}},
  "input" => %{"keyword" => "elixir"}
}

# Test simple interpolation
Variables.interpolate("URL: {{step_1.output.url}}", context)
# Expected: "URL: https://example.com"

# Test nested access
Variables.interpolate("Score: {{step_1.output.score}}", context)
# Expected: "Score: 8"

# Test filters
Variables.interpolate("Keyword: {{input.keyword | upcase}}", context)
# Expected: "Keyword: ELIXIR"

# Test array access
context_with_array = %{
  "step_1" => %{output: %{"results" => [%{"name" => "first"}, %{"name" => "second"}]}}
}
Variables.interpolate("First: {{step_1.output.results[0].name}}", context_with_array)
# Expected: "First: first"
```

**Expression Evaluation Test**
```elixir
# In IEx
alias GscAnalytics.Workflows.Expressions

context = %{
  "step_1" => %{output: %{"score" => 8, "clicks" => 100}}
}

# Test comparison
Expressions.evaluate("step_1.output.score > 7", context)
# Expected: {:ok, true}

Expressions.evaluate("step_1.output.clicks >= 100", context)
# Expected: {:ok, true}

# Test logical operators
Expressions.evaluate("step_1.output.score > 7 && step_1.output.clicks >= 100", context)
# Expected: {:ok, true}

Expressions.evaluate("step_1.output.score < 5 || step_1.output.clicks > 50", context)
# Expected: {:ok, true}
```

### After Step Executor System

**Step Execution Test**
```elixir
# In IEx
alias GscAnalytics.Workflows.Steps.Executor

# Test LLM step
llm_step = %{
  "id" => "step_1",
  "type" => "llm",
  "config" => %{
    "model" => "claude-3-7-sonnet",
    "system_prompt" => "You are helpful",
    "user_prompt" => "Say hello"
  }
}

context = %{}
account_id = 1

Executor.execute_step(llm_step, context, account_id)
# Expected: {:ok, %{text: "Hello! How can I help you?"}}

# Test API step
api_step = %{
  "id" => "step_2",
  "type" => "api",
  "config" => %{
    "method" => "GET",
    "url" => "https://api.example.com/data"
  }
}

Executor.execute_step(api_step, context, account_id)
# Expected: {:ok, %{status: 200, body: ...}}

# Test conditional step
conditional_step = %{
  "id" => "step_3",
  "type" => "conditional",
  "config" => %{
    "condition" => "step_1.output.score > 7"
  }
}

context = %{"step_1" => %{output: %{"score" => 8}}}

Executor.execute_step(conditional_step, context, account_id)
# Expected: {:ok, %{condition_met: true, branch: "true"}}
```

## Integration Testing

### End-to-End Workflow Test

**Create a simple 3-step workflow and execute it:**

```elixir
# In IEx
alias GscAnalytics.Schemas.Workflow
alias GscAnalytics.Workflows.{Execution, Engine, ProgressTracker}
alias GscAnalytics.Repo

# Subscribe to progress
ProgressTracker.subscribe()

# Create workflow
{:ok, workflow} = %Workflow{}
|> Workflow.changeset(%{
  name: "Simple Test Workflow",
  account_id: 1,
  created_by_id: 1,
  definition: %{
    version: "1.0",
    steps: [
      %{
        id: "step_1",
        type: "api",
        name: "Fetch Data",
        config: %{
          method: "GET",
          url: "https://httpbin.org/json"
        }
      },
      %{
        id: "step_2",
        type: "conditional",
        name: "Check Result",
        config: %{
          condition: "step_1.output.status == 200"
        }
      },
      %{
        id: "step_3",
        type: "code",
        name: "Process Result",
        config: %{
          code: "Map.get(context, \"step_1\") |> Map.get(:output)"
        }
      }
    ],
    connections: [
      %{from: "step_1", to: "step_2"},
      %{from: "step_2", to: "step_3"}
    ]
  }
})
|> Repo.insert()

# Create execution
{:ok, execution} = %Execution{}
|> Execution.changeset(%{
  workflow_id: workflow.id,
  account_id: 1,
  input_data: %{}
})
|> Repo.insert()

# Start and execute
{:ok, _pid} = Engine.start_execution(execution.id)
Engine.execute(execution.id)

# Watch progress messages
receive do
  {:workflow_progress, message} -> IO.inspect(message, label: "Progress")
after
  5000 -> IO.puts("No messages")
end

# Check final state
execution = Repo.get!(Execution, execution.id)
IO.inspect(execution.status, label: "Final Status")
IO.inspect(execution.output_data, label: "Output Data")

# Check events
events = GscAnalytics.Workflows.ExecutionEvent.for_execution(execution.id)
|> GscAnalytics.Workflows.ExecutionEvent.chronological()
|> Repo.all()

Enum.each(events, fn event ->
  IO.puts("#{event.event_type} - #{event.step_id}")
end)
```

## Test Files to Create

Once you have the full system, create these automated tests:

**1. Runtime Test** (`test/gsc_analytics/workflows/runtime_test.exs`)
```elixir
defmodule GscAnalytics.Workflows.RuntimeTest do
  use GscAnalytics.DataCase, async: true

  alias GscAnalytics.Workflows.Runtime

  describe "new/2" do
    test "creates ETS table with initial state" do
      execution_id = Ecto.UUID.generate()
      input = %{"test" => "data"}

      table = Runtime.new(execution_id, input)

      state = Runtime.get_state(table)
      assert state.execution_id == execution_id
      assert state.variables["input"] == input
      assert state.completed_steps == []

      Runtime.cleanup(table)
    end
  end

  describe "crash recovery" do
    test "restores state from database snapshot" do
      # Test implementation...
    end
  end
end
```

**2. Engine Test** (`test/gsc_analytics/workflows/engine_test.exs`)
```elixir
defmodule GscAnalytics.Workflows.EngineTest do
  use GscAnalytics.DataCase, async: false

  alias GscAnalytics.Workflows.Engine

  setup do
    # Create test workflow and execution
    %{execution: execution}
  end

  test "executes simple workflow", %{execution: execution} do
    {:ok, _pid} = Engine.start_execution(execution.id)
    Engine.execute(execution.id)

    # Wait for completion
    :timer.sleep(1000)

    execution = Repo.get!(Execution, execution.id)
    assert execution.status == :completed
  end
end
```

## Troubleshooting

### Common Issues

**1. "no process" errors for GenServers**
```elixir
# Verify supervision tree
Supervisor.which_children(GscAnalytics.Supervisor)
# Should show EngineRegistry, EngineSupervisor, ProgressTracker
```

**2. ETS table not found**
```elixir
# List all ETS tables
:ets.all() |> Enum.filter(&is_atom/1)
# Should include :workflow_template_cache (after Variables init)
```

**3. Database errors**
```bash
# Reset database
mix ecto.reset

# Run migrations
mix ecto.migrate
```

**4. Module not found**
```bash
# Recompile
mix compile --force

# Check for compilation errors
mix compile --warnings-as-errors
```

## Performance Testing

### Load Testing (Once Complete)

```elixir
# Create 100 concurrent workflow executions
1..100
|> Task.async_stream(fn i ->
  {:ok, execution} = create_test_execution(i)
  {:ok, _pid} = Engine.start_execution(execution.id)
  Engine.execute(execution.id)
end, max_concurrency: 10, timeout: 60_000)
|> Enum.to_list()
```

## Next Steps

1. **Add EngineSupervisor** - Enable full Engine testing
2. **Add ProgressTracker** - Test real-time updates
3. **Implement Variables** - Test template compilation
4. **Implement Expressions** - Test safe evaluation
5. **Implement Step Executors** - Test step execution
6. **Write Automated Tests** - Achieve >80% coverage

See `docs/WORKFLOW_SYSTEM.md` for complete implementation roadmap.
