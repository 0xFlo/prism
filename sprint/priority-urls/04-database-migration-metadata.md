---
ticket_id: "04"
title: "Database Migration for Priority URL Metadata"
status: pending
priority: P1
milestone: 2
estimate_days: 2
dependencies: []
blocks: ["05", "06", "07"]
success_metrics:
  - "Migration runs successfully in development and staging"
  - "New columns added to gsc_url_metadata table"
  - "Composite unique index created on (account_id, url)"
  - "Migration is reversible without data loss"
  - "Query performance validated with indexes"
---

# Ticket 04: Database Migration for Priority URL Metadata

## Context

Extend the existing `gsc_url_metadata` table with new columns to store priority tier information, page type classifications, and audit metadata. This migration provides the persistence layer for all priority URL data and ensures efficient querying through proper indexing.

The `gsc_url_metadata` table already exists with columns like `url_type`, `content_category`, and `update_priority`, but needs enhancements to support the full priority URL workflow.

## Acceptance Criteria

1. ✅ Create Ecto migration file with clear naming
2. ✅ Add `page_type` column (string, nullable)
3. ✅ Add `metadata_source` column (string, nullable)
4. ✅ Add `metadata_batch_id` column (string, nullable)
5. ✅ Add `priority_imported_at` column (utc_datetime, nullable)
6. ✅ Create composite unique index on `(account_id, url)`
7. ✅ Create index on `metadata_batch_id` for audit queries
8. ✅ Create index on `update_priority` for filtering
9. ✅ Migration includes rollback logic
10. ✅ Test migration on development database
11. ✅ Validate query performance with indexes using EXPLAIN
12. ✅ Update UrlMetadata schema module

## Technical Specifications

### File Location
```
priv/repo/migrations/*_add_priority_metadata_to_url_metadata.exs
lib/gsc_analytics/schemas/url_metadata.ex
```

### Migration Implementation

```elixir
defmodule GscAnalytics.Repo.Migrations.AddPriorityMetadataToUrlMetadata do
  use Ecto.Migration

  def change do
    alter table(:gsc_url_metadata) do
      # Page type classification (manual override or classifier output)
      add :page_type, :string

      # Audit trail fields
      add :metadata_source, :string  # e.g., "priority_import", "classifier", "manual"
      add :metadata_batch_id, :string  # Links to import_batches.batch_id
      add :priority_imported_at, :utc_datetime  # When priority data was imported
    end

    # Composite unique index for efficient upserts
    # This prevents duplicate entries for same account + URL
    create unique_index(
      :gsc_url_metadata,
      [:account_id, :url],
      name: :gsc_url_metadata_account_id_url_index
    )

    # Index for audit queries (find all URLs from specific import batch)
    create index(
      :gsc_url_metadata,
      [:metadata_batch_id],
      name: :gsc_url_metadata_batch_id_index,
      where: "metadata_batch_id IS NOT NULL"
    )

    # Index for priority filtering (dashboard queries)
    create index(
      :gsc_url_metadata,
      [:account_id, :update_priority],
      name: :gsc_url_metadata_account_priority_index,
      where: "update_priority IS NOT NULL"
    )

    # Index for page type filtering (dashboard queries)
    create index(
      :gsc_url_metadata,
      [:account_id, :page_type],
      name: :gsc_url_metadata_account_page_type_index,
      where: "page_type IS NOT NULL"
    )
  end
end
```

### Updated Schema Module

