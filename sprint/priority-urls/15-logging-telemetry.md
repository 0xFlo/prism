---
ticket_id: "15"
title: "Add Logging and Telemetry for Observability"
status: pending
priority: P3
milestone: 5
estimate_days: 2
dependencies: ["03", "14"]
blocks: []
success_metrics:
  - "Telemetry events emitted for all import operations"
  - "Structured logging with batch_id context"
  - "Metrics available in monitoring dashboard"
  - "Alerts configured for failed imports"
---

# Ticket 15: Add Logging and Telemetry for Observability

## Context

Add structured logging and telemetry events for all priority URL operations: imports, status checks, backfills. This enables monitoring, alerting, and debugging in production.

## Acceptance Criteria

1. ✅ Emit telemetry events for import start/complete/error
2. ✅ Add structured logging with batch_id, account_id context
3. ✅ Track metrics: import duration, URLs processed, error rate
4. ✅ Integrate with existing monitoring (Datadog/New Relic)
5. ✅ Configure alerts for failed imports
6. ✅ Add Oban job logging links to batch records
7. ✅ Create observability dashboard for priority imports

## Technical Specifications

```elixir
defmodule GscAnalytics.PriorityUrls.Telemetry do
  require Logger

  def emit_import_start(account_id, batch_id, file_count) do
    :telemetry.execute(
      [:gsc_analytics, :priority_import, :start],
      %{file_count: file_count},
      %{account_id: account_id, batch_id: batch_id}
    )

    Logger.info("Priority import started",
      account_id: account_id,
      batch_id: batch_id,
      files: file_count
    )
  end

  def emit_import_complete(account_id, batch_id, stats) do
    :telemetry.execute(
      [:gsc_analytics, :priority_import, :complete],
      %{
        duration_ms: stats.duration_ms,
        urls_imported: stats.urls_kept,
        urls_dropped: stats.urls_dropped
      },
      %{account_id: account_id, batch_id: batch_id, status: stats.status}
    )

    Logger.info("Priority import completed",
      account_id: account_id,
      batch_id: batch_id,
      urls_imported: stats.urls_kept,
      duration_ms: stats.duration_ms
    )
  end

  def emit_import_error(account_id, batch_id, error) do
    :telemetry.execute(
      [:gsc_analytics, :priority_import, :error],
      %{},
      %{account_id: account_id, batch_id: batch_id, error: error}
    )

    Logger.error("Priority import failed",
      account_id: account_id,
      batch_id: batch_id,
      error: Exception.message(error)
    )
  end
end
```

### Monitoring Dashboard

```elixir
# Metrics tracked:
# - priority_import.duration_seconds (histogram)
# - priority_import.urls_processed (counter)
# - priority_import.errors (counter)
# - priority_import.active_imports (gauge)
```

## Success Metrics

- ✓ All telemetry events firing correctly
- ✓ Logs structured and searchable
- ✓ Alerts trigger on failures
- ✓ Dashboard shows import health

## Related Files

- `03-import-reporting-audit.md` - Audit trail foundation
- `13-priority-import-workflow.md` - Emits telemetry events
