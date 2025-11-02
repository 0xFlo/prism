# Ticket-002: Persist Property Relationships & Migration

## Status: TODO
**Priority:** P0
**Estimate:** 1 day
**Dependencies:** ticket-001
**Blocks:** ticket-003, ticket-005, ticket-006

## Problem Statement
After designing the workspace ↔ property model, we must persist it in the database. The migration needs to introduce new tables (or extend existing ones), backfill current defaults, and keep production-safe rollback paths.

## Acceptance Criteria
- [ ] `workspace_properties` table created with proper indexes and constraints
- [ ] Existing `default_property` values backfilled into new table
- [ ] `property_url` column added to `gsc_time_series` and `gsc_performance` tables
- [ ] Ecto schemas created with changesets and validations
- [ ] `mix ecto.rollback` tested and works cleanly

## Implementation Plan

### 1. Create WorkspaceProperty Schema

```elixir
# lib/gsc_analytics/schemas/workspace_property.ex
defmodule GscAnalytics.Schemas.WorkspaceProperty do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "workspace_properties" do
    # CRITICAL: workspace_id is integer to match existing account_id type
    field :workspace_id, :integer  # Not a belongs_to since accounts are config-based
    field :property_url, :string
    field :display_name, :string
    field :is_active, :boolean, default: false
    field :metadata, :map, default: %{}

    timestamps()
  end

  def changeset(property, attrs) do
    property
    |> cast(attrs, [:workspace_id, :property_url, :display_name, :is_active, :metadata])
    |> validate_required([:workspace_id, :property_url])
    |> validate_format(:property_url, ~r/^(sc-domain:|https:\/\/)/)
    |> unique_constraint([:workspace_id, :property_url])
    |> validate_single_active_property()
  end

  defp validate_single_active_property(changeset) do
    # Database will enforce via partial unique index
    # Additional application-level validation can be added here
    changeset
  end
end
```

### 2. Migration Files (3-Phase Approach)

**Best Practice:** Separate constraint validation from creation to avoid long table locks during backfill.

**Migration 1: Create table with constraints**

```elixir
# priv/repo/migrations/XXXXXX_create_workspace_properties.exs
defmodule GscAnalytics.Repo.Migrations.CreateWorkspaceProperties do
  use Ecto.Migration

  def change do
    create table(:workspace_properties, primary_key: false) do
      add :id, :binary_id, primary_key: true
      # CRITICAL: workspace_id is integer, not binary_id
      add :workspace_id, :integer, null: false
      add :property_url, :string, null: false
      add :display_name, :string
      add :is_active, :boolean, default: false, null: false
      add :metadata, :map, default: %{}

      timestamps()
    end

    # Standard unique constraint for workspace + property combination
    create unique_index(:workspace_properties, [:workspace_id, :property_url])

    # Partial unique index to ensure only one active property per workspace
    create unique_index(:workspace_properties, [:workspace_id],
      where: "is_active = true",
      name: :unique_active_property_per_workspace
    )

    # Index for fast active property lookup
    create index(:workspace_properties, [:workspace_id, :is_active])
  end
end
```

**Migration 2: Backfill from existing data**

```elixir
# priv/repo/migrations/XXXXXX_backfill_workspace_properties.exs
defmodule GscAnalytics.Repo.Migrations.BackfillWorkspaceProperties do
  use Ecto.Migration

  def up do
    # Backfill from gsc_account_settings.default_property
    # Using Ecto.UUID.generate() for Elixir-generated UUIDs
    execute """
    INSERT INTO workspace_properties (id, workspace_id, property_url, display_name, is_active, inserted_at, updated_at)
    SELECT
      md5(random()::text || clock_timestamp()::text)::uuid,
      account_id,
      default_property,
      default_property,
      true,
      NOW(),
      NOW()
    FROM gsc_account_settings
    WHERE default_property IS NOT NULL
    ON CONFLICT (workspace_id, property_url) DO NOTHING
    """
  end

  def down do
    execute "DELETE FROM workspace_properties"
  end
end
```

**Migration 3: Add property_url to data tables**

```elixir
# priv/repo/migrations/XXXXXX_add_property_url_to_data_tables.exs
defmodule GscAnalytics.Repo.Migrations.AddPropertyUrlToDataTables do
  use Ecto.Migration

  def change do
    alter table(:gsc_time_series) do
      add :property_url, :string  # nullable initially
    end

    alter table(:gsc_performance) do
      add :property_url, :string  # nullable initially
    end

    # Composite indexes for efficient querying
    create index(:gsc_time_series, [:account_id, :property_url])
    create index(:gsc_performance, [:account_id, :property_url])
  end
end
```

**Migration 4: Backfill property_url in data tables**

```elixir
# priv/repo/migrations/XXXXXX_backfill_property_urls.exs
defmodule GscAnalytics.Repo.Migrations.BackfillPropertyUrls do
  use Ecto.Migration

  def up do
    # Backfill time_series with default_property from account_settings
    execute """
    UPDATE gsc_time_series ts
    SET property_url = gas.default_property
    FROM gsc_account_settings gas
    WHERE ts.account_id = gas.account_id
    AND gas.default_property IS NOT NULL
    AND ts.property_url IS NULL
    """

    # Backfill performance table
    execute """
    UPDATE gsc_performance p
    SET property_url = gas.default_property
    FROM gsc_account_settings gas
    WHERE p.account_id = gas.account_id
    AND gas.default_property IS NOT NULL
    AND p.property_url IS NULL
    """
  end

  def down do
    execute "UPDATE gsc_time_series SET property_url = NULL"
    execute "UPDATE gsc_performance SET property_url = NULL"
  end
end
```

### 3. Update Existing Schemas

No need to update GscAccount since accounts are config-based, but we should update the relationships:

```elixir
# lib/gsc_analytics/schemas/time_series.ex
# Add to schema block:
field :property_url, :string

# lib/gsc_analytics/schemas/performance.ex
# Add to schema block:
field :property_url, :string
```

## Testing Notes
- Test constraint enforcement (duplicate property URLs should fail)
- Verify `mix ecto.rollback` for each migration step
- Test with empty database and with existing data
- Verify indexes are created:
  ```sql
  SELECT * FROM pg_indexes WHERE tablename = 'workspace_properties';
  ```
- Verify partial unique index works:
  ```sql
  -- Should fail:
  INSERT INTO workspace_properties (id, workspace_id, property_url, is_active)
  VALUES (gen_random_uuid(), 1, 'test1', true);
  INSERT INTO workspace_properties (id, workspace_id, property_url, is_active)
  VALUES (gen_random_uuid(), 1, 'test2', true); -- Should fail
  ```

## Rollback Strategy

Each migration can be rolled back independently:
1. Migration 4: Sets property_urls back to NULL
2. Migration 3: Drops columns and indexes
3. Migration 2: Deletes backfilled data
4. Migration 1: Drops the workspace_properties table

The existing `default_property` in `gsc_account_settings` remains untouched as a fallback.