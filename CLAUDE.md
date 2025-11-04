# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Phoenix LiveView application that fetches, stores, and visualizes Google Search Console (GSC) analytics data. Built with Elixir/Phoenix 1.8, this app provides a dashboard for analyzing URL performance metrics including clicks, impressions, CTR, and search positions.

## Development Commands

### Setup & Development

```bash
# Initial setup (install deps, create DB, run migrations, build assets)
mix setup

# Start the Phoenix server
mix phx.server

# Start with interactive shell
iex -S mix phx.server

# Pre-commit validation (compile with warnings as errors, format, test)
mix precommit
```

### Database Operations

```bash
# Create and migrate database
mix ecto.create && mix ecto.migrate

# Reset database (drop, create, migrate, seed)
mix ecto.reset

# Run specific migration
mix ecto.migrate --step 1

# Run tests (creates test DB automatically)
mix test

# Debug specific test file
mix test test/path/to/test.exs

# Re-run only failed tests
mix test --failed
```

### Asset Management

```bash
# Install asset build tools
mix assets.setup

# Build assets for development
mix assets.build

# Build and minify for production
mix assets.deploy
```

### GSC Sync Operations

```elixir
# In IEx console (iex -S mix phx.server):

# Sync yesterday's data (accounting for GSC 3-day delay)
GscAnalytics.DataSources.GSC.Core.Sync.sync_yesterday()

# Sync specific date range
GscAnalytics.DataSources.GSC.Core.Sync.sync_date_range("sc-domain:example.com", ~D[2024-01-01], ~D[2024-01-31])

# Sync last N days (default: stops at 90 days)
GscAnalytics.DataSources.GSC.Core.Sync.sync_last_n_days("sc-domain:scrapfly.io", 30)

# Sync full history (with automatic empty threshold detection)
GscAnalytics.DataSources.GSC.Core.Sync.sync_full_history("sc-domain:scrapfly.io")

# List accessible GSC properties
GscAnalytics.DataSources.GSC.Core.Client.list_sites(1)
```

### URL Health Checking (HTTP Status)

```elixir
# In IEx console (iex -S mix phx.server):

# Check a single URL
GscAnalytics.Crawler.check_url("https://example.com")

# Check all stale URLs (unchecked or >7 days old)
GscAnalytics.Crawler.check_all(account_id: 1, filter: :stale)

# Check all broken links (4xx/5xx)
GscAnalytics.Crawler.check_all(account_id: 1, filter: :broken)

# Check all redirected URLs (3xx)
GscAnalytics.Crawler.check_all(account_id: 1, filter: :redirected)
```

**⚠️ Important Workflow Dependency:**
The HTTP status checker requires URLs to be synced from Google Search Console first. URLs are only available for HTTP checking when:
1. They have been synced via `Core.Sync` operations (above)
2. The `data_available` field is set to `true` (meaning GSC returned performance data)

**Recommended Workflow:**
1. **First**: Run a GSC sync to populate the database with URLs that have search traffic
2. **Then**: Run HTTP status checks to validate URL health
3. **Regularly**: Schedule both syncs and health checks to maintain data freshness

The crawler intentionally filters to URLs with `data_available == true` because it focuses on SEO-relevant URLs (those with actual search traffic). URLs without search traffic are not checked to optimize resource usage.

## Architecture Overview

### Module Organization (Post-Refactoring)

The GSC Analytics codebase uses a **data sources architecture** where all GSC-related modules live under `GscAnalytics.DataSources.GSC.*`:

- **Core** (`lib/gsc_analytics/data_sources/gsc/core/`) - Main business logic
- **Support** (`lib/gsc_analytics/data_sources/gsc/support/`) - Infrastructure services
- **Telemetry** (`lib/gsc_analytics/data_sources/gsc/telemetry/`) - Observability

### Core Components

**GSC Integration Layer** (`lib/gsc_analytics/data_sources/gsc/`)

Core modules:

- `Core.Client`: HTTP client for GSC Search Analytics API with retry logic and rate limiting
- `Core.Sync`: Thin orchestrator that delegates to the pipeline modules
  (`Core.Sync.State`, `Core.Sync.Pipeline`, `Core.Sync.URLPhase`,
  `Core.Sync.QueryPhase`, `Core.Sync.ProgressTracker`)
