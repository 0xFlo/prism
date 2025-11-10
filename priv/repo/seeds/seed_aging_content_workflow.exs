# Seeds the "Flag Aging Content for Updates" workflow template
#
# This workflow:
# 1. Queries for URLs with publish_date > 90 days ago
# 2. Updates their metadata with needs_update=true and priority=P2
#
# Usage: mix run priv/repo/seeds/seed_aging_content_workflow.exs

alias GscAnalytics.{Repo, Workflows}
alias GscAnalytics.Schemas.Workspace

require Logger

Logger.info("Seeding aging content workflow template...")

# Find the first active account (or use account_id: 1)
account =
  case Repo.all(Workspace) |> List.first() do
    nil ->
      Logger.warning("No workspaces found. Creating demo workspace...")

      %Workspace{
        name: "Demo Workspace",
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }
      |> Repo.insert!()

    workspace ->
      workspace
  end

# Get the first user for created_by_id (workflows require a valid user)
created_by_id = 1

workflow_definition = %{
  "version" => "1.0",
  "steps" => [
    %{
      "id" => "query_aging_content",
      "type" => "query",
      "name" => "Find Aging Content",
      "config" => %{
        "query_type" => "aging_content",
        "params" => %{
          "days_threshold" => 90
        }
      },
      "position" => %{"x" => 100, "y" => 100}
    },
    %{
      "id" => "update_metadata",
      "type" => "update_metadata",
      "name" => "Mark as Aging Content",
      "config" => %{
        "source_step" => "query_aging_content",
        "updates" => %{
          "content_category" => "Aging",
          "last_update_date" => Date.to_string(Date.utc_today())
        }
      },
      "position" => %{"x" => 100, "y" => 250}
    }
  ],
  "connections" => [
    %{
      "from" => "query_aging_content",
      "to" => "update_metadata"
    }
  ]
}

# Check if workflow already exists
existing_workflow =
  Workflows.list_workflows(account.id)
  |> Enum.find(&(&1.name == "Flag Aging Content for Updates"))

if existing_workflow do
  Logger.info("Workflow already exists (ID: #{existing_workflow.id}). Updating definition...")

  case Workflows.update_workflow(existing_workflow, %{
         definition: workflow_definition,
         description:
           "Identifies content published more than 90 days ago and flags it for updates. Sets needs_update=true and priority=P2 for editorial review.",
         status: :published,
         tags: ["content-audit", "aging-content", "automated"]
       }) do
    {:ok, workflow} ->
      Logger.info("✅ Updated workflow: #{workflow.name} (ID: #{workflow.id})")
      Logger.info("   The workflow definition has been updated to use content_category field.")

    {:error, changeset} ->
      Logger.error("❌ Failed to update workflow: #{inspect(changeset.errors)}")
  end
else
  Logger.info("Creating new workflow...")

  case Workflows.create_workflow(%{
         name: "Flag Aging Content for Updates",
         description:
           "Identifies content published more than 90 days ago and marks it with content_category='Aging' for editorial review.",
         status: :published,
         definition: workflow_definition,
         account_id: account.id,
         created_by_id: created_by_id,
         tags: ["content-audit", "aging-content", "automated"],
         version: 1
       }) do
    {:ok, workflow} ->
      Logger.info("✅ Created workflow: #{workflow.name} (ID: #{workflow.id})")
      Logger.info("   Account: #{account.name} (ID: #{account.id})")
      Logger.info("   Steps: #{length(workflow.definition["steps"])}")
      Logger.info("")
      Logger.info("To run this workflow:")
      Logger.info("1. Visit /dashboard/workflows in your browser")
      Logger.info("2. Click '#{workflow.name}'")
      Logger.info("3. Click 'Run Workflow' button")

    {:error, changeset} ->
      Logger.error("❌ Failed to create workflow: #{inspect(changeset.errors)}")
      Logger.error("Changeset: #{inspect(changeset)}")
  end
end

Logger.info("")
Logger.info("Seeding complete!")
