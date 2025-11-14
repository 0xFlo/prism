# Concurrent Processing Patterns in Elixir

## Overview

Practical patterns for concurrent batch processing, HTTP clients, error handling, and fault tolerance in Elixir/OTP applications, with examples from the GSC Analytics codebase.

## Official Documentation

- **Task Module**: https://hexdocs.pm/elixir/Task.html
- **Task.async_stream**: https://hexdocs.pm/elixir/Task.html#async_stream/3
- **Task.Supervisor**: https://hexdocs.pm/elixir/Task.Supervisor.html
- **DynamicSupervisor**: https://hexdocs.pm/elixir/DynamicSupervisor.html
- **Supervisor**: https://hexdocs.pm/elixir/Supervisor.html

---

## Task.async_stream Pattern

### Basic Usage

**Location**: `lib/gsc_analytics/crawler/batch_processor.ex:70-86`

```elixir
urls
|> Task.async_stream(
  fn url ->
    # Optional rate limiting delay
    if delay_ms > 0, do: Process.sleep(delay_ms)

    # Execute work
    result = HttpStatus.check_url(url, timeout: timeout)

    # Track progress (optional)
    if track_progress?, do: update_progress(result)

    {url, result}
  end,
  max_concurrency: concurrency,
  timeout: timeout + delay_ms + 1_000,
  on_timeout: :kill_task
)
|> Enum.to_list()
```

### Key Options

**`:max_concurrency`** - Number of concurrent tasks
```elixir
max_concurrency: System.schedulers_online()  # CPU-bound work
max_concurrency: 10                           # I/O-bound work (configurable)
```

**`:ordered`** - Whether results match input order
```elixir
ordered: false  # ✅ Better performance, order doesn't matter
ordered: true   # ❌ Slower, waits for previous tasks
```

**`:timeout`** - Per-task timeout
```elixir
timeout: 30_000  # 30 seconds per task
```

**`:on_timeout`** - Timeout strategy
```elixir
on_timeout: :kill_task    # ✅ Terminate hung tasks
on_timeout: :exit         # ❌ Crash entire stream
```

### Timeout Buffer Calculation

**Pattern**: Account for delays + processing time + safety margin

```elixir
# If polite delay is 100ms and work takes 30s:
timeout: timeout + delay_ms + 1_000  # 30000 + 100 + 1000 = 31100ms
```

**Why**: Prevents premature timeout due to rate limiting delays.

---

## Task.Supervisor Patterns

### Starting Under Supervision

```elixir
# application.ex
children = [
  {Task.Supervisor, name: GscAnalytics.TaskSupervisor}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

### Using Task.Supervisor.async_stream

**For fault-tolerant concurrent processing**:

```elixir
Task.Supervisor.async_stream(
  GscAnalytics.TaskSupervisor,
  items,
  fn item -> work(item) end,
  max_concurrency: 10
)
```

**Use `async_stream_nolink` if not trapping exits**:

```elixir
Task.Supervisor.async_stream_nolink(
  GscAnalytics.TaskSupervisor,
  items,
  fn item -> work(item) end
)
```

**Benefits**:
- Tasks supervised independently
- Failures don't crash parent
- Automatic cleanup on completion

---

## HTTP Client Patterns

### Pattern A: Erlang :httpc (Legacy)

**Location**: `lib/gsc_analytics/data_sources/gsc/support/batch_processor.ex:167-186`

```elixir
request = {
  String.to_charlist("#{base_url}/#{api_version}"),
  Enum.map(headers, fn {k, v} ->
    {String.to_charlist(k), String.to_charlist(v)}
  end),
  String.to_charlist("multipart/mixed; boundary=#{boundary}"),
  body
}

case :httpc.request(:post, request, [{:timeout, timeout}], []) do
  {:ok, {{_, 200, _}, resp_headers, resp_body}} ->
    {:ok, resp_headers, resp_body}

  {:ok, {{_, 401, _}, _, _}} ->
    {:error, :unauthorized}

  {:ok, {{_, status, _}, _, resp_body}} ->
    {:error, {:http_error, status, to_string(resp_body)}}

  {:error, reason} ->
    {:error, {:batch_request_failed, reason}}
