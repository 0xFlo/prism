# Elixir Telemetry Best Practices

## Overview

Comprehensive guide to instrumenting Elixir applications with Telemetry, including metrics collection, observability patterns, and production monitoring strategies.

## Official Documentation

- **Telemetry Library**: https://hexdocs.pm/telemetry/telemetry.html
- **Phoenix Telemetry Guide**: https://hexdocs.pm/phoenix/telemetry.html
- **Telemetry Metrics**: https://hexdocs.pm/telemetry_metrics/
- **Phoenix LiveDashboard**: https://hexdocs.pm/phoenix_live_dashboard/
- **PromEx (Prometheus)**: https://hexdocs.pm/prom_ex/readme.html

---

## Core Concepts

### Event Naming Conventions

Events use lists of atoms following a hierarchical prefix pattern:

```elixir
# ✅ Good: Hierarchical naming
[:gsc_analytics, :api, :request]
[:gsc_analytics, :sync, :complete]
[:gsc_analytics, :http_check, :batch_start]

# ❌ Bad: Flat naming
[:api_request]
[:sync_complete]
```

**Standard Span Suffixes**:
```elixir
[:my_app, :operation, :start]     # Operation begins
[:my_app, :operation, :stop]      # Operation completes successfully
[:my_app, :operation, :exception] # Operation raises error
```

---

### Handler Performance

**✅ Always use function captures** for optimal performance:

```elixir
:telemetry.attach_many(
  "my-handler",
  events,
  &MyModule.handle_event/4,  # Function capture
  nil
)
```

**❌ Never use anonymous functions** (slower):

```elixir
:telemetry.attach_many(
  "my-handler",
  events,
  fn event, measurements, metadata, config ->
    # Handler logic
  end,
  nil
)
```

**Handler Signature**:
```elixir
def handle_event(event_name, measurements, metadata, config) do
  # event_name: [:gsc_analytics, :api, :request]
  # measurements: %{duration_ms: 1234, rows: 100}
  # metadata: %{operation: "fetch_urls", site_url: "..."}
  # config: Handler configuration passed during attach
end
```

**Critical Rules**:
- Handlers execute **synchronously** in the dispatching process
- Failed handlers are automatically removed
- A `[:telemetry, :handler, :failure]` event is emitted on handler failure
- **Do NOT rely on handler execution order**

---

### Measurements vs Metadata

**Measurements** (numeric values for aggregation):
```elixir
%{
  duration_ms: 1247,
  rows: 412,
  success_count: 398,
  error_count: 14,
  batch_count: 10
}
```

**Metadata** (contextual information for filtering/tagging):
```elixir
%{
  operation: "fetch_all_urls",
  site_url: "sc-domain:example.com",
  date: ~D[2024-01-15],
  rate_limited: false,
  batch_id: "http-check-1234",
  attempt: 1
}
```

---

## The Span Pattern

### Why Use Spans?

Spans automatically handle start/stop/exception events with proper duration tracking.

**Manual Pattern** (verbose, error-prone):
```elixir
start_time = System.monotonic_time(:millisecond)

try do
  result = do_work()
  duration_ms = System.monotonic_time(:millisecond) - start_time

  :telemetry.execute(
    [:my_app, :operation, :stop],
    %{duration_ms: duration_ms},
    %{result: :ok}
  )

  {:ok, result}
rescue
  error ->
    duration_ms = System.monotonic_time(:millisecond) - start_time

    :telemetry.execute(
      [:my_app, :operation, :exception],
      %{duration_ms: duration_ms},
      %{error: inspect(error)}
    )

    reraise error, __STACKTRACE__
end
```

**Span Pattern** (clean, automatic):
```elixir
:telemetry.span(
  [:my_app, :operation],
  %{system_time: System.system_time()},  # Start metadata
  fn ->
    result = do_work()

    # Return {result, stop_metadata}
    {result, %{rows_processed: 100}}
  end
)
```