- `Core.Config`: Centralized configuration management
- `Core.Persistence`: Database operations and data storage

Support services:

- `Support.Authenticator`: GenServer managing JWT-based service account authentication with automatic token refresh
- `Support.RateLimiter`: Hammer-based rate limiter preventing API quota exhaustion
- `Support.SyncProgress`: GenServer tracking real-time sync job progress with PubSub broadcasts
- `Support.QueryPaginator`: Handles GSC API pagination for large result sets
- `Support.BatchProcessor`: Concurrent batch processing with configurable concurrency

Telemetry:

- `Telemetry.AuditLogger`: Structured JSON audit logging of API calls, sync operations, and auth events

**Data Schemas** (`lib/gsc_analytics/schemas/`)

- `Performance`: Aggregated URL performance metrics with caching
- `TimeSeries`: Daily time-series data for trend analysis (single source of truth)
- `UrlMetadata`: Editorial metadata (type, category, publish date)

**Analytics Layer** (`lib/gsc_analytics/analytics/`)

- `TimeSeriesAggregator`: On-the-fly aggregation of daily data into weekly/monthly views without data duplication

**Web Interface** (`lib/gsc_analytics_web/`)

- `DashboardLive`: Main LiveView dashboard with real-time filtering and sorting
- `DashboardController`: CSV export and sync triggers
- `Dashboard.HTMLHelpers`: Reusable UI helpers for metrics display

### Supervision Tree

The application supervisor (`lib/gsc_analytics/application.ex`) starts critical GenServers:

```elixir
children = [
  GscAnalyticsWeb.Telemetry,
  GscAnalytics.Repo,
  {Phoenix.PubSub, name: GscAnalytics.PubSub},

  # GSC Services (IMPORTANT: Use {Module, args} format for proper child specs)
  {GscAnalytics.DataSources.GSC.Support.Authenticator, name: GscAnalytics.DataSources.GSC.Support.Authenticator},
  {GscAnalytics.DataSources.GSC.Support.SyncProgress, []},

  GscAnalyticsWeb.Endpoint
]
```

**Critical Best Practice**: Always use `{Module, args}` tuple format for GenServers in supervision trees. Using bare module names (`Module` instead of `{Module, []}`) can cause silent startup failures if the module doesn't implement `child_spec/1`.

### Data Flow

1. **Authentication**: `Support.Authenticator` loads service account JSON, generates JWT, exchanges for OAuth2 token
2. **Sync Process**: `Core.Sync.sync_date_range/3` initializes `Core.Sync.State` and runs
   `Core.Sync.Pipeline.execute/1`, which coordinates:
   - `Core.Sync.URLPhase` for URL discovery and persistence (via `Core.Client`)
   - `Core.Sync.QueryPhase` for query pagination (via `Support.QueryPaginator`)
   - `Core.Sync.ProgressTracker` for real-time progress reporting
   - `Core.Persistence` for database storage inside the phases
3. **Storage**: Raw data stored in `TimeSeries`, aggregated into `Performance` table via `Core.Persistence`
4. **Dashboard**: LiveView queries `Performance` with Ecto, subscribes to `SyncProgress` PubSub for real-time updates

### Key Design Patterns

**Single Source of Truth Architecture**

- All metrics stored only in `TimeSeries` table (daily granularity)
- Weekly/monthly views calculated on-the-fly via `TimeSeriesAggregator`
- No pre-computed aggregations = no data duplication = simpler sync logic
- WoW (week-over-week) growth calculated dynamically from daily data
- URL detail page supports daily/weekly view toggle without storing duplicate data

**Service Account Authentication**

- Credentials loaded from `priv/production-284316-43f352dd1cda.json`
- JWT signed with RS256 algorithm using `joken` library
- Token auto-refreshes 10 minutes before expiry
- Supports multi-tenancy via `account_id` parameter (currently single-tenant)

**Rate Limiting Strategy**

- Uses Hammer ETS backend for in-memory rate tracking
- Per-site URL rate limiting prevents quota exhaustion
- Exponential backoff on 429 responses (1s → 2s → 4s)
- Max 3 retries before failure

**Data Caching**

- `Performance` records cache for 24 hours when data available
- 1-hour cache for no-data responses (data may become available)
- `cache_expires_at` field tracks expiry
- Query helpers: `cached/1`, `needs_refresh/1`

