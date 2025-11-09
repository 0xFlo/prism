# T007: Persistence Layer

**Status:** 🔵 Not Started
**Story Points:** 2
**Priority:** 🔥 P1 Critical
**TDD Required:** Partial (unit tests for save/query logic)

## Description
Implement database operations for storing and retrieving SERP snapshots.

## Acceptance Criteria
- [ ] `save_snapshot/1` function stores parsed SERP data
- [ ] Enforces property_id foreign key constraint
- [ ] Handles duplicate checks gracefully
- [ ] Query functions: latest_for_url, snapshots_for_property
- [ ] Tests cover save and query operations

## Implementation
```elixir
# lib/gsc_analytics/data_sources/serp/core/persistence.ex
defmodule GscAnalytics.DataSources.SERP.Core.Persistence do
  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.SerpSnapshot

  def save_snapshot(attrs) do
    %SerpSnapshot{}
    |> SerpSnapshot.changeset(attrs)
    |> Repo.insert()
  end

  def latest_for_url(property_id, url) do
    SerpSnapshot.latest_for_url(property_id, url)
    |> Repo.one()
  end

  def snapshots_for_property(property_id, opts \\ []) do
    limit = opts[:limit] || 100

    SerpSnapshot.for_property(property_id)
    |> SerpSnapshot.with_position()
    |> order_by([s], desc: s.checked_at)
    |> limit(^limit)
    |> Repo.all()
  end
end
```

## 📚 Reference Documentation
- **Ecto Guide:** [Research Doc](/Users/flor/Developer/prism/docs/phoenix-ecto-research.md)