```elixir
defmodule GscAnalytics.Schemas.UrlMetadata do
  use Ecto.Schema
  import Ecto.Changeset

  schema "gsc_url_metadata" do
    field :account_id, :integer
    field :property_url, :string
    field :url, :string

    # Existing fields
    field :url_type, :string
    field :content_category, :string
    field :update_priority, :string  # P1, P2, P3, P4

    # New priority URL fields
    field :page_type, :string
    field :metadata_source, :string
    field :metadata_batch_id, :string
    field :priority_imported_at, :utc_datetime

    # Other existing fields
    field :last_indexed, :utc_datetime
    field :last_crawled, :utc_datetime
    field :http_status_code, :integer
    field :canonical_url, :string

    timestamps()
  end

  @doc """
  Changeset for priority URL imports
  """
  def priority_import_changeset(metadata, attrs) do
    metadata
    |> cast(attrs, [
      :account_id,
      :url,
      :update_priority,
      :page_type,
      :metadata_source,
      :metadata_batch_id,
      :priority_imported_at
    ])
    |> validate_required([:account_id, :url, :update_priority])
    |> validate_inclusion(:update_priority, ~w(P1 P2 P3 P4))
    |> validate_inclusion(:metadata_source, ~w(priority_import classifier manual),
         message: "must be priority_import, classifier, or manual")
    |> unique_constraint([:account_id, :url],
         name: :gsc_url_metadata_account_id_url_index)
  end

  @doc """
  Changeset for classifier backfill
  """
  def classifier_backfill_changeset(metadata, attrs) do
    metadata
    |> cast(attrs, [:page_type, :url_type, :metadata_source])
    |> validate_required([:page_type])
  end
end
```

### Index Strategy Justification

#### 1. Composite Unique Index: `(account_id, url)`
**Purpose:** Enable efficient upserts and prevent duplicates

**Query Pattern:**
```sql
INSERT INTO gsc_url_metadata (account_id, url, ...)
VALUES (123, 'https://example.com/path', ...)
ON CONFLICT (account_id, url) DO UPDATE SET ...
```

**Benefits:**
- Ensures data integrity (one metadata record per account+URL)
- Speeds up ON CONFLICT resolution
- Used by importer for batch upserts

#### 2. Batch ID Index: `metadata_batch_id`
**Purpose:** Audit queries to find all URLs from specific import

**Query Pattern:**
```sql
SELECT * FROM gsc_url_metadata
WHERE metadata_batch_id = '1699123456789'
```

**Benefits:**
- Fast audit trail queries
- Enables batch rollback if needed
- Partial index (only rows with batch_id) keeps index small

#### 3. Priority Filter Index: `(account_id, update_priority)`
**Purpose:** Dashboard filters by priority tier

**Query Pattern:**
```sql
SELECT url, clicks, impressions
FROM gsc_data
JOIN gsc_url_metadata ON ...
WHERE metadata.account_id = 123
  AND metadata.update_priority IN ('P1', 'P2')
```

**Benefits:**
- Dramatically speeds up priority-filtered queries
- Partial index (only rows with priority) keeps index efficient
- Covers most common dashboard filter

#### 4. Page Type Index: `(account_id, page_type)`
**Purpose:** Dashboard filters by page type

**Query Pattern:**
```sql
SELECT url, clicks, impressions
FROM gsc_data
JOIN gsc_url_metadata ON ...
WHERE metadata.account_id = 123
  AND metadata.page_type = 'profile'
```

**Benefits:**
- Replaces expensive ILIKE pattern matching
- Enables instant page type filtering
- Partial index keeps size minimal

## Testing Requirements

### Migration Tests