**Batch Processing**

- `fetch_batch_performance/4` uses `Task.async_stream` for concurrent fetching
- Default 10 concurrent requests, configurable via `:max_concurrency`
- Automatic timeout handling (30s default)
- Error isolation per URL

**Audit Logging with Telemetry**

- Telemetry-based event system tracks all GSC API interactions
- `AuditLogger` writes structured JSON logs to `logs/gsc_audit.log`
- Events tracked:
  - `[:gsc_analytics, :api, :request]` - Every GSC API call with duration, rows, rate limiting
  - `[:gsc_analytics, :sync, :complete]` - Sync operation summaries (date range, total calls, URLs)
  - `[:gsc_analytics, :auth, :token_refresh]` - Authentication events (token refresh success/failure)
- Handlers attached automatically on application startup
- Zero overhead when handlers not attached (production-ready)

### Analyzing Audit Logs

The audit log uses line-delimited JSON format, perfect for Unix tools:

```bash
# Watch live API activity
tail -f logs/gsc_audit.log

# Count total API calls
grep "api.request" logs/gsc_audit.log | wc -l

# Find rate-limited requests
grep '"rate_limited":true' logs/gsc_audit.log

# Show last sync summary
grep "sync.complete" logs/gsc_audit.log | tail -1 | jq

# Calculate average API response time
cat logs/gsc_audit.log | jq -s 'map(select(.event=="api.request")) | map(.measurements.duration_ms) | add/length'

# Total URLs fetched today
grep "$(date +%Y-%m-%d)" logs/gsc_audit.log | jq -s 'map(select(.event=="api.request")) | map(.measurements.rows) | add'

# Check authentication health
grep "auth.token_refresh" logs/gsc_audit.log | tail -5 | jq
```

Example log entries:

```json
{"ts":"2025-10-04T15:30:12Z","event":"api.request","measurements":{"duration_ms":1247,"rows":412},"metadata":{"operation":"fetch_all_urls","site_url":"sc-domain:scrapfly.io","date":"2025-10-03","rate_limited":false}}
{"ts":"2025-10-04T15:32:45Z","event":"sync.complete","measurements":{"total_api_calls":30,"total_urls":12470,"duration_ms":145230},"metadata":{"site_url":"sc-domain:scrapfly.io","start_date":"2025-09-05","end_date":"2025-10-04"}}
```

## Configuration

### GSC Service Account Setup

1. Place service account JSON in `priv/production-284316-43f352dd1cda.json`
2. Update `config/config.exs`:

   ```elixir
   config :gsc_analytics, GscAnalytics.GSC,
     service_account_file: Path.expand("../priv/your-file.json", __DIR__)

   config :gsc_analytics,
     gsc_default_property: "sc-domain:yoursite.com"
   ```

3. Ensure service account has read access to GSC property

### Database Configuration

- PostgreSQL required (configured in `config/dev.exs`, `config/test.exs`, `config/runtime.exs`)
- Uses UUIDs for primary keys (`:binary_id`)
- Timestamps in UTC with microsecond precision

## Important Elixir/Phoenix Patterns

**HTTPc Usage (Not Req)**
This project uses Erlang's `:httpc` for HTTP requests instead of `Req` library:

```elixir
# Used in Client.search_analytics_query/4 and Authenticator.request_access_token/1
request = {url_charlist, headers_charlist, content_type_charlist, body}
:httpc.request(:post, request, [{:timeout, 30_000}], [])
```

**LiveView URL State Management**

- All dashboard state stored in URL query params (view_mode, sort_by, limit, needs_update)
- Use `push_patch/2` to update URL without full page reload
- `handle_params/3` reads URL params and assigns to socket

**Ecto Query Composition**
Performance schema provides composable query functions:

```elixir
Performance
|> Performance.for_account(1)
|> Performance.cached()
|> Performance.top_performing(10)
|> Repo.all()
```

**GenServer Continuation Pattern**
`Authenticator` uses `{:continue, :action}` for async initialization:

```elixir
def init(_opts) do
  {:ok, state, {:continue, :load_credentials}}
end

def handle_continue(:load_credentials, state) do
  # Load and then continue to fetch_token
  {:noreply, state, {:continue, :fetch_token}}
end
```

## Testing Guidelines

### Basic Testing Practices

