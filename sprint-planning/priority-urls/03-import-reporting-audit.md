---
ticket_id: "03"
title: "Create Import Summary Reports and Audit Trail"
status: pending
priority: P2
milestone: 1
estimate_days: 2
dependencies: ["02"]
blocks: ["15"]
success_metrics:
  - "Import summary includes all required statistics"
  - "Audit trail persisted to database for historical tracking"
  - "Overflow report shows which URLs were dropped"
  - "Reports exportable to JSON/CSV formats"
---

# Ticket 03: Create Import Summary Reports and Audit Trail

## Context

Extend the Mix task from Ticket 02 to generate comprehensive reports and maintain an audit trail of all import operations. This provides transparency into what was imported, what was dropped due to the 60k cap, validation failures, and allows historical tracking of import operations.

Reports serve multiple audiences:
- **Ops team:** Monitor import health and troubleshoot issues
- **Client (Rula):** Understand which URLs were accepted/rejected
- **Future audits:** Historical record of all import operations

## Acceptance Criteria

1. ✅ Create `import_batches` database table for audit trail
2. ✅ Persist batch record for every import (success or failure)
3. ✅ Generate detailed summary report with all statistics
4. ✅ Create overflow report listing dropped URLs with reasons
5. ✅ Create validation error report with specific failure reasons
6. ✅ Export reports to JSON format
7. ✅ Add `--export-csv` option to export overflow/errors as CSV
8. ✅ Include batch_id in all metadata records for traceability
9. ✅ Store import duration and performance metrics
10. ✅ CLI outputs summary to console (colorized)

## Technical Specifications

### File Location
```
lib/gsc_analytics/priority_urls/reporter.ex
lib/gsc_analytics/schemas/import_batch.ex
priv/repo/migrations/*_create_import_batches.exs
```

### Database Schema

#### Import Batches Table
```elixir
defmodule GscAnalytics.Schemas.ImportBatch do
  use Ecto.Schema
  import Ecto.Changeset

  schema "import_batches" do
    field :batch_id, :string
    field :account_id, :integer
    field :status, :string  # "success", "partial", "failed"
    field :source_files, {:array, :string}
    field :total_entries, :integer
    field :valid_entries, :integer
    field :invalid_entries, :integer
    field :unique_urls, :integer
    field :duplicates_removed, :integer
    field :urls_kept, :integer
    field :urls_dropped, :integer
    field :urls_p1, :integer
    field :urls_p2, :integer
    field :urls_p3, :integer
    field :urls_p4, :integer
    field :duration_seconds, :decimal
    field :error_message, :string
    field :validation_errors, :map  # JSON blob
    field :dropped_urls, :map       # JSON blob
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    timestamps()
  end
end
```

#### Migration
```elixir
defmodule GscAnalytics.Repo.Migrations.CreateImportBatches do
  use Ecto.Migration

  def change do
    create table(:import_batches) do
      add :batch_id, :string, null: false
      add :account_id, :integer, null: false
      add :status, :string, null: false
      add :source_files, {:array, :string}
      add :total_entries, :integer
      add :valid_entries, :integer
      add :invalid_entries, :integer
      add :unique_urls, :integer
      add :duplicates_removed, :integer
      add :urls_kept, :integer
      add :urls_dropped, :integer
      add :urls_p1, :integer
      add :urls_p2, :integer
      add :urls_p3, :integer
      add :urls_p4, :integer
      add :duration_seconds, :decimal
      add :error_message, :text
      add :validation_errors, :map
      add :dropped_urls, :map
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps()
    end

    create index(:import_batches, [:account_id])
    create index(:import_batches, [:batch_id])
    create index(:import_batches, [:started_at])
    create unique_index(:import_batches, [:account_id, :batch_id])
  end
end
```

### Reporter Module

