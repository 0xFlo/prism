---
ticket_id: "02"
title: "Build Mix Task Ingestion Pipeline"
status: pending
priority: P1
milestone: 1
estimate_days: 5
dependencies: ["01"]
blocks: ["03", "05", "13"]
success_metrics:
  - "Mix task runs successfully with valid JSON files"
  - "Import completes in <2 minutes for 65k URLs"
  - "60k cap enforced correctly with overflow handling"
  - "URL deduplication works with case/slash normalization"
  - "Validation errors are caught and reported"
---

# Ticket 02: Build Mix Task Ingestion Pipeline

## Context

Build the core import pipeline that reads 4 JSON files (`priority_urls_p1.json` through `priority_urls_p4.json`), validates against the schema from Ticket 01, normalizes URLs, enforces deduplication, applies the 60k cap, and prepares data for persistence in the database.

This Mix task is the primary interface for importing priority URLs and will be used both manually (for initial import) and via automation (Workflow step in Ticket 13).

## Acceptance Criteria

1. ✅ Create Mix task `mix prism.import_priority_urls`
2. ✅ Accept file paths via CLI options (default: `output/priority_urls_p*.json`)
3. ✅ Implement `--dry-run` flag that validates without persisting
4. ✅ Parse JSON files using streaming `:json` module for memory efficiency
5. ✅ Validate each entry against schema with NimbleOptions
6. ✅ Normalize URLs (lowercase host, trim trailing slashes)
7. ✅ Deduplicate URLs across all files (keep highest priority tier)
8. ✅ Enforce 60k cap (drop from lowest tier first, log overflow)
9. ✅ Batch upsert metadata into `gsc_url_metadata` table
10. ✅ Generate batch_id (timestamp) for audit trail
11. ✅ Handle errors gracefully (invalid JSON, missing files, DB errors)
12. ✅ Return summary statistics (counts per tier, duplicates, drops)

## Technical Specifications

### File Location
```
lib/mix/tasks/prism/import_priority_urls.ex
lib/gsc_analytics/priority_urls/importer.ex
lib/gsc_analytics/priority_urls/entry.ex
lib/gsc_analytics/priority_urls/validator.ex
lib/gsc_analytics/priority_urls/normalizer.ex
```

### Module Structure

#### 1. Mix Task (`Mix.Tasks.Prism.ImportPriorityUrls`)
```elixir
defmodule Mix.Tasks.Prism.ImportPriorityUrls do
  use Mix.Task
  alias GscAnalytics.PriorityUrls.Importer

  @shortdoc "Import priority URLs from JSON files"

  @moduledoc """
  Import priority URLs for a given account from JSON files.

  ## Usage

      mix prism.import_priority_urls --account-id 123
      mix prism.import_priority_urls --account-id 123 --dry-run
      mix prism.import_priority_urls --account-id 123 --files "custom/path/p*.json"

  ## Options

    * --account-id - Required. The account ID to import URLs for
    * --files - Optional. Glob pattern for JSON files (default: "output/priority_urls_p*.json")
    * --dry-run - Optional. Validate and report without persisting
    * --verbose - Optional. Show detailed progress
  """

  def run(args) do
    # Parse options
    # Start application
    # Call Importer.run/2
    # Print summary
  end
end
```

#### 2. Importer Module (`GscAnalytics.PriorityUrls.Importer`)
```elixir
defmodule GscAnalytics.PriorityUrls.Importer do
  alias GscAnalytics.PriorityUrls.{Entry, Validator, Normalizer}
  alias GscAnalytics.Repo

  @max_urls 60_000

  def run(account_id, opts \\ []) do
    # 1. Find JSON files matching glob pattern
    # 2. Stream and parse each file
    # 3. Validate entries
    # 4. Normalize URLs
    # 5. Deduplicate (keep highest priority)
    # 6. Enforce 60k cap
    # 7. Batch upsert to database (unless dry_run)
    # 8. Return summary statistics
  end

  defp stream_json_file(path) do
    # Use :json.decode_stream/1 for memory efficiency
    # Yield entries one at a time
  end

  defp deduplicate_entries(entries) do
    # Group by normalized URL
    # Keep entry with highest priority tier
    # P1 > P2 > P3 > P4
  end

  defp enforce_cap(entries, max \\ @max_urls) do
    # Count total
    # If > max: drop from P4, then P3, then P2 (never P1)
    # Return {kept, dropped}
  end

  defp batch_upsert(account_id, entries, batch_id) do
    # Convert entries to metadata records
    # Use Repo.insert_all with on_conflict: :replace_all
    # Batch size: 1000 records at a time
  end

  defp generate_batch_id do
    DateTime.utc_now()
    |> DateTime.to_unix(:millisecond)
    |> to_string()
  end
end
```

