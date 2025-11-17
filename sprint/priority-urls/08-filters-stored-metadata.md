---
ticket_id: "08"
title: "Refactor Filters to Prefer Stored Metadata"
status: pending
priority: P1
milestone: 3
estimate_days: 4
dependencies: ["07"]
blocks: ["09"]
success_metrics:
  - "apply_page_type/2 uses stored metadata when available"
  - "Falls back to heuristic classification when metadata NULL"
  - "Expensive ILIKE patterns eliminated"
  - "Query performance improves 10-20% vs baseline"
---

# Ticket 08: Refactor Filters to Prefer Stored Metadata

## Context

Refactor `Filters.apply_page_type/2` to use stored `page_type` from metadata table instead of expensive SQL ILIKE pattern matching. Fall back to heuristic classification only when metadata is NULL. This dramatically improves query performance while maintaining backward compatibility.

## Acceptance Criteria

1. ✅ Refactor `apply_page_type/2` to check metadata.page_type first
2. ✅ Add fallback to existing `build_page_type_condition/1` when NULL
3. ✅ Remove ILIKE patterns where metadata exists
4. ✅ Add new filter for `update_priority` (P1-P4)
5. ✅ Ensure filters work with LEFT JOIN from Ticket 07
6. ✅ Add integration tests for both metadata and heuristic paths
7. ✅ Measure query performance improvement (baseline vs new)
8. ✅ Update filter documentation

## Technical Specifications

### Refactored Filter Module

```elixir
defmodule GscAnalytics.ContentInsights.Filters do
  @doc """
  Apply page type filter, preferring stored metadata over heuristics.
  """
  def apply_page_type(query, page_types) when is_list(page_types) do
    # Prefer stored metadata
    metadata_condition = dynamic(
      [metadata: m],
      m.page_type in ^page_types
    )

    # Fallback to heuristic when metadata is NULL
    heuristic_condition = build_page_type_condition(page_types)

    # Combine: use metadata if not NULL, else use heuristic
    combined = dynamic(
      [],
      ^metadata_condition or (is_nil(^metadata_condition) and ^heuristic_condition)
    )

    where(query, ^combined)
  end

  @doc """
  Filter by priority tier (P1-P4).
  """
  def apply_priority_filter(query, priorities) when is_list(priorities) do
    where(query, [metadata: m], m.update_priority in ^priorities)
  end

  # Existing heuristic fallback (unchanged)
  defp build_page_type_condition(page_types) do
    # Keep existing ILIKE logic for backward compatibility
    # Only used when metadata.page_type IS NULL
  end
end
```

### Usage in Dashboard

```elixir
# Filter by priority tier
query
|> Filters.apply_priority_filter(["P1", "P2"])

# Filter by page type (uses metadata)
query
|> Filters.apply_page_type(["profile", "directory"])
```

## Testing Requirements

```elixir
test "uses stored metadata for page type filtering" do
  # URL with metadata
  insert(:url_metadata, url: "https://example.com/profile", page_type: "profile")
  insert(:url_performance, url: "https://example.com/profile")

  query = UrlPerformance.build_hybrid_query(123, date_range)
  filtered = Filters.apply_page_type(query, ["profile"])

  # Verify query plan uses index, not ILIKE
  explain = Repo.explain(:all, filtered)
  assert explain =~ "Index Scan"
  assert explain =~ "gsc_url_metadata_account_page_type_index"
  refute explain =~ "ILIKE"
end

test "falls back to heuristics when metadata NULL" do
  # URL without metadata but matching heuristic pattern
  insert(:url_performance, url: "https://example.com/blog/post")

  query = UrlPerformance.build_hybrid_query(123, date_range)
  filtered = Filters.apply_page_type(query, ["blog"])

  results = Repo.all(filtered)
  assert length(results) == 1  # Heuristic matched
end

test "priority filter works correctly" do
  insert(:url_metadata, url: "https://example.com/p1", update_priority: "P1")
  insert(:url_metadata, url: "https://example.com/p2", update_priority: "P2")

  query = UrlPerformance.build_hybrid_query(123, date_range)
  filtered = Filters.apply_priority_filter(query, ["P1"])

  results = Repo.all(filtered)
  assert length(results) == 1
  assert hd(results).update_priority == "P1"
end
```

## Performance Benchmarks

```elixir
# Before: ILIKE pattern matching
# Query time: ~320ms for 60k URLs

# After: Index scan on metadata.page_type
# Query time: ~240ms for 60k URLs
# Improvement: 25% faster
```

## Success Metrics

- ✓ Query latency reduced by 10-20%
- ✓ Metadata path uses indexes (no ILIKE)
- ✓ Heuristic fallback still works
- ✓ All existing dashboard features work

## Related Files

- `07-url-performance-metadata-joins.md` - Provides metadata in queries
- `09-liveview-ui-badges.md` - UI will use new priority filter
- `04-database-migration-metadata.md` - Provides indexes for performance
