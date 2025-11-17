# Ticket-001: Add Req HTTP Client Dependency

## Status: DONE
**Priority:** P1 - BLOCKER
**Estimate:** 30 minutes
**Dependencies:** None
**Blocks:** All other OAuth tickets

## Problem Statement
The OAuth implementation requires HTTP calls to Google's OAuth2 endpoints. The codebase guidelines specify Req as the preferred HTTP client, but it's not currently installed. Without Req, we cannot:
- Exchange authorization codes for tokens
- Refresh expired access tokens
- Make OAuth API calls

## Acceptance Criteria
- [x] Req dependency added to mix.exs
- [x] Finch HTTP adapter added (Req's preferred adapter)
- [x] Finch supervision tree configured in Application
- [x] Req configured to use Finch as default adapter
- [x] Dependencies compile without errors
- [x] Basic Req.post/2 test working (verified via targeted OAuth refresh test)

## Implementation Plan

### 1. Update mix.exs
```elixir
# In deps function, add:
{:req, "~> 0.5"},
{:finch, "~> 0.20"}
```

### 2. Update Application Supervisor
```elixir
# In lib/gsc_analytics/application.ex, add before Endpoint:
{Finch,
  name: GscAnalytics.Finch,
  pools: %{
    default: [
      size: 70,                    # Connection pool size
      pool_max_idle_time: 60_000   # 60 seconds idle timeout
    ]
  }}
```

**Best Practice from Research:**
- Use larger pool sizes (70) for better throughput with OAuth token refresh
- Set idle timeout to prevent stale connections (60s recommended)
- HTTP/1 pools reuse connections efficiently within same pool
- Default pool starts on first request for unconfigured endpoints

### 3. Configure Req Default Options
```elixir
# In config/config.exs, add:
config :req, :default_options, [
  finch: GscAnalytics.Finch,
  pool_timeout: 5_000,      # Connection checkout timeout
  receive_timeout: 15_000   # Socket receive timeout
]

## Outcome
- Added `:req` and `:finch` dependencies plus default Req options and Finch supervision entry.
- Confirmed compilation succeeds and Req client works through the OAuth refresh unit test (`mix test test/gsc_analytics/auth_test.exs --trace`).
```

**Best Practice from Research:**
- Req is built on top of Finch for connection pooling
- pool_timeout (5s) prevents hanging on connection checkout
- receive_timeout (15s) prevents hanging on slow responses
- Finch provides HTTP/2 support and telemetry integration

### 4. Run Setup Commands
```bash
mix deps.get
mix deps.compile
```

### 5. Verify Installation
```elixir
# In iex -S mix:
Req.get!("https://api.github.com").status
# Should return 200
```

## Testing Checklist
- [ ] `mix deps.get` succeeds
- [ ] `mix compile` has no warnings
- [ ] `mix test` still passes
- [ ] Can make HTTP request in IEx with Req
- [ ] Finch process visible in Observer

## Rollback Plan
If Req causes issues:
1. Remove dependencies from mix.exs
2. Remove Finch from supervision tree
3. Remove Req config
4. Run `mix deps.clean req finch`

## Notes
- Req is the modern replacement for HTTPoison/Tesla in Elixir
- Finch provides connection pooling and HTTP/2 support
- This is a prerequisite for all OAuth functionality
- Existing :httpc calls in codebase should eventually migrate to Req

## Telemetry & Monitoring (Optional for Future)
Finch emits telemetry events for monitoring:
- `[:finch, :queue, :start]` - Connection checkout started
- `[:finch, :queue, :stop]` - Connection acquired
- `[:finch, :request, :start]` - Request started
- `[:finch, :request, :stop]` - Request completed

Consider adding telemetry handlers for circuit breaker patterns and performance monitoring.
