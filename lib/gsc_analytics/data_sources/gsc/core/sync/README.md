# Sync Pipeline Overview

The Google Search Console sync is split into focused modules that make it
straightforward to reason about responsibilities and test behaviour.

## Modules

- **State** – typed struct with Agent-backed metrics storage
- **Pipeline** – chunk orchestration and halt condition evaluation
- **URLPhase** – URL fetching, persistence, and progress reporting
- **QueryPhase** – Query pagination, persistence, and failure handling
- **ProgressTracker** – Wrapper around `SyncProgress` with consistent step lookup

## Data Flow

```
State.new
  ↓
Pipeline.execute
  ↓
┌──────────────────────────┐
│ For each chunk:          │
│   URLPhase.fetch_and_store│
│     ↓                    │
│   QueryPhase.fetch_and_store│
│     ↓                    │
│   Metrics + halt checks  │
└──────────────────────────┘
  ↓
ProgressTracker.finish_job
```

## Testing

Run the focused test suites to validate the refactor:

```bash
mix test test/gsc_analytics/data_sources/gsc/core/sync_test.exs
mix test test/gsc_analytics/data_sources/gsc/core/sync_progress_integration_test.exs
```

These cover state transitions, progress reporting, and halt metadata to
ensure backwards compatibility with the previous monolithic implementation.
