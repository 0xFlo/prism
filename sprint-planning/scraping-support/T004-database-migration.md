# T004: Database Migration

**Status:** 🔵 Not Started
**Story Points:** 2
**Priority:** 🔥 P1 Critical
**TDD Required:** No (database setup)

## Description
Create the database migration for the `serp_snapshots` table with proper indexes and foreign key constraints.

## Acceptance Criteria
- [ ] Migration file created
- [ ] Table includes all schema fields
- [ ] Foreign key constraint on property_id
- [ ] Indexes for query performance (property_id, url, keyword, checked_at)
- [ ] Unique index prevents duplicate checks
- [ ] Migration runs successfully
- [ ] Migration rollback works

## Implementation Steps

1. **Generate migration**
   ```bash
   mix ecto.gen.migration create_serp_snapshots
   ```

2. **Implement migration**
   ```elixir
   # priv/repo/migrations/YYYYMMDDHHMMSS_create_serp_snapshots.exs
   defmodule GscAnalytics.Repo.Migrations.CreateSerpSnapshots do
     use Ecto.Migration

     def change do
       create table(:serp_snapshots, primary_key: false) do
         add :id, :binary_id, primary_key: true

         # Relations (CRITICAL: Use property_id for tenancy)
         add :account_id, :integer, null: false
         add :property_id, references(:properties, type: :binary_id, on_delete: :delete_all), null: false

         # URL being checked
         add :url, :string, null: false

         # SERP Data
         add :keyword, :string, null: false
         add :position, :integer
         add :serp_features, {:array, :string}, default: []
         add :competitors, {:array, :map}, default: []
         add :raw_response, :map

         # Metadata
         add :geo, :string, default: "us"
         add :checked_at, :utc_datetime, null: false
         add :api_cost, :decimal, precision: 10, scale: 2
         add :error_message, :text

         timestamps(type: :utc_datetime, updated_at: false)
       end

       # Indexes for query performance
       create index(:serp_snapshots, [:property_id, :url, :keyword])
       create index(:serp_snapshots, [:checked_at])  # For pruning old snapshots
       create index(:serp_snapshots, [:position])    # For ranking queries

       # Unique constraint prevents duplicate checks within same hour
       create unique_index(:serp_snapshots,
         [:property_id, :url, :keyword, :checked_at],
         name: :serp_snapshots_unique_check
       )
     end
   end
   ```

3. **Run migration**
   ```bash
   mix ecto.migrate
   ```

4. **Test rollback**
   ```bash
   mix ecto.rollback
   mix ecto.migrate
   ```

5. **Update test database**
   ```bash
   MIX_ENV=test mix ecto.reset
   ```

## Testing

No automated tests for migrations, but verify:

```bash
# Check table exists
psql gsc_analytics_dev -c "\d serp_snapshots"

# Check indexes
psql gsc_analytics_dev -c "\di serp_snapshots*"

# Check foreign key constraint
psql gsc_analytics_dev -c "
  SELECT
    tc.constraint_name,
    tc.table_name,
    kcu.column_name,
    ccu.table_name AS foreign_table_name
  FROM information_schema.table_constraints AS tc
  JOIN information_schema.key_column_usage AS kcu
    ON tc.constraint_name = kcu.constraint_name
  JOIN information_schema.constraint_column_usage AS ccu
    ON ccu.constraint_name = tc.constraint_name
  WHERE tc.table_name='serp_snapshots' AND tc.constraint_type = 'FOREIGN KEY';
"
```

## Definition of Done
- [ ] Migration created
- [ ] Migration runs without errors
- [ ] Migration rolls back successfully
- [ ] Table schema matches SerpSnapshot Ecto schema
- [ ] All indexes created
- [ ] Foreign key constraint works
- [ ] Test database updated

## Notes
- **CRITICAL:** Use property_id FK for proper tenancy (Codex requirement)
- Unique index on [:property_id, :url, :keyword, :checked_at] prevents duplicate API costs
- Index on :checked_at supports efficient pruning queries
- Index on :position supports ranking analysis

## 📚 Reference Documentation
- **Ecto Migrations:** [Guide](/Users/flor/Developer/prism/docs/phoenix-ecto-research.md)
- **Example:** Check existing migrations in `priv/repo/migrations/`
