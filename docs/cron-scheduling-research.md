# Cron Expression Syntax and Scheduling Best Practices

**Research Date:** 2025-11-08
**Focus:** Elixir/Oban scheduling for data pipeline jobs

---

## Table of Contents

1. [Cron Syntax](#cron-syntax)
2. [Elixir Scheduling Libraries](#elixir-scheduling-libraries)
3. [Best Practices](#best-practices)
4. [Monitoring and Alerting](#monitoring-and-alerting)

---

## 1. Cron Syntax

### Standard Format: 5 vs 6 Fields

#### Unix/Linux Cron (5 Fields)
```
┌───────────── minute (0-59)
│ ┌─────────── hour (0-23)
│ │ ┌───────── day of month (1-31)
│ │ │ ┌─────── month (1-12)
│ │ │ │ ┌───── day of week (0-7, Sunday=0 or 7)
│ │ │ │ │
* * * * * <command>
```

**Limitations:**
- No second precision (minimum 1 minute)
- Standard for system cron and most scheduling tools

#### Spring/Quartz Cron (6 Fields)
```
┌─────────────── second (0-59)
│ ┌───────────── minute (0-59)
│ │ ┌─────────── hour (0-23)
│ │ │ ┌───────── day of month (1-31)
│ │ │ │ ┌─────── month (1-12)
│ │ │ │ │ ┌───── day of week (0-7)
│ │ │ │ │ │
* * * * * * <command>
```

**Key Differences:**
- Adds seconds field at the beginning
- Used by Spring Framework, Quartz scheduler
- To convert 5-field to 6-field, prepend `0` or `*` for seconds

**Oban Uses:** 5-field standard Unix format

---

### Common Patterns

#### Hourly Schedules
```bash
# Every minute
* * * * *

# Every 5 minutes
*/5 * * * *

# Every 15 minutes
*/15 * * * *

# Every 30 minutes
*/30 * * * *

# Every hour (on the hour)
0 * * * *

# Every 2 hours
0 */2 * * *
```

#### Daily Schedules
```bash
# Daily at midnight
0 0 * * *

# Every morning at 8am
0 8 * * *

# Every night at 1am
0 1 * * *

# Every weekday at 9am
0 9 * * 1-5

# Every weekend at midnight
0 0 * * 0,6
```

#### Weekly & Monthly
```bash
# Weekly (Sundays at midnight)
0 0 * * 0

# Every Monday at noon
0 12 * * 1

# First day of month
0 0 1 * *

# Every 6 months
0 0 1 */6 *

# Annually (January 1st)
0 0 1 1 *
```

#### Special Characters

- `*` — All valid values for field
- `-` — Range (e.g., `1-5` for Mon-Fri)
- `,` — List (e.g., `0,6` for Sun and Sat)
- `/` — Step values (e.g., `*/15` for every 15 minutes)

---

### Special Nicknames (Oban Support)

Oban.Plugins.Cron supports these convenient aliases:

```elixir
@yearly      # "0 0 1 1 *"   (also @annually)
@monthly     # "0 0 1 * *"
@weekly      # "0 0 * * 0"
@daily       # "0 0 * * *"   (also @midnight)
@hourly      # "0 * * * *"
@reboot      # Execute once at startup (requires leadership)
```

**Source:** https://hexdocs.pm/oban/Oban.Plugins.Cron.html

---

### Timezone Considerations

#### Default Behavior
- **Unix cron:** Uses system timezone
- **Oban.Plugins.Cron:** Defaults to `Etc/UTC`

#### UTC Best Practice
- Use UTC for server timezone to avoid DST issues
- All jobs run in UTC time
- Convert to local time in application layer if needed

#### Custom Timezones in Oban

```elixir
config :my_app, Oban,
  plugins: [
    {Oban.Plugins.Cron,
     timezone: "America/Chicago",  # Requires tzdata dependency
     crontab: [
       {"0 9 * * *", MyApp.MorningJob}  # 9am Central Time
     ]}
  ]
```

**Requirements:**
- Install `tz` or `tzdata` package
- Configure timezone database in `config.exs`
- All jobs in crontab use same timezone

**Job Metadata:**
```elixir
%Oban.Job{
  meta: %{
    "cron" => true,
    "cron_expr" => "0 9 * * *",
    "cron_tz" => "America/Chicago"
  }
}
```

---

### Daylight Saving Time (DST) Handling

#### How Modern Cron Handles DST

**Spring Forward (clock moves ahead 1 hour):**
- Jobs scheduled during skipped hour run immediately after transition
- Example: 2:30am job runs at 3:01am when clock jumps 2am → 3am

**Fall Back (clock repeats 1 hour):**
- Jobs scheduled during repeated hour run only once
- Cron prevents duplicate executions

**Note:** Special handling only applies to time changes <3 hours

**Source:** https://blog.healthchecks.io/2021/10/how-debian-cron-handles-dst-transitions/

#### Best Practices for DST

1. **Use UTC timezone** (no DST transitions)
2. **Avoid 2-3am scheduling** in DST-observing timezones
3. **Use application-level scheduling** for local time requirements
4. **Test around DST transitions** (spring/fall)

---

## 2. Elixir Scheduling Libraries

### Oban.Plugins.Cron

**Type:** Database-backed job queue with cron scheduling
**Best For:** Production applications requiring durability, retries, observability

#### Configuration

```elixir
# config/config.exs
config :my_app, Oban,
  repo: MyApp.Repo,
  plugins: [
    {Oban.Plugins.Cron,
     timezone: "Etc/UTC",
     crontab: [
       # Basic format: {expression, worker}
       {"* * * * *", MyApp.MinuteWorker},

       # With custom args
       {"0 * * * *", MyApp.HourlyWorker, args: %{custom: "arg"}},

       # With job options
       {"0 0 * * *", MyApp.DailyWorker,
         max_attempts: 1,
         queue: :scheduled,
         tags: ["daily", "critical"]},

       # Using nicknames
       {"@daily", MyApp.BackupWorker}
     ]}
  ],
  queues: [default: 10, scheduled: 5]
```

#### Key Features

**Distributed Job Prevention:**
- Only leader node inserts cron jobs
- Prevents duplicate job creation across cluster
- Leadership election automatic via database

**Job Identification:**
```elixir
# All cron jobs marked with metadata
meta: %{
  "cron" => true,
  "cron_expr" => "@daily",
  "cron_tz" => "Etc/UTC"
}
```

**Expression Validation:**
```elixir
# Validate before deployment
iex> Oban.Plugins.Cron.parse("@hourly")
{:ok, #Oban.Cron.Expression<...>}

iex> Oban.Plugins.Cron.parse("60 * * * *")
{:error, %ArgumentError{message: "expression field 60 is out of range 0..59"}}
```

**Overlapping Job Prevention:**
```elixir
defmodule MyApp.LongRunningWorker do
  use Oban.Worker,
    queue: :scheduled,
    unique: [period: 3600, states: [:available, :scheduled, :executing]]

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    # Job won't start if previous instance still running
    :ok
  end
end
```

**Advantages:**
- Database persistence (survives restarts)
- Built-in retry logic with exponential backoff
- Telemetry integration for monitoring
- No duplicate jobs in distributed systems
- Job history and metrics
- Error tracking and debugging

**Limitations:**
- Requires database (PostgreSQL, MySQL, SQLite3)
- Minimum interval: 1 minute (no sub-minute scheduling)
- Pro version required for dynamic runtime scheduling

**Sources:**
- https://hexdocs.pm/oban/Oban.Plugins.Cron.html
- https://hexdocs.pm/oban/periodic_jobs.html

---

### Quantum Scheduler

**Type:** GenServer-based in-memory scheduler
**Best For:** Simple cron jobs, lightweight applications, development

#### Configuration

```elixir
# config/config.exs
config :my_app, MyApp.Scheduler,
  timezone: "America/Chicago",
  overlap: false,  # Prevent job overlap
  timeout: 30_000,  # GenServer call timeout
  jobs: [
    {"0 * * * *", {MyApp.Tasks, :hourly_job, []}},
    {"@daily", {MyApp.Tasks, :daily_cleanup, []}}
  ]

# lib/my_app/scheduler.ex
defmodule MyApp.Scheduler do
  use Quantum, otp_app: :my_app
end

# lib/my_app/application.ex
def start(_type, _args) do
  children = [
    MyApp.Repo,
    MyApp.Scheduler  # Add to supervision tree
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

#### Key Features

**Overlap Prevention:**
```elixir
config :my_app, MyApp.Scheduler,
  jobs: [
    {"* * * * *", {MyApp.Tasks, :task, []}, overlap: false}
  ]
```
- Set `overlap: false` to prevent next run if previous still executing
- Default is `true` (allows overlapping executions)

**Runtime Job Management:**
```elixir
# Add job dynamically
MyApp.Scheduler.new_job()
|> Quantum.Job.set_schedule(Crontab.CronExpression.Parser.parse!("*/5 * * * *"))
|> Quantum.Job.set_task({MyApp.Tasks, :dynamic_task, []})
|> MyApp.Scheduler.add_job()

# Delete job
MyApp.Scheduler.delete_job(job_name)
```

**Clustering Considerations:**
```elixir
config :my_app, MyApp.Scheduler,
  global: true  # Run as globally unique process across cluster
```
- Prevents same job running on multiple nodes
- Uses global process registration

**Advantages:**
- No database required
- Simple setup
- Runtime job management
- Lightweight

**Limitations:**
- Jobs lost on restart (no persistence)
- No retry logic (must implement manually)
- No job history
- Clustering requires configuration
- GenServer timeout issues under heavy load

**Sources:**
- https://github.com/quantum-elixir/quantum-core
- https://hexdocs.pm/quantum/configuration.html

---

### Comparison: Oban vs Quantum

| Feature | Oban.Plugins.Cron | Quantum |
|---------|-------------------|---------|
| **Persistence** | Database-backed | In-memory only |
| **Retry Logic** | Built-in with backoff | Manual implementation |
| **Job History** | Full audit trail | None |
| **Clustering** | Automatic via DB | Requires global config |
| **Monitoring** | Telemetry + metrics | Manual logging |
| **Min Interval** | 1 minute | 1 minute |
| **Setup Complexity** | Medium (needs DB) | Low |
| **Production Ready** | Yes | Limited |
| **Dependencies** | PostgreSQL/MySQL/SQLite | None |
| **Error Handling** | Comprehensive | Basic |

**Recommendation for Prism Project:**
- **Use Oban** for GSC sync jobs (already using Oban, needs persistence/retries)
- **Use Quantum** for lightweight tasks (if any non-critical scheduled tasks)

**Hybrid Approach (from community):**
> "Quantum takes cron config, and if the action is super fast, they just do it, but if it may fail or can take a while, they have Quantum simply enqueue an Oban job."

---

## 3. Best Practices

### Scheduling Frequency

#### General Guidelines

**Data Pipeline Jobs:**
- **High-frequency (every 5-15 min):** Real-time dashboards, alerts
- **Medium-frequency (hourly):** Analytics aggregation, metric updates
- **Low-frequency (daily):** Reports, backups, cleanup jobs
- **Weekly/Monthly:** Historical archives, compliance reports

**Minimum Intervals:**
- **Oban/Quantum:** 1 minute
- **AWS Data Pipeline:** 15 minutes
- **Sub-minute needs:** Use separate task scheduler or polling GenServer

**Source:** https://www.datacamp.com/tutorial/cron-job-in-data-engineering

#### GSC Sync Recommendations

Based on Google Search Console data characteristics:

```elixir
# Recommended schedule for Prism project
config :gsc_analytics, Oban,
  plugins: [
    {Oban.Plugins.Cron,
     timezone: "Etc/UTC",
     crontab: [
       # Daily sync at 4am UTC (after GSC data finalization)
       {"0 4 * * *", GscAnalytics.Workers.DailySyncWorker,
         max_attempts: 3,
         queue: :gsc_sync,
         tags: ["daily", "gsc"]},

       # Weekly full history validation (Sundays at 2am UTC)
       {"0 2 * * 0", GscAnalytics.Workers.HistoryValidationWorker,
         max_attempts: 1,
         queue: :gsc_sync,
         tags: ["weekly", "validation"]},

       # HTTP status checks (daily at 6am UTC, after sync)
       {"0 6 * * *", GscAnalytics.Workers.URLHealthCheckWorker,
         max_attempts: 2,
         queue: :crawler,
         tags: ["daily", "crawler"]}
     ]}
  ],
  queues: [
    gsc_sync: 1,    # Serial processing to respect rate limits
    crawler: 10     # Concurrent URL checks
  ]
```

**Rationale:**
- GSC has 3-day data delay (today's data finalized in ~72 hours)
- Daily sync captures yesterday's finalized data
- 4am UTC avoids peak hours
- HTTP checks run after sync to validate newly discovered URLs
- Serial queue for GSC API (respects rate limits)
- Concurrent queue for HTTP checks (independent requests)

---

### Avoiding Overlapping Jobs

#### Problem

Long-running jobs can overlap if:
- Job execution time > scheduling interval
- Example: Job scheduled every 1 hour takes 90 minutes

#### Solution 1: Oban Unique Jobs

```elixir
defmodule MyApp.SyncWorker do
  use Oban.Worker,
    queue: :gsc_sync,
    unique: [
      period: :infinity,  # Duration of uniqueness
      states: [:available, :scheduled, :executing]  # Check all states
    ]

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    # Long-running sync operation
    # Won't start if another instance in any of the unique states
    :ok
  end
end
```

**Unique Options:**
- `period: 3600` — 1 hour uniqueness window
- `period: :infinity` — Only one job ever (until completion)
- `states: [:executing]` — Prevent only concurrent execution
- `states: [:available, :scheduled, :executing]` — Prevent queuing new jobs

**Source:** https://hexdocs.pm/oban/Oban.html

#### Solution 2: Quantum Overlap Flag

```elixir
config :my_app, MyApp.Scheduler,
  jobs: [
    {"0 * * * *", {MyApp.Tasks, :long_task, []}, overlap: false}
  ]
```

#### Solution 3: External Locking

```elixir
defmodule MyApp.SyncWorker do
  use Oban.Worker

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case acquire_lock() do
      {:ok, lock} ->
        try do
          perform_sync()
        after
          release_lock(lock)
        end

      {:error, :locked} ->
        # Skip this run
        {:ok, :skipped_locked}
    end
  end

  defp acquire_lock do
    # Use database advisory lock, Redis, etc.
    Postgrex.query(MyApp.Repo, "SELECT pg_try_advisory_lock(12345)")
  end
end
```

---

### Distributed System Considerations

#### Oban Cluster Behavior

**Automatic Leader Election:**
- Only leader node inserts cron jobs
- Leadership determined via database
- Automatic failover if leader crashes
- No configuration required

**Job Distribution:**
- All nodes poll database for jobs
- Jobs distributed across available nodes
- Queue-based load balancing

**Example Multi-Node Setup:**
```elixir
# Same config on all nodes
config :gsc_analytics, Oban,
  repo: GscAnalytics.Repo,
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [{"0 * * * *", MyApp.Worker}]}  # Only inserted once by leader
  ],
  queues: [default: 10]  # All nodes process from shared queue
```

**Source:** https://hexdocs.pm/oban/Oban.Plugins.Cron.html

#### Quantum Cluster Behavior

**Default (Replicated Execution):**
- Each node runs jobs independently
- Same job executes on all nodes
- Can cause duplicate work

**Global Mode:**
```elixir
config :my_app, MyApp.Scheduler,
  global: true  # Only one scheduler across cluster
```

**Problem:** If global node crashes, jobs stop until restart

**Alternative (Manual Coordination):**
```elixir
# Only run on specific node
if Node.self() == :"primary@hostname" do
  # Run job
end
```

**Source:** https://medium.com/@deniel_chiang/elixir-phoenix-make-sure-uniqueness-quantum-job-on-fly-io-cluster-f940ceb89caa

---

### Error Handling and Retries

#### Oban Built-in Retries

```elixir
defmodule MyApp.SyncWorker do
  use Oban.Worker,
    max_attempts: 5,      # Total attempts (including initial)
    priority: 0,          # 0 (highest) to 3 (lowest)
    unique: [period: 60]  # Prevent duplicates

  @impl Oban.Worker
  def perform(%Oban.Job{attempt: attempt} = job) do
    case GscAnalytics.Core.Sync.sync_yesterday() do
      {:ok, result} ->
        {:ok, result}

      {:error, :rate_limited} ->
        # Snooze for 5 minutes and retry
        {:snooze, 300}

      {:error, :temporary} when attempt < 3 ->
        # Retry with exponential backoff
        {:error, :temporary}

      {:error, :permanent} ->
        # Don't retry, mark as failed
        {:discard, :permanent_error}
    end
  end
end
```

**Retry Behavior:**
- Automatic exponential backoff: `attempt^4 + 15 + jitter`
- Attempt 1: 16s, Attempt 2: 31s, Attempt 3: 96s, etc.
- `{:snooze, seconds}` — Custom delay before retry
- `{:discard, reason}` — Mark complete without retry

**Source:** https://hexdocs.pm/oban/Oban.Worker.html

#### Quantum Manual Retries

```elixir
defmodule MyApp.Tasks do
  require Logger

  def scheduled_task do
    retry_with_backoff(fn -> perform_work() end, max_attempts: 3)
  end

  defp retry_with_backoff(fun, opts) do
    max_attempts = Keyword.get(opts, :max_attempts, 3)

    Enum.reduce_while(1..max_attempts, nil, fn attempt, _acc ->
      case fun.() do
        {:ok, result} -> {:halt, {:ok, result}}
        {:error, reason} ->
          delay = :math.pow(2, attempt) * 1000 |> round()
          Logger.warning("Attempt #{attempt} failed: #{inspect(reason)}, retrying in #{delay}ms")
          Process.sleep(delay)
          if attempt == max_attempts, do: {:halt, {:error, reason}}, else: {:cont, nil}
      end
    end)
  end
end
```

---

### Logging Best Practices

#### Oban Structured Logging

```elixir
# Attach telemetry handler
:telemetry.attach_many(
  "gsc-job-logger",
  [
    [:oban, :job, :start],
    [:oban, :job, :stop],
    [:oban, :job, :exception]
  ],
  &MyApp.ObanLogger.handle_event/4,
  %{}
)

defmodule MyApp.ObanLogger do
  require Logger

  def handle_event([:oban, :job, :start], measurements, metadata, _config) do
    Logger.info("[Oban] Job started",
      worker: metadata.job.worker,
      attempt: metadata.job.attempt,
      queue: metadata.job.queue
    )
  end

  def handle_event([:oban, :job, :stop], measurements, metadata, _config) do
    Logger.info("[Oban] Job completed",
      worker: metadata.job.worker,
      duration_ms: div(measurements.duration, 1_000_000),
      queue_time_ms: div(measurements.queue_time, 1_000_000)
    )
  end

  def handle_event([:oban, :job, :exception], measurements, metadata, _config) do
    Logger.error("[Oban] Job failed",
      worker: metadata.job.worker,
      attempt: metadata.job.attempt,
      kind: metadata.kind,
      reason: inspect(metadata.reason),
      stacktrace: Exception.format_stacktrace(metadata.stacktrace)
    )
  end
end
```

**Source:** https://hexdocs.pm/oban/Oban.Telemetry.html

#### Quantum Logging

```elixir
defmodule MyApp.Tasks do
  require Logger

  def scheduled_task do
    start_time = System.monotonic_time()

    Logger.info("[Scheduler] Task started", task: :scheduled_task)

    try do
      result = perform_work()
      duration_ms = System.monotonic_time() - start_time |> div(1_000_000)
      Logger.info("[Scheduler] Task completed", task: :scheduled_task, duration_ms: duration_ms)
      result
    rescue
      e ->
        Logger.error("[Scheduler] Task failed",
          task: :scheduled_task,
          error: Exception.message(e),
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        )
        reraise e, __STACKTRACE__
    end
  end
end
```

---

## 4. Monitoring and Alerting

### Job Execution Tracking

#### Oban Telemetry Metrics

```elixir
# lib/gsc_analytics_web/telemetry.ex
defmodule GscAnalyticsWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000},
      {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp metrics do
    [
      # Job execution metrics
      counter("oban.job.stop.duration",
        event_name: [:oban, :job, :stop],
        measurement: :duration,
        unit: {:native, :millisecond},
        tags: [:worker, :queue]
      ),

      distribution("oban.job.stop.queue_time",
        event_name: [:oban, :job, :stop],
        measurement: :queue_time,
        unit: {:native, :millisecond},
        tags: [:worker, :queue]
      ),

      counter("oban.job.exception.count",
        event_name: [:oban, :job, :exception],
        tags: [:worker, :queue]
      ),

      # Custom business metrics
      last_value("gsc.sync.urls_synced",
        event_name: [:gsc_analytics, :sync, :complete],
        measurement: :total_urls,
        tags: [:site_url]
      )
    ]
  end
end
```

**Available Metrics:**
- **Duration:** Job execution time
- **Queue Time:** Time waiting in queue
- **Memory:** Memory usage during execution
- **Reductions:** CPU work (Erlang reductions)

**Source:** https://hexdocs.pm/oban/Oban.Telemetry.html

---

### Detecting Missed Runs

#### Heartbeat Monitoring Pattern

```elixir
# Send heartbeat after successful job
defmodule MyApp.SyncWorker do
  use Oban.Worker

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    result = perform_sync()

    # Send heartbeat to monitoring service
    send_heartbeat("gsc-daily-sync")

    {:ok, result}
  end

  defp send_heartbeat(check_name) do
    url = "https://healthchecks.io/ping/#{check_uuid(check_name)}"
    :httpc.request(:get, {String.to_charlist(url), []}, [], [])
  end
end
```

**Monitoring Services:**
- [Healthchecks.io](https://healthchecks.io/) — Free tier, simple pings
- [Cronitor](https://cronitor.io/) — Cron-specific monitoring
- [Better Stack](https://betterstack.com/uptime) — Uptime + cron monitoring

**Alerting:**
- Configure expected schedule (e.g., daily at 4am)
- Set grace period (e.g., 30 minutes)
- Alert if heartbeat not received within window

**Source:** https://betterstack.com/community/guides/monitoring/what-is-cron-monitoring/

---

#### Database-Based Monitoring

```elixir
# Track last successful sync
defmodule GscAnalytics.SyncMonitor do
  use Ecto.Schema
  import Ecto.Query

  schema "sync_monitor" do
    field :job_name, :string
    field :last_run_at, :utc_datetime
    field :last_status, :string
    field :run_count, :integer, default: 0

    timestamps()
  end

  def record_run(job_name, status) do
    attrs = %{
      job_name: job_name,
      last_run_at: DateTime.utc_now(),
      last_status: status
    }

    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert(
      on_conflict: [
        set: [
          last_run_at: attrs.last_run_at,
          last_status: attrs.last_status,
          run_count: fragment("? + 1", field(:run_count))
        ]
      ],
      conflict_target: :job_name
    )
  end

  def check_missed_runs(job_name, expected_interval_hours) do
    threshold = DateTime.add(DateTime.utc_now(), -expected_interval_hours, :hour)

    from(m in __MODULE__,
      where: m.job_name == ^job_name and m.last_run_at < ^threshold
    )
    |> Repo.one()
    |> case do
      nil -> {:ok, :never_run}
      %{last_run_at: last_run} ->
        hours_since = DateTime.diff(DateTime.utc_now(), last_run, :hour)
        {:error, {:missed_run, hours_since}}
    end
  end
end

# In worker
def perform(%Oban.Job{}) do
  result = perform_sync()
  SyncMonitor.record_run("gsc_daily_sync", "success")
  {:ok, result}
rescue
  e ->
    SyncMonitor.record_run("gsc_daily_sync", "failed")
    reraise e, __STACKTRACE__
end
```

---

### Duration Tracking and Alerting

#### Baseline Establishment

```elixir
# Track job durations over time
defmodule GscAnalytics.JobMetrics do
  use Ecto.Schema

  schema "job_metrics" do
    field :worker, :string
    field :duration_ms, :integer
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :rows_processed, :integer

    timestamps()
  end

  def calculate_baseline(worker, days \\ 30) do
    threshold = DateTime.add(DateTime.utc_now(), -days, :day)

    from(m in __MODULE__,
      where: m.worker == ^worker and m.started_at > ^threshold,
      select: %{
        avg_duration: avg(m.duration_ms),
        p95_duration: fragment("percentile_cont(0.95) within group (order by ?)", m.duration_ms),
        p99_duration: fragment("percentile_cont(0.99) within group (order by ?)", m.duration_ms)
      }
    )
    |> Repo.one()
  end

  def check_overrun(worker, current_duration_ms) do
    %{p95_duration: p95} = calculate_baseline(worker)

    if current_duration_ms > p95 * 1.5 do
      # Alert: Job taking 50% longer than p95
      {:alert, :duration_overrun, current_duration_ms / p95}
    else
      :ok
    end
  end
end
```

#### Oban Job Timeout

```elixir
defmodule MyApp.SyncWorker do
  use Oban.Worker,
    max_attempts: 3,
    timeout: :timer.minutes(30)  # Kill job after 30 minutes

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    # Job will be killed if exceeds 30 minutes
    # Raises `Oban.TimeoutError`
    :ok
  end
end
```

---

### Failure Alerting Strategies

#### Alert Levels

```elixir
defmodule MyApp.AlertManager do
  require Logger

  # Critical: Immediate page-out
  def alert_critical(job, error) do
    Logger.error("[CRITICAL] Job failed", worker: job.worker, error: inspect(error))
    send_pagerduty(job, error)
  end

  # Important: Email during business hours
  def alert_important(job, error) do
    Logger.warning("[IMPORTANT] Job failed", worker: job.worker, error: inspect(error))
    send_email(job, error)
  end

  # Routine: Batch daily
  def alert_routine(job, error) do
    Logger.info("[ROUTINE] Job failed", worker: job.worker, error: inspect(error))
    store_for_daily_report(job, error)
  end
end

# Attach to Oban telemetry
:telemetry.attach(
  "job-failure-alerts",
  [:oban, :job, :exception],
  fn _event, _measurements, metadata, _config ->
    cond do
      metadata.job.tags |> Enum.member?("critical") ->
        MyApp.AlertManager.alert_critical(metadata.job, metadata.reason)

      metadata.job.tags |> Enum.member?("important") ->
        MyApp.AlertManager.alert_important(metadata.job, metadata.reason)

      true ->
        MyApp.AlertManager.alert_routine(metadata.job, metadata.reason)
    end
  end,
  %{}
)
```

**Source:** https://odown.com/blog/cron-job-monitoring/

---

### Example: Complete Monitoring Setup

```elixir
# lib/gsc_analytics/workers/daily_sync_worker.ex
defmodule GscAnalytics.Workers.DailySyncWorker do
  use Oban.Worker,
    queue: :gsc_sync,
    max_attempts: 3,
    timeout: :timer.minutes(30),
    unique: [period: 3600, states: [:available, :scheduled, :executing]],
    tags: ["daily", "critical", "gsc"]

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{attempt: attempt} = job) do
    start_time = System.monotonic_time()

    # Emit custom telemetry start event
    :telemetry.execute(
      [:gsc_analytics, :sync, :start],
      %{system_time: System.system_time()},
      %{job_id: job.id, attempt: attempt}
    )

    result = GscAnalytics.DataSources.GSC.Core.Sync.sync_yesterday()

    duration_ms = System.monotonic_time() - start_time |> div(1_000_000)

    case result do
      {:ok, %{total_urls: urls, total_api_calls: calls}} ->
        # Success telemetry
        :telemetry.execute(
          [:gsc_analytics, :sync, :complete],
          %{duration_ms: duration_ms, total_urls: urls, total_api_calls: calls},
          %{site_url: "sc-domain:scrapfly.io", status: :success}
        )

        # Send heartbeat
        send_heartbeat("gsc-daily-sync")

        # Check duration baseline
        check_duration_alert(duration_ms)

        {:ok, result}

      {:error, :rate_limited} ->
        Logger.warning("[GSC Sync] Rate limited, snoozing 5 minutes")
        {:snooze, 300}

      {:error, reason} when attempt < 3 ->
        Logger.warning("[GSC Sync] Failed attempt #{attempt}", reason: inspect(reason))
        {:error, reason}

      {:error, reason} ->
        Logger.error("[GSC Sync] All attempts failed", reason: inspect(reason))

        # Alert on final failure
        send_alert(:critical, "GSC daily sync failed after #{attempt} attempts: #{inspect(reason)}")

        {:discard, reason}
    end
  end

  defp send_heartbeat(check_name) do
    # Implementation from earlier
  end

  defp check_duration_alert(duration_ms) do
    # Implementation from earlier
  end

  defp send_alert(level, message) do
    # Implementation from earlier
  end
end
```

---

## References

### Official Documentation

- **Oban.Plugins.Cron:** https://hexdocs.pm/oban/Oban.Plugins.Cron.html
- **Oban Telemetry:** https://hexdocs.pm/oban/Oban.Telemetry.html
- **Oban Periodic Jobs:** https://hexdocs.pm/oban/periodic_jobs.html
- **Quantum Configuration:** https://hexdocs.pm/quantum/configuration.html
- **Crontab.guru Examples:** https://crontab.guru/examples.html

### Articles and Guides

- **Cron Jobs in Data Engineering:** https://www.datacamp.com/tutorial/cron-job-in-data-engineering
- **How Debian Cron Handles DST:** https://blog.healthchecks.io/2021/10/how-debian-cron-handles-dst-transitions/
- **Better Stack Cron Monitoring:** https://betterstack.com/community/guides/monitoring/what-is-cron-monitoring/
- **Oban Job Processing Guide:** https://www.atlantbh.com/background-jobs-in-elixir/
- **Quantum Job Scheduling:** https://victorbjorklund.com/job-scheduling-cron-job-elixir-phoenix-quantum/

### Tools and Services

- **Healthchecks.io:** https://healthchecks.io/
- **Cronitor:** https://cronitor.io/
- **Better Stack:** https://betterstack.com/uptime
- **Crontab Generator:** https://www.freetool.dev/crontab-generator/

---

## Appendix: Quick Reference

### Cron Expression Cheat Sheet

```bash
# Field order: minute hour day month weekday

# Every minute
* * * * *

# Every 15 minutes
*/15 * * * *

# Daily at 4am
0 4 * * *

# Weekdays at 9am
0 9 * * 1-5

# First day of month
0 0 1 * *

# Weekly on Sunday
0 0 * * 0
```

### Oban Configuration Template

```elixir
config :my_app, Oban,
  repo: MyApp.Repo,
  plugins: [
    {Oban.Plugins.Cron,
     timezone: "Etc/UTC",
     crontab: [
       {"0 4 * * *", MyApp.DailyWorker,
         max_attempts: 3,
         queue: :scheduled,
         tags: ["daily", "critical"]}
     ]}
  ],
  queues: [
    default: 10,
    scheduled: 1
  ]
```

### Worker Template

```elixir
defmodule MyApp.DailyWorker do
  use Oban.Worker,
    queue: :scheduled,
    max_attempts: 3,
    timeout: :timer.minutes(30),
    unique: [period: 3600, states: [:available, :scheduled, :executing]],
    tags: ["daily"]

  @impl Oban.Worker
  def perform(%Oban.Job{attempt: attempt}) do
    # Job logic
    :ok
  end
end
```
