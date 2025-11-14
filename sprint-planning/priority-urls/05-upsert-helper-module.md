---
ticket_id: "05"
title: "Extract Reusable Metadata Upsert Helper Module"
status: pending
priority: P2
milestone: 2
estimate_days: 2
dependencies: ["02", "04"]
blocks: ["06", "13", "14"]
success_metrics:
  - "Reusable upsert module created and tested"
  - "Mix task refactored to use upsert helper"
  - "Upsert handles conflicts correctly with composite unique index"
  - "Performance: <500ms for 1k upserts"
---

# Ticket 05: Extract Reusable Metadata Upsert Helper Module

## Context

The Mix task (Ticket 02) and future workflow steps (Ticket 13) both need to upsert metadata records. Extract common upsert logic into a reusable module that handles batching, conflict resolution, and audit trail creation. This follows DRY principles and ensures consistent metadata persistence across all entry points.

## Acceptance Criteria

1. ✅ Create `GscAnalytics.Metadata` module with upsert functions
2. ✅ Implement `upsert_priority_metadata/3` for batch upserts
3. ✅ Handle ON CONFLICT using composite unique index from Ticket 04
4. ✅ Support batch sizes up to 1000 records for performance
5. ✅ Return summary statistics (inserted, updated, errors)
6. ✅ Refactor Mix task to use new helper
7. ✅ Refactor existing `UpdateMetadataStep` to use helper if applicable
8. ✅ Add comprehensive unit tests
9. ✅ Validate performance with 10k+ record batches

## Technical Specifications

### Module Structure

```elixir
defmodule GscAnalytics.Metadata do
  @moduledoc """
  Reusable helpers for upserting URL metadata across different sources
  (priority imports, classifier backfills, workflows).
  """

  alias GscAnalytics.{Repo, Schemas.UrlMetadata}
  require Logger

  @default_batch_size 1000

  @doc """
  Upsert priority URL metadata in batches.

  ## Options
    * `:batch_size` - Number of records per batch (default: 1000)
    * `:return_stats` - Return detailed statistics (default: true)

  ## Returns
    * `{:ok, stats}` - Success with statistics
    * `{:error, reason}` - Failure with reason

  ## Examples

      entries = [
        %{account_id: 123, url: "https://example.com", update_priority: "P1"},
        %{account_id: 123, url: "https://example.com/path", update_priority: "P2"}
      ]

      {:ok, stats} = Metadata.upsert_priority_metadata(123, entries, batch_id)
      # => {:ok, %{inserted: 2, updated: 0, total: 2}}
  """
  def upsert_priority_metadata(account_id, entries, batch_id, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    return_stats = Keyword.get(opts, :return_stats, true)

    started_at = System.monotonic_time(:millisecond)

    try do
      stats = entries
        |> Stream.chunk_every(batch_size)
        |> Enum.reduce(%{inserted: 0, updated: 0, errors: 0}, fn batch, acc ->
          case upsert_batch(account_id, batch, batch_id) do
            {:ok, batch_stats} -> merge_stats(acc, batch_stats)
            {:error, reason} ->
              Logger.error("Batch upsert failed: #{inspect(reason)}")
              %{acc | errors: acc.errors + length(batch)}
          end
        end)

      elapsed_ms = System.monotonic_time(:millisecond) - started_at

      final_stats = Map.merge(stats, %{
        total: length(entries),
        duration_ms: elapsed_ms,
        batch_id: batch_id
      })

      if return_stats do
        {:ok, final_stats}
      else
        :ok
      end
    rescue
      e ->
        Logger.error("Metadata upsert failed: #{Exception.message(e)}")
        {:error, e}
    end
  end

  @doc """
  Upsert a single batch of metadata records.
  """
  defp upsert_batch(account_id, entries, batch_id) do
    now = DateTime.utc_now()

    records = Enum.map(entries, fn entry ->
      %{
        account_id: account_id,
        url: entry.url,
        update_priority: entry.priority_tier,
        page_type: entry[:page_type],
        metadata_source: "priority_import",
        metadata_batch_id: batch_id,
        priority_imported_at: now,
        inserted_at: now,
        updated_at: now
      }
    end)

    {count, _} = Repo.insert_all(
      UrlMetadata,
      records,
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:account_id, :url],
      returning: [:id]
    )

    {:ok, %{inserted: count, updated: 0}}
  end

  @doc """
  Backfill page types from classifier without overwriting manual values.
  """
  def backfill_page_types(account_id, url_classifications, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)

    url_classifications
    |> Stream.chunk_every(batch_size)
    |> Enum.reduce(%{updated: 0}, fn batch, acc ->
      case backfill_batch(account_id, batch) do
        {:ok, count} -> %{acc | updated: acc.updated + count}
        {:error, _} -> acc
      end
    end)
  end

  defp backfill_batch(account_id, classifications) do
    # Only update rows where page_type is NULL (don't override manual values)
    updates = Enum.map(classifications, fn {url, page_type} ->
      %{
        account_id: account_id,
        url: url,
        page_type: page_type,
        url_type: page_type,  # Keep legacy field in sync
        metadata_source: "classifier",
        updated_at: DateTime.utc_now()
      }
    end)

    {count, _} = Repo.insert_all(
      UrlMetadata,
      updates,
      on_conflict: [
        set: [
          page_type: {:fragment, "COALESCE(EXCLUDED.page_type, gsc_url_metadata.page_type)"},
          metadata_source: {:fragment, "COALESCE(gsc_url_metadata.metadata_source, EXCLUDED.metadata_source)"},
          updated_at: DateTime.utc_now()
        ]
      ],
      conflict_target: [:account_id, :url]
    )

    {:ok, count}
  end

  defp merge_stats(acc, new_stats) do
    %{
      inserted: acc.inserted + new_stats.inserted,
      updated: acc.updated + new_stats.updated,
      errors: acc.errors + Map.get(new_stats, :errors, 0)
    }
  end
end
```

