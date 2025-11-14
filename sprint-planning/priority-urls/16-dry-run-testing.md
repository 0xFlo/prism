---
ticket_id: "16"
title: "Dry-Run Testing with Sample Data"
status: pending
priority: P1
milestone: 6
estimate_days: 2
dependencies: ["01", "02", "03", "04", "05"]
blocks: ["17"]
success_metrics:
  - "Dry-run completes successfully with sample Rula files"
  - "60k cap enforcement validated"
  - "No database changes during dry-run"
  - "All validation rules tested"
---

# Ticket 16: Dry-Run Testing with Sample Data

## Context

Before production rollout, validate the entire import pipeline with real Rula data files in dry-run mode. Confirm validation rules work, 60k cap is enforced correctly, and no unexpected errors occur.

## Acceptance Criteria

1. ✅ Obtain sample Rula JSON files (~63.5k URLs)
2. ✅ Run Mix task with `--dry-run` flag
3. ✅ Validate all 4 files parse correctly
4. ✅ Confirm 60k cap drops correct URLs (from P4)
5. ✅ Review overflow report for dropped URLs
6. ✅ Verify validation catches malformed entries
7. ✅ Ensure no database changes during dry-run
8. ✅ Document any issues found and fix

## Testing Procedure

```bash
# Step 1: Place sample files
cp /path/to/rula/priority_urls_p*.json output/

# Step 2: Run dry-run
mix prism.import_priority_urls \
  --account-id 123 \
  --dry-run \
  --export-overflow overflow_report.json \
  --verbose

# Step 3: Review output
cat overflow_report.json | jq '.dropped_urls | length'
# Expected: ~3500 URLs dropped (63.5k → 60k)

# Step 4: Verify no DB changes
psql -d prism_dev -c "SELECT COUNT(*) FROM gsc_url_metadata WHERE metadata_batch_id IS NOT NULL;"
# Expected: 0 (dry-run doesn't persist)
```

## Success Metrics

- ✓ Dry-run completes without errors
- ✓ Exactly 60,000 URLs kept
- ✓ Dropped URLs are all P4 tier
- ✓ Validation report accurate
- ✓ No database changes

## Related Files

- `02-mix-task-ingestion-pipeline.md` - Implements dry-run
- `03-import-reporting-audit.md` - Generates reports
- `17-production-rollout-feature-flag.md` - Next step