#### 3. Entry Struct (`GscAnalytics.PriorityUrls.Entry`)
```elixir
defmodule GscAnalytics.PriorityUrls.Entry do
  @enforce_keys [:url, :priority_tier]
  defstruct [:url, :priority_tier, :page_type, :notes, :tags, :source_file]

  @type t :: %__MODULE__{
    url: String.t(),
    priority_tier: String.t(),
    page_type: String.t() | nil,
    notes: String.t() | nil,
    tags: [String.t()] | nil,
    source_file: String.t() | nil
  }
end
```

#### 4. Validator Module (`GscAnalytics.PriorityUrls.Validator`)
```elixir
defmodule GscAnalytics.PriorityUrls.Validator do
  @priority_tiers ~w(P1 P2 P3 P4)

  def validate_entry(entry) do
    # Validate required fields
    # Validate URL format (must have protocol)
    # Validate priority_tier (must be P1-P4)
    # Return {:ok, entry} or {:error, reason}
  end

  defp validate_url(url) do
    # Check for http:// or https://
    # Check for valid hostname
    # Use URI.parse/1
  end
end
```

#### 5. Normalizer Module (`GscAnalytics.PriorityUrls.Normalizer`)
```elixir
defmodule GscAnalytics.PriorityUrls.Normalizer do
  def normalize_url(url) do
    uri = URI.parse(url)

    %URI{uri |
      scheme: String.downcase(uri.scheme || "https"),
      host: String.downcase(uri.host || ""),
      path: normalize_path(uri.path)
    }
    |> URI.to_string()
  end

  defp normalize_path(nil), do: "/"
  defp normalize_path(path) do
    # Trim trailing slash unless it's the root
    case String.trim_trailing(path, "/") do
      "" -> "/"
      normalized -> normalized
    end
  end

  def normalize_entry(%Entry{url: url} = entry) do
    %Entry{entry | url: normalize_url(url)}
  end
end
```

### CLI Interface

```bash
# Basic usage with defaults
mix prism.import_priority_urls --account-id 123

# Dry run (validate only)
mix prism.import_priority_urls --account-id 123 --dry-run

# Custom file path
mix prism.import_priority_urls --account-id 123 --files "custom/path/p*.json"

# Verbose output
mix prism.import_priority_urls --account-id 123 --verbose
```

### Database Upsert Strategy

```elixir
# Batch upsert with on_conflict
records = entries
  |> Enum.map(fn entry ->
    %{
      account_id: account_id,
      url: entry.url,
      update_priority: entry.priority_tier,
      page_type: entry.page_type,
      metadata_source: "priority_import",
      metadata_batch_id: batch_id,
      priority_imported_at: DateTime.utc_now(),
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
  end)

Repo.insert_all(
  GscAnalytics.Schemas.UrlMetadata,
  records,
  on_conflict: {:replace_all_except, [:id, :inserted_at]},
  conflict_target: [:account_id, :url]
)
```

## Testing Requirements

### Unit Tests

```elixir
# test/gsc_analytics/priority_urls/validator_test.exs
defmodule GscAnalytics.PriorityUrls.ValidatorTest do
  test "validates URL with protocol" do
    assert {:ok, _} = Validator.validate_entry(%Entry{
      url: "https://example.com/path",
      priority_tier: "P1"
    })
  end

  test "rejects URL without protocol" do
    assert {:error, _} = Validator.validate_entry(%Entry{
      url: "example.com/path",
      priority_tier: "P1"
    })
  end

  test "rejects invalid priority tier" do
    assert {:error, _} = Validator.validate_entry(%Entry{
      url: "https://example.com/path",
      priority_tier: "High"
    })
  end
end

# test/gsc_analytics/priority_urls/normalizer_test.exs
defmodule GscAnalytics.PriorityUrls.NormalizerTest do
  test "lowercases hostname" do
    assert Normalizer.normalize_url("https://Example.COM/Path") ==
      "https://example.com/Path"
  end

  test "trims trailing slash" do
    assert Normalizer.normalize_url("https://example.com/path/") ==
      "https://example.com/path"
  end

  test "preserves root slash" do
    assert Normalizer.normalize_url("https://example.com/") ==
      "https://example.com/"
  end
end

# test/gsc_analytics/priority_urls/importer_test.exs
defmodule GscAnalytics.PriorityUrls.ImporterTest do
  test "deduplicates URLs keeping highest priority" do
    entries = [
      %Entry{url: "https://example.com/path", priority_tier: "P2"},
      %Entry{url: "https://example.com/path", priority_tier: "P1"}
    ]

    result = Importer.deduplicate_entries(entries)
    assert length(result) == 1
    assert hd(result).priority_tier == "P1"
  end

  test "enforces 60k cap dropping from lowest tier" do
    # Create 65k entries (20k P1, 20k P2, 20k P3, 5k P4)
    entries = generate_test_entries(65_000)

    {kept, dropped} = Importer.enforce_cap(entries, 60_000)

    assert length(kept) == 60_000
    assert length(dropped) == 5_000
    # All P4 should be dropped first
    assert Enum.all?(dropped, &(&1.priority_tier == "P4"))
  end
end
```

