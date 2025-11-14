---
ticket_id: "14"
title: "Trigger Post-Import HTTP Status Checks"
status: pending
priority: P2
milestone: 5
estimate_days: 2
dependencies: ["13"]
blocks: ["15"]
success_metrics:
  - "HTTP status checks enqueued for new/changed URLs"
  - "Jobs batched efficiently (not overwhelming queue)"
  - "Only priority URLs processed (not entire dataset)"
---

# Ticket 14: Trigger Post-Import HTTP Status Checks

## Context

After importing priority URLs (Ticket 13), automatically enqueue HTTP status check jobs for new or changed URLs. This ensures crawler and status data is fresh for newly prioritized URLs without manually triggering checks.

## Acceptance Criteria

1. ✅ Detect new URLs (not in metadata before import)
2. ✅ Detect changed priority tiers (P3 → P1)
3. ✅ Enqueue `HttpStatusCheckWorker` for affected URLs
4. ✅ Batch jobs to avoid overwhelming Oban queue
5. ✅ Call `Persistence.enqueue_http_status_checks/3` for changed URLs
6. ✅ Log job counts and batch IDs
7. ✅ Make post-import hook configurable (can disable)
8. ✅ Add metrics for job enqueueing

## Technical Specifications

```elixir
defmodule GscAnalytics.PriorityUrls.PostImportHooks do
  alias GscAnalytics.Workers.HttpStatusCheckWorker
  alias GscAnalytics.DataSources.GSC.Core.Persistence

  @doc """
  Enqueue status checks for URLs affected by priority import.
  """
  def enqueue_status_checks(account_id, batch_id, opts \\ []) do
    # Find URLs from this batch
    new_or_changed_urls = fetch_batch_urls(account_id, batch_id)

    # Batch enqueue (1000 at a time)
    new_or_changed_urls
    |> Enum.chunk_every(1000)
    |> Enum.each(fn batch ->
      Persistence.enqueue_http_status_checks(account_id, batch, batch_id)
    end)

    Logger.info("Enqueued HTTP status checks for #{length(new_or_changed_urls)} URLs (batch: #{batch_id})")

    {:ok, %{urls_enqueued: length(new_or_changed_urls)}}
  end

  defp fetch_batch_urls(account_id, batch_id) do
    from(m in UrlMetadata,
      where: m.account_id == ^account_id,
      where: m.metadata_batch_id == ^batch_id,
      select: m.url
    )
    |> Repo.all()
  end
end
```

### Integration with Workflow

```elixir
defmodule GscAnalytics.Workflows.Steps.PriorityImportStep do
  def run(params, context) do
    case Importer.run(account_id, opts) do
      {:ok, stats} ->
        # Enqueue post-import jobs
        unless params["skip_status_checks"] do
          PostImportHooks.enqueue_status_checks(account_id, stats.batch_id)
        end

        {:ok, stats}
    end
  end
end
```

## Testing Requirements

```elixir
test "enqueues status checks for new URLs" do
  batch_id = "batch_001"

  # Import 100 new URLs
  insert_list(100, :url_metadata, account_id: 123, metadata_batch_id: batch_id)

  {:ok, result} = PostImportHooks.enqueue_status_checks(123, batch_id)

  assert result.urls_enqueued == 100

  # Verify Oban jobs created
  jobs = Repo.all(Oban.Job, where: [worker: "HttpStatusCheckWorker"])
  assert length(jobs) == 100
end

test "batches large imports efficiently" do
  batch_id = "batch_large"
  insert_list(10_000, :url_metadata, account_id: 123, metadata_batch_id: batch_id)

  {:ok, _} = PostImportHooks.enqueue_status_checks(123, batch_id)

  # Verify jobs batched (not all at once)
  # Should not overwhelm queue
end
```

## Success Metrics

- ✓ Status checks enqueued for all new/changed URLs
- ✓ Jobs processed within 1 hour for 60k URLs
- ✓ Queue not overwhelmed (max 5k pending jobs)

## Related Files

- `13-priority-import-workflow.md` - Invokes this after import
- `15-logging-telemetry.md` - Logs job metrics