```elixir
defmodule GscAnalytics.PriorityUrls.Reporter do
  alias GscAnalytics.Schemas.ImportBatch
  alias GscAnalytics.Repo

  @doc """
  Create and persist an import batch record
  """
  def create_batch(account_id, batch_id, stats, opts \\ []) do
    %ImportBatch{}
    |> ImportBatch.changeset(%{
      batch_id: batch_id,
      account_id: account_id,
      status: stats.status,
      source_files: stats.source_files,
      total_entries: stats.total_entries,
      valid_entries: stats.valid_entries,
      invalid_entries: stats.invalid_entries,
      unique_urls: stats.unique_urls,
      duplicates_removed: stats.duplicates_removed,
      urls_kept: stats.urls_kept,
      urls_dropped: stats.urls_dropped,
      urls_p1: stats.urls_p1,
      urls_p2: stats.urls_p2,
      urls_p3: stats.urls_p3,
      urls_p4: stats.urls_p4,
      duration_seconds: stats.duration_seconds,
      validation_errors: stats.validation_errors,
      dropped_urls: stats.dropped_urls,
      started_at: stats.started_at,
      completed_at: stats.completed_at
    })
    |> Repo.insert()
  end

  @doc """
  Generate console summary report with colors
  """
  def print_summary(stats, opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, false)

    IO.puts "\n" <> IO.ANSI.bright() <> "Priority URL Import Summary" <> IO.ANSI.reset()
    IO.puts String.duplicate("=", 50)
    IO.puts "Account ID: #{stats.account_id}"
    IO.puts "Batch ID: #{stats.batch_id}"
    IO.puts "Files processed: #{length(stats.source_files)}"

    # Validation section
    IO.puts "\n#{IO.ANSI.cyan()}Validation:#{IO.ANSI.reset()}"
    IO.puts "  ✓ Valid entries: #{stats.valid_entries}"

    if stats.invalid_entries > 0 do
      IO.puts "  #{IO.ANSI.red()}✗ Invalid entries: #{stats.invalid_entries}#{IO.ANSI.reset()}"
      print_validation_errors(stats.validation_errors)
    end

    # Deduplication section
    IO.puts "\n#{IO.ANSI.cyan()}Deduplication:#{IO.ANSI.reset()}"
    IO.puts "  Unique URLs: #{stats.unique_urls}"
    IO.puts "  Duplicates removed: #{stats.duplicates_removed}"

    # Cap enforcement section
    if stats.urls_dropped > 0 do
      IO.puts "\n#{IO.ANSI.yellow()}60k Cap Enforcement:#{IO.ANSI.reset()}"
      IO.puts "  URLs kept: #{stats.urls_kept}"
      IO.puts "  #{IO.ANSI.yellow()}URLs dropped: #{stats.urls_dropped}#{IO.ANSI.reset()}"
      print_dropped_breakdown(stats.dropped_urls)
    end

    # Priority distribution section
    IO.puts "\n#{IO.ANSI.cyan()}Priority Distribution:#{IO.ANSI.reset()}"
    IO.puts "  P1: #{format_number(stats.urls_p1)} URLs"
    IO.puts "  P2: #{format_number(stats.urls_p2)} URLs"
    IO.puts "  P3: #{format_number(stats.urls_p3)} URLs"
    IO.puts "  P4: #{format_number(stats.urls_p4)} URLs"

    # Performance section
    IO.puts "\n#{IO.ANSI.cyan()}Performance:#{IO.ANSI.reset()}"
    IO.puts "  Time elapsed: #{Float.round(stats.duration_seconds, 1)}s"

    # Dry run warning
    if dry_run do
      IO.puts "\n#{IO.ANSI.yellow()}[DRY RUN] - No changes persisted to database#{IO.ANSI.reset()}"
    else
      IO.puts "\n#{IO.ANSI.green()}✓ Import completed successfully#{IO.ANSI.reset()}"
    end
  end

  @doc """
  Export overflow report to JSON
  """
  def export_overflow_json(stats, output_path) do
    report = %{
      batch_id: stats.batch_id,
      account_id: stats.account_id,
      total_dropped: stats.urls_dropped,
      dropped_urls: stats.dropped_urls
    }

    File.write!(output_path, Jason.encode!(report, pretty: true))
    IO.puts "Overflow report saved to: #{output_path}"
  end

  @doc """
  Export overflow report to CSV
  """
  def export_overflow_csv(stats, output_path) do
    headers = ["url", "priority_tier", "reason", "page_type"]

    rows = stats.dropped_urls
    |> Enum.map(fn entry ->
      [entry.url, entry.priority_tier, entry.drop_reason, entry.page_type || ""]
    end)

    csv_content = [headers | rows]
    |> CSV.encode()
    |> Enum.to_list()
    |> IO.iodata_to_binary()

    File.write!(output_path, csv_content)
    IO.puts "Overflow CSV saved to: #{output_path}"
  end

  @doc """
  Export validation errors to JSON
  """
  def export_validation_errors_json(stats, output_path) do
    report = %{
      batch_id: stats.batch_id,
      account_id: stats.account_id,
      total_errors: stats.invalid_entries,
      errors: stats.validation_errors
    }

    File.write!(output_path, Jason.encode!(report, pretty: true))
    IO.puts "Validation errors saved to: #{output_path}"
  end

  # Private helpers

  defp print_validation_errors(errors) do
    errors
    |> Enum.group_by(& &1.reason)
    |> Enum.each(fn {reason, entries} ->
      IO.puts "    - #{reason}: #{length(entries)}"
    end)
  end

  defp print_dropped_breakdown(dropped_urls) do
    dropped_urls
    |> Enum.group_by(& &1.priority_tier)
    |> Enum.each(fn {tier, entries} ->
      IO.puts "    - #{tier} tier: #{length(entries)}"
    end)
  end

  defp format_number(num) do
    num
    |> Integer.to_string()
    |> String.reverse()
    |> String.split("", trim: true)
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end
end
```

