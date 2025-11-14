# Elixir/OTP Patterns for Concurrent Systems

## Overview

This directory contains comprehensive documentation on Elixir/OTP patterns for building robust, concurrent systems. These guides are specifically tailored for the GSC Analytics project but apply broadly to any Elixir application requiring high-performance concurrent processing.

## Contents

### [GenServer Coordination](./genserver-coordination.md)
**Topics Covered**:
- GenServer as dispatcher pattern
- Multi-instance pattern for scalability
- Backpressure and queue management
- ETS-backed state recovery
- Task supervision patterns
- Broadway for production pipelines
- Testing GenServer coordinators

**When to Read**: Implementing the Phase 4 QueryCoordinator, designing concurrent batch processing systems, or managing stateful workers.

**Key Patterns**:
- Coordinator GenServer + Task.async workers
- Queue limits with rejection for backpressure
- ETS for crash recovery
- GenStage for pull-based backpressure

---

### [Rate Limiting](./rate-limiting.md)
**Topics Covered**:
- Hammer library usage and patterns
- Token bucket vs leaky bucket algorithms
- Distributed rate limiting with ETS
- QPM budget management
- Exponential backoff strategies
- Circuit breaker pattern
- Smart retry logic

**When to Read**: Integrating with external APIs, implementing rate limiters for Phase 4, or managing API quota budgets.

**Key Patterns**:
- Sliding window rate limiting
- Full jitter exponential backoff
- Circuit breakers for cascading failure prevention
- Idempotency for safe retries

---

### [Telemetry](./telemetry.md)
**Topics Covered**:
- Event naming conventions
- Handler performance optimization
- The span pattern
- Instrumenting GenServers, Oban workers, and concurrent tasks
- Telemetry.Metrics definitions
- PromEx for production monitoring
- OpenTelemetry integration

**When to Read**: Adding observability to new features, optimizing telemetry performance, or setting up production monitoring.

**Key Patterns**:
- `:telemetry.span/3` for automatic instrumentation
- Telemetry.Metrics for LiveDashboard
- PromEx for Grafana dashboards
- Periodic measurements for business metrics

---

### [Concurrent Processing](./concurrent-processing.md)
**Topics Covered**:
- Task.async_stream patterns
- HTTP client best practices (:httpc, Finch, Req)
- Idempotency patterns
- Error handling and fault tolerance
- Supervision strategies
- Batch processing optimizations

**When to Read**: Building concurrent batch processors, handling external HTTP APIs, or optimizing parallel data processing.

**Key Patterns**:
- Task.async_stream with bounded concurrency
- DynamicSupervisor + Registry for worker management
- Exponential backoff with selective retry
- PostgreSQL batch size limits (65,535 parameters)

---

## Quick Navigation

### By Use Case

**Implementing Phase 4 Concurrent HTTP Batches**:
1. [GenServer Coordination](./genserver-coordination.md) - Coordinator architecture
2. [Rate Limiting](./rate-limiting.md) - QPM budget management
3. [Concurrent Processing](./concurrent-processing.md) - Task.async_stream patterns
4. [Telemetry](./telemetry.md) - Instrumentation and monitoring

**Adding Observability**:
1. [Telemetry](./telemetry.md) - Instrumentation guide
2. [GenServer Coordination](./genserver-coordination.md) - Mailbox monitoring
3. [Rate Limiting](./rate-limiting.md) - QPM tracking

**External API Integration**:
1. [Rate Limiting](./rate-limiting.md) - Rate limiters and retries
2. [Concurrent Processing](./concurrent-processing.md) - HTTP clients
3. [Telemetry](./telemetry.md) - API call instrumentation

**Optimizing Performance**:
1. [Concurrent Processing](./concurrent-processing.md) - Batch processing
2. [GenServer Coordination](./genserver-coordination.md) - Backpressure
3. [Telemetry](./telemetry.md) - Performance measurement

---

## Common Patterns Reference

### Concurrent Batch Processing

```elixir
# Basic pattern
items
|> Task.async_stream(
  fn item -> process(item) end,
  max_concurrency: 10,
  timeout: 30_000,
  on_timeout: :kill_task
)
|> Enum.to_list()
```