- Tests use `DataCase` for database tests, `ConnCase` for controller tests
- `LazyHTML` available for parsing HTML in LiveView tests
- Use `Phoenix.LiveViewTest` functions: `render/1`, `element/2`, `has_element?/2`
- Test against DOM IDs not text content (text changes frequently)
- Database automatically created/migrated via `mix test` alias

### Performance Testing

The project includes an opt-in performance test suite that validates query efficiency and response times without affecting normal test runs.

**Running Performance Tests**

```bash
# Run ONLY performance tests (excludes all regular tests)
mix test --only performance

# Regular test runs exclude performance tests by default
mix test  # Performance tests are skipped
```

**Performance Test Features**

- Tests are gated with `@moduletag :performance` for isolation
- Validates query budgets (no N+1 queries)
- Uses manageable datasets (250 URLs, 14 days of data)
- Chunked database inserts to avoid PostgreSQL parameter limits
- Measures response times and throughput
- Located in: `test/gsc_analytics_web/live/dashboard_performance_test.exs`

**Performance Benchmarks**

The test suite includes various benchmarks that report metrics like:
- URL processing throughput (URLs/second)
- Query efficiency (URLs per query)
- Memory usage per URL
- Scaling factors for increasing data sizes

### Performance Testing Best Practices

**PostgreSQL Parameter Limits**

When bulk inserting test data, PostgreSQL has a hard limit of **65,535 parameters** per query. With `Repo.insert_all/2`:

```elixir
# ❌ BAD: 5000 records × 14 fields = 70,000 params (exceeds limit)
Repo.insert_all(Performance, generate_records(5000))

# ✅ GOOD: Batch into chunks of 4000 records max
generate_records(5000)
|> Enum.chunk_every(4000)
|> Enum.each(&Repo.insert_all(Performance, &1))
```

**Safe batch size calculation**: `(65,535 / field_count) * 0.9` to leave margin for overhead.

### LiveView Testing with GenServers

When testing LiveViews that depend on GenServers (like `SyncProgress`):

```elixir
# The GenServer should be started by the supervision tree in test mode
# ConnCase automatically sets up the test environment
test "dashboard sync loads", %{conn: conn} do
  {:ok, view, html} = live(conn, ~p"/dashboard/sync")
  assert html =~ "Sync Status"
end
```

**Note**: If you get "no process" errors for GenServers in tests, verify:

1. GenServer is listed in `application.ex` supervision tree with proper `{Module, args}` format
2. Test environment doesn't override the supervision tree
3. GenServer `start_link/1` accepts the args passed by supervisor

## Common Issues

**Token Refresh Failures**

- Check service account JSON format and private key validity
- Verify system time is synchronized (JWT `iat`/`exp` validation)
- Check network connectivity to `https://oauth2.googleapis.com/token`
- Review auth events: `grep "auth.token_refresh" logs/gsc_audit.log | tail -10 | jq`

**GSC API 403 Errors**

- Service account must be added to GSC property as user
- Domain property format: `sc-domain:example.com`
- URL property format: `https://example.com/`

**Rate Limiting Triggers**

- GSC API has undocumented rate limits per property
- Reduce `:max_concurrency` in `fetch_batch_performance/4`
- Increase delays in `RateLimiter` configuration
- Check rate limiting patterns: `grep '"rate_limited":true' logs/gsc_audit.log | jq`

**Diagnosing Sync Issues**

- Check audit log for failed API calls: `grep '"error"' logs/gsc_audit.log | tail -5 | jq`
- Review sync completion metrics: `grep "sync.complete" logs/gsc_audit.log | tail -1 | jq .measurements`
- Monitor API response times: `cat logs/gsc_audit.log | jq -s 'map(select(.event=="api.request")) | map(.measurements.duration_ms) | add/length'`

## Phoenix LiveView Best Practices (v1.1+)

This project follows Phoenix LiveView 1.1+ best practices for optimal performance and maintainability:

### 1. Change Tracking with :key Attributes

**Always use `:key` attributes in `:for` comprehensions** for optimal DOM diffing:

```heex
<!-- ✅ Good: Explicit key for efficient change tracking -->
<tr :for={url <- @urls} :key={url.url}>

<!-- ❌ Bad: No key - falls back to index-based tracking -->
<tr :for={url <- @urls}>
```