### Updated Importer Integration

```elixir
defmodule GscAnalytics.PriorityUrls.Importer do
  alias GscAnalytics.PriorityUrls.Reporter

  def run(account_id, opts \\ []) do
    started_at = DateTime.utc_now()
    batch_id = generate_batch_id()

    try do
      # Run import logic from Ticket 02
      stats = %{
        account_id: account_id,
        batch_id: batch_id,
        status: "success",
        started_at: started_at,
        completed_at: DateTime.utc_now(),
        duration_seconds: calculate_duration(started_at),
        # ... all other stats
      }

      # Print console summary
      Reporter.print_summary(stats, opts)

      # Persist batch record (unless dry_run)
      unless Keyword.get(opts, :dry_run, false) do
        Reporter.create_batch(account_id, batch_id, stats)
      end

      # Export reports if requested
      if export_path = Keyword.get(opts, :export_overflow) do
        Reporter.export_overflow_json(stats, export_path)
      end

      if csv_path = Keyword.get(opts, :export_csv) do
        Reporter.export_overflow_csv(stats, csv_path)
      end

      {:ok, stats}
    rescue
      e ->
        # Record failed batch
        error_stats = %{
          account_id: account_id,
          batch_id: batch_id,
          status: "failed",
          error_message: Exception.message(e),
          started_at: started_at,
          completed_at: DateTime.utc_now()
        }

        Reporter.create_batch(account_id, batch_id, error_stats)
        {:error, e}
    end
  end
end
```

### CLI Options Update

```elixir
# mix prism.import_priority_urls options
@switches [
  account_id: :integer,
  files: :string,
  dry_run: :boolean,
  verbose: :boolean,
  export_overflow: :string,
  export_errors: :string,
  export_csv: :boolean
]

# Usage examples:
# mix prism.import_priority_urls --account-id 123 --export-overflow overflow.json
# mix prism.import_priority_urls --account-id 123 --export-csv --export-overflow overflow.csv
```

## Testing Requirements

### Unit Tests

```elixir
# test/gsc_analytics/priority_urls/reporter_test.exs
defmodule GscAnalytics.PriorityUrls.ReporterTest do
  use GscAnalytics.DataCase

  describe "create_batch/3" do
    test "persists batch record with all statistics" do
      stats = build_test_stats()

      {:ok, batch} = Reporter.create_batch(123, "batch_001", stats)

      assert batch.account_id == 123
      assert batch.batch_id == "batch_001"
      assert batch.status == "success"
      assert batch.urls_kept == 60_000
    end
  end

  describe "print_summary/2" do
    test "outputs formatted summary to console" do
      stats = build_test_stats()

      output = capture_io(fn ->
        Reporter.print_summary(stats)
      end)

      assert output =~ "Priority URL Import Summary"
      assert output =~ "Valid entries: 63,500"
      assert output =~ "P1: 15,234 URLs"
    end
  end

  describe "export_overflow_json/2" do
    test "creates JSON file with dropped URLs" do
      stats = build_test_stats_with_drops()
      path = "test/tmp/overflow.json"

      Reporter.export_overflow_json(stats, path)

      assert File.exists?(path)
      {:ok, content} = File.read(path)
      {:ok, json} = Jason.decode(content)

      assert json["total_dropped"] == 1200
      assert length(json["dropped_urls"]) == 1200
    end
  end

  describe "export_overflow_csv/2" do
    test "creates CSV file with dropped URLs" do
      stats = build_test_stats_with_drops()
      path = "test/tmp/overflow.csv"

      Reporter.export_overflow_csv(stats, path)

      assert File.exists?(path)
      {:ok, content} = File.read(path)

      assert content =~ "url,priority_tier,reason,page_type"
      assert content =~ "https://example.com/dropped,P4,60k_cap_exceeded"
    end
  end
end
```

