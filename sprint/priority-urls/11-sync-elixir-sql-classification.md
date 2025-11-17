---
ticket_id: "11"
title: "Sync Elixir and SQL Classification Logic"
status: pending
priority: P2
milestone: 4
estimate_days: 2
dependencies: ["10"]
blocks: ["12"]
success_metrics:
  - "SQL helper functions match Elixir classifier logic"
  - "Classification results identical between Elixir and SQL"
  - "Prefer stored metadata to avoid divergence"
---

# Ticket 11: Sync Elixir and SQL Classification Logic

## Context

Historically, page type classification logic existed in both `PageTypeClassifier` (Elixir) and SQL helper functions, leading to divergence. With stored metadata (Ticket 04), we can compute once and store results. Update SQL helpers to match new Elixir patterns or eliminate them entirely in favor of stored values.

## Acceptance Criteria

1. ✅ Document current SQL classification logic
2. ✅ Update SQL helpers to match new Elixir patterns (Ticket 10)
3. ✅ OR eliminate SQL helpers and rely on stored metadata
4. ✅ Ensure classification consistency (Elixir == SQL)
5. ✅ Add tests comparing Elixir vs SQL output
6. ✅ Recommend approach: compute once (Elixir), store, query (SQL)

## Technical Specifications

### Option A: Update SQL Helpers

```sql
CREATE OR REPLACE FUNCTION classify_page_type(url text, account_id integer)
RETURNS text AS $$
BEGIN
  -- Check if Rula account
  IF account_id = (SELECT id FROM accounts WHERE name = 'Rula') THEN
    IF url ~ '/therapist/[\w-]+$' THEN
      RETURN 'profile';
    ELSIF url ~ '/therapists/?$' THEN
      RETURN 'directory';
    ELSIF url ~ '/therapy/locations/' THEN
      RETURN 'location';
    END IF;
  END IF;

  -- Existing logic...
  RETURN 'other';
END;
$$ LANGUAGE plpgsql;
```

### Option B: Eliminate SQL Helpers (Recommended)

```elixir
# Instead of SQL classification:
# 1. Run PageTypeClassifier once during import/backfill
# 2. Store result in metadata.page_type
# 3. Query stored value (no runtime classification)

# Benefits:
# - Single source of truth (Elixir classifier)
# - No divergence between Elixir and SQL
# - Faster queries (no regex in SQL)
```

## Testing Requirements

```elixir
test "Elixir and SQL classification match" do
  urls = [
    "https://www.rula.com/therapist/john-smith",
    "https://www.rula.com/therapists",
    "https://www.rula.com/therapy/locations/ca"
  ]

  for url <- urls do
    elixir_result = PageTypeClassifier.classify(url, account_id: rula_id)
    sql_result = classify_via_sql(url, rula_id)

    assert elixir_result == sql_result,
      "Classification mismatch for #{url}: Elixir=#{elixir_result}, SQL=#{sql_result}"
  end
end
```

## Success Metrics

- ✓ 100% consistency between Elixir and SQL
- ✓ Decision made: update SQL or eliminate
- ✓ Implementation matches decision

## Related Files

- `10-classifier-directory-patterns.md` - New patterns to sync
- `08-filters-stored-metadata.md` - Already prefers stored values