**Why**: LiveView 1.1's improved change tracking uses keys to minimize DOM updates. Without explicit keys, it falls back to index-based tracking which can cause unnecessary re-renders.

### 2. Function Components with Type Safety

**Extract reusable UI into function components** with proper `attr` declarations:

```elixir
# lib/gsc_analytics_web/components/dashboard_components.ex
defmodule GscAnalyticsWeb.Components.DashboardComponents do
  use Phoenix.Component

  attr :urls, :list, required: true
  attr :view_mode, :string, default: "basic"

  def url_table(assigns) do
    ~H"""
    <table>
      <tr :for={url <- @urls} :key={url.url}>
        ...
      </tr>
    </table>
    """
  end
end
```

**Benefits**:

- Type safety through `attr` validation
- Reusable across LiveViews
- Testable in isolation
- Self-documenting API

### 3. Safe Assign Defaults

**Use `assign_new/3` in mount/3** to prevent runtime errors:

```elixir
def mount(_params, _session, socket) do
  {:ok,
   socket
   |> assign_new(:urls, fn -> [] end)
   |> assign_new(:stats, fn -> %{} end)}
end
```

**Why**: Prevents "key not found" errors if template references assigns before `handle_params/3` runs.

### 4. URL State Management

**All UI state should live in URL params** for bookmarkable, shareable views:

```elixir
# Read state from URL in handle_params/3
def handle_params(params, _uri, socket) do
  sort_by = params["sort_by"] || "clicks"
  {:noreply, assign(socket, :sort_by, sort_by)}
end

# Update URL with push_patch/2
def handle_event("sort", %{"column" => col}, socket) do
  params = %{sort_by: col, ...}
  {:noreply, push_patch(socket, to: ~p"/dashboard?#{params}")}
end
```

### 5. PubSub Subscriptions

**Subscribe only on connected sockets** to avoid double subscriptions:

```elixir
def mount(_params, _session, socket) do
  # ✅ Good: Only subscribe after WebSocket connection
  if connected?(socket), do: SyncProgress.subscribe()

  {:ok, socket}
end
```

### 6. Performance: Streams for Large Lists

**For 500+ items, use `stream/3`** instead of assigns:

```elixir
def mount(_params, _session, socket) do
  {:ok, stream(socket, :urls, [])}
end

def handle_params(params, _uri, socket) do
  urls = ContentInsights.list_urls(params)
  {:noreply, stream(socket, :urls, urls, reset: true)}
end
```

Template:

```heex
<tbody id="urls" phx-update="stream">
  <tr :for={{dom_id, url} <- @streams.urls} :key={dom_id}>
```

**Current project status**: Using standard assigns (works well for <500 URLs). Consider streams if dataset grows.

## Project Guidelines

**Development Server Protocol**
❌ NEVER automatically kill Phoenix servers running on port 4000
❌ NEVER run `lsof -ti:4000 | xargs kill` without explicit user request
✅ If you encounter "port 4000 already in use" errors, assume the user has the server running in their own terminal
✅ Simply inform the user the server is already running and skip server startup
✅ Only start servers if explicitly requested for testing

**Pre-commit Process**
Always run `mix precommit` before committing. This alias:

1. Compiles with `--warning-as-errors` flag
2. Unlocks unused dependencies
3. Runs code formatter
4. Executes full test suite

**HTTP Client Choice**
Use `:httpc` (Erlang's built-in HTTP client) for all external requests. The project does NOT use Req, Tesla, or HTTPoison.

**Phoenix v1.8 Specifics**

- No `Phoenix.View` module (removed in v1.8)
- Use `to_form/2` for forms, never `form_for`
- HEEx templates use `{...}` for attribute interpolation, `<%= ... %>` for block constructs
- Router `scope` blocks provide automatic aliasing

For detailed Elixir/Phoenix guidelines, see `AGENTS.md` which contains comprehensive language-specific rules.

✅ ALWAYS use built-in JSON module (Elixir v1.18+)
❌ NEVER use Jason
❌ NEVER alias Jason as JSON

Jason is only a transitive dependency (Phoenix brings it in). Since we have native JSON support, we should
use it exclusively.

---

## Priorities Syntax

Please use the following Priority Orders:

1. 🔥 P1 Critical
2. 🟡 P2 Medium
3. Deprioritized

- 🚨 alerts
- ⚠️ warning
- ✅ done

---