### Emitted Events

1. **Start Event**: `[:my_app, :operation, :start]`
   - Measurements: `%{system_time: ..., monotonic_time: ...}`
   - Metadata: User-defined + `telemetry_span_context`

2. **Stop Event**: `[:my_app, :operation, :stop]`
   - Measurements: `%{duration: ..., monotonic_time: ...}`
   - Metadata: Start metadata + stop metadata + `telemetry_span_context`

3. **Exception Event**: `[:my_app, :operation, :exception]`
   - Measurements: `%{duration: ..., monotonic_time: ...}`
   - Metadata: `%{kind: :error, reason: ..., stacktrace: ...}`

**Duration**: Automatically computed as `monotonic_time_stop - monotonic_time_start` in native units.

---

## Instrumenting Different Components

### GenServers

```elixir
defmodule MyServer do
  use GenServer

  def handle_call(msg, _from, state) do
    {result, _meta} = :telemetry.span(
      [:my_app, :server, :call],
      %{message: msg},
      fn ->
        result = do_work(msg)
        {result, %{rows_processed: length(result)}}
      end
    )

    {:reply, result, state}
  end
end
```

---

### Oban Workers

**Current Pattern** (manual):
```elixir
@impl Oban.Worker
def perform(%Oban.Job{args: args} = job) do
  start_time = System.monotonic_time(:millisecond)

  # Emit start event
  :telemetry.execute(
    [:gsc_analytics, :http_check, :batch_start],
    %{url_count: url_count},
    %{batch_id: batch_id, attempt: job.attempt}
  )

  try do
    result = process_batch(args)
    duration_ms = System.monotonic_time(:millisecond) - start_time

    :telemetry.execute(
      [:gsc_analytics, :http_check, :batch_complete],
      %{duration_ms: duration_ms, success_count: ...},
      %{batch_id: batch_id}
    )

    :ok
  rescue
    error ->
      duration_ms = System.monotonic_time(:millisecond) - start_time

      :telemetry.execute(
        [:gsc_analytics, :http_check, :batch_failed],
        %{duration_ms: duration_ms},
        %{batch_id: batch_id, error: inspect(error)}
      )

      reraise error, __STACKTRACE__
  end
end
```

**Recommended Pattern** (span):
```elixir
@impl Oban.Worker
def perform(%Oban.Job{args: args} = job) do
  :telemetry.span(
    [:gsc_analytics, :http_check, :batch],
    %{
      batch_id: args["batch_id"],
      attempt: job.attempt,
      url_count: length(args["urls"])
    },
    fn ->
      result = process_batch(args)

      # Return result + stop metadata
      {result, %{
        success_count: count_successes(result),
        error_count: count_errors(result)
      }}
    end
  )
end
```

---

### Concurrent Task Instrumentation

```elixir
def fetch_batch_performance(urls, opts \\ []) do
  :telemetry.span(
    [:gsc_analytics, :api, :batch_fetch],
    %{url_count: length(urls)},
    fn ->
      results =
        urls
        |> Task.async_stream(
          fn url ->
            :telemetry.span(
              [:gsc_analytics, :api, :single_fetch],
              %{url: url},
              fn ->
                result = fetch_url_data(url)
                {result, %{rows: length(result)}}
              end
            )
          end,
          max_concurrency: 10,
          timeout: 30_000
        )
        |> Enum.to_list()

      {results, %{success_count: count_ok(results)}}
    end
  )
end
```

**Note**: Telemetry events are process-local. For distributed tracing across processes, use OpenTelemetry.

---

## Telemetry.Metrics

### Metric Types

