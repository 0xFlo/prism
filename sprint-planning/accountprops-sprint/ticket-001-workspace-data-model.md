# Ticket-001: Design Workspace + Property Data Model

## Status: TODO
**Priority:** P0
**Estimate:** 0.5 day
**Dependencies:** None
**Blocks:** ticket-002, ticket-004, ticket-005

## Problem Statement
The system treats each `account_id` as a single Search Console property. We need a flexible data model that lets a workspace own multiple properties, capture human-readable labels, and preserve OAuth linkage while remaining backward-compatible with existing data.

## Goals
- Define an entity relationship diagram for Workspace ↔ Google Login ↔ Property
- Specify storage requirements and migration strategy
- Decide how to represent active vs. available properties and historical selections
- Outline fallback rules for service-account-backed workspaces

## Acceptance Criteria
- [ ] Schema design completed with `workspace_properties` join table using foreign keys (NOT Postgres schemas)
- [ ] Unique `(workspace_id, property_url)` constraint defined
- [ ] Fields: `is_active` boolean, `display_name` string, `metadata` jsonb
- [ ] Migration strategy outlined (3-phase approach for backward compatibility)
- [ ] Rollback strategy documented

## Implementation Plan

### 1. Data Model Design (Foreign Key Approach)

**Why Foreign Keys vs Postgres Schemas:**
- Properties share the same workspace's OAuth credentials (not separate tenants)
- Need to switch between properties in the same UI session
- Simple queries: `WHERE workspace_id = ? AND property_url = ?`
- Cross-property analytics remain easy
- Postgres schemas are overkill for this use case (intended for true multi-tenancy with data isolation)

**Proposed Schema:**

```elixir
# IMPORTANT: Account IDs are integers, not UUIDs
# Existing: gsc_accounts (workspaces) - configured in application config
# - id (integer) - configured via :gsc_analytics config
# - name (display name)

# Existing: gsc_account_settings (runtime overrides)
# - account_id (integer, foreign key)
# - display_name (user override)
# - default_property (DEPRECATED, will migrate data out)
# - oauth tokens, etc.

# NEW: workspace_properties (join table)
defmodule GscAnalytics.Schemas.WorkspaceProperty do
  schema "workspace_properties" do
    # Use binary_id for new tables (following existing pattern for new entities)
    field :id, :binary_id, primary_key: true
    # Foreign key is integer to match existing account_id type
    field :workspace_id, :integer  # References account_id (integer)
    field :property_url, :string    # GSC property identifier (sc-domain:example.com)
    field :display_name, :string    # User-friendly label
    field :is_active, :boolean      # Currently selected property for sync/dashboard
    field :metadata, :map           # Future extensibility (verification status, etc.)

    timestamps()
  end
end

# Constraints:
# - unique index on (workspace_id, property_url)
# - partial unique index on (workspace_id) where is_active = true (ensures single active)
# - index on (workspace_id, is_active) for fast active property lookup
# - foreign key constraint to gsc_account_settings(account_id)
```

### 2. Existing Schema Updates

Add `property_url` column to data tables:
- `gsc_time_series` - add `property_url` string column (nullable initially for migration)
- `gsc_performance` - add `property_url` string column (nullable initially for migration)
- Index: `(account_id, property_url)` for efficient queries

### 3. Migration Strategy

**Phase 1:** Create new structures (backward compatible)
- Create `workspace_properties` table with binary_id primary key
- Backfill from existing `default_property` field in gsc_account_settings
- Add `property_url` columns to data tables (nullable)

**Phase 2:** Data migration (can be done in background)
- Populate `property_url` in existing `gsc_time_series`/`gsc_performance` rows from account_settings `default_property`

**Phase 3:** Enforcement (after verification)
- Make `property_url` NOT NULL in data tables
- Keep `default_property` column in gsc_account_settings for rollback safety (deprecate in later release)

### 4. Normalization Rules
- Property URLs canonicalized to GSC format (`sc-domain:` or `https://`)
- Display names default to property URL if not provided
- Only one `is_active = true` property per workspace (enforced via partial unique index)
- Hard delete approach (soft deletes add complexity; can add later if needed)

## Critical Implementation Notes

### ID Type Consistency
- **Account IDs are integers** throughout the existing system (not UUIDs)
- New `workspace_properties` table should use `binary_id` for its primary key (following pattern for new entities)
- Foreign key `workspace_id` must be `:integer` to match existing `account_id` type

### Database Constraints
```sql
-- Ensure single active property per workspace
CREATE UNIQUE INDEX unique_active_property_per_workspace
ON workspace_properties (workspace_id)
WHERE is_active = true;
```

## Deliverables
- Schema definitions ready for ticket-002 implementation
- Migration strategy documented above
- Rollback procedure for each phase