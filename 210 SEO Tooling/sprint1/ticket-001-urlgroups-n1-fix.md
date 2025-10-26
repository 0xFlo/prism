# Ticket #001: Fix UrlGroups N+1 Query with Chain Preloading

**Status**: ✅ Done (2025-10-19)
**Estimate**: 4 hours
**Priority**: 🔴 High
**Phase**: 1 (Quick Wins)
**Dependencies**: None

---

## Problem Statement

The current `UrlGroups.resolve/2` function performs sequential queries for each redirect hop in a chain, causing N+1 query issues. A 3-hop redirect chain results in 7 queries:

1. `Repo.get_by` for URL1 → finds redirect to URL2
2. `Repo.get_by` for URL2 → finds redirect to URL3
3. `Repo.get_by` for URL3 → finds canonical
4. `fetch_related_performance_rows` → finds all rows pointing to canonical
5. `time_bounds` → finds earliest/latest dates

**File**: `lib/gsc_analytics/url_groups.ex:86-101`

---

## Solution

Implement iterative redirect chain preloading that fetches redirect levels in batches:

### Approach
1. Fetch all Performance rows for the initial URL
2. Extract redirect targets not yet seen
3. Fetch Performance rows for those targets
4. Repeat until no new redirects found
5. Walk the preloaded chain in-memory to find canonical

### Expected Query Count
- 3-hop chain: **4 queries** (was 7) → 43% reduction
- 5-hop chain: **5 queries** (was 11) → 55% reduction

---

## Acceptance Criteria

- [x] `resolve/2` maintains same API signature
- [x] Returns same result structure as before
- [x] Handles redirect chains up to 10 hops deep
- [x] Detects and handles circular redirects gracefully
- [x] Query count reduced for multi-hop chains
- [x] Existing tests pass
- [x] New tests added for:
  - [x] 3-hop redirect chain
  - [x] 5-hop redirect chain
  - [x] Circular redirect detection
  - [x] Chain with nil/empty redirect_url

---

## Outcome

- Implemented iterative redirect chain loader and walker in `Tools/gsc_analytics/lib/gsc_analytics/url_groups.ex:18-148`, cutting redirect resolution queries from 7 → 4 for a 3-hop chain.
- Added focused regression coverage in `Tools/gsc_analytics/test/gsc_analytics/url_groups_test.exs:1-142`, covering multi-hop, cyclical, and nil redirect cases.
- Verified dashboard URL detail flows locally; no API changes required for downstream callers.

---

## Implementation Tasks

### Task 1: Add chain preloading helper (1h)
```elixir
# lib/gsc_analytics/url_groups.ex

defp fetch_redirect_chain(url, account_id, chain_map, seen_urls) do
  # Fetch Performance rows for unseen URLs
  # Build map of url -> redirect_url
  # Find new redirect targets
  # Recurse if new targets found
end
```

**Files to modify**:
- `lib/gsc_analytics/url_groups.ex`

### Task 2: Add in-memory chain walker (30m)
```elixir
defp walk_chain(url, chain_map, visited) do
  # Navigate chain using preloaded map
  # Detect cycles with visited set
end
```

### Task 3: Replace canonical_url/3 implementation (30m)
- Keep public API same
- Call `fetch_redirect_chain` + `walk_chain`
- Remove recursive `Repo.get_by` calls

### Task 4: Add comprehensive tests (1.5h)
Create `test/gsc_analytics/url_groups_test.exs`:
- Test multi-hop chains
- Test circular redirect detection
- Test query count (use ExUnit query counter)
- Test edge cases (nil redirects, empty strings)

### Task 5: Manual verification (30m)
- Check dashboard URL detail page with redirected URL
- Verify redirect events still display correctly
- Verify chart data aggregates across URL group

---

## Testing Strategy

### Unit Tests
```elixir
test "resolves 3-hop redirect chain with reduced queries" do
  # Setup: URL1 → URL2 → URL3 (canonical)
  # Assert: canonical_url == URL3
  # Assert: query count <= 4
end

test "detects circular redirects" do
  # Setup: URL1 → URL2 → URL1
  # Assert: returns one of the URLs (no infinite loop)
end
```

### Integration Test
```elixir
test "URL detail page works with multi-hop redirect", %{conn: conn} do
  # Navigate to old URL
  # Verify canonical resolution
  # Verify time series aggregation
end
```

---

## Performance Benchmark

Before:
```
3-hop chain: 7 queries, ~45ms
5-hop chain: 11 queries, ~75ms
```

Target:
```
3-hop chain: ≤4 queries, ~25ms
5-hop chain: ≤5 queries, ~35ms
```

---

## Rollback Plan

If issues arise:
1. Revert commit
2. Original implementation remains in git history
3. No schema changes, safe to rollback

---

## Related Files

- `lib/gsc_analytics/url_groups.ex` (modify)
- `test/gsc_analytics/url_groups_test.exs` (create)
- `lib/gsc_analytics/dashboard.ex` (verify no impact)
- `lib/gsc_analytics_web/live/dashboard_url_live.ex` (verify no impact)

---

## Notes

- Keep `fetch_related_performance_rows` and `time_bounds` as-is (only 1 query each)
- Ensure preload handles edge cases (nil redirect_url, empty strings, self-redirects)
- Consider adding Telemetry events for monitoring query count in production
