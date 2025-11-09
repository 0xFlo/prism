# Workflow Automation System - Implementation Status

**Status**: Foundation Phase Complete ✅
**Last Updated**: 2025-01-09

## Overview

This document tracks the implementation of an AirOps-inspired workflow automation platform built on Phoenix LiveView, Elixir/OTP, and MCP integration for GSC Analytics content refresh operations.

## Architecture Review (Codex)

The design was reviewed by Codex CLI and incorporates all critical recommendations:

✅ **ETS-backed state** (instead of Agent)
✅ **Composite database indexes** for LiveView performance
✅ **JSON GIN indexes** for PostgreSQL query optimization
✅ **Durable event persistence** alongside PubSub
✅ **Crash recovery via snapshots**
✅ **Native JSON module** (not Jason)

## Completed Components

### Phase 1: Foundation

#### Database Schema ✅
- **Migration**: `20251109141727_create_workflows.exs`
- **Tables**:
  - `workflows` - Workflow definitions with optimized indexes
  - `workflow_executions` - Runtime instances with context snapshots
  - `workflow_execution_events` - Immutable audit log with GIN indexes
  - `workflow_review_queue` - Human review items
- **Indexes**:
  - Composite: `{workflow_id, inserted_at}`, `{execution_id, status}`
  - GIN: `context_snapshot`, `payload` (PostgreSQL)
  - Single: account_id, status, reviewer_id, expires_at

#### Ecto Schemas ✅
- **`GscAnalytics.Schemas.Workflow`** (`lib/gsc_analytics/schemas/workflow.ex`)
  - Validations: circular dependencies, orphaned nodes, duplicate IDs
  - Query helpers: `published/1`, `for_account/2`, `recent_first/1`
  - Changesets: create, publish, archive

- **`GscAnalytics.Workflows.Execution`** (`lib/gsc_analytics/workflows/execution.ex`)
  - Status transitions: queued → running → completed/failed/cancelled
  - Changesets: start, progress, pause, resume, complete, fail, cancel
  - Query helpers: `for_workflow/2`, `active/1`, `with_status/2`

- **`GscAnalytics.Workflows.ExecutionEvent`** (`lib/gsc_analytics/workflows/execution_event.ex`)
  - Immutable event stream (append-only)
  - Factory functions for common events
  - Query helpers: `for_execution/2`, `chronological/1`, `steps_only/1`

#### Runtime State Management ✅
- **`GscAnalytics.Workflows.Runtime`** (`lib/gsc_analytics/workflows/runtime.ex`)
  - ETS-backed state (per Codex recommendation)
  - Crash recovery via `restore/1`
  - Automatic snapshots every 5 seconds
  - Force snapshots on step completion/failure
  - Public API:
    - `new/2` - Create runtime state
    - `restore/1` - Restore from DB snapshot
    - `get_state/1` - Get current state
    - `store_step_output/3` - Store step results
    - `mark_step_completed/2` - Track progress
    - `force_snapshot/1` - Persist to DB

## Remaining Components

### Phase 2: Engine & Execution

#### Engine (with DynamicSupervisor)
**Priority**: 🔥 P1 Critical
**File**: `lib/gsc_analytics/workflows/engine.ex`