**Docs**: [Concurrent Processing](./concurrent-processing.md#taskasync_stream-pattern)

---

### Rate Limiting Before API Call

```elixir
case RateLimiter.check_rate(property_url, batch_size) do
  :ok ->
    HTTPClient.fetch(url)

  {:error, retry_ms} ->
    Logger.warn("Rate limited, retry after #{retry_ms}ms")
    Process.sleep(retry_ms)
end
```

**Docs**: [Rate Limiting](./rate-limiting.md#phase-4-rate-limiting-integration)

---

### Telemetry Span

```elixir
:telemetry.span(
  [:my_app, :operation],
  %{metadata: "value"},
  fn ->
    result = do_work()
    {result, %{rows: count}}
  end
)
```

**Docs**: [Telemetry](./telemetry.md#the-span-pattern)

---

### GenServer Coordinator

```elixir
defmodule Coordinator do
  use GenServer

  def take_batch(pid, worker_id) do
    GenServer.call(pid, {:take_batch, worker_id})
  end

  def handle_call({:take_batch, worker_id}, _from, state) do
    case :queue.out(state.batch_queue) do
      {{:value, batch}, new_queue} ->
        {:reply, {:ok, batch}, %{state | batch_queue: new_queue}}
      {:empty, _} ->
        {:reply, :no_batches, state}
    end
  end
end
```

**Docs**: [GenServer Coordination](./genserver-coordination.md#genserver-as-dispatcher-pattern)

---

### Exponential Backoff with Retry

```elixir
use Retry

retry with: exponential_backoff() |> randomize |> cap(60_000) do
  risky_operation()
after
  result -> {:ok, result}
rescue
  error -> {:error, error}
end
```

**Docs**: [Rate Limiting](./rate-limiting.md#backoff-strategies-and-retry-patterns)

---

## Integration with Sprint Planning

These patterns directly support the **Phase 4 implementation** documented in:
- `sprint-planning/speedup/README.md`
- `sprint-planning/speedup/PHASE4_IMPLEMENTATION_PLAN.md`
- `sprint-planning/speedup/TICKETS.md`

### Sprint Ticket Mapping

| Ticket | Relevant Documentation |
|--------|------------------------|
| **S01** - QueryCoordinator GenServer | [GenServer Coordination](./genserver-coordination.md) |
| **S02** - ConcurrentBatchWorker | [Concurrent Processing](./concurrent-processing.md) |
| **S03** - RateLimiter + Config | [Rate Limiting](./rate-limiting.md) |
| **S04** - QueryPaginator Refactor | [GenServer Coordination](./genserver-coordination.md), [Concurrent Processing](./concurrent-processing.md) |
| **S05** - Telemetry + Tests | [Telemetry](./telemetry.md) |
| **S06** - Validation + Rollout | All guides |

---

## Official Resources

### Elixir Core
- **Elixir Guides**: https://elixir-lang.org/getting-started/introduction.html
- **Mix & OTP Guide**: https://elixir-lang.org/getting-started/mix-otp/introduction-to-mix.html
- **Elixir School**: https://elixirschool.com/

### OTP Documentation
- **OTP Design Principles**: https://www.erlang.org/doc/design_principles/users_guide.html
- **GenServer**: https://hexdocs.pm/elixir/GenServer.html
- **Supervisor**: https://hexdocs.pm/elixir/Supervisor.html

### Libraries
- **Hammer (Rate Limiting)**: https://hexdocs.pm/hammer/readme.html
- **Telemetry**: https://hexdocs.pm/telemetry/telemetry.html
- **PromEx**: https://hexdocs.pm/prom_ex/readme.html
- **Oban**: https://hexdocs.pm/oban/Oban.html
- **Finch**: https://hexdocs.pm/finch/Finch.html

---

## Contributing to These Docs

When adding new patterns:

1. **Add code examples** from actual codebase when possible
2. **Link to official documentation** for deeper dives
3. **Include "When to Use" sections** for pattern selection
4. **Add testing examples** to demonstrate proper usage
5. **Cross-reference related patterns** in other docs

---

## Quick Tips

### Performance
- Use `Task.async_stream` for bounded concurrency
- Set timeouts on all async operations
- Use ETS for shared state (avoid GenServer bottlenecks)
- Add jitter to exponential backoff

### Reliability
- Implement backpressure (queue limits, mailbox monitoring)
- Make operations idempotent (Oban uniqueness, DB constraints)
- Use selective retry logic (don't retry 4xx errors)
- Monitor with telemetry + PromEx

### Testing
- Test concurrent scenarios with multiple processes
- Test timeout and failure cases
- Use telemetry test helpers for event verification
- Verify idempotency with duplicate operations

---

## Related Documentation

- **Project README**: `../README.md` - Project overview and setup
- **CLAUDE.md**: `../CLAUDE.md` - Project-specific guidelines for AI assistance
- **Workflow Builder Architecture**: `../workflow-builder-architecture.md` - React + LiveView patterns
- **Sprint Planning**: `../sprint-planning/speedup/` - Phase 4 implementation plan

---

## Feedback and Questions

These patterns are based on:
- Official Elixir/OTP documentation
- Production Elixir systems at scale
- Elixir community best practices
- Real patterns from the GSC Analytics codebase

For questions or suggestions, refer to the official documentation links or consult the Elixir Forum: https://elixirforum.com/
