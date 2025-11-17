---
ticket_id: "13"
title: "Create Priority Import Workflow Step"
status: pending
priority: P2
milestone: 5
estimate_days: 3
dependencies: ["02", "05"]
blocks: ["14"]
success_metrics:
  - "Workflow step created and configurable"
  - "Can be scheduled via Ops tooling"
  - "Invokes Mix task with correct parameters"
  - "Integrates with existing workflow engine"
---

# Ticket 13: Create Priority Import Workflow Step

## Context

Create a workflow step that wraps the Mix task (Ticket 02) and metadata upsert helper (Ticket 05) for automated, scheduled priority URL imports. This allows Ops to trigger imports on a schedule or manually via the workflow UI.

## Acceptance Criteria

1. ✅ Create `GscAnalytics.Workflows.Steps.PriorityImportStep`
2. ✅ Accept configurable file paths and account_id
3. ✅ Invoke `Importer.run/2` with correct options
4. ✅ Return workflow-compatible result format
5. ✅ Handle errors gracefully (retry logic)
6. ✅ Log workflow execution via Oban
7. ✅ Support dry-run mode for testing
8. ✅ Integrate with existing workflow scheduler

## Technical Specifications

```elixir
defmodule GscAnalytics.Workflows.Steps.PriorityImportStep do
  @behaviour GscAnalytics.Workflows.Step

  alias GscAnalytics.PriorityUrls.Importer

  @impl true
  def run(params, context) do
    account_id = params["account_id"]
    file_pattern = params["file_pattern"] || "output/priority_urls_p*.json"
    dry_run = params["dry_run"] || false

    case Importer.run(account_id, files: file_pattern, dry_run: dry_run) do
      {:ok, stats} ->
        {:ok, %{
          status: "success",
          urls_imported: stats.urls_kept,
          batch_id: stats.batch_id
        }}

      {:error, reason} ->
        {:error, "Priority import failed: #{inspect(reason)}"}
    end
  end
end
```

### Workflow Configuration

```yaml
# config/workflows/rula_priority_import.yml
name: "Rula Priority URL Import"
schedule: "0 2 * * 0"  # Every Sunday at 2 AM
steps:
  - type: priority_import
    params:
      account_id: 123
      file_pattern: "output/priority_urls_p*.json"
      dry_run: false
```

## Testing Requirements

```elixir
test "workflow step invokes importer successfully" do
  params = %{"account_id" => 123, "file_pattern" => "test/fixtures/p*.json"}

  {:ok, result} = PriorityImportStep.run(params, %{})

  assert result.status == "success"
  assert result.urls_imported > 0
end

test "handles importer errors gracefully" do
  params = %{"account_id" => 999, "file_pattern" => "nonexistent/*.json"}

  {:error, message} = PriorityImportStep.run(params, %{})

  assert message =~ "Priority import failed"
end
```

## Success Metrics

- ✓ Workflow step runs successfully
- ✓ Can be scheduled and triggered
- ✓ Errors logged and handled
- ✓ Integrates with Oban dashboard

## Related Files

- `02-mix-task-ingestion-pipeline.md` - Wraps this functionality
- `05-upsert-helper-module.md` - Uses upsert helper
- `14-post-import-job-enqueueing.md` - Triggers follow-up jobs
