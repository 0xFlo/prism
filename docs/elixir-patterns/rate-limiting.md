# Rate Limiting Patterns in Elixir

## Overview

Comprehensive guide to implementing rate limiting in Elixir applications, with specific focus on external API integration and QPM (queries per minute) budget management for the GSC Analytics project.

## Official Documentation

- **Hammer Library**: https://hexdocs.pm/hammer/readme.html
- **Hammer Tutorial**: https://hexdocs.pm/hammer/tutorial.html
- **Hammer Distributed ETS**: https://hexdocs.pm/hammer/distributed-ets.html
- **Retry Library**: https://hexdocs.pm/retry/Retry.html
- **GenRetry**: https://hexdocs.pm/gen_retry/GenRetry.html

---

## Hammer Library Usage

### Core Concepts

Hammer uses a **fixed window counter** that divides time into fixed-size windows and counts requests per window.

**Parameters**:
- **Limit**: Maximum number of actions permitted
- **Scale**: Time window in milliseconds
- **Key**: Unique identifier (e.g., `"api:#{property_url}"`)

### Basic Implementation

```elixir
defmodule MyApp.RateLimit do
  use Hammer, backend: :ets
end

# Start service
MyApp.RateLimit.start_link(clean_period: :timer.minutes(1))

# Check rate limit
case MyApp.RateLimit.hit(key, scale_ms, limit) do
  {:allow, current_count} ->
    # Proceed with request
    Logger.debug("Rate limit OK: #{current_count}/#{limit}")
    :ok

  {:deny, ms_until_next_window} ->
    # Reject with 429
    Logger.warn("Rate limited, retry after #{ms_until_next_window}ms")
    {:error, :rate_limited, ms_until_next_window}
end
```

### Best Practices

**1. Key Structure**

Combine action name with identifier for granular control:

```elixir
# Per-user API limits
key = "api_request:#{user_id}"

# Per-property GSC limits
key = "gsc_api:#{property_url}"

# Per-IP limits
key = "login_attempt:#{ip_address}"
```

**2. Backend Selection**

```elixir
# ETS backend (single-node, fast)
use Hammer, backend: :ets

# Redis backend (distributed, persistent)
use Hammer,
  backend: :redis,
  redis_url: "redis://localhost:6379/2"
```

**When to use each**:
- **ETS**: Single-node applications, in-memory state acceptable
- **Redis**: Multi-node clusters, need persistence across restarts

**3. Custom Increments for Weighted Costs**

```elixir
# Bulk operations count as multiple hits
batch_size = 50
case Hammer.hit(key, 60_000, 600, batch_size) do
  {:allow, _count} -> :ok
  {:deny, retry_ms} -> {:error, :rate_limited, retry_ms}
end
```

---

## Token Bucket vs Leaky Bucket Algorithms

### Algorithm Comparison

| Feature | Token Bucket | Leaky Bucket |
|---------|-------------|--------------|
| **Traffic Pattern** | Allows bursts | Smooths to steady stream |
| **Request Processing** | Immediate if tokens available | Fixed rate regardless of input |
| **Use Case** | APIs with variable traffic | Guaranteed uniform output |
| **Latency** | Low (milliseconds) | Consistent (~1s for 60/min) |
| **Implementation** | Timer-based token refill | Queue + periodic processing |

### Token Bucket Implementation

**Characteristics**:
- Tokens refresh at fixed intervals
- Requests consume tokens immediately
- Queue requests when tokens depleted
- Cannot exceed maximum token count

```elixir
defmodule TokenBucket do
  use GenServer

  def init(opts) do
    state = %{
      available_tokens: opts[:requests_per_timeframe],
      max_tokens: opts[:requests_per_timeframe],
      token_refresh_rate: opts[:token_refresh_rate],
      request_queue: :queue.new()
    }

    # Schedule token refill
    Process.send_after(self(), :refill_tokens, state.token_refresh_rate)

    {:ok, state}
  end

  def handle_call(:request, from, state) do
    if state.available_tokens > 0 do
      # Process immediately
      new_state = %{state | available_tokens: state.available_tokens - 1}
      {:reply, :ok, new_state}
    else
      # Queue request
      new_queue = :queue.in(from, state.request_queue)
      {:noreply, %{state | request_queue: new_queue}}
    end
  end

  def handle_info(:refill_tokens, state) do
    # Add tokens (up to max)
    new_tokens = min(
      state.available_tokens + 1,
      state.max_tokens
    )

    # Process queued requests
    new_state = process_queue(%{state | available_tokens: new_tokens})

    # Schedule next refill
    Process.send_after(self(), :refill_tokens, state.token_refresh_rate)

    {:noreply, new_state}
  end

  defp process_queue(state) do
    case :queue.out(state.request_queue) do
      {{:value, from}, new_queue} when state.available_tokens > 0 ->
        GenServer.reply(from, :ok)
        process_queue(%{state |
          request_queue: new_queue,
          available_tokens: state.available_tokens - 1
        })

      _ ->
        state
    end
  end
end
```