### Integration Tests

```elixir
test "full import creates batch record", %{account: account} do
  args = ["--account-id", to_string(account.id)]

  Mix.Tasks.Prism.ImportPriorityUrls.run(args)

  # Verify batch record created
  batch = Repo.get_by!(ImportBatch, account_id: account.id)
  assert batch.status == "success"
  assert batch.urls_kept == 60_000
  assert batch.duration_seconds > 0
end

test "failed import records error in batch", %{account: account} do
  # Provide invalid file path
  args = ["--account-id", to_string(account.id), "--files", "invalid/*.json"]

  assert {:error, _} = Mix.Tasks.Prism.ImportPriorityUrls.run(args)

  # Verify error batch created
  batch = Repo.get_by!(ImportBatch, account_id: account.id)
  assert batch.status == "failed"
  assert batch.error_message != nil
end
```

## Implementation Notes

### Statistics Structure

```elixir
%{
  account_id: 123,
  batch_id: "1699123456789",
  status: "success",  # or "partial", "failed"
  source_files: [
    "output/priority_urls_p1.json",
    "output/priority_urls_p2.json",
    "output/priority_urls_p3.json",
    "output/priority_urls_p4.json"
  ],
  total_entries: 63_542,
  valid_entries: 63_500,
  invalid_entries: 42,
  unique_urls: 61_200,
  duplicates_removed: 2_300,
  urls_kept: 60_000,
  urls_dropped: 1_200,
  urls_p1: 15_234,
  urls_p2: 18_456,
  urls_p3: 20_123,
  urls_p4: 6_187,
  duration_seconds: 87.3,
  validation_errors: [
    %{url: "example.com/bad", reason: "missing_protocol", line: 42},
    # ...
  ],
  dropped_urls: [
    %{
      url: "https://example.com/dropped",
      priority_tier: "P4",
      drop_reason: "60k_cap_exceeded",
      page_type: "profile"
    },
    # ...
  ],
  started_at: ~U[2025-11-13 10:00:00Z],
  completed_at: ~U[2025-11-13 10:01:27Z]
}
```

### Console Output Colors

- **Green:** Success messages, checkmarks
- **Red:** Errors, validation failures
- **Yellow:** Warnings (dropped URLs, dry-run notice)
- **Cyan:** Section headers
- **Bright:** Main title

### Report File Naming Convention

```elixir
# Automatic file naming if path not specified
def default_overflow_path(batch_id) do
  "output/overflow_report_#{batch_id}.json"
end

def default_errors_path(batch_id) do
  "output/validation_errors_#{batch_id}.json"
end
```

## Success Metrics

1. **Audit Trail Completeness**
   - ✓ 100% of imports have corresponding batch record
   - ✓ Failed imports are recorded with error details
   - ✓ Batch records include all required statistics

2. **Report Quality**
   - ✓ Console summary is clear and actionable
   - ✓ Overflow report includes all dropped URLs with reasons
   - ✓ Validation error report specifies exact failure reasons
   - ✓ Reports are exportable in JSON and CSV formats

3. **Performance**
   - ✓ Report generation adds <5 seconds to import time
   - ✓ Batch record insert completes in <1 second
   - ✓ JSON export completes in <2 seconds for 1k entries

4. **Usability**
   - ✓ Console output is readable without scrolling (key stats visible)
   - ✓ Export files are valid JSON/CSV
   - ✓ Batch records queryable via Ecto for dashboards

## Related Files

- `02-mix-task-ingestion-pipeline.md` - Core import logic this extends
- `15-logging-telemetry.md` - Will add observability on top of this audit trail
- `17-production-rollout-feature-flag.md` - Will use batch records for monitoring

## Next Steps

After this ticket is complete:
1. **Ticket 15:** Add telemetry events and structured logging
2. **Dashboard:** Query `import_batches` table to show import history
3. **Alerting:** Monitor for failed imports via batch status
4. **Client communication:** Share overflow reports with Rula for review