```elixir
# test/gsc_analytics/repo/migrations/add_priority_metadata_test.exs
defmodule GscAnalytics.Repo.Migrations.AddPriorityMetadataTest do
  use GscAnalytics.DataCase

  alias GscAnalytics.Repo
  import Ecto.Migrator

  @migration_version 20251113_120000  # Replace with actual timestamp

  describe "migration up" do
    test "adds new columns to gsc_url_metadata" do
      # Run migration
      migrate_to(@migration_version)

      # Verify columns exist
      assert column_exists?(:gsc_url_metadata, :page_type)
      assert column_exists?(:gsc_url_metadata, :metadata_source)
      assert column_exists?(:gsc_url_metadata, :metadata_batch_id)
      assert column_exists?(:gsc_url_metadata, :priority_imported_at)
    end

    test "creates composite unique index" do
      migrate_to(@migration_version)

      indexes = get_indexes(:gsc_url_metadata)
      assert Enum.any?(indexes, &(&1.name == :gsc_url_metadata_account_id_url_index))
      assert Enum.any?(indexes, &(&1.unique == true))
    end

    test "creates partial indexes with WHERE clauses" do
      migrate_to(@migration_version)

      batch_index = get_index(:gsc_url_metadata, :gsc_url_metadata_batch_id_index)
      assert batch_index.where =~ "metadata_batch_id IS NOT NULL"
    end
  end

  describe "migration down" do
    test "removes columns and indexes cleanly" do
      # Migrate up then down
      migrate_to(@migration_version)
      migrate_to(@migration_version - 1)

      # Verify columns removed
      refute column_exists?(:gsc_url_metadata, :page_type)
      refute column_exists?(:gsc_url_metadata, :metadata_source)

      # Verify indexes removed
      indexes = get_indexes(:gsc_url_metadata)
      refute Enum.any?(indexes, &(&1.name == :gsc_url_metadata_account_id_url_index))
    end
  end
end
```

### Schema Tests

```elixir
# test/gsc_analytics/schemas/url_metadata_test.exs
defmodule GscAnalytics.Schemas.UrlMetadataTest do
  use GscAnalytics.DataCase

  alias GscAnalytics.Schemas.UrlMetadata

  describe "priority_import_changeset/2" do
    test "validates required fields" do
      changeset = UrlMetadata.priority_import_changeset(%UrlMetadata{}, %{})

      assert %{account_id: ["can't be blank"]} = errors_on(changeset)
      assert %{url: ["can't be blank"]} = errors_on(changeset)
      assert %{update_priority: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates priority tier values" do
      attrs = %{
        account_id: 123,
        url: "https://example.com",
        update_priority: "High"  # Invalid
      }

      changeset = UrlMetadata.priority_import_changeset(%UrlMetadata{}, attrs)

      assert %{update_priority: ["is invalid"]} = errors_on(changeset)
    end

    test "accepts valid priority import data" do
      attrs = %{
        account_id: 123,
        url: "https://example.com/path",
        update_priority: "P1",
        page_type: "profile",
        metadata_source: "priority_import",
        metadata_batch_id: "batch_001",
        priority_imported_at: DateTime.utc_now()
      }

      changeset = UrlMetadata.priority_import_changeset(%UrlMetadata{}, attrs)

      assert changeset.valid?
    end
  end

  describe "unique constraint" do
    test "prevents duplicate account_id + url combinations" do
      account_id = 123
      url = "https://example.com/path"

      # Insert first record
      %UrlMetadata{}
      |> UrlMetadata.priority_import_changeset(%{
        account_id: account_id,
        url: url,
        update_priority: "P1"
      })
      |> Repo.insert!()

      # Attempt duplicate
      result = %UrlMetadata{}
      |> UrlMetadata.priority_import_changeset(%{
        account_id: account_id,
        url: url,
        update_priority: "P2"
      })
      |> Repo.insert()

      assert {:error, changeset} = result
      assert %{account_id: ["has already been taken"]} = errors_on(changeset)
    end
  end
end
```

### Performance Tests

