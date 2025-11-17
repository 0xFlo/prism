# Phase 4 Production Rollout Guide

## Current Status
✅ **Ready for cautious production deployment**
- Performance: 1.09× speedup (9% faster than sequential)
- Stability: All tests passing, no critical errors
- Configuration: Optimized and tested

## Deployment Settings

### Configuration Values (lib/gsc_analytics/data_sources/gsc/core/config.ex)
```elixir
# Critical values for Phase 4
def max_in_flight, do: 300        # Increased from 10
def default_batch_size, do: 25    # Reduced from 50
def max_concurrency, do: 3        # Start conservative
```

### Code Changes Required
1. ✅ **Already Applied**: QueryCoordinator uses async `cast` for submit_results
2. ✅ **Already Applied**: Rate limiter temporarily disabled
3. ⚠️ **TODO**: Increase database pool size in config/runtime.exs

## Rollout Steps

### Stage 1: Single Workspace Test (Day 1)
```bash
# Test with smallest workspace first
mix phase4.rollout --site-url "sc-domain:rula.com" \
  --account-id 4 --days 7 \
  --concurrency 3 --queue-size 1000 --in-flight 300
```

### Stage 2: Primary Workspace (Day 2)
```bash
# Deploy to main workspace with monitoring
mix phase4.rollout --site-url "sc-domain:scrapfly.io" \
  --account-id 5 --days 30 \
  --concurrency 3 --queue-size 1000 --in-flight 300
```

### Stage 3: Production Enable (Day 3)
Enable in production by setting environment variable:
```bash
ENABLE_CONCURRENT_SYNC=true
GSC_MAX_CONCURRENCY=3
```

## Monitoring Checklist

### Key Metrics to Watch
- [ ] Sync duration compared to baseline
- [ ] Database connection pool utilization
- [ ] Memory usage during sync
- [ ] Error rates (especially Postgrex timeouts)
- [ ] API call counts match expected values

### Warning Signs
⚠️ **Rollback if you see**:
- Postgrex timeout errors > 5% of requests
- Memory usage > 2GB
- Sync taking longer than sequential baseline
- Incomplete data (missing URLs or queries)

### Logs to Monitor
```bash
# Watch real-time sync progress
tail -f logs/gsc_audit.log | grep -E "sync|error"

# Check for database issues
grep -i "postgrex\|timeout" logs/error.log

# Verify API call efficiency
grep "api.request" logs/gsc_audit.log | tail -20
```

## Next Optimizations (Post-Deployment)

### Week 1: Database Pool
```elixir
# In config/runtime.exs
config :gsc_analytics, GscAnalytics.Repo,
  pool_size: 20  # Increase from 10
```

### Week 2: Async Database Writes
Move `refresh_lifetime_stats_incrementally` to background job:
- Use Oban or Task.Supervisor
- Batch updates every 1000 URLs
- Run outside critical path

### Week 3: Google Batch API
Implement proper multipart batching:
- Use Google's batch endpoint
- Send 50-100 requests per HTTP call
- Expected 2-3× speedup

## Rollback Plan

If issues arise:
1. Set `ENABLE_CONCURRENT_SYNC=false` immediately
2. Revert config changes:
   - max_in_flight back to 10
   - default_batch_size back to 50
3. Re-enable rate limiter if API errors occur
4. Monitor sequential sync to ensure stability

## Success Criteria

Phase 4 is successful if:
- ✅ 9% speedup maintained in production
- ✅ No increase in error rates
- ✅ Database pool remains stable
- ✅ Memory usage < 1.5× sequential

## Contact

Issues or questions:
- Check sprint-planning/speedup/PHASE4_FINDINGS.md for detailed analysis
- Review test results in output/phase4_rollout_*.md
- Monitor #gsc-sync Slack channel for alerts