end
```

**Considerations**:
- Requires charlist conversion
- Pattern matching for status codes
- Manual error handling
- No connection pooling

---

### Pattern B: Finch (Modern)

**Location**: `lib/gsc_analytics/application.ex:28-35`

```elixir
{Finch,
 name: GscAnalytics.Finch,
 pools: %{
   default: [
     size: 70,
     pool_max_idle_time: 60_000
   ]
 }}
```

**Usage**:

```elixir
Finch.build(:get, "https://api.example.com/data")
|> Finch.request(GscAnalytics.Finch)
```

**Benefits**:
- Connection pooling (70 concurrent)
- Idle connection management
- Better performance for high concurrency
- Modern Elixir API

---

### Pattern C: Req (High-Level)

**Not currently used in project, but recommended for new code**:

```elixir
# mix.exs
{:req, "~> 0.4"}

# Usage
Req.new(
  base_url: "https://api.example.com",
  retry: :transient,
  retry_delay: &exp_backoff/1,
  max_retries: 3
)
|> Req.get!(url: "/endpoint")
```

**Benefits**:
- Built-in retry with exponential backoff
- Automatic decompression
- Telemetry integration
- Simplified API

---

## Idempotency Patterns

### Oban Uniqueness Constraints

**Location**: `lib/gsc_analytics/workers/http_status_check_worker.ex:83-89`

```elixir
use Oban.Worker,
  queue: :http_checks,
  priority: 2,
  max_attempts: 3,
  unique: [
    period: 600,  # 10 minutes
    states: [:available, :scheduled, :executing],
    keys: [:urls]  # Deduplicate by URL list
  ]
```

**Benefits**:
- Prevents duplicate concurrent jobs
- Configurable uniqueness window
- Multiple deduplication strategies

### Database-Level Idempotency

**Pattern**: Unique constraints + ON CONFLICT

```elixir
Repo.insert_all(
  TimeSeries,
  records,
  on_conflict: {:replace, [:clicks, :impressions, :ctr, :position]},
  conflict_target: [:account_id, :property_url, :url, :date]
)
```

**Benefits**:
- Safe retries
- Prevents duplicates at DB level
- Atomic upserts

---

## Error Handling and Fault Tolerance

### Exponential Backoff Pattern

**Location**: `lib/gsc_analytics/data_sources/gsc/support/retry_helper.ex`

```elixir
def with_retry(operation, opts \\ []) do
  max_retries = Keyword.get(opts, :max_retries, 3)
  retry_on = Keyword.get(opts, :retry_on, fn _ -> true end)
  on_retry = Keyword.get(opts, :on_retry, fn _, _ -> :ok end)

  do_retry(operation, retry_on, on_retry, 0, max_retries, opts)
end

defp do_retry(operation, retry_on, on_retry, attempt, max_attempts, opts) do
  case operation.() do
    {:ok, result} ->
      {:ok, result}

    error ->
      if retry_on.(error) and attempt < max_attempts do
        delay = calculate_backoff(attempt, opts[:base_delay] || 1000)
        on_retry.(error, attempt)
        Process.sleep(delay)
        do_retry(operation, retry_on, on_retry, attempt + 1, max_attempts, opts)
      else
        error
      end
  end
end

def calculate_backoff(attempt, base_delay) when is_integer(base_delay) do
  (base_delay * :math.pow(2, attempt)) |> round()