```elixir
defmodule MyApp.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def metrics do
    [
      # Counter: Total count of events
      counter("gsc_analytics.http_check.batch.stop.count",
        tags: [:priority],
        description: "Total HTTP check batches completed"
      ),

      # Sum: Accumulate measurement values
      sum("gsc_analytics.http_check.batch.stop.url_count",
        tags: [:batch_id],
        description: "Total URLs checked"
      ),

      # Last Value: Most recent measurement
      last_value("vm.memory.total",
        unit: {:byte, :megabyte}
      ),

      # Summary: Statistical distribution (min, max, avg)
      summary("gsc_analytics.http_check.batch.stop.duration",
        unit: {:native, :millisecond},
        tags: [:priority],
        description: "HTTP check batch duration distribution"
      ),

      # Distribution: Histogram buckets
      distribution("phoenix.router_dispatch.stop.duration",
        unit: {:native, :millisecond},
        buckets: [100, 300, 500, 1000, 3000, 5000],
        tags: [:route, :method]
      )
    ]
  end
end
```

---

### LiveDashboard Integration

Built-in for Phoenix 1.5+:

```elixir
# router.ex
scope "/" do
  pipe_through :browser

  live_dashboard "/dashboard",
    metrics: MyAppWeb.Telemetry,
    additional_pages: [
      my_custom_page: MyApp.CustomLiveDashboardPage
    ]
end
```

LiveDashboard automatically consumes `Telemetry.Metrics` and renders real-time charts.

---

## PromEx for Production Monitoring

### Setup

```elixir
# mix.exs
{:prom_ex, "~> 1.11"}

# application.ex
children = [
  MyApp.PromEx,
  # ... other children
]

# lib/my_app/prom_ex.ex
defmodule MyApp.PromEx do
  use PromEx, otp_app: :my_app

  @impl true
  def plugins do
    [
      PromEx.Plugins.Application,
      PromEx.Plugins.Beam,
      {PromEx.Plugins.Phoenix, router: MyAppWeb.Router},
      {PromEx.Plugins.Ecto, repos: [MyApp.Repo]},
      {PromEx.Plugins.Oban, oban_supervisors: [{Oban, :default}]},

      # Custom metrics
      MyApp.CustomMetricsPlugin
    ]
  end

  @impl true
  def dashboard_assigns, do: [
    datasource_id: "prometheus",
    default_selected_interval: "30s"
  ]
end
```

**Benefits**:
- Instant Grafana dashboards for Phoenix, Ecto, Oban
- Prometheus metrics export at `/metrics`
- Zero-config monitoring
- Production-grade observability

---

## Custom Metrics Plugin

```elixir
defmodule MyApp.CustomMetricsPlugin do
  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    Event.build(
      :my_app_event_metrics,
      [
        # Counter metrics
        counter(
          [:gsc_analytics, :api, :request, :count],
          event_name: [:gsc_analytics, :api, :request],
          description: "Total GSC API requests",
          measurement: :rows,
          tags: [:operation, :rate_limited]
        ),

        # Histogram metrics
        distribution(
          [:gsc_analytics, :api, :request, :duration, :milliseconds],
          event_name: [:gsc_analytics, :api, :request],
          description: "GSC API request duration",
          measurement: :duration,
          unit: {:native, :millisecond},
          reporter_options: [
            buckets: [10, 100, 500, 1000, 2000, 5000, 10000]
          ],
          tags: [:operation]
        ),

        # Sum metrics
        sum(
          [:gsc_analytics, :sync, :complete, :total_urls],
          event_name: [:gsc_analytics, :sync, :complete],
          description: "Total URLs synced",
          measurement: :total_urls,
          tags: [:site_url]
        )
      ]
    )
  end

  @impl true
  def polling_metrics(_opts) do
    Polling.build(
      :my_app_polling_metrics,
      poll_rate: 5_000,
      [
        # Custom business metrics
        last_value(
          [:gsc_analytics, :queue, :depth],
          mfa: {__MODULE__, :measure_sync_queue_depth, []},
          description: "Oban sync queue depth"
        ),

        last_value(
          [:gsc_analytics, :urls, :stale_count],
          mfa: {__MODULE__, :measure_stale_urls, []},
          description: "URLs not checked in 7+ days"
        )
      ]
    )
  end

  def measure_sync_queue_depth do
    count = Oban.Job
      |> where([j], j.queue == "gsc_sync" and j.state in ["available", "scheduled"])
      |> Repo.aggregate(:count)

    %{count: count}
  end

  def measure_stale_urls do
    seven_days_ago = DateTime.add(DateTime.utc_now(), -7, :day)

    count = from(p in Performance,
      where: is_nil(p.http_checked_at) or p.http_checked_at < ^seven_days_ago,
      select: count()
    )
    |> Repo.one()

    %{count: count}
  end
end
```