**When to Use**:
- User-facing APIs where responsiveness matters
- Variable traffic patterns with legitimate bursts
- Systems expecting occasional spikes

### Leaky Bucket Implementation

**Characteristics**:
- Processes requests at consistent rate
- Queues incoming requests
- Uses timer to pop requests at fixed intervals

```elixir
defmodule LeakyBucket do
  use GenServer

  def init(opts) do
    requests_per_minute = opts[:requests_per_minute]
    poll_rate = calculate_poll_rate(requests_per_minute)

    state = %{
      request_queue: :queue.new(),
      request_queue_poll_rate: poll_rate
    }

    # Start processing loop
    Process.send_after(self(), :process_request, poll_rate)

    {:ok, state}
  end

  def handle_call(:request, from, state) do
    # Always queue
    new_queue = :queue.in(from, state.request_queue)
    {:noreply, %{state | request_queue: new_queue}}
  end

  def handle_info(:process_request, state) do
    new_state = case :queue.out(state.request_queue) do
      {{:value, from}, new_queue} ->
        # Execute request asynchronously to avoid blocking GenServer
        Task.Supervisor.start_child(RequestSupervisor, fn ->
          result = execute_request()
          GenServer.reply(from, result)
        end)

        %{state | request_queue: new_queue}

      {:empty, _queue} ->
        state
    end

    # Schedule next processing
    Process.send_after(self(), :process_request, state.request_queue_poll_rate)

    {:noreply, new_state}
  end

  defp calculate_poll_rate(requests_per_minute) do
    # Convert to milliseconds between requests
    div(60_000, requests_per_minute)
  end
end
```

**When to Use**:
- External API calls with strict rate limits
- Background jobs requiring predictable throughput
- Systems prioritizing uniform load distribution

**Performance Note**: Mean latency ~1.00 seconds for 60 req/min limit with very low variance (~0.006s SD).

---

## QPM Budget Management

### Implementation Strategies

**1. Sliding Window Algorithm**

More granular than fixed windows, prevents burst at window boundaries:

```elixir
defmodule SlidingWindowRateLimit do
  @qpm_limit 600
  @window_ms 60_000

  def check_limit(property_url) do
    now = System.system_time(:millisecond)
    window_start = now - @window_ms

    key = "gsc_qpm:#{property_url}"

    # Count requests in sliding window
    request_count = count_requests_since(key, window_start)

    if request_count < @qpm_limit do
      record_request(key, now)
      {:allow, @qpm_limit - request_count - 1}
    else
      retry_after = calculate_retry_after(key, window_start)
      {:deny, retry_after}
    end
  end

  defp count_requests_since(key, timestamp) do
    # ETS-based: Filter by timestamp
    :ets.select_count(:rate_limit_requests, [
      {{key, :"$1"}, [{:>=, :"$1", timestamp}], [true]}
    ])
  end

  defp record_request(key, timestamp) do
    :ets.insert(:rate_limit_requests, {key, timestamp})
  end

  defp calculate_retry_after(key, window_start) do
    # Find oldest request in window
    case :ets.select(:rate_limit_requests, [
      {{key, :"$1"}, [{:>=, :"$1", window_start}], [:"$1"]}
    ]) do
      [oldest | _] ->
        # Retry when oldest request falls out of window
        oldest + @window_ms - System.system_time(:millisecond)

      [] ->
        0
    end
  end
end
```

**Benefits**:
- No burst at window boundaries
- More accurate rate limiting
- Better user experience

**Tradeoffs**:
- Higher memory usage (stores all timestamps)
- More complex cleanup logic

---

**2. Per-Resource QPM Limits**

Different limits for different API endpoints:

```elixir
defmodule ResourceBasedRateLimit do
  @qpm_limits %{
    "search_analytics" => 600,
    "batch_operations" => 300,
    "real_time_queries" => 1200
  }

  def check_rate(resource_type, property_url) do
    limit = Map.get(@qpm_limits, resource_type, 600)
    key = "gsc_api:#{resource_type}:#{property_url}"

    Hammer.hit(key, 60_000, limit)
  end
end
```

---

**3. Actual QPM Tracking**

Monitor real API usage against budget:

```elixir
defmodule QPMTracker do
  def track_request(property_url) do
    now = System.system_time(:millisecond)
    key = "qpm_tracker:#{property_url}"

    # Record request with timestamp
    :ets.insert(:qpm_tracking, {key, now})

    # Emit telemetry
    actual_qpm = calculate_current_qpm(key)

    :telemetry.execute(
      [:gsc_analytics, :rate_limit, :qpm],
      %{actual_qpm: actual_qpm, budget_qpm: 600},
      %{property_url: property_url}
    )
  end

  defp calculate_current_qpm(key) do
    window_start = System.system_time(:millisecond) - 60_000

    count = :ets.select_count(:qpm_tracking, [
      {{key, :"$1"}, [{:>=, :"$1", window_start}], [true]}
    ])

    # Cleanup old entries
    :ets.select_delete(:qpm_tracking, [
      {{key, :"$1"}, [{:<, :"$1", window_start}], [true]}
    ])

    count
  end

  def remaining_quota(property_url, limit \\ 600) do
    key = "qpm_tracker:#{property_url}"
    actual = calculate_current_qpm(key)
    limit - actual
  end
end
```

**Integration with Phase 4**:

```elixir
# Before spawning workers, check remaining quota
remaining = QPMTracker.remaining_quota(property_url)
max_safe_concurrency = div(remaining, batch_size)

# Adjust concurrency dynamically
actual_concurrency = min(max_safe_concurrency, configured_max_concurrency)
```

---

## Backoff Strategies and Retry Patterns

### Exponential Backoff Implementation

```elixir
defmodule ExponentialBackoff do
  @base_delay 1000
  @max_delay 60_000

  def calculate_delay(attempt) do
    # 2^attempt * base_delay
    delay = :math.pow(2, attempt) * @base_delay

    # Cap at max_delay
    min(delay, @max_delay)
  end

  def with_jitter(delay, jitter_factor \\ 0.1) do
    # Add random jitter (±10% by default)
    jitter = delay * jitter_factor * (:rand.uniform() * 2 - 1)
    round(delay + jitter)
  end
end
```

**Why Jitter Matters**: Prevents thundering herd problem when many clients retry simultaneously.

### Retry Library Usage

```elixir
use Retry

retry with: exponential_backoff() |> randomize |> cap(60_000) |> expiry(300_000) do
  GSCClient.fetch_data(url)
after
  result -> {:ok, result}
rescue
  error in [RuntimeError] ->
    Logger.error("Failed after retries: #{inspect(error)}")
    {:error, error}
end
```

**Options**:
- `exponential_backoff()`: 1s, 2s, 4s, 8s, ...
- `randomize`: Adds jitter
- `cap(60_000)`: Max 60 second delay
- `expiry(300_000)`: Give up after 5 minutes

---

### Advanced Jitter Strategies

**1. Full Jitter** (Recommended by AWS):

```elixir
defmodule FullJitter do
  def calculate(attempt, base_delay \\ 1000) do
    max_delay = :math.pow(2, attempt) * base_delay
    :rand.uniform(round(max_delay))
  end
end
```

**Benefits**: Maximum spread, best for distributed systems

**2. Decorrelated Jitter**:

```elixir
defmodule DecorrelatedJitter do
  def calculate(last_delay, base_delay \\ 1000, max_delay \\ 60_000) do
    temp = last_delay * 3
    min(max_delay, base_delay + :rand.uniform(round(temp - base_delay)))
  end
end
```

**Benefits**: Better performance under high contention

---

### Smart Retry Logic

Not all errors should trigger retries:

```elixir
defmodule SmartRetry do
  def should_retry?(error) do
    case error do
      # Retry transient errors
      {:error, :timeout} -> true
      {:error, :econnrefused} -> true
      {:error, :nxdomain} -> true

      # Don't retry client errors (4xx)
      {:error, %{status: status}} when status in 400..499 -> false

      # Retry server errors (5xx)
      {:error, %{status: status}} when status in 500..599 -> true

      # Retry rate limits with backoff
      {:error, :rate_limited} -> true

      # Default: don't retry
      _ -> false
    end
  end

  def retry_with_backoff(operation, attempt \\ 0, max_attempts \\ 3) do
    case operation.() do
      {:ok, result} ->
        {:ok, result}

      error ->
        if should_retry?(error) and attempt < max_attempts do
          delay = ExponentialBackoff.calculate_delay(attempt)
          Logger.info("Retrying after #{delay}ms (attempt #{attempt + 1})")
          Process.sleep(delay)
          retry_with_backoff(operation, attempt + 1, max_attempts)
        else
          error
        end
    end
  end
end
```

---

### Idempotency Patterns

Ensure requests are safe to retry:

```elixir
defmodule IdempotentRequest do
  def call(request) do
    # Generate idempotency key from request content
    key = generate_idempotency_key(request)

    retry with: exponential_backoff() do
      HTTPClient.post(url, body, headers: [
        {"idempotency-key", key},
        {"authorization", "Bearer #{token}"}
      ])
    end
  end

  defp generate_idempotency_key(request) do
    # Hash request to create stable key
    :crypto.hash(:sha256, :erlang.term_to_binary(request))
    |> Base.encode16()
  end
end
```

---

## Circuit Breaker Pattern

Prevent cascading failures when external service is down:

```elixir
defmodule CircuitBreaker do
  use GenServer

  @failure_threshold 5
  @timeout 30_000  # 30 seconds

  def init(_) do
    {:ok, %{
      state: :closed,
      failures: 0,
      opened_at: nil
    }}
  end

  def call(service, request) do
    GenServer.call(__MODULE__, {:call, service, request})
  end

  def handle_call({:call, service, request}, _from, state) do
    case state.state do
      :closed ->
        # Normal operation
        execute_with_tracking(service, request, state)

      :open ->
        # Circuit open - check if should attempt recovery
        if should_attempt_recovery?(state) do
          transition_to_half_open(service, request, state)
        else
          {:reply, {:error, :circuit_open}, state}
        end

      :half_open ->
        # Test if service recovered
        attempt_recovery(service, request, state)
    end
  end

  defp execute_with_tracking(service, request, state) do
    case apply(service, :call, [request]) do
      {:ok, result} ->
        # Success - reset failure count
        {:reply, {:ok, result}, %{state | failures: 0}}

      {:error, _} = error ->
        # Failure - increment counter
        new_failures = state.failures + 1

        if new_failures >= @failure_threshold do
          # Open circuit
          Logger.error("Circuit breaker opened after #{new_failures} failures")
          {:reply, error, %{
            state |
            state: :open,
            failures: new_failures,
            opened_at: System.monotonic_time(:millisecond)
          }}
        else
          {:reply, error, %{state | failures: new_failures}}
        end
    end
  end

  defp should_attempt_recovery?(state) do
    now = System.monotonic_time(:millisecond)
    (now - state.opened_at) >= @timeout
  end

  defp transition_to_half_open(service, request, state) do
    Logger.info("Circuit breaker attempting recovery")

    case apply(service, :call, [request]) do
      {:ok, result} ->
        # Success - close circuit
        Logger.info("Circuit breaker closed")
        {:reply, {:ok, result}, %{state | state: :closed, failures: 0}}

      {:error, _} = error ->
        # Still failing - stay open
        {:reply, error, %{state | opened_at: System.monotonic_time(:millisecond)}}
    end
  end
end
```

---

## Phase 4 Rate Limiting Integration

### Requirements

1. Rate check BEFORE HTTP call in worker
2. Support batch-sized increments
3. Track actual QPM vs budget
4. Alert at 80% quota

### Implementation

