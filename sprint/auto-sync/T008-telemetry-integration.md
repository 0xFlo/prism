# T008: Telemetry Integration and Audit Logging

**Status:** 🔵 Not Started
**Story Points:** 2
**Priority:** 🟡 P2 Medium
**TDD Required:** No (observability)
**Depends On:** T006

## Description
Integrate automatic sync events with existing telemetry infrastructure and audit logging system.

## Acceptance Criteria
- [ ] Auto-sync events logged to `logs/gsc_audit.log`
- [ ] Telemetry events follow existing audit log format
- [ ] Events include all relevant metadata (workspaces, duration, success/failure)
- [ ] Compatible with existing AuditLogger module
- [ ] No breaking changes to existing telemetry

## Implementation Steps

### 1. Review Existing Telemetry Structure

**Check current events:**
- `[:gsc_analytics, :api, :request]` - API calls
- `[:gsc_analytics, :sync, :complete]` - Manual sync operations
- `[:gsc_analytics, :auth, :token_refresh]` - Authentication

**New events to add:**
- `[:gsc_analytics, :auto_sync, :started]` - Auto-sync job started
- `[:gsc_analytics, :auto_sync, :complete]` - Auto-sync job completed
- `[:gsc_analytics, :auto_sync, :failure]` - Auto-sync job failed

### 2. Update AuditLogger to Handle Auto-Sync Events

**File:** `lib/gsc_analytics/data_sources/gsc/telemetry/audit_logger.ex`

Add new event handlers:

```elixir
defmodule GscAnalytics.DataSources.GSC.Telemetry.AuditLogger do
  # ... existing code ...

  def handle_event([:gsc_analytics, :auto_sync, :started], _measurements, metadata, _config) do
    log_entry = %{
      ts: DateTime.utc_now() |> DateTime.to_iso8601(),
      event: "auto_sync.started",
      metadata: %{
        job_id: metadata[:job_id],
        sync_days: metadata[:sync_days],
        total_workspaces: metadata[:total_workspaces]
      }
    }

    write_log(log_entry)
  end

  def handle_event([:gsc_analytics, :auto_sync, :complete], measurements, metadata, _config) do
    results = metadata[:results]

    log_entry = %{
      ts: DateTime.utc_now() |> DateTime.to_iso8601(),
      event: "auto_sync.complete",
      measurements: %{
        duration_ms: measurements[:duration_ms],
        total_workspaces: measurements[:total_workspaces],
        successes: measurements[:successes],
        failures: measurements[:failures],
        total_urls: measurements[:total_urls],
        total_queries: measurements[:total_queries],
        urls_per_second: measurements[:urls_per_second]
      },
      metadata: %{
        success_rate: calculate_success_rate(measurements),
        workspace_details: format_workspace_results(results)
      }
    }

    write_log(log_entry)
  end

  def handle_event([:gsc_analytics, :auto_sync, :failure], measurements, metadata, _config) do
    log_entry = %{
      ts: DateTime.utc_now() |> DateTime.to_iso8601(),
      event: "auto_sync.failure",
      measurements: %{
        duration_ms: measurements[:duration],
        attempt: metadata[:job][:attempt]
      },
      metadata: %{
        error: format_error(metadata[:reason]),
        stacktrace: format_stacktrace(metadata[:stacktrace]),
        job_id: metadata[:job][:id]
      }
    }

    write_log(log_entry)
  end

# Oban exposes :kind, :reason, and :stacktrace in failure events.
# Always pattern-match on :reason, never :error.

  defp calculate_success_rate(%{total_workspaces: 0}), do: 0

  defp calculate_success_rate(%{successes: successes, total_workspaces: total}) do
    Float.round(successes / total * 100, 2)
  end

  defp format_workspace_results(results) do
    %{
      successful_workspaces: Enum.map(results.successes, fn {ws, summary} ->
        %{
          workspace_id: ws.id,
          property_url: ws.property_url,
          urls_synced: summary[:total_urls],
          queries_synced: summary[:total_queries]
        }
      end),
      failed_workspaces: Enum.map(results.failures, fn {ws, reason} ->
        %{
          workspace_id: ws.id,
          property_url: ws.property_url,
          error: inspect(reason)
        }
      end)
    }
  end

  defp format_error(error) do
    Exception.message(error)
  rescue
    _ -> inspect(error)
  end

  defp format_stacktrace(stacktrace) do
    Exception.format_stacktrace(stacktrace)
  rescue
    _ -> inspect(stacktrace)
  end
end
```