---

## Periodic Measurements

```elixir
defmodule MyAppWeb.Telemetry do
  use Supervisor

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp periodic_measurements do
    [
      # VM measurements
      {__MODULE__, :measure_vm_info, []},

      # Custom business metrics
      {GscAnalytics.Metrics, :measure_sync_queue_depth, []},
      {GscAnalytics.Metrics, :measure_stale_urls_count, []},
      {GscAnalytics.Metrics, :measure_coordinator_mailbox, []}
    ]
  end

  def measure_vm_info do
    :telemetry.execute(
      [:vm, :memory],
      :erlang.memory(),
      %{}
    )
  end
end
```

---

## Testing Telemetry

### Unit Testing Event Emission

```elixir
defmodule MyAppTest do
  use ExUnit.Case, async: true

  test "emits telemetry event on success" do
    # Attach test handler
    ref = :telemetry_test.attach_event_handlers(self(), [
      [:my_app, :operation, :stop]
    ])

    # Execute operation
    MyApp.do_work()

    # Assert event was emitted
    assert_receive {
      [:my_app, :operation, :stop],
      %{duration: duration},
      %{result: :ok}
    }

    assert duration > 0

    :telemetry.detach(ref)
  end
end
```

---

### Integration Testing with Handlers

```elixir
test "handler processes events correctly" do
  # Track handler calls
  test_pid = self()

  :telemetry.attach(
    "test-handler",
    [:my_app, :operation, :stop],
    fn event, measurements, metadata, _ ->
      send(test_pid, {:telemetry_event, event, measurements, metadata})
    end,
    nil
  )

  MyApp.do_work()

  assert_receive {:telemetry_event, [:my_app, :operation, :stop], %{duration: _}, %{}}

  :telemetry.detach("test-handler")
end
```

---

## OpenTelemetry Integration

For distributed tracing across services:

```elixir
# mix.exs
{:opentelemetry, "~> 1.3"},
{:opentelemetry_exporter, "~> 1.6"},
{:opentelemetry_phoenix, "~> 1.1"},
{:opentelemetry_ecto, "~> 1.1"}

# config/runtime.exs
config :opentelemetry, :resource,
  service: [
    name: "gsc_analytics",
    version: Application.spec(:gsc_analytics, :vsn)
  ]

config :opentelemetry, :processors,
  otel_batch_processor: %{
    exporter: {:otel_exporter_stdout, []}  # Or Jaeger, Zipkin, etc.
  }

# application.ex
def start(_type, _args) do
  OpentelemetryPhoenix.setup()
  OpentelemetryEcto.setup([:gsc_analytics, :repo])

  children = [
    # ... rest of children
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

**Benefits**:
- Distributed tracing across services
- Context propagation across processes
- Integration with Jaeger, Zipkin, Honeycomb
- Standardized observability

**Overhead**: ~5-10% with sampling

---

## Performance Considerations

### Measurement Overhead

Telemetry has minimal overhead:
- Event dispatch: **~1-2 microseconds**
- Monotonic time: **~100 nanoseconds**

### Optimization Tips

1. **Use `:telemetry.span/3`** instead of manual start/stop
2. **Avoid expensive computations in metadata** - compute in handler if needed
3. **Use sampling for high-frequency events**:

```elixir
def maybe_emit_telemetry(event, measurements, metadata) do
  # Only emit 1% of events
  if :rand.uniform(100) == 1 do
    :telemetry.execute(event, measurements, metadata)
  end