```elixir
defmodule ConcurrentBatchWorker do
  def worker_loop(coordinator_pid) do
    case QueryCoordinator.take_batch(coordinator_pid, self()) do
      {:ok, batch} ->
        # Check rate limit BEFORE HTTP call
        case check_rate_limit(batch) do
          :ok ->
            fetch_and_submit(coordinator_pid, batch)

          {:error, :rate_limited, retry_ms} ->
            # Return batch to coordinator
            QueryCoordinator.requeue_batch(coordinator_pid, batch)

            # Sleep before retrying
            Process.sleep(retry_ms)
        end

        worker_loop(coordinator_pid)

      :no_batches ->
        Process.sleep(1000)
        worker_loop(coordinator_pid)
    end
  end

  defp check_rate_limit(batch) do
    property_url = batch.property_url
    batch_size = batch.size

    # Check with batch-sized increment
    case RateLimiter.check_rate(property_url, batch_size) do
      :ok ->
        # Track actual usage
        QPMTracker.track_request(property_url, batch_size)
        :ok

      {:error, retry_ms} ->
        Logger.warn("Rate limited for #{property_url}, retry after #{retry_ms}ms")
        {:error, :rate_limited, retry_ms}
    end
  end
end
```

### RateLimiter Module Enhancement

```elixir
defmodule RateLimiter do
  use Hammer, backend: :ets

  @qpm_limit 600
  @window_ms 60_000
  @alert_threshold 0.8  # 80%

  def check_rate(property_url, request_count \\ 1) do
    key = "gsc_api:#{property_url}"

    case Hammer.hit(key, @window_ms, @qpm_limit, request_count) do
      {:allow, current_count} ->
        # Check if approaching limit
        if current_count / @qpm_limit >= @alert_threshold do
          Logger.warn("Approaching rate limit: #{current_count}/#{@qpm_limit} (#{round(current_count / @qpm_limit * 100)}%)")

          :telemetry.execute(
            [:gsc_analytics, :rate_limit, :approaching],
            %{current: current_count, limit: @qpm_limit},
            %{property_url: property_url}
          )
        end

        :ok

      {:deny, retry_ms} ->
        :telemetry.execute(
          [:gsc_analytics, :rate_limit, :exceeded],
          %{limit: @qpm_limit},
          %{property_url: property_url, retry_ms: retry_ms}
        )

        {:error, retry_ms}
    end
  end
end
```

---

## Testing Rate Limiters

```elixir
defmodule RateLimiterTest do
  use ExUnit.Case, async: false

  test "enforces QPM limit" do
    property = "sc-domain:test.com"

    # Should allow up to limit
    for _ <- 1..600 do
      assert :ok = RateLimiter.check_rate(property)
    end

    # Should deny 601st request
    assert {:error, retry_ms} = RateLimiter.check_rate(property)
    assert retry_ms > 0
  end

  test "handles concurrent requests correctly" do
    property = "sc-domain:test.com"

    # Spawn 100 concurrent requests
    tasks = for _ <- 1..100 do
      Task.async(fn ->
        RateLimiter.check_rate(property)
      end)
    end

    results = Task.await_many(tasks)

    # All should succeed (under limit)
    assert Enum.all?(results, &match?(:ok, &1))
  end

  test "batch increments work correctly" do
    property = "sc-domain:test.com"

    # 12 batches of 50 = 600 requests
    for _ <- 1..12 do
      assert :ok = RateLimiter.check_rate(property, 50)
    end

    # Next batch should fail
    assert {:error, _} = RateLimiter.check_rate(property, 50)
  end
end
```

---

## Key Takeaways

1. **Hammer for simplicity** - ETS backend for single-node, Redis for distributed
2. **Token bucket for bursts** - Better user experience, allows legitimate spikes
3. **Leaky bucket for uniformity** - Predictable load on external APIs
4. **Sliding windows > fixed windows** - More accurate, prevents boundary bursts
5. **Always add jitter** - Prevents thundering herd on retry
6. **Circuit breakers prevent cascades** - Fail fast when service is down
7. **Track actual QPM** - Monitor against budget, alert at 80%

---

## Resources

### Official Libraries
- **Hammer**: https://hexdocs.pm/hammer/readme.html
- **ElixirRetry**: https://hexdocs.pm/retry/Retry.html
- **GenRetry**: https://hexdocs.pm/gen_retry/GenRetry.html

### Implementation Guides
- **Rate Limiting with GenServers**: https://akoutmos.com/post/rate-limiting-with-genservers/
- **Token and Leaky Buckets**: https://elixirmerge.com/p/implementing-rate-limiting-in-elixir-with-leaky-and-token-buckets
- **DockYard ETS Guide**: https://dockyard.com/blog/2017/05/19/optimizing-elixir-and-phoenix-with-ets
- **Exponential Backoff**: https://blog.finiam.com/blog/exponential-backoff-with-elixir