end
```

**Usage**:

```elixir
RetryHelper.with_retry(
  fn -> GSCClient.fetch_data(url) end,
  max_retries: 3,
  base_delay: 1000,
  retry_on: &retryable_error?/1,
  on_retry: fn error, attempt ->
    Logger.warn("Retry #{attempt} after error: #{inspect(error)}")
  end
)
```

---

### Selective Retry Logic

**Location**: `lib/gsc_analytics/data_sources/gsc/support/batch_processor.ex:142-151`

```elixir
defp retryable_error?({:error, :token_refresh_needed}), do: false
defp retryable_error?({:error, :unauthorized}), do: false
defp retryable_error?({:error, {:rate_limited, _}}), do: true
defp retryable_error?({:error, {:server_error, _, _}}), do: true
defp retryable_error?({:error, :timeout}), do: true
defp retryable_error?({:error, :econnrefused}), do: true
defp retryable_error?({:error, :nxdomain}), do: true
defp retryable_error?({:error, _}), do: false
defp retryable_error?(_), do: false
```

**Best Practice**: Don't retry:
- 4xx client errors (except 429 rate limits)
- Authentication failures
- Permanent errors

**Do retry**:
- 5xx server errors
- Network failures (timeout, connection refused)
- Rate limits (with backoff)

---

## Supervision Strategies

### Conditional Child Specs

**Location**: `lib/gsc_analytics/application.ex:10-18`

```elixir
authenticator_children =
  if Application.get_env(:gsc_analytics, :start_authenticator, true) do
    [{GscAnalytics.DataSources.GSC.Support.Authenticator,
      name: GscAnalytics.DataSources.GSC.Support.Authenticator}]
  else
    []
  end
```

**Use Case**: Disable services in test environment

---

### DynamicSupervisor + Registry Pattern

**Location**: `lib/gsc_analytics/application.ex:42-44`

```elixir
{Registry, keys: :unique, name: GscAnalytics.Workflows.EngineRegistry},
{DynamicSupervisor,
  strategy: :one_for_one,
  name: GscAnalytics.Workflows.EngineSupervisor}
```

**Usage**:

```elixir
# Start child dynamically
DynamicSupervisor.start_child(
  GscAnalytics.Workflows.EngineSupervisor,
  {WorkflowEngine, execution_id: id}
)

# Look up via Registry
case Registry.lookup(GscAnalytics.Workflows.EngineRegistry, id) do
  [{pid, _}] -> pid
  [] -> nil
end
```

**Benefits**:
- Start/stop workers dynamically
- Named process lookup
- Automatic cleanup on crash

---

### Proper Child Spec Format

**❌ Bad** (silent failures):
```elixir
children = [
  Authenticator  # If module doesn't define child_spec/1, silently fails
]
```

**✅ Good** (explicit):
```elixir
children = [
  {Authenticator, name: Authenticator}  # Always works
]
```

**Best Practice**: Always use `{Module, args}` tuple format.

---

## Smart Re-check Strategy

**Location**: `lib/gsc_analytics/workers/http_status_check_worker.ex:327-363`

```elixir
def filter_urls_needing_check(urls, opts) do
  now = DateTime.utc_now()
  seven_days_ago = DateTime.add(now, -7, :day)
  three_days_ago = DateTime.add(now, -3, :day)

  Enum.filter(urls, fn url ->
    cond do
      # Never checked
      is_nil(url.http_status) ->
        true

      # Stale (>7 days)
      url.http_checked_at < seven_days_ago ->
        true

      # Broken link (<7 days but check more frequently)
      url.http_status >= 400 and url.http_checked_at < three_days_ago ->
        true

      # Healthy, recently checked
      true ->
        false
    end
  end)
end
```

**Benefits**:
- Focus resources on critical URLs
- Reduce unnecessary checks
- Adaptive re-check intervals

---

## Backpressure via Job Scheduling

**Location**: `lib/gsc_analytics/workers/http_status_check_worker.ex:20-32`

```elixir
def schedule_in_seconds(url_count) do
  cond do
    url_count < 500 -> 60              # 1 minute
    url_count < 2000 -> 5 * 60         # 5 minutes
    url_count < 5000 -> 15 * 60        # 15 minutes
    true -> 30 * 60                    # 30 minutes
  end
end

def priority_for_count(url_count) do
  cond do
    url_count < 500 -> 1   # High priority
    url_count < 5000 -> 2  # Medium priority
    true -> 3              # Low priority
  end