### 3. Attach Event Handlers on Application Start

**File:** `lib/gsc_analytics/application.ex`

Update start function:

```elixir
def start(_type, _args) do
  # ... existing supervision tree setup ...

  # Attach telemetry handlers
  attach_telemetry_handlers()

  Supervisor.start_link(children, opts)
end

defp attach_telemetry_handlers do
  events = [
    [:gsc_analytics, :api, :request],
    [:gsc_analytics, :sync, :complete],
    [:gsc_analytics, :auth, :token_refresh],
    # New auto-sync events
    [:gsc_analytics, :auto_sync, :started],
    [:gsc_analytics, :auto_sync, :complete],
    [:gsc_analytics, :auto_sync, :failure]
  ]

  :telemetry.attach_many(
    "gsc-audit-logger",
    events,
    &GscAnalytics.DataSources.GSC.Telemetry.AuditLogger.handle_event/4,
    nil
  )
end
```

### 4. Update Worker to Emit Started Event

**File:** `lib/gsc_analytics/workers/gsc_sync_worker.ex`

```elixir
@impl Oban.Worker
def perform(%Oban.Job{id: job_id} = job) do
  # Emit started event
  emit_started_event(job_id)

  Logger.info("Starting automated GSC sync (last #{@sync_days} days)")

  {duration_ms, result} = :timer.tc(fn -> Sync.sync_all_workspaces(days: @sync_days) end)
  duration_ms = div(duration_ms, 1000)

  case result do
    {:ok, results} ->
      handle_success(results, duration_ms)

    {:error, reason} ->
      handle_error(reason, job_id)
  end
end

defp emit_started_event(job_id) do
  workspaces = GscAnalytics.Accounts.list_active_workspaces()

  :telemetry.execute(
    [:gsc_analytics, :auto_sync, :started],
    %{},
    %{
      job_id: job_id,
      sync_days: @sync_days,
      total_workspaces: length(workspaces)
    }
  )
end

defp handle_error(reason, job_id) do
  Logger.error("Automated GSC sync failed: #{inspect(reason)}")

  :telemetry.execute(
    [:gsc_analytics, :auto_sync, :failure],
    %{},
    %{
      job_id: job_id,
      error: reason
    }
  )

  {:error, reason}
end
```

### 5. Create Log Analysis Helpers

**File:** `lib/mix/tasks/gsc.analyze_logs.ex`