### Refactored Importer

```elixir
defmodule GscAnalytics.PriorityUrls.Importer do
  alias GscAnalytics.Metadata

  def run(account_id, opts \\ []) do
    # ... validation, deduplication, cap enforcement ...

    # Use extracted upsert helper
    unless Keyword.get(opts, :dry_run, false) do
      {:ok, upsert_stats} = Metadata.upsert_priority_metadata(
        account_id,
        entries,
        batch_id
      )

      stats = Map.merge(stats, upsert_stats)
    end

    {:ok, stats}
  end
end
```

## Testing Requirements

### Unit Tests

```elixir
defmodule GscAnalytics.MetadataTest do
  use GscAnalytics.DataCase

  describe "upsert_priority_metadata/4" do
    test "inserts new metadata records" do
      entries = [
        %{url: "https://example.com/path1", priority_tier: "P1"},
        %{url: "https://example.com/path2", priority_tier: "P2"}
      ]

      {:ok, stats} = Metadata.upsert_priority_metadata(123, entries, "batch_001")

      assert stats.inserted == 2
      assert stats.total == 2
      assert stats.batch_id == "batch_001"
    end

    test "updates existing metadata on conflict" do
      # Insert initial record
      insert(:url_metadata, account_id: 123, url: "https://example.com", update_priority: "P2")

      # Upsert with higher priority
      entries = [%{url: "https://example.com", priority_tier: "P1"}]
      {:ok, _} = Metadata.upsert_priority_metadata(123, entries, "batch_002")

      # Verify update
      metadata = Repo.get_by(UrlMetadata, account_id: 123, url: "https://example.com")
      assert metadata.update_priority == "P1"
      assert metadata.metadata_batch_id == "batch_002"
    end

    test "handles large batches efficiently" do
      entries = for i <- 1..10_000 do
        %{url: "https://example.com/path#{i}", priority_tier: "P1"}
      end

      {time_microseconds, {:ok, stats}} = :timer.tc(fn ->
        Metadata.upsert_priority_metadata(123, entries, "batch_large")
      end)

      assert stats.total == 10_000
      time_ms = time_microseconds / 1000
      assert time_ms < 5000, "10k upserts took #{time_ms}ms (should be < 5000ms)"
    end
  end

  describe "backfill_page_types/3" do
    test "adds page types to records without them" do
      # Create metadata without page_type
      insert(:url_metadata, account_id: 123, url: "https://example.com/profile", page_type: nil)

      classifications = [{"https://example.com/profile", "profile"}]
      stats = Metadata.backfill_page_types(123, classifications)

      assert stats.updated == 1

      metadata = Repo.get_by(UrlMetadata, url: "https://example.com/profile")
      assert metadata.page_type == "profile"
      assert metadata.metadata_source == "classifier"
    end

    test "does not overwrite manual page types" do
      # Create metadata with manual page_type
      insert(:url_metadata,
        account_id: 123,
        url: "https://example.com/custom",
        page_type: "custom_type",
        metadata_source: "manual"
      )

      classifications = [{"https://example.com/custom", "profile"}]
      Metadata.backfill_page_types(123, classifications)

      metadata = Repo.get_by(UrlMetadata, url: "https://example.com/custom")
      assert metadata.page_type == "custom_type"  # Not overwritten
      assert metadata.metadata_source == "manual"  # Preserved
    end
  end
end
```

## Success Metrics

1. **Performance**
   - ✓ 1k upserts complete in <500ms
   - ✓ 10k upserts complete in <5 seconds
   - ✓ Memory usage stays constant (batching works)

2. **Correctness**
   - ✓ Conflicts resolved using composite unique index
   - ✓ Existing records updated correctly
   - ✓ Statistics accurate (inserted vs updated counts)
   - ✓ Backfill doesn't override manual values

3. **Reusability**
   - ✓ Mix task successfully refactored to use helper
   - ✓ Helper functions have clear, documented APIs
   - ✓ Error handling is consistent

## Related Files

- `02-mix-task-ingestion-pipeline.md` - Will be refactored to use this
- `04-database-migration-metadata.md` - Provides indexes this leverages
- `06-backfill-metadata-classifier.md` - Will use backfill helper
- `13-priority-import-workflow.md` - Will use upsert helper

## Next Steps

1. **Ticket 06:** Use backfill helper for classifier integration
2. **Ticket 13:** Use upsert helper in workflow step
3. **Future:** Extend for other metadata sources (manual edits, API imports)
