---
ticket_id: "17"
title: "Production Rollout with Feature Flag"
status: pending
priority: P1
milestone: 6
estimate_days: 3
dependencies: ["16"]
blocks: ["18"]
success_metrics:
  - "Feature flag created for Rula account"
  - "Import runs successfully in production"
  - "Dashboard displays priority badges correctly"
  - "No performance degradation"
---

# Ticket 17: Production Rollout with Feature Flag

## Context

Deploy priority URL feature to production with a feature flag scoped to Rula account. Monitor dashboard performance, badge display, and query latency. Be prepared to rollback if issues occur.

## Acceptance Criteria

1. ✅ Create feature flag `priority_urls_enabled` for account
2. ✅ Run production import for Rula account
3. ✅ Verify 60,000 URLs imported successfully
4. ✅ Check dashboard displays priority badges
5. ✅ Monitor query performance (target: <250ms)
6. ✅ Verify filters work correctly
7. ✅ Set up alerts for import failures
8. ✅ Document rollback procedure

## Rollout Checklist

```bash
# Pre-rollout
[ ] Database migration applied to production
[ ] Feature flag configured in production
[ ] Monitoring dashboards ready
[ ] Rollback plan documented

# Rollout
[ ] Enable feature flag for Rula account only
[ ] Run import with real Rula files
[ ] Verify import batch record created
[ ] Check dashboard for priority badges
[ ] Test filters (priority tier, page type)
[ ] Monitor query performance for 24 hours

# Post-rollout
[ ] Review batch record and overflow report
[ ] Validate 100% badge accuracy
[ ] Measure query latency improvement
[ ] Gather client feedback
[ ] Document lessons learned
```

## Monitoring Queries

```sql
-- Check import success
SELECT * FROM import_batches
WHERE account_id = 123
ORDER BY created_at DESC
LIMIT 1;

-- Verify URL count
SELECT COUNT(*) FROM gsc_url_metadata
WHERE account_id = 123
AND metadata_batch_id IS NOT NULL;
-- Expected: 60,000

-- Check priority distribution
SELECT update_priority, COUNT(*)
FROM gsc_url_metadata
WHERE account_id = 123
GROUP BY update_priority;
```

## Rollback Procedure

```bash
# If issues occur:
# 1. Disable feature flag
mix prism.feature_flags.disable priority_urls_enabled --account-id 123

# 2. Clear imported metadata (optional)
psql -d prism_prod -c "
  UPDATE gsc_url_metadata
  SET update_priority = NULL,
      page_type = NULL,
      metadata_batch_id = NULL
  WHERE account_id = 123;
"

# 3. Monitor recovery
# Dashboard should fall back to heuristic classification
```

## Success Metrics

- ✓ Import completes in <2 minutes
- ✓ 60,000 URLs imported
- ✓ Dashboard loads in <250ms
- ✓ Priority badges 100% accurate
- ✓ No errors in logs

## Related Files

- `16-dry-run-testing.md` - Validated before this
- `18-performance-validation-docs.md` - Measures impact