### Integration Tests

```elixir
# test/mix/tasks/prism/import_priority_urls_test.exs
defmodule Mix.Tasks.Prism.ImportPriorityUrlsTest do
  use GscAnalytics.DataCase

  setup do
    # Create test account
    account = insert(:account)

    # Create test JSON files
    files = create_test_json_files()

    {:ok, account: account, files: files}
  end

  test "imports priority URLs successfully", %{account: account} do
    args = ["--account-id", to_string(account.id), "--dry-run"]

    Mix.Tasks.Prism.ImportPriorityUrls.run(args)

    # Verify summary output
    # Check metadata records created
  end

  test "handles malformed JSON gracefully" do
    # Test with invalid JSON file
    # Assert error message
    # Assert no partial imports
  end

  test "respects dry-run flag" do
    args = ["--account-id", "123", "--dry-run"]

    Mix.Tasks.Prism.ImportPriorityUrls.run(args)

    # Assert no database changes
    assert Repo.aggregate(UrlMetadata, :count) == 0
  end
end
```

### Performance Tests

```elixir
test "imports 65k URLs in under 2 minutes" do
  # Create 65k test entries
  entries = generate_test_entries(65_000)

  {time_microseconds, _result} = :timer.tc(fn ->
    Importer.run(account_id, entries: entries)
  end)

  time_seconds = time_microseconds / 1_000_000
  assert time_seconds < 120, "Import took #{time_seconds}s (should be < 120s)"
end
```

## Implementation Notes

### Performance Considerations

1. **Streaming JSON Parsing**
   - Use `:json.decode_stream/1` instead of reading entire file into memory
   - Process entries one at a time to keep memory usage constant
   - Target: <100 MB memory usage for 65k URLs

2. **Batch Database Inserts**
   - Group upserts into batches of 1000 records
   - Use `Repo.insert_all` with `:on_conflict` strategy
   - Avoid N+1 queries

3. **URL Deduplication**
   - Use Map for O(1) lookup during deduplication
   - Key: normalized URL, Value: highest priority entry
   - Process files in priority order (P1 → P4) to keep first match

### Error Handling

```elixir
def run(account_id, opts) do
  try do
    # Main logic
  rescue
    File.Error -> {:error, "JSON files not found at specified path"}
    Jason.DecodeError -> {:error, "Invalid JSON format in one or more files"}
    Ecto.Error -> {:error, "Database error during import"}
  end
end
```

### Summary Output Format

```
Priority URL Import Summary
===========================
Account ID: 123
Batch ID: 1699123456789
Files processed: 4
Total entries: 63,542

Validation:
  ✓ Valid entries: 63,500
  ✗ Invalid entries: 42
    - Missing required fields: 12
    - Invalid URL format: 20
    - Invalid priority tier: 10

Deduplication:
  Unique URLs: 61,200
  Duplicates removed: 2,300

60k Cap Enforcement:
  URLs kept: 60,000
  URLs dropped: 1,200
    - P4 tier: 1,200

Priority Distribution:
  P1: 15,234 URLs
  P2: 18,456 URLs
  P3: 20,123 URLs
  P4: 6,187 URLs

Database Status:
  ✓ Records upserted: 60,000
  Time elapsed: 87.3 seconds

[DRY RUN] - No changes persisted to database
```

## Success Metrics

1. **Performance**
   - ✓ Import completes in <2 minutes for 65k URLs
   - ✓ Memory usage <100 MB during import
   - ✓ Database upsert completes in <30 seconds

2. **Correctness**
   - ✓ 0 validation errors on valid test data
   - ✓ 100% of malformed entries caught and reported
   - ✓ URL deduplication works correctly (verified with test cases)
   - ✓ 60k cap enforced with correct tier-based dropping

3. **Usability**
   - ✓ CLI help text is clear and complete
   - ✓ Error messages are actionable
   - ✓ Summary output provides all necessary information
   - ✓ Dry-run flag allows validation without persistence

## Related Files

- `01-json-schema-documentation.md` - Schema specification this implements
- `03-import-reporting-audit.md` - Extended reporting built on this foundation
- `05-upsert-helper-module.md` - Will extract upsert logic from this module
- `13-priority-import-workflow.md` - Will wrap this Mix task in workflow

## Next Steps

After this ticket is complete:
1. **Ticket 03:** Enhance reporting with detailed audit trail
2. **Ticket 05:** Extract reusable upsert helper from this implementation
3. **Ticket 13:** Wrap Mix task in workflow step for automation
4. **Initial Import:** Run against real Rula data files
