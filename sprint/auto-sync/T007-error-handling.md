# T007: Enhanced Error Handling and Monitoring

**Status:** 🔵 Not Started
**Story Points:** 2
**Priority:** 🟡 P2 Medium
**TDD Required:** Partial (test critical paths)
**Depends On:** T006

## Description
Add robust error handling, monitoring, and alerting capabilities for the automated sync system.

## Acceptance Criteria
- [ ] Dead letter queue for failed jobs after max retries
- [ ] Error notification system (log-based initially)
- [ ] Health check endpoint for sync status
- [ ] Metrics tracking for sync performance
- [ ] Graceful degradation when GSC API is unavailable

## Implementation Steps

### 1. Configure Oban Error Handling

**File:** `config/runtime.exs`

```elixir
# Add to Oban plugins configuration
{Oban.Plugins.Stager, interval: 1000},
{Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
{Oban.Plugins.Lifeline, rescue_after: :timer.minutes(30)}
```

**Lifeline plugin:** Rescues orphaned jobs if worker crashes

### 2. Add Error Telemetry Handler

**File:** `lib/gsc_analytics/telemetry.ex`

Add to existing telemetry setup:

```elixir
defmodule GscAnalytics.Telemetry do
  # ... existing code ...

  def handle_event([:oban, :job, :exception], measurements, metadata, _config) do
    if metadata.job.queue == :gsc_sync do
      Logger.error("""
      Oban job failed:
      - Worker: #{metadata.job.worker}
      - Attempt: #{metadata.job.attempt}
      - Error: #{Exception.message(metadata.error)}
      - Duration: #{measurements.duration}
      """)

      # Emit custom telemetry for alerting systems
      :telemetry.execute(
        [:gsc_analytics, :auto_sync, :failure],
        measurements,
        metadata
      )
    end
  end

  # Attach in setup function
  def attach_handlers do
    :telemetry.attach(
      "oban-errors",
      [:oban, :job, :exception],
      &__MODULE__.handle_event/4,
      nil
    )
  end
end
```

### 3. Add Health Check Endpoint

**Router placement (very important per `AGENTS.md`):**

- Route lives inside the existing browser pipeline but **outside** `:require_authenticated_user` so uptime services can hit it without a session.
- Add a dedicated scope so it is obvious that the endpoint is safe for unauthenticated access because it only exposes operational metadata.

**File:** `lib/gsc_analytics_web/router.ex`

```elixir
scope "/health", GscAnalyticsWeb do
  # We intentionally avoid :require_authenticated_user here because the endpoint
  # only returns aggregate operational info and needs to be reachable by uptime monitors.
  pipe_through [:browser]

  get "/sync", HealthController, :sync_status
end
```

**File:** `lib/gsc_analytics_web/controllers/health_controller.ex`

```elixir
defmodule GscAnalyticsWeb.HealthController do
  use GscAnalyticsWeb, :controller
  alias GscAnalytics.DataSources.GSC.Support.SyncProgress

  def sync_status(conn, _params) do
    # Check last sync job status
    last_job = get_last_sync_job()

    status = %{
      last_sync: format_job_status(last_job),
      oban_health: check_oban_health(),
      database: check_database_health()
    }

    http_status = if status.oban_health == :ok and status.database == :ok, do: 200, else: 503

    conn
    |> put_status(http_status)
    |> json(status)
  end

  defp get_last_sync_job do
    import Ecto.Query

    GscAnalytics.Repo.one(
      from j in Oban.Job,
        where: j.queue == "gsc_sync",
        order_by: [desc: j.scheduled_at],
        limit: 1
    )
  end

  defp format_job_status(nil), do: %{status: "never_run"}

  defp format_job_status(job) do
    %{
      status: job.state,
      scheduled_at: job.scheduled_at,
      completed_at: job.completed_at,
      attempt: job.attempt,
      errors: job.errors
    }
  end

  defp check_oban_health do
    case Oban.check_queue(queue: :gsc_sync) do
      {:ok, _stats} -> :ok
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp check_database_health do
    GscAnalytics.Repo.query("SELECT 1")
    :ok
  rescue
    _ -> :error
  end
end
```


### 4. Add Circuit Breaker for GSC API

**File:** `lib/gsc_analytics/data_sources/gsc/support/circuit_breaker.ex`

