# T002: Create Oban Database Migration

**Status:** 🔵 Not Started
**Story Points:** 1
**Priority:** 🔥 P1 Critical
**TDD Required:** No (database schema)
**Depends On:** T001

## Description
Generate and run Ecto migration to create Oban's job queue tables in PostgreSQL.

## Acceptance Criteria
- [ ] Migration file created with Oban schema
- [ ] Migration runs successfully in dev environment
- [ ] Migration runs successfully in test environment
- [ ] Oban tables exist in database (oban_jobs, oban_peers)

## Implementation Steps

1. **Generate migration**
   ```bash
   mix ecto.gen.migration add_oban_tables
   ```

2. **Edit migration file**
   ```elixir
   defmodule GscAnalytics.Repo.Migrations.AddObanTables do
     use Ecto.Migration

     def up do
       Oban.Migration.up(version: 12)
     end

     def down do
       Oban.Migration.down(version: 12)
     end
   end
   ```

3. **Run migration in dev**
   ```bash
   mix ecto.migrate
   ```

4. **Run migration in test**
   ```bash
   MIX_ENV=test mix ecto.migrate
   ```

5. **Verify tables created**
   ```bash
   psql -d gsc_analytics_dev -c "\dt oban*"
   # Should show: oban_jobs, oban_peers
   ```

## Testing
- Manual verification via psql
- Ensure `mix ecto.rollback` works correctly

## Definition of Done
- [ ] Migration file exists in `priv/repo/migrations/`
- [ ] Migration runs without errors
- [ ] Oban tables visible in database
- [ ] Rollback tested and works
- [ ] Both dev and test databases migrated

## Notes
- Using Oban.Migration.up(version: 12) for latest schema
- Version 12 includes all necessary columns for Oban 2.18
- Tables created: `oban_jobs`, `oban_peers`

## 📚 Reference Documentation
- **Primary:** [Oban Reference](/Users/flor/Developer/prism/docs/OBAN_REFERENCE.md) - Migration section
- **Secondary:** [Phoenix/Ecto Research](/Users/flor/Developer/prism/docs/phoenix-ecto-research.md) - Migration best practices
- **Official:** https://hexdocs.pm/oban/Oban.Migration.html
- **Index:** [Documentation Index](docs/DOCUMENTATION_INDEX.md)