end
```

4. **OpenTelemetry sampling**:

```elixir
config :opentelemetry,
  sampler: {:parent_based, {:trace_id_ratio_based, 0.1}}  # Sample 10%
```

---

## Recommendations for GSC Analytics

### 1. Add Metrics to Telemetry Module

```elixir
# lib/gsc_analytics_web/telemetry.ex
def metrics do
  [
    # ... existing Phoenix/Ecto metrics ...

    # GSC API Metrics
    counter("gsc_analytics.api.request.count",
      tags: [:operation, :rate_limited],
      description: "Total GSC API requests"
    ),

    summary("gsc_analytics.api.request.duration",
      unit: {:native, :millisecond},
      tags: [:operation],
      description: "GSC API request duration"
    ),

    sum("gsc_analytics.api.request.rows",
      tags: [:operation],
      description: "Total rows fetched from GSC API"
    ),

    # Sync Metrics
    counter("gsc_analytics.sync.complete.count",
      tags: [:site_url],
      description: "Total sync operations completed"
    ),

    summary("gsc_analytics.sync.complete.duration",
      unit: {:native, :millisecond},
      description: "Sync operation duration"
    ),

    # HTTP Check Metrics
    counter("gsc_analytics.http_check.batch.stop.count",
      tags: [:priority],
      description: "HTTP check batches completed"
    ),

    distribution("gsc_analytics.http_check.batch.stop.duration",
      unit: {:native, :millisecond},
      buckets: [100, 500, 1000, 2000, 5000, 10000],
      description: "HTTP check batch duration"
    )
  ]
end
```

### 2. Refactor to Use Spans

Replace manual try/rescue with `:telemetry.span/3` in:
- `HttpStatusCheckWorker.perform/1`
- `Core.Sync.sync_date_range/4`
- `BatchProcessor` operations

### 3. Add Periodic Measurements

```elixir
defp periodic_measurements do
  [
    # Process info
    {__MODULE__, :measure_vm_info, []},

    # Custom business metrics
    {GscAnalytics.Metrics, :measure_sync_queue_depth, []},
    {GscAnalytics.Metrics, :measure_stale_urls_count, []},
    {GscAnalytics.Metrics, :measure_coordinator_mailbox, []}
  ]
end
```

### 4. Consider PromEx for Production

Provides instant Grafana dashboards and Prometheus integration with minimal setup.

---

## Key Takeaways

1. **Use `:telemetry.span/3`** - Automatic start/stop/exception handling
2. **Define Telemetry.Metrics** - Enable LiveDashboard and PromEx
3. **Function captures for handlers** - Optimal performance
4. **Separate measurements from metadata** - Numeric vs contextual
5. **Follow naming conventions** - `[:app, :component, :operation, :stage]`
6. **Handlers execute synchronously** - Keep them fast
7. **PromEx for production** - Grafana dashboards with zero config

---

## Resources

### Official Documentation
- **Telemetry**: https://hexdocs.pm/telemetry/telemetry.html
- **Phoenix Telemetry**: https://hexdocs.pm/phoenix/telemetry.html
- **Telemetry.Metrics**: https://hexdocs.pm/telemetry_metrics/
- **PromEx**: https://hexdocs.pm/prom_ex/readme.html
- **OpenTelemetry**: https://opentelemetry.io/docs/instrumentation/erlang/

### Community Guides
- **Thoughtbot**: https://thoughtbot.com/blog/instrumenting-your-phoenix-application-using-telemetry
- **Elixir School Part 1**: https://elixirschool.com/blog/instrumenting-phoenix-with-telemetry-part-one
- **Elixir School Part 2**: https://elixirschool.com/blog/instrumenting_phoenix_with_telemetry_part_two
- **Telemetry Conventions**: https://keathley.io/blog/telemetry-conventions.html