```elixir
defmodule GscAnalytics.DataSources.GSC.Support.CircuitBreaker do
  @moduledoc """
  Circuit breaker pattern to prevent cascading failures when GSC API is down.
  """

  use GenServer
  require Logger

  @failure_threshold 5
  @timeout_duration :timer.minutes(5)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def call(fun) do
    case GenServer.call(__MODULE__, :get_state) do
      :closed -> execute_with_tracking(fun)
      :open -> {:error, :circuit_open}
    end
  end

  defp execute_with_tracking(fun) do
    case fun.() do
      {:ok, _} = success ->
        GenServer.cast(__MODULE__, :success)
        success

      {:error, _} = error ->
        GenServer.cast(__MODULE__, :failure)
        error
    end
  end

  # GenServer implementation
  def init(_opts) do
    {:ok, %{state: :closed, failures: 0, last_failure: nil}}
  end

  def handle_call(:get_state, _from, state) do
    current_state = determine_state(state)
    {:reply, current_state, %{state | state: current_state}}
  end

  def handle_cast(:success, state) do
    {:noreply, %{state | failures: 0}}
  end

  def handle_cast(:failure, state) do
    failures = state.failures + 1
    new_state = if failures >= @failure_threshold, do: :open, else: :closed

    if new_state == :open do
      Logger.error("Circuit breaker OPENED after #{failures} failures")
      Process.send_after(self(), :attempt_reset, @timeout_duration)
    end

    {:noreply, %{state | failures: failures, state: new_state, last_failure: DateTime.utc_now()}}
  end

  def handle_info(:attempt_reset, state) do
    Logger.info("Circuit breaker attempting reset")
    {:noreply, %{state | state: :half_open}}
  end

  defp determine_state(%{state: :open, last_failure: last_failure}) do
    if DateTime.diff(DateTime.utc_now(), last_failure, :millisecond) > @timeout_duration do
      :half_open
    else
      :open
    end
  end

  defp determine_state(%{state: state}), do: state
end
```

**Add to supervision tree:**

```elixir
# application.ex
{GscAnalytics.DataSources.GSC.Support.CircuitBreaker, []}
```

**Integrate with Client:**

```elixir
# In Client.search_analytics_query/4
def search_analytics_query(site_url, start_date, end_date, opts) do
  CircuitBreaker.call(fn ->
    # Existing HTTP request logic
    do_search_analytics_query(site_url, start_date, end_date, opts)
  end)
end
```

### 5. Add Performance Metrics

**File:** `lib/gsc_analytics/workers/gsc_sync_worker.ex`

Add metrics tracking to worker:

```elixir
defp emit_telemetry(results, duration_ms) do
  total_urls = Enum.sum(for {_ws, summary} <- results.successes, do: summary[:total_urls] || 0)
  total_queries = Enum.sum(for {_ws, summary} <- results.successes, do: summary[:total_queries] || 0)

  :telemetry.execute(
    [:gsc_analytics, :auto_sync, :complete],
    %{
      total_workspaces: results.total_workspaces,
      successes: length(results.successes),
      failures: length(results.failures),
      duration_ms: duration_ms,
      total_urls: total_urls,
      total_queries: total_queries,
      urls_per_second: if(duration_ms > 0, do: total_urls / (duration_ms / 1000), else: 0)
    },
    %{results: results}
  )
end
```

## Testing

**File:** `test/gsc_analytics/support/circuit_breaker_test.exs`

```elixir
defmodule GscAnalytics.DataSources.GSC.Support.CircuitBreakerTest do
  use ExUnit.Case
  alias GscAnalytics.DataSources.GSC.Support.CircuitBreaker

  test "opens after threshold failures" do
    # Simulate 5 failures
    for _ <- 1..5 do
      CircuitBreaker.call(fn -> {:error, :api_failure} end)
    end

    # Circuit should be open
    assert {:error, :circuit_open} = CircuitBreaker.call(fn -> {:ok, :data} end)
  end

  test "resets after timeout" do
    # Open circuit
    for _ <- 1..5 do
      CircuitBreaker.call(fn -> {:error, :api_failure} end)
    end

    # Wait for reset
    Process.sleep(5_100)  # 5 minutes + buffer

    # Should attempt request
    refute {:error, :circuit_open} = CircuitBreaker.call(fn -> {:ok, :data} end)
  end
end
```

## Definition of Done
- [ ] Oban error handling configured
- [ ] Telemetry handlers attached
- [ ] Health check endpoint working
- [ ] Circuit breaker implemented and tested
- [ ] Performance metrics tracked
- [ ] Error notifications logged
- [ ] Documentation updated

## Notes
- **Circuit breaker:** Prevents hammering GSC API when it's down
- **Health endpoint:** Useful for monitoring tools (Uptime Robot, Pingdom, etc.)
- **Metrics:** Can be exported to Prometheus/Grafana in future
- **Dead letter queue:** Oban's built-in pruner handles job cleanup

## 📚 Reference Documentation
- **Primary:** [Error Handling Research](/Users/flor/Developer/prism/docs/elixir_error_handling_research.md) - Complete error handling guide
- **Secondary:** [Oban Reference](/Users/flor/Developer/prism/docs/OBAN_REFERENCE.md) - Retry and error handling
- **Tertiary:** [Phoenix/Ecto Research](/Users/flor/Developer/prism/docs/phoenix-ecto-research.md) - Telemetry integration
- **Libraries:** `fuse` (circuit breaker), `external_service` (retry + circuit breaker)
- **Official:** https://hexdocs.pm/oban/Oban.Plugins.Lifeline.html
- **Index:** [Documentation Index](docs/DOCUMENTATION_INDEX.md)
