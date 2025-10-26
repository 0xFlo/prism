# Ticket-001: Add Req HTTP Client Dependency

## Status: TODO
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
- [ ] Req dependency added to mix.exs
- [ ] Finch HTTP adapter added (Req's preferred adapter)
- [ ] Finch supervision tree configured in Application
- [ ] Req configured to use Finch as default adapter
- [ ] Dependencies compile without errors
- [ ] Basic Req.post/2 test working

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
{Finch, name: GscAnalytics.Finch}
```

### 3. Configure Req Default Options
```elixir
# In config/config.exs, add:
config :req, :default_options, [finch: GscAnalytics.Finch]
```

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