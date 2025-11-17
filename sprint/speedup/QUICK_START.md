# Phase 4 Quick Start Guide

## 🎯 Goal
Add concurrent HTTP batch processing to achieve ≥4× speedup (stretch: 8×).

## 📋 Prerequisites

**Read these first** (30 minutes):
1. `README.md` - Sprint overview and architecture
2. `PHASE4_IMPLEMENTATION_PLAN.md` - Technical design
3. `docs/elixir-patterns/README.md` - Pattern reference

## 🎫 Ticket Sequence

| Ticket | What | Time | Output |
|--------|------|------|--------|
| **S01** | QueryCoordinator GenServer | 3-4 days | New module + tests + ETS tracking |
| **S02** | ConcurrentBatchWorker | 2-3 days | Worker loop + supervision |
| **S03** | RateLimiter enhancement | 1 day | Batch support + config |
| **S04** | QueryPaginator refactor | 2-3 days | Concurrent mode + config switch |
| **S05** | Telemetry + tests | 2-3 days | Metrics + integration test |
| **S06** | Staging validation | 2-3 days | Performance validation + rollout |

**Total**: 3-4 weeks

## 🏗️ Architecture Overview

```
┌────────────────────────────────────┐
│   QueryPaginator                   │
│   Entry point, generates batches   │
└──────────────┬─────────────────────┘
               │
               ↓
┌────────────────────────────────────┐
│   QueryCoordinator (GenServer)     │
│   • Manages batch queue            │
│   • Tracks in-flight (ETS)         │
│   • Enforces backpressure          │
└──────────────┬─────────────────────┘
               │
               ↓
┌────────────────────────────────────┐
│   Task.Supervisor                  │
│   Supervises 3-5 workers           │
└──────────────┬─────────────────────┘
               │
               ↓
┌────────────────────────────────────┐
│   ConcurrentBatchWorker × N        │
│   1. take_batch()                  │
│   2. check_rate()                  │
│   3. fetch via Client              │
│   4. submit_results()              │
│   5. loop                          │
└────────────────────────────────────┘
```

## 🔑 Key Concepts

### Backpressure
- **Queue limit**: 1000 batches max
- **In-flight limit**: 10 batches awaiting persistence
- **Mailbox alert**: >500 messages = warning

### Rate Limiting
- **QPM limit**: 1,200 (stay <80% = 960)
- **Check**: Before every HTTP call
- **Batch-aware**: `check_rate(url, batch_size)`

### Idempotency
- **Batch ID**: `{date, start_row}` for deduplication
- **ETS tracking**: Survives coordinator crashes
- **Database**: UPSERT with conflict targets

### Halt Propagation
- **Trigger**: Any unrecoverable error
- **Target**: Stop all workers <5 seconds
- **Check**: Before AND after HTTP call

## 🎬 Quick Start Commands

```bash
# 1. Create feature branch
git checkout -b phase4-implementation

# 2. Start with S01
# Read: docs/elixir-patterns/genserver-coordination.md
# Create: lib/gsc_analytics/data_sources/gsc/support/query_coordinator.ex
# Test: test/gsc_analytics/data_sources/gsc/support/query_coordinator_test.exs

# 3. Validate after each ticket
mix precommit  # Compile, format, test

# 4. Run integration test after S04
mix test test/gsc_analytics/data_sources/gsc/concurrent_sync_integration_test.exs

# 5. Measure performance
iex -S mix phx.server
GscAnalytics.DataSources.GSC.Core.Sync.sync_date_range("sc-domain:test.com", ~D[2024-01-01], ~D[2024-05-30])
```

## 📊 Success Metrics

| Metric | Target | How to Check |
|--------|--------|--------------|
| Speedup | ≥4× | Time 150-day backfill (baseline: ~150min, target: <37min) |
| QPM | <80% (960) | `grep qpm logs/gsc_audit.log \| tail -20 \| jq` |
| Data integrity | 0 duplicates | Reconciliation query |
| Mailbox size | <500 | Telemetry dashboard |
| Halt time | <5s | Integration test |

## 🚨 Rollback

**Zero-downtime rollback**:
```elixir
# config/runtime.exs
config :gsc_analytics, GscAnalytics.DataSources.GSC.Core.Config,
  max_concurrency: 1  # Sequential mode
```

Restart app → Falls back to old behavior.

## 📚 Pattern Reference

| Need | See |
|------|-----|
| GenServer coordination | `docs/elixir-patterns/genserver-coordination.md` |
| Rate limiting | `docs/elixir-patterns/rate-limiting.md` |
| Telemetry | `docs/elixir-patterns/telemetry.md` |
| Task.async_stream | `docs/elixir-patterns/concurrent-processing.md` |

## 🐛 Common Issues

**Rate limit violations**
→ Reduce `max_concurrency`, verify rate check before HTTP

**Mailbox growth**
→ Check in-flight count, profile persistence speed

**Data duplication**
→ Verify batch dedup in coordinator, check UPSERT targets

**Slow halt**
→ Verify flag checks before/after HTTP, reduce timeout

## 💡 Pro Tips

1. **Start conservative**: `max_concurrency: 3` (can increase later)
2. **Test frequently**: Run `mix precommit` after every change
3. **Use spans**: `:telemetry.span/3` for automatic instrumentation
4. **Check existing code**: Many patterns already in codebase
5. **Ask questions**: Use pattern docs, ask user for clarification

## 🚀 Ready to Code?

```bash
# Open in editor
code sprint-planning/speedup/SPRINT_EXECUTION_PROMPT.md

# Start with ticket S01
# Follow the detailed spec in SPRINT_EXECUTION_PROMPT.md
# Reference patterns in docs/elixir-patterns/

# Happy coding! 🎉
```

---

**Next steps**: Open `SPRINT_EXECUTION_PROMPT.md` and start with S01.