end
```

**Benefits**:
- Prevents queue overload during large syncs
- Spreads work over time
- Priority-based processing

---

## Batch Processing Best Practices

### PostgreSQL Parameter Limits

**Problem**: PostgreSQL has a 65,535 parameter limit per query

```elixir
# ❌ BAD: 5000 records × 14 fields = 70,000 params (exceeds limit)
Repo.insert_all(Performance, generate_records(5000))

# ✅ GOOD: Batch into chunks
generate_records(5000)
|> Enum.chunk_every(4000)
|> Enum.each(&Repo.insert_all(Performance, &1))
```

**Formula**: `(65,535 / field_count) * 0.9` for safe batch size

---

### Concurrent Inserts with Idempotency

```elixir
records
|> Enum.chunk_every(1000)
|> Task.async_stream(
  fn chunk ->
    Repo.insert_all(
      TimeSeries,
      chunk,
      on_conflict: :replace_all,
      conflict_target: [:account_id, :property_url, :url, :date]
    )
  end,
  max_concurrency: 5
)
|> Enum.to_list()
```

**Benefits**:
- Parallel writes
- Safe retries
- Controlled concurrency

---

## Polite Rate Limiting

**Pattern**: Add delays between requests to external APIs

```elixir
urls
|> Task.async_stream(
  fn url ->
    # Rate limiting delay
    Process.sleep(100)  # 100ms between requests

    fetch_url(url)
  end,
  max_concurrency: 10
)
```

**Calculation**:

```
requests_per_second = max_concurrency / (delay_seconds + avg_request_time)

# Example: 10 concurrent, 0.1s delay, 0.5s request time
RPS = 10 / (0.1 + 0.5) = 16.7 requests/second
```

---

## Testing Concurrent Code

### Testing Task.async_stream

```elixir
test "processes items concurrently" do
  items = 1..100

  results =
    items
    |> Task.async_stream(
      fn item -> item * 2 end,
      max_concurrency: 10
    )
    |> Enum.to_list()

  # All results present
  assert length(results) == 100

  # All successful
  assert Enum.all?(results, &match?({:ok, _}, &1))
end
```

### Testing Timeouts

```elixir
test "kills tasks on timeout" do
  results =
    [1, 2, 3]
    |> Task.async_stream(
      fn item ->
        if item == 2, do: Process.sleep(10_000)
        item * 2
      end,
      timeout: 100,
      on_timeout: :kill_task
    )
    |> Enum.to_list()

  # Two successes, one timeout
  assert length(results) == 3
  assert Enum.count(results, &match?({:ok, _}, &1)) == 2
  assert Enum.count(results, &match?({:exit, :timeout}, &1)) == 1
end
```

---

## Key Takeaways

1. **Task.async_stream for bounded concurrency** - Prevents resource exhaustion
2. **Always set timeouts** - Prevent hung processes
3. **Use Task.Supervisor for fault tolerance** - Isolate failures
4. **Finch for HTTP pooling** - Better performance than :httpc
5. **Exponential backoff with jitter** - Prevents thundering herd
6. **Selective retry logic** - Don't retry 4xx errors
7. **Idempotency at multiple levels** - Oban + database constraints
8. **Chunk large batches** - Respect PostgreSQL limits
9. **Polite rate limiting** - Add delays for external APIs
10. **DynamicSupervisor + Registry** - Dynamic worker management

---

## Resources

### Official Documentation
- **Task**: https://hexdocs.pm/elixir/Task.html
- **Task.Supervisor**: https://hexdocs.pm/elixir/Task.Supervisor.html
- **DynamicSupervisor**: https://hexdocs.pm/elixir/DynamicSupervisor.html
- **Finch**: https://hexdocs.pm/finch/Finch.html
- **Req**: https://hexdocs.pm/req/Req.html

### Community Resources
- **Elixir Patterns**: https://elixirpatterns.dev/
- **Concurrent Data Processing**: https://pragprog.com/titles/sgdpelixir/
- **OTP Design Principles**: https://www.erlang.org/doc/design_principles/users_guide.html