```elixir
# test/gsc_analytics/performance/metadata_queries_test.exs
defmodule GscAnalytics.Performance.MetadataQueriesTest do
  use GscAnalytics.DataCase

  describe "query performance with indexes" do
    setup do
      # Seed 60k metadata records
      account_id = 123
      records = generate_metadata_records(60_000, account_id)
      Repo.insert_all(UrlMetadata, records)

      {:ok, account_id: account_id}
    end

    test "priority filter uses index", %{account_id: account_id} do
      query = from m in UrlMetadata,
        where: m.account_id == ^account_id,
        where: m.update_priority in ["P1", "P2"]

      # Get query plan
      {_time, explain} = :timer.tc(fn ->
        Repo.explain(:all, query)
      end)

      # Verify index is used (not sequential scan)
      assert explain =~ "Index Scan"
      assert explain =~ "gsc_url_metadata_account_priority_index"
      refute explain =~ "Seq Scan"
    end

    test "page type filter uses index", %{account_id: account_id} do
      query = from m in UrlMetadata,
        where: m.account_id == ^account_id,
        where: m.page_type == "profile"

      explain = Repo.explain(:all, query)

      assert explain =~ "Index Scan"
      assert explain =~ "gsc_url_metadata_account_page_type_index"
    end

    test "upsert with composite index is efficient" do
      records = generate_metadata_records(1000, 999)

      {time_microseconds, _result} = :timer.tc(fn ->
        Repo.insert_all(
          UrlMetadata,
          records,
          on_conflict: {:replace_all_except, [:id, :inserted_at]},
          conflict_target: [:account_id, :url]
        )
      end)

      time_ms = time_microseconds / 1000
      # Should complete in under 500ms for 1k records
      assert time_ms < 500
    end
  end
end
```

## Implementation Notes

### Migration Naming Convention
```
YYYYMMDDHHMMSS_add_priority_metadata_to_url_metadata.exs
```

Example: `20251113120000_add_priority_metadata_to_url_metadata.exs`

### Running the Migration

```bash
# Development
mix ecto.migrate

# Staging (before production)
MIX_ENV=staging mix ecto.migrate

# Production (with caution)
MIX_ENV=production mix ecto.migrate

# Rollback if needed
mix ecto.rollback --step 1
```

### Index Size Estimation

For 60,000 URLs:
- Composite unique index: ~5-10 MB
- Batch ID partial index: ~2-3 MB (only priority URLs)
- Priority partial index: ~3-5 MB (only priority URLs)
- Page type partial index: ~3-5 MB (only classified URLs)

**Total index overhead:** ~15-25 MB (negligible for query performance gain)

### Partial Index Rationale

Using partial indexes with WHERE clauses keeps index size small:
```sql
CREATE INDEX ... WHERE metadata_batch_id IS NOT NULL
```

This indexes only ~60k priority URLs, not all URLs in the table (which could be millions). Dramatically reduces index size and maintenance cost.

### Migration Timing

- **Development:** <1 second (small dataset)
- **Staging:** 2-5 seconds (moderate dataset)
- **Production:** Estimate 10-30 seconds for millions of URLs

**Recommendation:** Run during low-traffic window (2-4 AM)

### Column Nullability

All new columns are nullable because:
1. Existing rows don't have priority data
2. Not all URLs will be priority URLs
3. Classifier backfill happens gradually (Ticket 06)
4. Allows incremental rollout

## Success Metrics

1. **Migration Success**
   - ✓ Migration completes without errors in dev/staging/prod
   - ✓ All columns added successfully
   - ✓ All indexes created successfully
   - ✓ Rollback works without data loss

2. **Query Performance**
   - ✓ Priority filter queries use index (verified with EXPLAIN)
   - ✓ Page type filter queries use index
   - ✓ Upsert operations complete in <500ms for 1k records
   - ✓ No full table scans on filtered queries

3. **Data Integrity**
   - ✓ Unique constraint prevents duplicate account+URL pairs
   - ✓ Existing data unaffected by migration
   - ✓ Schema validation enforces correct data types

## Related Files

- `02-mix-task-ingestion-pipeline.md` - Will use these columns for persistence
- `05-upsert-helper-module.md` - Will use composite unique index
- `07-url-performance-metadata-joins.md` - Will join on these columns
- `08-filters-stored-metadata.md` - Will leverage these indexes

## Next Steps

After this ticket is complete:
1. **Ticket 05:** Extract upsert helper using new schema and indexes
2. **Ticket 06:** Backfill existing URLs with classifier output
3. **Ticket 07:** Update dashboard queries to join metadata table
4. **Production monitoring:** Watch query performance after index creation