```elixir
defmodule Mix.Tasks.Gsc.AnalyzeLogs do
  @moduledoc """
  Analyzes GSC audit logs for insights.

  ## Usage

      mix gsc.analyze_logs
      mix gsc.analyze_logs --auto-sync-only
      mix gsc.analyze_logs --since "2025-01-01"
  """

  use Mix.Task
  require Logger

  @shortdoc "Analyzes GSC audit logs"

  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [auto_sync_only: :boolean, since: :string],
        aliases: [a: :auto_sync_only, s: :since]
      )

    analyze(opts)
  end

  defp analyze(opts) do
    log_file = Path.expand("../../../logs/gsc_audit.log", __DIR__)

    unless File.exists?(log_file) do
      IO.puts("No audit log found at #{log_file}")
      System.halt(1)
    end

    entries =
      log_file
      |> File.stream!()
      |> Stream.map(&parse_json/1)
      |> Stream.reject(&is_nil/1)
      |> filter_by_date(opts[:since])
      |> filter_by_event(opts[:auto_sync_only])
      |> Enum.to_list()

    print_summary(entries)
  end

  defp parse_json(line) do
    JSON.decode(line)
  rescue
    _ -> nil
  end

  defp filter_by_date(stream, nil), do: stream

  defp filter_by_date(stream, since_date) do
    {:ok, since_dt, _} = DateTime.from_iso8601(since_date <> "T00:00:00Z")

    Stream.filter(stream, fn entry ->
      {:ok, entry_dt, _} = DateTime.from_iso8601(entry["ts"])
      DateTime.compare(entry_dt, since_dt) in [:gt, :eq]
    end)
  end

  defp filter_by_event(stream, true) do
    Stream.filter(stream, fn entry ->
      String.starts_with?(entry["event"], "auto_sync.")
    end)
  end

  defp filter_by_event(stream, _), do: stream

  defp print_summary(entries) do
    total = length(entries)
    IO.puts("\n=== GSC Audit Log Analysis ===\n")
    IO.puts("Total events: #{total}")

    # Group by event type
    by_event =
      entries
      |> Enum.group_by(& &1["event"])
      |> Enum.map(fn {event, items} -> {event, length(items)} end)
      |> Enum.sort_by(fn {_event, count} -> count end, :desc)

    IO.puts("\nEvents by type:")

    for {event, count} <- by_event do
      IO.puts("  #{event}: #{count}")
    end

    # Auto-sync specific metrics
    auto_sync_complete =
      Enum.filter(entries, fn e -> e["event"] == "auto_sync.complete" end)

    if length(auto_sync_complete) > 0 do
      print_auto_sync_metrics(auto_sync_complete)
    end
  end

  defp print_auto_sync_metrics(entries) do
    IO.puts("\n=== Auto-Sync Metrics ===")

    avg_duration =
      entries
      |> Enum.map(& &1["measurements"]["duration_ms"])
      |> Enum.sum()
      |> Kernel./(length(entries))
      |> Float.round(2)

    total_workspaces = Enum.sum(Enum.map(entries, & &1["measurements"]["total_workspaces"]))
    total_successes = Enum.sum(Enum.map(entries, & &1["measurements"]["successes"]))
    total_failures = Enum.sum(Enum.map(entries, & &1["measurements"]["failures"]))

    IO.puts("Runs: #{length(entries)}")
    IO.puts("Average duration: #{avg_duration}ms")
    IO.puts("Total workspaces processed: #{total_workspaces}")
    IO.puts("Total successes: #{total_successes}")
    IO.puts("Total failures: #{total_failures}")
    IO.puts(
      "Overall success rate: #{Float.round(total_successes / total_workspaces * 100, 2)}%"
    )
  end
end
```

## Testing

**Manual verification:**

```bash
# Start app with auto-sync enabled
ENABLE_AUTO_SYNC=true iex -S mix phx.server

# Trigger manual job
iex> GscAnalytics.Workers.GscSyncWorker.new(%{}) |> Oban.insert()

# Check audit log
tail -f logs/gsc_audit.log | jq

# Should see:
# {"ts":"...","event":"auto_sync.started",...}
# {"ts":"...","event":"auto_sync.complete",...}

# Run log analysis
mix gsc.analyze_logs --auto-sync-only
```

## Definition of Done
- [ ] Auto-sync events logged to audit log
- [ ] Events follow existing JSON format
- [ ] All metadata captured (job ID, duration, success/failure)
- [ ] Telemetry handlers attached on app start
- [ ] Log analysis task works
- [ ] Documentation updated with new events

## Notes
- **Log format consistency:** Use same JSON structure as existing events
- **Performance:** Telemetry adds <1ms overhead per event
- **Storage:** Audit logs rotated weekly (configure in future)
- **Analysis:** `mix gsc.analyze_logs` provides quick insights without external tools
