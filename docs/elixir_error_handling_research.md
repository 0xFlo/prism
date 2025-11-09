# Elixir Error Handling and Resilience Patterns for Background Jobs

Comprehensive research on error handling, retry strategies, observability, and testing for Elixir background job systems.

---

## Table of Contents

1. [Elixir Error Handling](#1-elixir-error-handling)
2. [Retry Strategies](#2-retry-strategies)
3. [Observability](#3-observability)
4. [Graceful Degradation](#4-graceful-degradation)
5. [Testing Error Scenarios](#5-testing-error-scenarios)
6. [Production Deployment Best Practices](#6-production-deployment-best-practices)
7. [Libraries and Tools](#7-libraries-and-tools)

---

## 1. Elixir Error Handling

### 1.1 The "Let It Crash" Philosophy

**Core Principle**: Elixir embraces OTP's "let it crash" philosophy, encouraging processes to fail and rely on supervision trees for recovery.

**Important Nuance**: The philosophy is often misunderstood. It doesn't mean ignoring errors - it means:
- Delegating recovery to supervisors instead of defensive programming
- Reverting to a known good state through process restart
- Gracefully handling **expected** errors through logging, error tuples, or recovery functions
- Letting **unexpected** errors crash and restart the process

**Key Quote**:
> "An important point of the 'Let it crash!' philosophy is that the idea behind restarting the process is to revert it to a correct state. When restoring the state from before the crash, how can we be sure that the state was correct?"

**Source**: [AmberBit - The Misunderstanding of "Let It Crash"](https://www.amberbit.com/blog/2019/7/26/the-misunderstanding-of-let-it-crash/)

### 1.2 Supervisor Strategies

Supervisors automatically restart crashed processes using one of three strategies:

#### `:one_for_one`
- Restarts only the failed process
- Use when processes are independent

```elixir
Supervisor.start_link(children, strategy: :one_for_one)
```

#### `:one_for_all`
- Terminates and restarts ALL children when any child crashes
- Use when all processes depend on each other

```elixir
Supervisor.start_link(children, strategy: :one_for_all)
```

#### `:rest_for_one`
- Restarts the crashed process and all siblings started AFTER it
- Use when processes have sequential dependencies

```elixir
Supervisor.start_link(children, strategy: :rest_for_one)
```

**Sources**:
- [Elixir Documentation - Supervisor and Application](https://elixir-lang.readthedocs.io/en/latest/mix_otp/5.html)
- [OOZOU - Understanding Elixir OTP Applications Part 2](https://oozou.com/blog/understanding-elixir-otp-applications-part-2-fault-tolerance-138)

### 1.3 Error Tuple Patterns (`{:ok, result}` vs `{:error, reason}`)

**Convention**: Create two versions of functions:
- `foo/1` - Returns `{:ok, result}` or `{:error, reason}` tuples
- `foo!/1` - Returns unwrapped result or raises an exception

```elixir
# Safe version with error tuples
def fetch_user(id) do
  case Repo.get(User, id) do
    nil -> {:error, :not_found}
    user -> {:ok, user}
  end
end

# Bang version that raises
def fetch_user!(id) do
  case fetch_user(id) do
    {:ok, user} -> user
    {:error, reason} -> raise "User not found: #{reason}"
  end
end
```

**Best Practices for Error Tuples**:

1. **Use Two-Element Tuples**: Keep error shape consistent: `{:error, reason}`
2. **Avoid Strings as Reasons**: Use atoms or exception structs for pattern matching
3. **Use Exception Structs in Error Tuples**: Leverage `Exception.message/1` for formatting

```elixir
# ❌ BAD: String errors complicate pattern matching
{:error, "Database connection failed"}

# ✅ GOOD: Atom for simple errors
{:error, :database_unavailable}

# ✅ BETTER: Exception struct for rich errors
{:error, %DBConnection.ConnectionError{reason: :timeout}}
```

4. **Pattern Match with `case`, Not Pipes**:

```elixir
# ❌ BAD: Piping into case
fetch_user(id)
|> case do
  {:ok, user} -> user
  {:error, _} -> nil
end

# ✅ GOOD: Assign then pattern match
user_result = fetch_user(id)
case user_result do
  {:ok, user} -> user
  {:error, _} -> nil
end
```

5. **Use `with` for Happy Path Chaining**:

```elixir
# ✅ Use `with` when you can fall through errors without specific handling
def process_order(order_id) do
  with {:ok, order} <- fetch_order(order_id),
       {:ok, user} <- fetch_user(order.user_id),
       {:ok, payment} <- charge_card(user, order.total) do
    {:ok, complete_order(order)}
  end
end

# ❌ DON'T use `else` to handle all potential errors
# Better to let errors bubble up or handle them explicitly
```

**Sources**:
- [Elixir Best Practices for Error Values - Moxley Stratton](https://medium.com/@moxicon/elixir-best-practices-for-error-values-50dc015a06f5)
- [Elixir School - Error Handling](https://elixirschool.com/en/lessons/intermediate/error_handling)
- [Leveraging Exceptions in Elixir - Leandro Cesquini](https://leandrocp.com.br/2020/08/leveraging-exceptions-to-handle-errors-in-elixir/)

### 1.4 Exception Handling Best Practices

**Philosophy**: In Elixir, `try/catch/rescue` is uncommon because supervision trees handle failures.

**When to Use Exceptions**:
- Control flow should use error tuples
- Exceptions are for truly exceptional, unexpected errors
- Let supervisors restart processes instead of rescuing

```elixir
# ❌ BAD: Using exceptions for control flow
try do
  case User.fetch(id) do
    nil -> raise "Not found"
    user -> user
  end
rescue
  _ -> %User{}
end

# ✅ GOOD: Use error tuples for expected failures
case User.fetch(id) do
  {:ok, user} -> user
  {:error, :not_found} -> %User{}
end
```

**Source**: [Elixir Documentation - try, catch, and rescue](https://hexdocs.pm/elixir/try-catch-and-rescue.html)

---

## 2. Retry Strategies

### 2.1 Exponential Backoff

**Pattern**: Progressively increase delay between retries to reduce load on failing systems.

**Formula**: `delay = base_delay * (2 ^ attempt_number) + random_jitter`

#### Library: `retry` (ElixirRetry)

**Installation**:
```elixir
{:retry, "~> 0.18"}
```

**Basic Usage**:
```elixir
use Retry

# Linear backoff
retry with: linear_backoff(500, 1) |> Stream.take(5) do
  ExternalAPI.fetch_data()
end

# Exponential backoff with jitter
retry with: exponential_backoff() |> randomize() |> expiry(10_000) do
  ExternalAPI.fetch_data()
end

# Rescue specific errors
retry with: exponential_backoff(), rescue_only: [TimeoutError] do
  ExternalAPI.fetch_data()
end
```

**Composable Delays**:
```elixir
# Combine strategies
retry with: exponential_backoff(100) |> randomize() |> cap(10_000) |> expiry(60_000) do
  risky_operation()
end
```

**Sources**:
- [GitHub - safwank/ElixirRetry](https://github.com/safwank/ElixirRetry)
- [HexDocs - Retry](https://hexdocs.pm/retry/0.3.0/Retry.html)

#### Library: `gen_retry`

**GenServer-based Retry**:
```elixir
{:gen_retry, "~> 1.4"}

# Retry function with exponential backoff
GenRetry.retry(fn -> external_call() end,
  retries: 5,
  delay: 1000,
  exp_base: 2
)
```

**Source**: [HexDocs - GenRetry](https://hexdocs.pm/gen_retry/GenRetry.html)

### 2.2 Circuit Breaker Pattern

**Purpose**: Prevent cascading failures by "opening" the circuit when error thresholds are exceeded.

**States**:
- **Closed**: Normal operation, requests pass through
- **Open**: Error threshold exceeded, requests fail immediately
- **Half-Open**: Testing if service recovered

#### Library: `fuse` (Erlang)

**The Standard**: Battle-tested Erlang library with extensive QuickCheck testing.

**Installation**:
```elixir
{:fuse, "~> 2.5"}
```

**Configuration**:
```elixir
# In application.ex
def start(_type, _args) do
  # Install circuit breaker
  :fuse.install(:external_api, {
    {:standard, 5, 10_000},  # 5 failures in 10 seconds trips circuit
    {:reset, 30_000}          # Try again after 30 seconds
  })

  # ... rest of supervision tree
end
```

**Usage**:
```elixir
# Check circuit before making request
case :fuse.ask(:external_api, :sync) do
  :ok ->
    # Circuit closed, make request
    case make_request() do
      {:ok, result} ->
        {:ok, result}
      {:error, _} = error ->
        :fuse.melt(:external_api)  # Record failure
        error
    end

  :blown ->
    # Circuit open, fail fast
    {:error, :circuit_open}
end

# Or use run/3 which handles ask/melt automatically
:fuse.run(:external_api, fn ->
  make_request()
end)
```

**Sources**:
- [GitHub - jlouis/fuse](https://github.com/jlouis/fuse)
- [RokkinCat - Circuit Breakers in Elixir](https://rokkincat.com/blog/2015/09/24/circuit-breakers-in-elixir)
- [MojoTech - Safeguard with Fuse](https://www.mojotech.com/blog/safeguard-web-service-failures-in-elixir-with-fuse/)

#### Library: `external_service`

**The All-in-One**: Combines retry logic, rate limiting, AND circuit breakers.

**Installation**:
```elixir
{:external_service, "~> 1.1"}
```

**Configuration**:
```elixir
defmodule MyApp.ExternalAPI do
  use ExternalService,
    retry_opts: [
      backoff: {:exponential, 100},
      cap: 10_000,
      expiry: 60_000
    ],
    fuse_opts: [
      fuse_strategy: {:standard, 5, 10_000},
      fuse_refresh: 30_000
    ],
    rate_limit_opts: [
      limit: 100,        # 100 requests
      period: 60_000     # per 60 seconds
    ]
end
```

**Usage**:
```elixir
ExternalAPI.call(fn ->
  HTTPoison.get("https://api.example.com/data")
end)
```

**Source**: [GitHub - jvoegele/external_service](https://github.com/jvoegele/external_service)

#### Library: `breaker_box`

**Elixir-Friendly Wrapper**: Supervised circuit breaker management.

**Installation**:
```elixir
{:breaker_box, "~> 1.0"}
```

**Features**:
- Integrates with Elixir supervision trees
- Multiple named circuit breakers
- User-friendly configuration API

**Source**: [GitHub - DoggettCK/breaker_box](https://github.com/DoggettCK/breaker_box)

### 2.3 Dead Letter Queues with Oban

Oban doesn't have a traditional "dead letter queue", but provides similar functionality through job state management.

#### Discarded Jobs

When jobs reach `max_attempts`, they're marked as **discarded** in the database.

**Query Discarded Jobs**:
```elixir
import Ecto.Query

# Find all discarded jobs
discarded_jobs =
  from(j in Oban.Job,
    where: j.state == "discarded",
    order_by: [desc: j.attempted_at]
  )
  |> Repo.all()
```

#### Manual Retry

**Retry Specific Job**:
```elixir
# Retry single job by ID
Oban.retry_job(Repo, job_id)

# Retry all discarded jobs
from(j in Oban.Job, where: j.state == "discarded")
|> Oban.retry()
```

#### Custom Dead Letter Queue Pattern

**Create Separate Queue for Failed Jobs**:
```elixir
defmodule MyWorker do
  use Oban.Worker, queue: :default, max_attempts: 3

  @impl Oban.Worker
  def perform(%Job{attempt: attempt} = job) when attempt == @max_attempts do
    # Last attempt - send to dead letter queue
    %{worker: "DeadLetterWorker", args: job.args}
    |> Oban.insert(queue: :dead_letter)

    {:error, :max_attempts_reached}
  end

  def perform(job) do
    # Normal processing
    do_work(job.args)
  end
end
```

**Sources**:
- [Oban - Error Handling](https://hexdocs.pm/oban/error_handling.html)
- [Oban - Handling Expected Failures](https://hexdocs.pm/oban/expected-failures.html)
- [Elixir Forum - Handling Failed Oban Jobs](https://elixirforum.com/t/handling-failed-oban-jobs/38409)

### 2.4 Oban Retry Configuration

#### Default Behavior

```elixir
# Default configuration
use Oban.Worker,
  queue: :default,
  max_attempts: 20  # Default: retry up to 20 times
```

**Retry Schedule**: Exponential backoff with jitter
- Attempt 1: ~15 seconds
- Attempt 2: ~31 seconds
- Attempt 3: ~1 minute
- Attempt 10: ~17 minutes
- Attempt 20: ~6 days

#### Custom Max Attempts

**Per-Worker Configuration**:
```elixir
defmodule MyWorker do
  use Oban.Worker,
    queue: :critical,
    max_attempts: 5  # Only retry 5 times
end
```

**Per-Job Configuration**:
```elixir
%{user_id: 123}
|> MyWorker.new(max_attempts: 3)
|> Oban.insert()
```

#### Custom Backoff Strategy

**Linear Backoff**:
```elixir
defmodule MyWorker do
  use Oban.Worker

  @impl Oban.Worker
  def backoff(%Job{attempt: attempt}) do
    # Linear: 10 seconds per attempt
    attempt * 10
  end
end
```

**Custom Exponential**:
```elixir
defmodule MyWorker do
  use Oban.Worker

  @impl Oban.Worker
  def backoff(%Job{attempt: attempt}) do
    # Slower exponential backoff
    trunc(:math.pow(2, attempt) * 30)
  end
end
```

#### Expected Failures (Don't Consume Retries)

**Use `:discard` for Expected Errors**:
```elixir
defmodule MyWorker do
  use Oban.Worker

  @impl Oban.Worker
  def perform(%Job{args: %{"url" => url}}) do
    case fetch_url(url) do
      {:ok, data} ->
        {:ok, data}

      {:error, :not_found} ->
        # Expected error - discard without retrying
        {:discard, :not_found}

      {:error, :timeout} ->
        # Unexpected error - will retry
        {:error, :timeout}
    end
  end
end
```

**Sources**:
- [Oban.Worker Documentation](https://hexdocs.pm/oban/Oban.Worker.html)
- [Elixir Forum - Oban Error Handling and Job Retry](https://elixirforum.com/t/oban-error-handling-and-job-retry/25640)
- [Elixir Forum - Expected Errors Not Consuming Retries](https://elixirforum.com/t/best-approach-to-make-expected-errors-not-consume-retries-in-oban/48188)

---

## 3. Observability

### 3.1 Three Pillars of Observability

1. **Logs**: Detailed event information (structured or unstructured)
2. **Metrics**: Time-series measurements with metadata
3. **Traces**: Collection of related events across call stacks and services

**Source**: [Underjord - Unpacking Elixir Observability](https://underjord.io/unpacking-elixir-observability.html)

### 3.2 Structured Logging with Logger

**Why Structured Logging?**: Machine-parseable JSON logs enable powerful querying and analysis.

#### Basic Configuration

**In `config/config.exs`**:
```elixir
config :logger, :console,
  format: {LoggerJSON.Formatters.Basic, :format},
  metadata: [:request_id, :user_id, :job_id]
```

**Installation**:
```elixir
{:logger_json, "~> 5.1"}
```

#### Usage

```elixir
require Logger

Logger.info("User created",
  user_id: user.id,
  email: user.email,
  source: "registration_api"
)

# Outputs JSON:
# {"level":"info","message":"User created","user_id":123,"email":"user@example.com","source":"registration_api","timestamp":"2024-11-08T10:30:45.123Z"}
```

#### Integration with Loki/Grafana

**Configure Logger Backend**:
```elixir
# config/runtime.exs
if config_env() == :prod do
  config :logger,
    backends: [
      LoggerJSON,
      {Loki.Backend, [
        url: "https://loki.example.com",
        labels: %{app: "my_app", env: "production"}
      ]}
    ]
end
```

**Sources**:
- [AppSignal Blog - Structured Logging in Phoenix](https://blog.appsignal.com/2023/07/18/observe-your-phoenix-app-with-structured-logging.html)
- [Alex Koutmos - Structured Logging with Loki](https://akoutmos.com/post/elixir-logging-loki/)

### 3.3 Telemetry for Error Tracking

**Telemetry**: Lightweight library for dynamic event dispatching in Elixir/Erlang.

#### Core Concepts

**Execute Events**:
```elixir
:telemetry.execute(
  [:my_app, :api, :request],
  %{duration: 145, status: 200},  # measurements
  %{method: "GET", path: "/users"} # metadata
)
```

**Attach Handlers**:
```elixir
:telemetry.attach(
  "my-handler-id",
  [:my_app, :api, :request],
  &MyApp.TelemetryHandler.handle_event/4,
  nil
)
```

#### Error Tracking Handler

```elixir
defmodule MyApp.TelemetryHandler do
  require Logger

  def handle_event([:oban, :job, :exception], measurements, metadata, _config) do
    Logger.error("Job failed",
      job_id: metadata.job.id,
      worker: metadata.job.worker,
      error: Exception.message(metadata.error),
      duration_ms: measurements.duration,
      attempt: metadata.job.attempt
    )

    # Send to error tracking service
    Sentry.capture_exception(metadata.error,
      stacktrace: metadata.stacktrace,
      extra: %{
        job_id: metadata.job.id,
        worker: metadata.job.worker,
        args: metadata.job.args
      }
    )
  end
end
```

#### Phoenix & Ecto Built-in Events

Phoenix and Ecto emit telemetry events for free:

**Phoenix Events**:
- `[:phoenix, :endpoint, :start]`
- `[:phoenix, :endpoint, :stop]`
- `[:phoenix, :router_dispatch, :start]`
- `[:phoenix, :router_dispatch, :stop]`

**Ecto Events**:
- `[:my_app, :repo, :query]`

**Oban Events**:
- `[:oban, :job, :start]`
- `[:oban, :job, :stop]`
- `[:oban, :job, :exception]`

**Sources**:
- [Elixir School - Instrumenting Phoenix with Telemetry](https://elixirschool.com/blog/instrumenting-phoenix-with-telemetry-part-one)
- [Samuel Mullen - Elixir Telemetry](https://samuelmullen.com/articles/the-hows-whats-and-whys-of-elixir-telemetry)
- [Elixir Merge - Telemetry and Observability](https://elixirmerge.com/p/exploring-telemetry-and-observability-practices-in-elixir-applications)

### 3.4 APM Integration

#### AppSignal

**Best for**: Elixir/Phoenix-specific needs, easiest setup

**Installation**:
```bash
mix appsignal.install YOUR_PUSH_API_KEY
```

**Features**:
- Automatic instrumentation for Phoenix, Ecto, Oban
- Performance monitoring
- Error tracking with breadcrumbs
- Custom metrics via decorators

**Custom Error Reporting**:
```elixir
Appsignal.send_error(exception, stacktrace, fn span ->
  Appsignal.Span.set_attribute(span, "user_id", user.id)
  Appsignal.Span.set_attribute(span, "job_id", job.id)
end)
```

**Source**: [AppSignal - Phoenix Monitoring Guide](https://blog.appsignal.com/2024/09/17/a-complete-guide-to-phoenix-for-elixir-monitoring-with-appsignal.html)

#### Sentry

**Best for**: Multi-language projects, detailed error reports

**Installation**:
```elixir
{:sentry, "~> 10.0"}

# config/config.exs
config :sentry,
  dsn: "https://public@sentry.io/1",
  environment_name: Mix.env(),
  enable_source_code_context: true,
  root_source_code_paths: [File.cwd!()]
```

**Integration with Logger**:
```elixir
config :logger,
  backends: [:console, Sentry.LoggerBackend]
```

**Capturing Exceptions**:
```elixir
try do
  risky_operation()
rescue
  exception ->
    Sentry.capture_exception(exception,
      stacktrace: __STACKTRACE__,
      extra: %{user_id: 123},
      tags: %{source: "background_job"}
    )
    reraise exception, __STACKTRACE__
end
```

**Source**: [Sentry Documentation - Elixir](https://docs.sentry.io/platforms/elixir/)

#### Honeybadger

**Best for**: Teams using Elixir in production (built by Elixir users)

**Installation**:
```elixir
{:honeybadger, "~> 0.21"}

# config/config.exs
config :honeybadger,
  api_key: System.get_env("HONEYBADGER_API_KEY"),
  environment_name: :prod,
  exclude_envs: [:dev, :test]
```

**Features**:
- Automatic error reporting in controllers and background jobs
- Application logs collection
- Performance metrics
- Breadcrumbs for error context

**Manual Error Reporting**:
```elixir
Honeybadger.notify(%RuntimeError{message: "Something broke"},
  context: %{user_id: user.id},
  metadata: %{job: job}
)
```

**Sources**:
- [Honeybadger - Elixir Integration](https://docs.honeybadger.io/lib/elixir/integrations/other/)
- [StakNine - Best Error Monitoring for Phoenix](https://staknine.com/best-error-monitoring-elixir-phoenix/)

### 3.5 OpenTelemetry Integration

**OpenTelemetry**: Language-agnostic standard for logs, metrics, and traces.

**Installation**:
```elixir
{:opentelemetry, "~> 1.3"},
{:opentelemetry_exporter, "~> 1.6"},
{:opentelemetry_phoenix, "~> 1.1"},
{:opentelemetry_ecto, "~> 1.1"},
{:opentelemetry_oban, "~> 1.0"}
```

**Configuration**:
```elixir
# config/runtime.exs
config :opentelemetry,
  span_processor: :batch,
  traces_exporter: :otlp

config :opentelemetry_exporter,
  otlp_protocol: :grpc,
  otlp_endpoint: "http://localhost:4317"
```

**Setup Instrumentation**:
```elixir
# lib/my_app/application.ex
def start(_type, _args) do
  OpentelemetryPhoenix.setup()
  OpentelemetryEcto.setup([:my_app, :repo])
  OpentelemetryOban.setup()

  # ... rest of supervision tree
end
```

**Custom Spans**:
```elixir
require OpenTelemetry.Tracer

def process_payment(order) do
  OpenTelemetry.Tracer.with_span "process_payment" do
    OpenTelemetry.Tracer.set_attributes([
      {"order.id", order.id},
      {"order.total", order.total}
    ])

    charge_card(order)
  end
end
```

**Sources**:
- [OpenTelemetry - Erlang/Elixir](https://opentelemetry.io/docs/instrumentation/erlang/)
- [Last9 - OpenTelemetry with Elixir](https://last9.io/blog/opentelemetry-with-elixir/)
- [Fly.io - OpenTelemetry and N+1](https://fly.io/phoenix-files/opentelemetry-and-the-infamous-n-plus-1/)

---

## 4. Graceful Degradation

### 4.1 Timeout Handling

**Philosophy**: Set explicit timeouts to prevent resource exhaustion when operations hang.

#### GenServer Timeouts

```elixir
# Call with timeout
GenServer.call(pid, :slow_operation, 5_000)  # 5 second timeout

# Default timeout: 5 seconds
GenServer.call(pid, :operation)

# Infinite timeout (dangerous!)
GenServer.call(pid, :operation, :infinity)
```

**Custom Timeout Handling**:
```elixir
defmodule MyGenServer do
  use GenServer

  # Handle call with custom timeout
  def handle_call(:slow_query, _from, state) do
    result = case Task.yield(Task.async(fn -> slow_query() end), 3_000) do
      {:ok, data} ->
        {:ok, data}
      nil ->
        # Task still running after 3s
        {:error, :timeout}
    end

    {:reply, result, state}
  end
end
```

**Source**: [DEV.to - Managing Timeouts in GenServer](https://dev.to/herminiotorres/managing-timeouts-in-genserver-in-elixir-how-to-control-waiting-time-in-critical-operations-25jc)

#### Task Timeouts

**Task.await with Timeout**:
```elixir
task = Task.async(fn -> expensive_operation() end)

try do
  result = Task.await(task, 5_000)  # 5 second timeout
  {:ok, result}
rescue
  :exit, {:timeout, _} ->
    Task.shutdown(task, :brutal_kill)  # Clean up the task
    {:error, :timeout}
end
```

**Task.async_stream with Timeout**:
```elixir
urls = ["url1", "url2", "url3"]

results = Task.async_stream(
  urls,
  &fetch_url/1,
  timeout: 5_000,        # Per-task timeout
  on_timeout: :kill_task # Kill tasks that timeout
)
|> Enum.to_list()
```

**Timeout Options**:
- `:kill_task` - Kill the timed-out task (default)
- `:exit` - Exit the stream

**Sources**:
- [Elixir Docs - Task](https://hexdocs.pm/elixir/Task.html)
- [Stack Overflow - Elixir Task Timeout](https://stackoverflow.com/questions/47947445/elixir-rescue-catch-task-timeout)

### 4.2 Partial Failure Handling

**Pattern**: Return partial results when some operations fail instead of failing completely.

```elixir
defmodule Dashboard do
  def load_dashboard_data(user_id) do
    # Start all operations concurrently
    tasks = [
      Task.async(fn -> fetch_user_stats(user_id) end),
      Task.async(fn -> fetch_recent_orders(user_id) end),
      Task.async(fn -> fetch_recommendations(user_id) end)
    ]

    # Collect results with timeouts
    results = tasks
    |> Enum.map(fn task ->
      case Task.yield(task, 3_000) || Task.shutdown(task) do
        {:ok, result} -> {:ok, result}
        nil -> {:error, :timeout}
      end
    end)

    # Return partial data
    %{
      user_stats: extract_result(Enum.at(results, 0), %{}),
      recent_orders: extract_result(Enum.at(results, 1), []),
      recommendations: extract_result(Enum.at(results, 2), [])
    }
  end

  defp extract_result({:ok, data}, _default), do: data
  defp extract_result({:error, _}, default), do: default
end
```

**Source**: [Google Groups - Graceful Degradation When Task Fails](https://groups.google.com/d/topic/elixir-lang-talk/rblNhLwYtuw)

### 4.3 Fallback Strategies

**Cache + Fallback Pattern**:
```elixir
defmodule ExternalData do
  def fetch_with_fallback(key) do
    case Cache.get(key) do
      nil ->
        # Try external service
        case fetch_from_api(key) do
          {:ok, data} ->
            Cache.put(key, data)
            {:ok, data}
          {:error, _} ->
            # Fallback to stale cache or default
            case Cache.get_stale(key) do
              nil -> {:ok, default_data()}
              stale -> {:ok, stale}
            end
        end
      cached ->
        {:ok, cached}
    end
  end
end
```

### 4.4 Graceful Shutdown

**Phoenix Shutdown Process**:
1. Stop accepting new connections
2. Finish in-progress requests
3. Drain active channels
4. Shut down processes

**Configuration**:
```elixir
# config/config.exs
config :my_app, MyAppWeb.Endpoint,
  http: [
    port: 4000,
    transport_options: [
      socket_opts: [:inet6],
      max_connections: :infinity,
      num_acceptors: 100
    ]
  ],
  server: true,
  # Graceful shutdown timeout
  shutdown: 30_000  # 30 seconds
```

**Plug.Cowboy.Drainer** (built-in):
- Automatically drains connections on shutdown
- Waits for in-flight requests to complete
- Respects shutdown timeout

**Custom Graceful Shutdown for GenServer**:
```elixir
defmodule MyWorker do
  use GenServer

  def terminate(reason, state) do
    # Clean up resources
    cleanup_connections(state.connections)
    flush_buffer(state.buffer)

    :ok
  end
end
```

**Sources**:
- [CodeSync - Graceful Shutdown in Elixir](https://codesync.global/media/graceful-shutdown-in-elixir-try-not-to-drop-the-ball/)
- [Elixir Merge - Graceful Shutdown in Phoenix](https://elixirmerge.com/p/implementing-graceful-shutdown-in-phoenix-applications)
- [GitHub Gist - Phoenix Drain Stop](https://gist.github.com/aaronjensen/33cc2aeb74746cac3bcb40dcefdd9c09)

### 4.5 Resource Exhaustion Prevention

#### Connection Pooling with Poolboy

**Why**: Limit concurrent connections to databases/external services.

**Installation**:
```elixir
{:poolboy, "~> 1.5"}
```

**Configuration**:
```elixir
defmodule MyApp.Application do
  def start(_type, _args) do
    poolboy_config = [
      name: {:local, :worker_pool},
      worker_module: MyApp.Worker,
      size: 10,              # 10 workers
      max_overflow: 5        # + 5 temporary workers under load
    ]

    children = [
      :poolboy.child_spec(:worker_pool, poolboy_config, [])
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

**Usage**:
```elixir
:poolboy.transaction(:worker_pool, fn pid ->
  GenServer.call(pid, {:process, data})
end, 5_000)  # 5 second checkout timeout
```

**Default Timeout**: 5 seconds - if no worker available, timeout error

**Source**: [Elixir School - Poolboy](https://elixirschool.com/en/lessons/misc/poolboy)

#### Task Concurrency Control

**Limit Concurrent Tasks**:
```elixir
# Process 1000 items with max 10 concurrent tasks
Task.async_stream(
  items,
  &process_item/1,
  max_concurrency: 10,  # System.schedulers_online/0 by default
  timeout: 30_000
)
|> Stream.run()
```

**Source**: [Elixir Docs - Task.async_stream](https://hexdocs.pm/elixir/Task.html#async_stream/3)

---

## 5. Testing Error Scenarios

### 5.1 Fault Injection

#### Library: `snabbkaffe` (Erlang)

**Advanced chaos engineering for Erlang/Elixir**.

**Installation**:
```elixir
{:snabbkaffe, "~> 1.0", only: :test}
```

**Fault Scenarios**:
```elixir
# Always crash
snabbkaffe_nemesis:always_crash()

# Recover after N failures
snabbkaffe_nemesis:recover_after(10)

# Random crash with 10% probability
snabbkaffe_nemesis:random_crash(0.1)

# Periodic crash
snabbkaffe_nemesis:periodic_crash()
```

**Inject Crash at Specific Trace Event**:
```elixir
?inject_crash(
  #{?snk_kind := database_query, table := users},
  snabbkaffe_nemesis:random_crash(0.2)
)
```

**Source**: [EMQ - Advanced Testing of Erlang/Elixir](https://www.emqx.com/en/blog/advanced-testing-of-erlang-and-elixir-applications)

### 5.2 Testing Timeouts

**Mock Slow Operations**:
```elixir
defmodule MyModuleTest do
  use ExUnit.Case

  test "handles timeout gracefully" do
    # Start slow operation
    task = Task.async(fn ->
      Process.sleep(10_000)  # Simulate slow operation
      :result
    end)

    # Expect timeout
    assert catch_exit(Task.await(task, 100)) == {:timeout, _}
  end

  test "task shutdown cleans up resources" do
    task = Task.async(fn ->
      Process.sleep(10_000)
    end)

    # Verify task is alive
    assert Process.alive?(task.pid)

    # Shutdown task
    Task.shutdown(task, :brutal_kill)

    # Verify cleanup
    refute Process.alive?(task.pid)
  end
end
```

**Source**: [Elixir Docs - Task Tests](https://github.com/elixir-lang/elixir/blob/main/lib/elixir/test/elixir/task_test.exs)

### 5.3 Testing Error Conditions with ExUnit

**Assert Errors Are Raised**:
```elixir
test "raises on invalid input" do
  assert_raise ArgumentError, "invalid user id", fn ->
    User.fetch!("invalid")
  end
end
```

**Pattern Match on Error Tuples**:
```elixir
test "returns error tuple on failure" do
  assert {:error, :not_found} = User.fetch(999)
end
```

**Testing Async Errors**:
```elixir
test "GenServer handles errors gracefully" do
  {:ok, pid} = MyGenServer.start_link()

  # Cause error
  send(pid, :bad_message)

  # Wait for error handling
  :timer.sleep(100)

  # Verify GenServer still alive (supervisor restarted it)
  assert Process.alive?(pid)
end
```

### 5.4 Mocking Failures with Mox

**Installation**:
```elixir
{:mox, "~> 1.0", only: :test}
```

**Define Behavior**:
```elixir
# lib/my_app/external_api.ex
defmodule MyApp.ExternalAPI do
  @callback fetch_data(id :: String.t()) :: {:ok, map()} | {:error, atom()}
end
```

**Create Mock**:
```elixir
# test/test_helper.exs
Mox.defmock(MyApp.MockExternalAPI, for: MyApp.ExternalAPI)
```

**Test Failure Scenarios**:
```elixir
defmodule MyModuleTest do
  use ExUnit.Case, async: true
  import Mox

  setup :verify_on_exit!

  test "handles API failure" do
    # Mock failure
    expect(MyApp.MockExternalAPI, :fetch_data, fn _id ->
      {:error, :timeout}
    end)

    # Verify graceful handling
    assert {:error, :timeout} = MyModule.process("123")
  end

  test "retries on failure" do
    # Mock 2 failures, then success
    MyApp.MockExternalAPI
    |> expect(:fetch_data, fn _id -> {:error, :timeout} end)
    |> expect(:fetch_data, fn _id -> {:error, :timeout} end)
    |> expect(:fetch_data, fn _id -> {:ok, %{data: "success"}} end)

    assert {:ok, _} = MyModule.process_with_retry("123")
  end
end
```

**Sources**:
- [Medium - Advanced Testing Strategies](https://medium.com/@jonnyeberhardt7/break-it-before-it-breaks-you-advanced-testing-strategies-in-elixir-513e24184666)
- [Mox Documentation](https://hexdocs.pm/mox/)

### 5.5 Property-Based Testing with StreamData

**Installation**:
```elixir
{:stream_data, "~> 1.0", only: :test}
```

**Test Error Handling with Random Inputs**:
```elixir
defmodule MyModuleTest do
  use ExUnit.Case
  use ExUnitProperties

  property "handles all integer inputs without crashing" do
    check all input <- integer() do
      # Should never crash, even with edge cases
      result = MyModule.process(input)
      assert result in [:ok, :error]
    end
  end

  property "validates email format" do
    check all email <- string(:printable) do
      case MyModule.validate_email(email) do
        {:ok, _} ->
          assert String.contains?(email, "@")
        {:error, _} ->
          refute String.contains?(email, "@")
      end
    end
  end
end
```

**Source**: [CloudDevs - Testing Elixir Applications](https://clouddevs.com/elixir/testing-applications/)

---

## 6. Production Deployment Best Practices

### 6.1 Erlang Releases

**Why**: Package application + dependencies + BEAM VM into single deployable artifact.

**Tools**:
- **Elixir Releases** (built-in since Elixir 1.9)
- **Distillery** (legacy, pre-1.9)

**Create Release**:
```bash
# Generate release configuration
mix release.init

# Build release
MIX_ENV=prod mix release
```

**Release Structure**:
```
_build/prod/rel/my_app/
├── bin/
│   └── my_app         # Start script
├── lib/
│   └── my_app-0.1.0/  # Application code
├── releases/
│   └── 0.1.0/
└── erts-13.0/         # Erlang runtime
```

**Advantages**:
- Self-contained (no Erlang/Elixir installation needed)
- Hot code upgrades
- Reduced startup time
- Production-optimized

**Source**: [Cogini - Best Practices for Deploying Elixir Apps](https://www.cogini.com/blog/best-practices-for-deploying-elixir-apps/)

### 6.2 Configuration Management

**Runtime Configuration** (`config/runtime.exs`):
```elixir
import Config

if config_env() == :prod do
  database_url = System.get_env("DATABASE_URL") ||
    raise "DATABASE_URL not set!"

  config :my_app, MyApp.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  config :my_app, MyAppWeb.Endpoint,
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE"),
    server: true
end
```

**Load Config in Supervisor**:
```elixir
defmodule MyApp.Application do
  def start(_type, _args) do
    # Load configuration
    database_url = Application.get_env(:my_app, MyApp.Repo)[:url]

    children = [
      {MyApp.Repo, url: database_url},
      # ...
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

**Source**: [MoldStud - Deployment Best Practices](https://moldstud.com/articles/p-what-are-the-best-practices-for-deploying-elixir-applications)

### 6.3 Health Checks

**Basic Health Endpoint**:
```elixir
# lib/my_app_web/router.ex
scope "/", MyAppWeb do
  get "/health", HealthController, :check
end

# lib/my_app_web/controllers/health_controller.ex
defmodule MyAppWeb.HealthController do
  use MyAppWeb, :controller

  def check(conn, _params) do
    # Check critical dependencies
    checks = %{
      database: check_database(),
      cache: check_cache(),
      external_api: check_external_api()
    }

    status = if all_healthy?(checks), do: 200, else: 503

    conn
    |> put_status(status)
    |> json(checks)
  end

  defp check_database do
    case Ecto.Adapters.SQL.query(Repo, "SELECT 1", []) do
      {:ok, _} -> %{status: "ok"}
      {:error, reason} -> %{status: "error", reason: inspect(reason)}
    end
  end

  defp all_healthy?(checks) do
    Enum.all?(checks, fn {_, %{status: status}} -> status == "ok" end)
  end
end
```

### 6.4 Error Monitoring Setup

**Production Checklist**:
1. ✅ Configure error reporting (Sentry/Honeybadger/AppSignal)
2. ✅ Set up structured logging
3. ✅ Configure telemetry handlers
4. ✅ Enable APM integration
5. ✅ Set alert thresholds

**Example Production Config**:
```elixir
# config/runtime.exs
if config_env() == :prod do
  # Error reporting
  config :sentry,
    dsn: System.fetch_env!("SENTRY_DSN"),
    environment_name: :prod,
    enable_source_code_context: true

  # Structured logging
  config :logger,
    backends: [LoggerJSON],
    level: :info

  # APM
  config :appsignal, :config,
    active: true,
    push_api_key: System.fetch_env!("APPSIGNAL_KEY")
end
```

**Source**: [TeamExtension - Deployment Best Practices](https://teamextension.blog/2023/06/16/elixir-deployment-and-production-best-practices/)

### 6.5 CI/CD Pipeline

**Example GitHub Actions**:
```yaml
name: CI/CD

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:14
        env:
          POSTGRES_PASSWORD: postgres
    steps:
      - uses: actions/checkout@v3
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.15'
          otp-version: '26'
      - run: mix deps.get
      - run: mix compile --warnings-as-errors
      - run: mix test

  deploy:
    needs: test
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - run: MIX_ENV=prod mix release
      - run: ./deploy.sh  # Your deployment script
```

**Source**: [CloudDevs - Error Handling and Fault Tolerance](https://clouddevs.com/elixir/error-handling-and-fault-tolerance/)

---

## 7. Libraries and Tools

### 7.1 Error Handling & Retry

| Library | Purpose | Link |
|---------|---------|------|
| **retry** | Retry with exponential backoff | [GitHub](https://github.com/safwank/ElixirRetry) |
| **gen_retry** | GenServer-based retry | [Hex](https://hex.pm/packages/gen_retry) |
| **fuse** | Circuit breaker (Erlang) | [GitHub](https://github.com/jlouis/fuse) |
| **external_service** | All-in-one: retry + rate limit + circuit breaker | [GitHub](https://github.com/jvoegele/external_service) |
| **breaker_box** | Elixir circuit breaker wrapper | [GitHub](https://github.com/DoggettCK/breaker_box) |
| **OK** | Result moads for error handling | [GitHub](https://github.com/CrowdHailer/OK) |

### 7.2 Observability

| Library | Purpose | Link |
|---------|---------|------|
| **telemetry** | Event dispatching | [Hex](https://hex.pm/packages/telemetry) |
| **logger_json** | Structured JSON logging | [Hex](https://hex.pm/packages/logger_json) |
| **opentelemetry** | Distributed tracing | [Hex](https://hex.pm/packages/opentelemetry) |
| **opentelemetry_phoenix** | Phoenix instrumentation | [Hex](https://hex.pm/packages/opentelemetry_phoenix) |
| **opentelemetry_ecto** | Ecto instrumentation | [Hex](https://hex.pm/packages/opentelemetry_ecto) |
| **opentelemetry_oban** | Oban instrumentation | [Hex](https://hex.pm/packages/opentelemetry_oban) |

### 7.3 Error Reporting Services

| Service | Best For | Elixir Support | Link |
|---------|----------|----------------|------|
| **AppSignal** | Elixir/Phoenix projects | Excellent | [appsignal.com](https://www.appsignal.com) |
| **Sentry** | Multi-language projects | Good | [sentry.io](https://sentry.io) |
| **Honeybadger** | Elixir teams | Excellent | [honeybadger.io](https://www.honeybadger.io) |

### 7.4 Background Jobs

| Library | Purpose | Link |
|---------|---------|------|
| **oban** | Database-backed job processing | [GitHub](https://github.com/oban-bg/oban) |
| **oban_pro** | Advanced Oban features | [oban.pro](https://oban.pro) |

### 7.5 Resource Management

| Library | Purpose | Link |
|---------|---------|------|
| **poolboy** | Worker pool management | [Hex](https://hex.pm/packages/poolboy) |
| **hammer** | Rate limiting | [Hex](https://hex.pm/packages/hammer) |

### 7.6 Testing

| Library | Purpose | Link |
|---------|---------|------|
| **mox** | Mock and stub testing | [Hex](https://hex.pm/packages/mox) |
| **stream_data** | Property-based testing | [Hex](https://hex.pm/packages/stream_data) |
| **snabbkaffe** | Fault injection & chaos testing | [Hex](https://hex.pm/packages/snabbkaffe) |

---

## Summary

### Key Takeaways

1. **Let It Crash (Properly)**: Use supervisors for unexpected errors, error tuples for expected ones
2. **Retry Smart**: Exponential backoff with jitter, circuit breakers for cascading failures
3. **Observe Everything**: Telemetry + structured logs + APM = comprehensive observability
4. **Fail Gracefully**: Timeouts, partial results, fallbacks prevent total failures
5. **Test Failures**: Fault injection, mocks, and property-based tests catch edge cases
6. **Deploy Safely**: Releases, health checks, CI/CD, monitoring from day one

### Quick Reference Patterns

**Error Handling**:
```elixir
# ✅ Expected errors: error tuples
{:ok, result} | {:error, reason}

# ✅ Unexpected errors: let it crash + supervisor
Supervisor.start_link(children, strategy: :one_for_one)

# ✅ External calls: circuit breaker + retry
:fuse.run(:external_api, fn -> make_request() end)
```

**Observability**:
```elixir
# ✅ Emit events
:telemetry.execute([:app, :operation], %{duration: 123}, %{user: 1})

# ✅ Structured logs
Logger.info("Operation complete", user_id: 1, duration: 123)

# ✅ Error reporting
Sentry.capture_exception(error, extra: %{context: "background_job"})
```

**Resilience**:
```elixir
# ✅ Timeouts
Task.await(task, 5_000)

# ✅ Partial results
Task.async_stream(items, &process/1, timeout: 3_000, on_timeout: :kill_task)

# ✅ Resource limits
Task.async_stream(items, &process/1, max_concurrency: 10)
```

---

## Additional Resources

### Official Documentation
- [Elixir Getting Started - Processes](https://elixir-lang.org/getting-started/processes.html)
- [Elixir Supervisor](https://hexdocs.pm/elixir/Supervisor.html)
- [Elixir Task](https://hexdocs.pm/elixir/Task.html)
- [Oban Documentation](https://hexdocs.pm/oban/)

### Books
- "Programming Elixir" by Dave Thomas
- "Designing Elixir Systems with OTP" by James Edward Gray II & Bruce Tate
- "Adopting Elixir" by Ben Marx, José Valim, & Bruce Tate

### Blogs & Articles
- [Elixir School](https://elixirschool.com/)
- [AppSignal Blog - Elixir Alchemy](https://blog.appsignal.com/elixir-alchemy)
- [Fly.io Phoenix Files](https://fly.io/phoenix-files/)

---

**Research compiled**: 2024-11-08
**Total sources reviewed**: 50+
**Focus areas**: Production-ready error handling, observability, and resilience patterns for Elixir background job systems