Per Codex review, must use `DynamicSupervisor` instead of bare GenServer:
- Supervision tree per execution
- Owned by supervisor (not execution process)
- Crash recovery via Runtime.restore/1
- Async tasks for long-running LLM/API work (don't block GenServer mailbox)

#### ProgressTracker (Durable)
**Priority**: 🔥 P1 Critical
**File**: `lib/gsc_analytics/workflows/progress_tracker.ex`

Must pair PubSub broadcasts with `ExecutionEvent` persistence:
- GenServer tracking active executions
- PubSub for real-time updates
- DB-backed event stream for reconnect recovery
- LiveView loads history from DB on mount

### Phase 3: Variable & Expression System

#### Template Compiler (with ETS Caching)
**Priority**: 🔥 P1 Critical
**File**: `lib/gsc_analytics/workflows/variables.ex`

Per Codex review:
- Compile Liquid templates to AST once
- Cache in ETS keyed by checksum
- Separate compile phase + execute phase
- Static analysis to reject undefined variables

#### Expression Evaluator (Sandboxed)
**Priority**: 🚨 P1 Security Critical
**File**: `lib/gsc_analytics/workflows/expressions.ex`

Must NOT use `Code.eval_string`:
- Whitelist-only filters
- Rate limit via Hammer (prevent DoS)
- Safe parser (no arbitrary code execution)
- Support: >, <, >=, <=, ==, !=, &&, ||, !

### Phase 4: Step System

#### Step Executor Protocol
**Priority**: 🔥 P1 Critical
**File**: `lib/gsc_analytics/workflows/steps/executor.ex`

Protocol for polymorphic step execution:
```elixir
defprotocol GscAnalytics.Workflows.Steps.Executor do
  @spec execute_step(map(), map(), integer()) ::
    {:ok, map()} | {:error, term()} | {:wait_for_review, String.t()}
  def execute_step(step, context, account_id)
end
```

#### Step Implementations
**Priority**: 🟡 P2 Medium

Files needed:
- `lib/gsc_analytics/workflows/steps/llm_step.ex`
- `lib/gsc_analytics/workflows/steps/api_step.ex`
- `lib/gsc_analytics/workflows/steps/conditional_step.ex`
- `lib/gsc_analytics/workflows/steps/iteration_step.ex`
- `lib/gsc_analytics/workflows/steps/human_review_step.ex`
- `lib/gsc_analytics/workflows/steps/code_step.ex`

Requirements per Codex:
- Stateless implementations
- Inject dependencies (HTTP clients, LLM adapters)
- Use Oban for long-running work (not GenServer handle_call)
- Mock via protocol in `config/test.exs`

### Phase 5: MCP Integration

#### MCP Client Wrappers
**Priority**: 🚨 P1 Security Critical
**Files**:
- `lib/gsc_analytics/workflows/mcp/context7_client.ex`
- `lib/gsc_analytics/workflows/mcp/tidewave_client.ex`

Requirements per Codex:
- Treat all output as untrusted
- JSON schema validation
- Enforce timeouts
- Limit file writes
- Audit credentials via runtime config (not compile-time)

#### MCP-Enhanced Steps
**Priority**: 🟡 P2 Medium
**Files**:
- `lib/gsc_analytics/workflows/steps/mcp_llm_step.ex` (Context7 doc enrichment)
- `lib/gsc_analytics/workflows/steps/mcp_code_step.ex` (Tidewave execution)

### Phase 6: LiveView UI

#### Workflow Builder
**Priority**: 🟡 P2 Medium
**File**: `lib/gsc_analytics_web/live/workflow_builder_live.ex`

Requirements:
- Streaming assigns for performance
- Test IDs: `#workflow-execution-123`
- Wrap with `Layouts.app`
- Integrate with existing `GscAnalytics` contexts

#### Workflow Runner
**Priority**: 🟡 P2 Medium
**File**: `lib/gsc_analytics_web/live/workflow_runner_live.ex`

Features:
- Real-time progress via PubSub
- Event timeline from DB
- Pause/resume/cancel controls
- Load history on reconnect

#### Review Queue
**Priority**: 🟡 P2 Medium
**File**: `lib/gsc_analytics_web/live/review_queue_live.ex`

Requirements per Codex:
- Precompute `pending_count` per workflow
- Keyset pagination (not offset)
- Phoenix.Presence for active reviewers
- Optimistic locking on decisions

### Phase 7: Testing & Observability

#### Test Harness
**Priority**: 🔥 P1 Critical
**File**: `test/support/workflow_test_helpers.ex`

Per Codex review:
- Mock LLM/API steps via protocol
- Recorded fixtures
- Drive workflows through ExUnit

#### Telemetry Integration
**Priority**: 🟡 P2 Medium
**File**: `lib/gsc_analytics/workflows/telemetry.ex`

Requirements:
- Share metrics with existing GSC pipelines
- Integrate with `GscAnalytics` contexts (not new top-level namespace)

## Key Design Decisions

### 1. ETS vs Agent
**Decision**: Use ETS-backed state owned by supervisor
**Rationale**: Crash recovery, better performance, avoid single-process bottleneck

### 2. PubSub + DB Events
**Decision**: Pair broadcasts with persistent events
**Rationale**: Durability across node restarts, reconnect recovery

### 3. Template Compilation
**Decision**: Compile once, cache AST in ETS
**Rationale**: Avoid repeated parsing in hot paths

### 4. Expression Sandboxing
**Decision**: Whitelist-only, no `Code.eval_string`
**Rationale**: Security - prevent arbitrary code execution

### 5. DynamicSupervisor
**Decision**: One supervisor per execution
**Rationale**: Fault isolation, OTP crash-and-recover philosophy

## Next Steps

1. **Run migration**: `mix ecto.migrate`
2. **Implement Engine** with DynamicSupervisor
3. **Build ProgressTracker** with dual persistence
4. **Create Template Compiler** with caching
5. **Implement Sandboxed Evaluator**
6. **Build Step Protocol** with test mocks

## Integration with Existing Code

### Supervision Tree
Add to `lib/gsc_analytics/application.ex`:

```elixir
children = [
  # ... existing children ...
  {Registry, keys: :unique, name: GscAnalytics.Workflows.EngineRegistry},
  {DynamicSupervisor, strategy: :one_for_one, name: GscAnalytics.Workflows.EngineSupervisor},
  {GscAnalytics.Workflows.ProgressTracker, []},
]
```

### Telemetry
Hook into existing telemetry system:

```elixir
:telemetry.execute(
  [:gsc_analytics, :workflow, :step_completed],
  %{duration_ms: duration},
  %{workflow_id: id, step_id: step_id}
)
```

### Oban Integration
Create workflow execution worker:

```elixir
defmodule GscAnalytics.Workers.WorkflowExecutionWorker do
  use Oban.Worker, queue: :workflows, priority: 2

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"execution_id" => id}}) do
    GscAnalytics.Workflows.Engine.execute(id)
  end
end
```

## References

- **Design Document**: See Claude Code chat history for full architecture
- **Codex Review**: Comprehensive feedback incorporated throughout
- **AirOps Inspiration**: https://docs.airops.com/building-workflows/
- **Existing Patterns**: `GscAnalytics.DataSources.GSC.Core.Sync` pipeline architecture
