# Script to seed test workflows for the workflow runner
# Run with: mix run priv/repo/seed_workflows.exs

import Ecto.Query

alias GscAnalytics.Repo
alias GscAnalytics.Workflows
alias GscAnalytics.Schemas.Workflow
alias GscAnalytics.Auth.User
alias GscAnalytics.Schemas.Workspace

# Get first user and workspace (you'll need at least one)
user = Repo.one(from u in User, limit: 1)
workspace = Repo.one(from w in Workspace, limit: 1)

if is_nil(user) or is_nil(workspace) do
  IO.puts("❌ No user or workspace found. Please create a user first via the UI.")
  System.halt(1)
end

IO.puts("Creating test workflows for user #{user.email} in workspace #{workspace.name}...")

# Test Workflow 1: Simple 3-step workflow
workflow1_attrs = %{
  name: "Simple Test Workflow",
  description: "A basic 3-step workflow to test the execution engine",
  status: :published,
  definition: %{
    "version" => "1.0",
    "steps" => [
      %{
        "id" => "step_1",
        "type" => "test",
        "name" => "Initialize",
        "config" => %{"delay_ms" => 1000}
      },
      %{
        "id" => "step_2",
        "type" => "test",
        "name" => "Process Data",
        "config" => %{"delay_ms" => 2000}
      },
      %{
        "id" => "step_3",
        "type" => "test",
        "name" => "Finalize",
        "config" => %{"delay_ms" => 1000}
      }
    ],
    "connections" => [
      %{"from" => "step_1", "to" => "step_2"},
      %{"from" => "step_2", "to" => "step_3"}
    ]
  }
}

case Repo.get_by(Workflow, name: workflow1_attrs.name, account_id: workspace.id) do
  nil ->
    {:ok, _workflow} = Workflows.create_workflow(Map.merge(workflow1_attrs, %{
      account_id: workspace.id,
      created_by_id: user.id
    }))
    IO.puts("✅ Created: Simple Test Workflow")

  existing ->
    IO.puts("⚠️  Already exists: Simple Test Workflow (ID: #{existing.id})")
end

# Test Workflow 2: Multi-step content workflow
workflow2_attrs = %{
  name: "Content Processing Pipeline",
  description: "Demo workflow with 5 steps simulating content processing",
  status: :published,
  definition: %{
    "version" => "1.0",
    "steps" => [
      %{
        "id" => "fetch_content",
        "type" => "api",
        "name" => "Fetch Content",
        "config" => %{"url" => "https://example.com/api/content"}
      },
      %{
        "id" => "analyze",
        "type" => "llm",
        "name" => "Analyze with AI",
        "config" => %{"model" => "claude-3-7-sonnet"}
      },
      %{
        "id" => "validate",
        "type" => "conditional",
        "name" => "Validate Quality",
        "config" => %{"condition" => "analyze.output.score > 0.8"}
      },
      %{
        "id" => "transform",
        "type" => "code",
        "name" => "Transform Data",
        "config" => %{"code" => "Map.put(data, :processed, true)"}
      },
      %{
        "id" => "publish",
        "type" => "api",
        "name" => "Publish Result",
        "config" => %{"url" => "https://example.com/api/publish"}
      }
    ],
    "connections" => [
      %{"from" => "fetch_content", "to" => "analyze"},
      %{"from" => "analyze", "to" => "validate"},
      %{"from" => "validate", "to" => "transform"},
      %{"from" => "transform", "to" => "publish"}
    ]
  }
}

case Repo.get_by(Workflow, name: workflow2_attrs.name, account_id: workspace.id) do
  nil ->
    {:ok, _workflow} = Workflows.create_workflow(Map.merge(workflow2_attrs, %{
      account_id: workspace.id,
      created_by_id: user.id
    }))
    IO.puts("✅ Created: Content Processing Pipeline")

  existing ->
    IO.puts("⚠️  Already exists: Content Processing Pipeline (ID: #{existing.id})")
end

# Test Workflow 3: Quick test workflow
workflow3_attrs = %{
  name: "Quick Test",
  description: "Single step workflow for quick testing",
  account_id: workspace.id,
  created_by_id: user.id,
  status: :draft,
  definition: %{
    "version" => "1.0",
    "steps" => [
      %{
        "id" => "single_step",
        "type" => "test",
        "name" => "Quick Test Step",
        "config" => %{"delay_ms" => 500}
      }
    ],
    "connections" => []
  }
}

case Repo.get_by(Workflow, name: workflow3_attrs.name, account_id: workspace.id) do
  nil ->
    {:ok, _workflow} = Workflows.create_workflow(Map.merge(workflow3_attrs, %{
      account_id: workspace.id,
      created_by_id: user.id
    }))
    IO.puts("✅ Created: Quick Test")

  existing ->
    IO.puts("⚠️  Already exists: Quick Test (ID: #{existing.id})")
end

IO.puts("\n✨ Workflow seeding complete!")
IO.puts("Navigate to /dashboard/workflows to see and run the test workflows.")
