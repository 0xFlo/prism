# Oban Official Documentation & Best Practices Reference

**Last Updated:** 2025-11-08
**Oban Version:** 2.20.1 (released 2025-08-15)
**Official Documentation:** https://hexdocs.pm/oban/
**GitHub Repository:** https://github.com/oban-bg/oban

---

## Table of Contents

1. [Overview](#overview)
2. [Installation & Setup](#installation--setup)
3. [Configuration](#configuration)
4. [Workers](#workers)
5. [Cron Plugin](#cron-plugin)
6. [Pruner Plugin](#pruner-plugin)
7. [Testing](#testing)
8. [Error Handling & Retries](#error-handling--retries)
9. [Unique Jobs](#unique-jobs)
10. [Telemetry & Monitoring](#telemetry--monitoring)
11. [Production Best Practices](#production-best-practices)
12. [Troubleshooting](#troubleshooting)
13. [Oban Pro Features](#oban-pro-features)
14. [Recent Changes (v2.20)](#recent-changes-v220)
15. [Additional Resources](#additional-resources)

---

## Overview

**What is Oban?**

Oban is a robust job processing library for Elixir, backed by modern PostgreSQL, MySQL, or SQLite3. It provides reliable, observable, and feature-rich background job execution.

**Source:** https://hexdocs.pm/oban/

**Key Features:**

- Database-backed persistence (PostgreSQL 12+, MySQL 8.4+, SQLite3 3.37+)
- Automatic retries with exponential backoff
- Job history retention for metrics and inspection
- Unique job constraints
- Scheduled and cron jobs
- Queue isolation and prioritization
- Graceful shutdown
- ACID compliance and transaction safety
- Comprehensive telemetry integration

**Requirements:**

- Elixir 1.15+
- Erlang 24+
- One of: PostgreSQL 12.0+, MySQL 8.4+, or SQLite3 3.37.0+

---

## Installation & Setup

### 1. Add Dependency

**Source:** https://hexdocs.pm/oban/introduction/installation.html

Add to `mix.exs`:

```elixir
def deps do
  [
    {:oban, "~> 2.20"}
  ]
end
```

### 2. Run Installation Task (Recommended)

**Source:** https://github.com/oban-bg/oban/blob/main/guides/introduction/installation.md

```bash
# Semi-automatic installation (recommended)
mix oban.install

# OR using Igniter (if available)
mix igniter.install oban
```

The installation task handles:
- Database migrations
- Configuration setup
- Supervisor tree integration

### 3. Manual Setup

If not using the install task:

**Generate Migration:**

```bash
mix ecto.gen.migration add_oban_jobs_table
```

Then use Oban's migration helper in the generated file:

```elixir
defmodule MyApp.Repo.Migrations.AddObanJobsTable do
  use Ecto.Migration

  def up do
    Oban.Migration.up(version: 13)
  end

  def down do
    Oban.Migration.down(version: 13)
  end
end
```

**Run Migration:**

```bash
mix ecto.migrate
```

---

## Configuration

### Basic Configuration

**Source:** https://hexdocs.pm/oban/Oban.html

```elixir
# config/config.exs
config :my_app, Oban,
  repo: MyApp.Repo,
  queues: [default: 10, mailers: 20, media: 5],
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron,
     crontab: [
       {"0 2 * * *", MyApp.NightlyWorker},
       {"* * * * *", MyApp.MinuteWorker},
       {"0 0 1 * *", MyApp.MonthlyWorker, max_attempts: 1}
     ]}
  ]
```

### Supervision Tree Setup

**Source:** https://github.com/oban-bg/oban/blob/main/guides/introduction/installation.md

```elixir
# lib/my_app/application.ex
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      MyApp.Repo,
      {Oban, Application.fetch_env!(:my_app, Oban)}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
  end
end
```

**IMPORTANT:** Always use `{Module, args}` tuple format for GenServers in supervision trees to ensure proper child specs.

### Configuration Options

**Source:** https://hexdocs.pm/oban/Oban.html

| Option | Description | Default |
|--------|-------------|---------|
| `:repo` | Ecto repository for job storage | **Required** |
| `:queues` | Queue names and concurrency limits | `[]` |
| `:plugins` | List of plugin modules/configs | `[]` |
| `:engine` | Database adapter (Basic/Lite/Dolphin) | Auto-detected |
| `:log` | Query logging level or `false` | `false` |
| `:node` | Identifier for the node running Oban | Auto-generated |
| `:prefix` | Database schema for job storage | `"public"` |
| `:testing` | Test mode (`:inline`, `:manual`, `:disabled`) | `:disabled` |
| `:dispatch_cooldown` | Milliseconds between job fetches | `5` |
| `:shutdown_grace_period` | Timeout for graceful shutdown | `15_000` (15s) |
| `:peer` | Peer module for leadership election | `Oban.Peers.Postgres` |

### Database Engine Selection

**Source:** https://github.com/oban-bg/oban/blob/main/guides/introduction/installation.md

```elixir
# PostgreSQL (default)
config :my_app, Oban,
  engine: Oban.Engines.Basic,
  repo: MyApp.Repo

# MySQL
config :my_app, Oban,
  engine: Oban.Engines.Dolphin,
  repo: MyApp.Repo

# SQLite3
config :my_app, Oban,
  engine: Oban.Engines.Lite,
  repo: MyApp.Repo
```

### Multiple Oban Instances

**Source:** https://context7.com/oban-bg/oban/llms.txt

```elixir
# config/config.exs
config :my_app, MyApp.PrimaryOban,
  name: MyApp.PrimaryOban,
  repo: MyApp.Repo,
  queues: [default: 10, mailers: 20]

config :my_app, MyApp.SecondaryOban,
  name: MyApp.SecondaryOban,
  repo: MyApp.Repo,
  prefix: "secondary",
  queues: [exports: 5, reports: 10]

# lib/my_app/application.ex
def start(_type, _args) do
  children = [
    MyApp.Repo,
    {Oban, Application.fetch_env!(:my_app, MyApp.PrimaryOban)},
    {Oban, Application.fetch_env!(:my_app, MyApp.SecondaryOban)}
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end

# Usage
%{user_id: 123}
|> MyApp.Workers.EmailWorker.new()
|> Oban.insert(MyApp.PrimaryOban)
```

### Test Configuration

**Source:** https://github.com/oban-bg/oban/blob/main/guides/introduction/installation.md

```elixir
# config/test.exs
config :my_app, Oban,
  testing: :manual,  # Recommended - allows controlled job execution
  queues: false,     # Disables queue processing
  plugins: false     # Disables plugins
```

**Testing Modes:**

- `:manual` — Jobs inserted into database, executed on demand via `drain_queue/1`
- `:inline` — Jobs execute immediately within the calling process (no database)
- `:disabled` — Standard production behavior (not recommended for tests)

---

## Workers

**Source:** https://hexdocs.pm/oban/Oban.Worker.html

### Basic Worker Definition

```elixir
defmodule MyApp.Workers.EmailWorker do
  use Oban.Worker, queue: :mailers, max_attempts: 5

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"email" => email, "user_id" => user_id}}) do
    case MyApp.Mailer.send_welcome_email(email) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
```

### Worker Configuration Options

**Source:** https://hexdocs.pm/oban/Oban.Worker.html

Compile-time options (via `use Oban.Worker`):

| Option | Description | Default |
|--------|-------------|---------|
| `:max_attempts` | Maximum retry attempts | `20` |
| `:priority` | Execution priority (0-9, 0 is highest) | `0` |
| `:queue` | Queue name as atom | `:default` |
| `:tags` | List of string identifiers | `[]` |
| `:replace` | Job fields to replace on conflict | `[]` |
| `:unique` | Uniqueness configuration | `false` |

### Worker Callbacks

**Required:**

- `perform/1` — Receives `%Oban.Job{}`, returns job result

**Optional:**

- `backoff/1` — Custom retry delay calculation (returns seconds)
- `timeout/1` — Maximum execution time (returns milliseconds)

### Return Values

**Source:** https://hexdocs.pm/oban/Oban.Worker.html

From `perform/1`:

- `:ok` or `{:ok, value}` — Job completed successfully
- `{:error, reason}` — Job failed, will retry if attempts remain
- `{:cancel, reason}` — Cancel job without retrying
- `{:snooze, seconds}` — Postpone execution without consuming retry attempts
- `{:discard, reason}` — Discard job immediately (since v2.13)

### Enqueuing Jobs

```elixir
# Basic enqueue
%{email: "user@example.com", user_id: 123}
|> MyApp.Workers.EmailWorker.new()
|> Oban.insert()

# With runtime options (overrides worker defaults)
%{email: "user@example.com"}
|> MyApp.Workers.EmailWorker.new(
  queue: :urgent,
  max_attempts: 3,
  priority: 1,
  tags: ["welcome"],
  scheduled_at: DateTime.add(DateTime.utc_now(), 3600)
)
|> Oban.insert()
```

### Custom Backoff Strategy

**Source:** https://github.com/oban-bg/oban/blob/main/guides/testing/testing_workers.md

```elixir
defmodule MyApp.Workers.RetryWorker do
  use Oban.Worker

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    # Job logic
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    # Custom backoff: 2s, 4s, 6s, 8s...
    attempt * 2
  end
end
```

### Custom Timeout

**Source:** https://github.com/oban-bg/oban/blob/main/guides/testing/testing_workers.md

```elixir
defmodule MyApp.Workers.SlowWorker do
  use Oban.Worker

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    # Long-running job logic
  end

  @impl Oban.Worker
  def timeout(%Oban.Job{attempt: attempt}) do
    # Increase timeout with each retry
    attempt * 60_000  # 1 min, 2 min, 3 min...
  end
end
```

---

## Cron Plugin

**Source:** https://hexdocs.pm/oban/Oban.Plugins.Cron.html

### Configuration

```elixir
config :my_app, Oban,
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"* * * * *", MyApp.Workers.MinuteWorker},
       {"0 * * * *", MyApp.Workers.HourlyWorker, args: %{custom: "arg"}},
       {"0 0 * * *", MyApp.Workers.DailyWorker, max_attempts: 1},
       {"0 12 * * MON", MyApp.Workers.MondayWorker, queue: :scheduled, tags: ["mondays"]},
       {"@daily", MyApp.Workers.CleanupWorker},
       {"@hourly", MyApp.Workers.HealthCheck},
       {"0 0 1 * *", MyApp.Workers.MonthlyInvoice}
     ],
     timezone: "America/New_York"}
  ]
```

### Crontab Format

**Source:** https://hexdocs.pm/oban/Oban.Plugins.Cron.html

Jobs are declared as tuples:

```elixir
{expression, worker}
{expression, worker, options}
```

**Cron Expression Format:**

```
* * * * *
│ │ │ │ │
│ │ │ │ └─── Day of week (0-6, Sunday=0)
│ │ │ └───── Month (1-12)
│ │ └─────── Day of month (1-31)
│ └───────── Hour (0-23)
└─────────── Minute (0-59)
```

### Supported Nicknames

**Source:** https://hexdocs.pm/oban/Oban.Plugins.Cron.html

| Nickname | Equivalent | Description |
|----------|-----------|-------------|
| `@yearly` / `@annually` | `0 0 1 1 *` | Once per year |
| `@monthly` | `0 0 1 * *` | Once per month |
| `@weekly` | `0 0 * * 0` | Once per week (Sunday) |
| `@daily` / `@midnight` | `0 0 * * *` | Once per day |
| `@hourly` | `0 * * * *` | Once per hour |
| `@reboot` | N/A | Once at startup |

### Cron Options

**Source:** https://hexdocs.pm/oban/Oban.Plugins.Cron.html

- `:crontab` — List of cron expressions with workers (required)
- `:timezone` — Timezone for scheduling (default: `"Etc/UTC"`, requires `tz` package)

### Job Identification

**Source:** https://hexdocs.pm/oban/Oban.Plugins.Cron.html

Cron-enqueued jobs include metadata:

```elixir
defmodule MyApp.Workers.DailyWorker do
  use Oban.Worker

  @impl Oban.Worker
  def perform(%Oban.Job{meta: meta} = job) do
    # meta contains:
    # %{
    #   "cron" => true,
    #   "cron_expr" => "@daily",
    #   "cron_tz" => "America/New_York"
    # }
    IO.inspect(meta)
    :ok
  end
end
```

### Validation

**Source:** https://hexdocs.pm/oban/Oban.Plugins.Cron.html

Validate cron expressions:

```elixir
Oban.Plugins.Cron.parse("0 2 * * *")
# => {:ok, expression}

Oban.Plugins.Cron.parse("invalid")
# => {:error, "..."}
```

### @reboot Best Practice

**Source:** https://github.com/oban-bg/oban/blob/main/guides/learning/periodic_jobs.md

In development, use `Oban.Peers.Global` for better `@reboot` handling:

```elixir
# config/dev.exs
config :my_app, Oban,
  peer: Oban.Peers.Global,
  # ...
```

This prevents delays associated with leadership relinquishment during restarts.

---

## Pruner Plugin

**Source:** https://hexdocs.pm/oban/Oban.Plugins.Pruner.html

### Purpose

Automatically removes completed, cancelled, and discarded jobs to maintain database performance.

**CRITICAL:** Enable this plugin for all production deployments.

### Configuration

```elixir
# Basic (uses defaults)
config :my_app, Oban,
  plugins: [Oban.Plugins.Pruner]

# Custom configuration
config :my_app, Oban,
  plugins: [
    {Oban.Plugins.Pruner,
     interval: :timer.minutes(5),  # Pruning frequency
     max_age: 3600,                 # Job age threshold (seconds)
     limit: 50_000}                 # Max jobs per cycle
  ]
```

### Options

**Source:** https://hexdocs.pm/oban/Oban.Plugins.Pruner.html

| Option | Description | Default |
|--------|-------------|---------|
| `:interval` | Frequency of pruning cycles (milliseconds) | `30_000` (30s) |
| `:max_age` | Job age threshold before deletion (seconds) | `60` |
| `:limit` | Maximum jobs pruned per cycle | `10_000` |

### Best Practices

**Source:** https://hexdocs.pm/oban/Oban.Plugins.Pruner.html

- **Always enable in production** for sustained performance
- **Increase `:limit`** if generating >10k jobs per minute
- **Set appropriate `:max_age`** based on retention requirements (e.g., 7 days = 604,800 seconds)

### Example: 7-Day Retention

```elixir
config :my_app, Oban,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7}  # 7 days
  ]
```

### Telemetry

**Source:** https://hexdocs.pm/oban/Oban.Plugins.Pruner.html

Emits `[:oban, :plugin, :stop]` events with `:pruned_jobs` metadata containing deleted job records (id, queue, state).

---

## Testing

**Source:** https://hexdocs.pm/oban/Oban.Testing.html and https://hexdocs.pm/oban/testing.html

### Test Configuration

```elixir
# config/test.exs
config :my_app, Oban,
  testing: :manual,
  queues: false,
  plugins: false
```

### Setup in Test Case

**Source:** https://github.com/oban-bg/oban/blob/main/guides/testing/testing.md

```elixir
defmodule MyApp.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      use Oban.Testing, repo: MyApp.Repo
    end
  end
end
```

Or in individual test files:

```elixir
defmodule MyApp.WorkerTest do
  use MyApp.DataCase, async: true

  use Oban.Testing, repo: MyApp.Repo
end
```

### Testing Modes

**Source:** https://github.com/oban-bg/oban/blob/main/guides/introduction/installation.md

**`:manual` Mode (Recommended)**

Jobs inserted into database, executed on demand:

```elixir
test "processes job manually" do
  {:ok, job} =
    %{user_id: 123}
    |> MyApp.Workers.EmailWorker.new()
    |> Oban.insert()

  assert %{success: 1} = Oban.drain_queue(queue: :mailers)
  assert_received {:email_sent, 123}
end
```

**`:inline` Mode**

Jobs execute immediately without database:

```elixir
# config/test.exs
config :my_app, Oban, testing: :inline

# Test
test "executes job inline" do
  {:ok, job} =
    %{user_id: 123}
    |> MyApp.Workers.EmailWorker.new()
    |> Oban.insert()

  # Job already executed
  assert_received {:email_sent, 123}
end
```

### Testing Helpers

**Source:** https://hexdocs.pm/oban/Oban.Testing.html

#### assert_enqueued/1,2

Verify jobs matching criteria exist:

```elixir
test "scheduling activation upon sign up" do
  {:ok, account} = MyApp.Account.sign_up(email: "parker@example.com")

  assert_enqueued worker: MyApp.ActivationWorker,
                  args: %{id: account.id},
                  queue: :default
end
```

**Match criteria:**
- `worker` — Worker module
- `args` — Job arguments (supports nested matching)
- `queue` — Queue name
- `priority` — Priority level
- `scheduled_at` — Execution timing (with time delta)
- `meta` — Metadata fields
- `tags` — Job tags

#### refute_enqueued/1,2,3

Confirm jobs aren't present:

```elixir
test "no email sent for invalid user" do
  {:error, _} = MyApp.Account.sign_up(email: "invalid")

  refute_enqueued worker: MyApp.ActivationWorker
end
```

#### all_enqueued/1

Retrieve all matching jobs:

```elixir
test "enqueuing one job for each child record" do
  :ok = MyApp.Account.notify_owners(account())

  assert jobs = all_enqueued(worker: MyApp.NotificationWorker)
  assert 3 == length(jobs)
end
```

#### perform_job/2,3

Execute jobs directly (unit testing):

```elixir
test "activating a new user" do
  user = MyApp.User.create(email: "parker@example.com")

  assert {:ok, _user} = perform_job(MyApp.ActivationWorker, %{id: user.id})
end
```

#### drain_queue/1

Execute all available jobs (integration testing):

```elixir
test "processes all pending jobs" do
  :ok = Business.schedule_a_meeting(%{email: "monty@brewster.com"})

  assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :mailer)
end
```

**Options:**

- `:queue` — Queue to drain (required)
- `:with_scheduled` — Include scheduled jobs (boolean or DateTime)
- `:with_recursion` — Drain jobs enqueued by other jobs
- `:with_limit` — Limit number of jobs drained
- `:with_safety` — Catch errors (default: true)

```elixir
# Drain scheduled jobs
Oban.drain_queue(queue: :default, with_scheduled: true)

# Drain up to specific time
future_time = DateTime.add(DateTime.utc_now(), 3600, :second)
Oban.drain_queue(queue: :default, with_scheduled: future_time)

# Drain recursively (for jobs that enqueue other jobs)
Oban.drain_queue(queue: :default, with_recursion: true)

# Drain limited number
Oban.drain_queue(queue: :default, with_limit: 5)
```

#### with_testing_mode/2

Temporarily switch testing modes:

```elixir
test "switch to inline mode temporarily" do
  Oban.Testing.with_testing_mode(:inline, fn ->
    {:ok, %Job{state: "completed"}} =
      Oban.insert(MyWorker.new(%{id: 123}))
  end)
end
```

### Testing Worker Callbacks

**Source:** https://github.com/oban-bg/oban/blob/main/guides/testing/testing_workers.md

```elixir
test "custom backoff calculation" do
  assert 2 == MyWorker.backoff(%Oban.Job{attempt: 1})
  assert 4 == MyWorker.backoff(%Oban.Job{attempt: 2})
end

test "custom timeout calculation" do
  assert 1000 == MyWorker.timeout(%Oban.Job{attempt: 1})
  assert 2000 == MyWorker.timeout(%Oban.Job{attempt: 2})
end
```

### Testing Configuration

**Source:** https://github.com/oban-bg/oban/blob/main/guides/testing/testing_config.md

Validate plugin configurations:

```elixir
test "testing cron plugin configuration" do
  config = MyApp.Oban.cron_config()

  assert :ok = Oban.Plugins.Cron.validate(config)
end

test "production oban config is valid" do
  config =
    "config/config.exs"
    |> Config.Reader.read!(env: :prod)
    |> get_in([:my_app, Oban])

  assert :ok = Oban.Config.validate(config)
end
```

---

## Error Handling & Retries

**Source:** https://hexdocs.pm/oban/error_handling.html

### Automatic Retries

Jobs automatically retry when they fail (unless cancelled or discarded). Default: **20 attempts**.

### Error Recording

**Source:** https://hexdocs.pm/oban/error_handling.html

Failures are captured in the `errors` array on `Oban.Job`:

```elixir
%{
  at: ~U[2025-11-08 10:00:00Z],
  attempt: 1,
  error: "** (RuntimeError) Something went wrong\n    stacktrace..."
}
```

### Retry Backoff

**Source:** https://hexdocs.pm/oban/error_handling.html

Uses **exponential backoff with jitter**:

- Delays increase exponentially (8s, 16s, 32s...)
- Randomized variation prevents job clustering
- Default formula: `attempt^4 + 15 + random(30)`

### Configuring Max Attempts

**Worker-level:**

```elixir
defmodule MyApp.Workers.LimitedWorker do
  use Oban.Worker, queue: :limited, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    # Job logic
  end
end
```

**Job-level (runtime override):**

```elixir
%{user_id: 123}
|> MyApp.Workers.EmailWorker.new(max_attempts: 5)
|> Oban.insert()
```

### Custom Backoff

**Source:** https://hexdocs.pm/oban/Oban.Worker.html

```elixir
defmodule MyApp.Workers.CustomBackoffWorker do
  use Oban.Worker

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt, unsaved_error: error}) do
    # Access error for error-specific backoff
    case error do
      %{kind: :timeout} -> attempt * 60  # Longer backoff for timeouts
      _ -> attempt * 10  # Default backoff
    end
  end
end
```

### Error Reporting Integration

**Source:** https://github.com/oban-bg/oban/blob/main/guides/introduction/ready_for_production.md

#### Sentry Integration

```elixir
defmodule MyApp.ObanReporter do
  def attach do
    :telemetry.attach("oban-errors", [:oban, :job, :exception], &__MODULE__.handle_event/4, [])
  end

  def handle_event([:oban, :job, :exception], measure, meta, _) do
    extra =
      meta.job
      |> Map.take([:id, :args, :meta, :queue, :worker])
      |> Map.merge(measure)

    Sentry.capture_exception(meta.reason, stacktrace: meta.stacktrace, extra: extra)
  end
end

# In application.ex
@impl Application
def start(_type, _args) do
  MyApp.ObanReporter.attach()
  # ...
end
```

#### AppSignal Integration

**Source:** https://hexdocs.pm/oban/error_handling.html

Oban provides built-in support for Sentry and AppSignal with native integrations requiring minimal setup.

---

## Unique Jobs

**Source:** https://hexdocs.pm/oban/unique_jobs.html

### Overview

**IMPORTANT:** "Uniqueness operates at **job insertion time**...Uniqueness only prevents duplicate insertions. Once unique jobs are in the queue, they'll run according to the queue's concurrency settings."

Unique jobs **DO NOT** run one at a time or in sequence. They only prevent duplicate enqueuing.

### Basic Configuration

```elixir
# Enable with defaults
use Oban.Worker, unique: true

# Or with specific period
use Oban.Worker, unique: [period: 60]  # 60 seconds
```

### Configuration Options

**Source:** https://hexdocs.pm/oban/unique_jobs.html

| Option | Description | Default |
|--------|-------------|---------|
| `:period` | Duration until job no longer considered duplicate (seconds) | `60` |
| `:fields` | Fields to compare for uniqueness | `[:worker, :queue, :args]` |
| `:keys` | Specific keys within `:args` or `:meta` to compare | All keys |
| `:states` | Job states to check for uniqueness | `:successful` |
| `:timestamp` | Period calculation against `:inserted_at` or `:scheduled_at` | `:inserted_at` |

### State Groups

**Source:** https://hexdocs.pm/oban/unique_jobs.html (v2.20+)

Predefined state groups (v2.20+):

- `:all` — All states
- `:incomplete` — Unfinished jobs (available, scheduled, executing, retryable)
- `:scheduled` — Only scheduled jobs (debouncing pattern)
- `:successful` — Default; excludes cancelled/discarded

### Configuration Strategies

#### Default Uniqueness

```elixir
use Oban.Worker, unique: true
# Equivalent to:
use Oban.Worker, unique: [
  period: 60,
  fields: [:worker, :queue, :args],
  states: :successful
]
```

#### Debouncing Pattern

**Source:** https://hexdocs.pm/oban/unique_jobs.html

Prevent scheduling duplicate jobs:

```elixir
use Oban.Worker, unique: [
  period: {2, :minutes},
  states: :scheduled,
  timestamp: :scheduled_at
]
```

#### Field-Specific Uniqueness

**Source:** https://hexdocs.pm/oban/unique_jobs.html

Compare only specific fields:

```elixir
# Compare only worker and queue (ignore args)
use Oban.Worker, unique: [
  fields: [:worker, :queue]
]
```

#### Key-Specific Uniqueness

**Source:** https://hexdocs.pm/oban/unique_jobs.html

Compare only specific keys within args:

```elixir
# Only compare :url key within args
use Oban.Worker, unique: [
  keys: [:url],
  fields: [:worker, :args]
]
```

#### Cross-Queue Uniqueness

**Source:** https://github.com/oban-bg/oban/blob/main/guides/learning/unique_jobs.md

```elixir
use Oban.Worker, unique: [
  fields: [:worker, :args],  # Exclude :queue
  states: :all
]
```

#### Advanced Configuration

**Source:** https://github.com/oban-bg/oban/blob/main/guides/learning/unique_jobs.md

```elixir
use Oban.Worker,
  unique: [
    period: {2, :minutes},
    timestamp: :scheduled_at,
    keys: [:url],
    states: :all,
    fields: [:worker, :args]
  ]
```

### Conflict Handling

**Source:** https://hexdocs.pm/oban/unique_jobs.html

Insert always returns `{:ok, job}`, but the `:conflict?` field indicates duplicates:

```elixir
{:ok, job} = Oban.insert(MyWorker.new(%{id: 123}))
job.conflict?  # true if duplicate existed
```

### Replace Strategy

**Source:** https://hexdocs.pm/oban/unique_jobs.html

Update job fields upon conflicts:

```elixir
use Oban.Worker, unique: [
  period: 300,
  replace: [:args, :scheduled_at, :priority]
]
```

**Supported replace fields:** `:args`, `:max_attempts`, `:meta`, `:priority`, `:queue`, `:scheduled_at`, `:tags`, `:worker`

### Runtime Override

```elixir
# Worker default
use Oban.Worker, unique: [period: 60]

# Runtime override (does NOT merge with worker default)
%{id: 123}
|> MyWorker.new(unique: [period: 300, states: :all])
|> Oban.insert()
```

### Oban Pro: Index-Backed Uniqueness

**Source:** https://hexdocs.pm/oban/unique_jobs.html

Oban Pro's Smart Engine enforces uniqueness through a unique index, making insertion entirely safe between processes and nodes. Unlike standard uniqueness, the index-backed version applies for the job's entire lifetime.

---

## Telemetry & Monitoring

**Source:** https://hexdocs.pm/oban/Oban.Telemetry.html

### Telemetry Events

Oban emits structured telemetry events across multiple categories.

#### Job Events

**Source:** https://hexdocs.pm/oban/Oban.Telemetry.html

- `[:oban, :job, :start]` — Job fetched, ready to execute
- `[:oban, :job, :stop]` — Job succeeded
- `[:oban, :job, :exception]` — Job failed

**Measurements:** `system_time`, `duration`, `memory`, `queue_time`, `reductions`

**Metadata:**
- `:conf` — Oban instance configuration
- `:job` — The executing job
- `:state` — Result state (success, failure, cancelled, discard, snoozed)
- `:result` — Return value from perform/1
- For exceptions: `:kind`, `:reason`, `:stacktrace`

#### Engine Events

**Source:** https://hexdocs.pm/oban/Oban.Telemetry.html

Span events for database operations:

- Initialization: `init`, `refresh`, `put_meta`
- Job operations: `insert`, `cancel`, `complete`, `delete`, `retry`, `snooze`
- Bulk operations: `fetch`, `prune`, `stage`, `cancel_all_jobs`, `delete_all_jobs`, etc.

#### Infrastructure Events

**Source:** https://hexdocs.pm/oban/Oban.Telemetry.html

- **Notifier:** `notify`, `switch`
- **Peer:** Leader election and clustering
- **Plugin:** Initialization and execution (`:init`, `:start`, `:stop`, `:exception`)
- **Queue:** Graceful shutdown
- **Stager:** Local/global mode switching

### Default Logger

**Source:** https://hexdocs.pm/oban/Oban.Telemetry.html

Oban provides a default structured JSON logger:

```elixir
# In application.ex
def start(_type, _args) do
  Oban.Telemetry.attach_default_logger(level: :info)
  # ...
end
```

**Options:**

- `:level` — Log level (`:debug`, `:info`, `:warning`, `:error`)
- `:encode` — Set to `false` to disable JSON encoding (default: `true`)
- `:events` — Event categories to log (`:job`, `:notifier`, `:plugin`, `:peer`, `:queue`, `:stager`, `:all`)

```elixir
# Log only job and plugin events at debug level
Oban.Telemetry.attach_default_logger(
  level: :debug,
  events: [:job, :plugin]
)
```

### Custom Handlers

**Source:** https://hexdocs.pm/oban/Oban.Telemetry.html

```elixir
:telemetry.attach(
  "oban-job-logger",
  [:oban, :job, :stop],
  &MyApp.ObanLogger.handle_event/4,
  []
)

defmodule MyApp.ObanLogger do
  def handle_event([:oban, :job, :stop], measurements, metadata, _config) do
    Logger.info("Job completed",
      worker: metadata.job.worker,
      queue: metadata.job.queue,
      duration_ms: System.convert_time_unit(measurements.duration, :native, :millisecond)
    )
  end
end
```

### OpenTelemetry Integration

**Source:** Search results from elixirmerge.com

OpentelemetryOban creates OpenTelemetry spans from Oban events:

```elixir
# In application.ex
def start(_type, _args) do
  OpentelemetryOban.setup()
  # ...
end
```

Traces job execution and plugin operations automatically.

### Error Reporting Best Practices

**Source:** https://elixirmerge.com/p/enhancing-oban-job-logging-with-telemetry

**Threshold-Based Reporting:**

Only report errors after multiple attempts:

```elixir
def handle_event([:oban, :job, :exception], _measure, meta, _) do
  if meta.job.attempt >= 3 do
    Sentry.capture_exception(meta.reason, stacktrace: meta.stacktrace)
  end
end
```

**Metadata Enrichment:**

Attach job context to all logs:

```elixir
def handle_event([:oban, :job, :start], _measure, meta, _) do
  Logger.metadata(
    worker: meta.job.worker,
    queue: meta.job.queue,
    job_id: meta.job.id
  )
end
```

---

## Production Best Practices

**Source:** Multiple sources including https://hexdocs.pm/oban/troubleshooting.html and guides

### 1. Enable Essential Plugins

```elixir
config :my_app, Oban,
  plugins: [
    # REQUIRED: Automatic job cleanup
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},  # 7 days

    # RECOMMENDED: Rescue orphaned jobs after crashes
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(30)},

    # Optional: Periodic jobs
    {Oban.Plugins.Cron, crontab: [...]}
  ]
```

### 2. Configure Graceful Shutdown

**Source:** https://hexdocs.pm/oban/troubleshooting.html

```elixir
config :my_app, Oban,
  shutdown_grace_period: :timer.seconds(60),  # Default: 15s
  # ...
```

Increase for long-running jobs to prevent orphaned jobs.

### 3. Lifeline Plugin Setup

**Source:** https://github.com/oban-bg/oban/blob/main/guides/introduction/ready_for_production.md

```elixir
config :my_app, Oban,
  plugins: [
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(30)}
  ]
```

Rescues jobs left in `executing` state after unexpected shutdowns.

### 4. Multi-Node Configuration

**Source:** https://hexdocs.pm/oban/troubleshooting.html

**Web nodes (no job processing):**

```elixir
config :my_app, Oban,
  peer: false,   # Disable leadership
  queues: [],    # No queue processing
  plugins: []    # No plugins
```

**Worker nodes:**

```elixir
config :my_app, Oban,
  peer: Oban.Peers.Postgres,  # Default, enable leadership
  queues: [default: 10, mailers: 20],
  plugins: [Oban.Plugins.Pruner, ...]
```

**Why?** "Plugins require leadership to function, so when a web node becomes leader the plugins go dormant."

### 5. PgBouncer Compatibility

**Source:** https://hexdocs.pm/oban/troubleshooting.html

Transaction pooling disables LISTEN/NOTIFY, breaking Oban.

**Solutions:**

**Option A:** Use `Oban.Notifiers.PG` (Distributed Erlang)

```elixir
config :my_app, Oban,
  notifier: Oban.Notifiers.PG
```

**Option B:** Session pooling mode in PgBouncer

**Option C:** Dedicated Repo bypassing PgBouncer

```elixir
config :my_app, Oban,
  repo: MyApp.ObanRepo  # Separate repo without PgBouncer
```

### 6. Database Indexing

**Source:** https://hexdocs.pm/oban/changelog.html (v2.20)

Always run the latest migration for performance optimizations:

```bash
mix ecto.gen.migration upgrade_oban_to_v13
```

```elixir
defmodule MyApp.Repo.Migrations.UpgradeObanToV13 do
  use Ecto.Migration

  def up do
    Oban.Migration.up(version: 13)
  end

  def down do
    Oban.Migration.down(version: 13)
  end
end
```

Migration V13 adds indexes for Pruner performance.

### 7. Queue Configuration Strategy

**Source:** https://github.com/oban-bg/oban/blob/main/guides/recipes/splitting-queues.md

**Dynamic queue configuration via environment variable:**

```elixir
defmodule MyApp.Application do
  def start(_type, _args) do
    children = [
      MyApp.Repo,
      {Oban, oban_opts()}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  defp oban_opts do
    env_queues = System.get_env("OBAN_QUEUES")

    :my_app
    |> Application.get_env(Oban)
    |> Keyword.update(:queues, [], &queues(env_queues, &1))
  end

  defp queues("*", defaults), do: defaults
  defp queues(nil, defaults), do: defaults
  defp queues(_, false), do: false

  defp queues(values, _defaults) when is_binary(values) do
    values
    |> String.split(" ", trim: true)
    |> Enum.map(&String.split(&1, ",", trim: true))
    |> Keyword.new(fn [queue, limit] ->
      {String.to_existing_atom(queue), String.to_integer(limit)}
    end)
  end
end
```

**Usage:**

```bash
# Process all queues
OBAN_QUEUES="*" mix phx.server

# Process specific queues
OBAN_QUEUES="default,10 mailers,20" mix phx.server

# No queue processing
OBAN_QUEUES="" mix phx.server
```

### 8. Monitoring & Alerting

**Source:** https://hexdocs.pm/oban/Oban.Telemetry.html

Attach telemetry handlers for:

- Job exceptions (error reporting)
- Queue health metrics
- Plugin execution tracking
- Performance monitoring

```elixir
:telemetry.attach_many(
  "oban-monitoring",
  [
    [:oban, :job, :exception],
    [:oban, :plugin, :exception],
    [:oban, :queue, :shutdown]
  ],
  &MyApp.ObanMonitor.handle_event/4,
  []
)
```

### 9. Job Timeout Configuration

**Source:** https://hexdocs.pm/oban/Oban.Worker.html

Configure appropriate timeouts for long-running jobs:

```elixir
defmodule MyApp.Workers.ExportWorker do
  use Oban.Worker

  @impl Oban.Worker
  def timeout(_job) do
    :timer.minutes(30)  # 30 minutes
  end
end
```

### 10. Reliable Scheduling Pattern

**Source:** https://github.com/oban-bg/oban/blob/main/guides/recipes/reliable-scheduling.md

For at-most-once scheduling with at-least-once delivery:

```elixir
defmodule MyApp.Workers.ScheduledWorker do
  use Oban.Worker, queue: :scheduled, max_attempts: 10

  @one_day 60 * 60 * 24

  @impl true
  def perform(%{args: %{"email" => email} = args, attempt: 1}) do
    # Schedule next iteration BEFORE delivery
    args
    |> new(schedule_in: @one_day)
    |> Oban.insert!()

    deliver_email(email)
  end

  def perform(%{args: %{"email" => email}}) do
    # Subsequent retries just deliver
    deliver_email(email)
  end
end
```

---

## Troubleshooting

**Source:** https://hexdocs.pm/oban/troubleshooting.html

### Jobs Stuck in Executing State

**Problem:** Jobs remain in `executing` status after deployment/restart.

**Solutions:**

1. **Increase shutdown grace period:**

```elixir
config :my_app, Oban,
  shutdown_grace_period: :timer.seconds(60)
```

2. **Enable Lifeline plugin:**

```elixir
config :my_app, Oban,
  plugins: [
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(10)}
  ]
```

### Plugins Not Running (Multi-Node)

**Problem:** Cron/Pruner stop functioning when web nodes become leader.

**Solution:** Disable leadership on non-worker nodes:

```elixir
# Web nodes
config :my_app, Oban, peer: false
```

### @reboot Jobs Not Running in Development

**Problem:** Restart jobs don't execute immediately after restart.

**Solutions:**

1. **Use Global peer in dev:**

```elixir
# config/dev.exs
config :my_app, Oban,
  peer: Oban.Peers.Global
```

2. **Wait 30s for leadership acquisition**

3. **Clear peers table:**

```sql
DELETE FROM oban_peers;
```

### PgBouncer Transaction Pooling Issues

**Problem:** LISTEN/NOTIFY disabled, breaking job triggers.

**Solutions:**

1. **Use PG notifier:**

```elixir
config :my_app, Oban,
  notifier: Oban.Notifiers.PG
```

2. **Switch to session pooling in PgBouncer**

3. **Use dedicated repo without PgBouncer**

### Migrations Re-running

**Problem:** Missing version comment causes all migrations to re-run.

**Solution:** Set table comment manually:

```sql
COMMENT ON TABLE public.oban_jobs IS '13';
```

### Verifying Configuration

**Source:** https://github.com/oban-bg/oban/blob/main/guides/introduction/installation.md

```elixir
# In IEx
iex> Oban.config()
%Oban.Config{repo: MyApp.Repo, queues: [default: 10], ...}
```

### Queue Control

**Source:** https://hexdocs.pm/oban/Oban.html

```elixir
# Pause queue
Oban.pause_queue(queue: :default)

# Resume queue
Oban.resume_queue(queue: :default)

# Scale queue
Oban.scale_queue(queue: :default, limit: 20)

# Stop queue
Oban.stop_queue(queue: :default)

# Check queue status
Oban.check_queue(queue: :default)
```

---

## Oban Pro Features

**Source:** https://oban.pro/ and https://context7.com/oban-bg/oban/llms.txt

### Free vs Pro Comparison

**Open Source (Free):**

- Database-backed persistence with retries
- Automatic error handling
- Transaction safety
- Basic instrumentation
- Job retention for monitoring
- Queue isolation
- Unique jobs (with race conditions)
- Cron scheduling
- Pruning plugin

**Oban Pro (Paid):**

### Pro Features

#### 1. Smart Engine

**Source:** https://oban.pro/docs/pro/1.6.7/Oban.Pro.Engines.Smart.html

- **Global concurrency** — Limits concurrent jobs across all nodes
- **Rate limiting** — Controls job execution within time windows (sliding window)
- **Queue partitioning** — Segment queues so limits apply separately per partition
- **Index-backed uniqueness** — Race-condition-free uniqueness via database index
- **Performance:** 92% fewer database queries, 96% fewer transactions

#### 2. Workflows & Orchestration

**Source:** https://oban.pro/

- Complex multi-step job coordination
- Cascading context between steps
- Nested sub-workflows
- Fully distributed execution

#### 3. DynamicQueues Plugin

**Source:** https://oban.pro/docs/pro/1.1.5/Oban.Pro.Plugins.DynamicQueues.html

- Runtime queue configuration
- Persist changes across restarts
- Node-specific queue limiting
- Global queue management across cluster

```elixir
# Example
Oban.Pro.DynamicQueues.set_queue(MyApp.Oban,
  queue: :exports,
  limit: 5,
  local_limit: 2,
  rate_limit: {100, :per_minute}
)
```

#### 4. DynamicPruner Plugin

**Source:** https://github.com/oban-bg/oban/blob/main/guides/upgrading/v2.0.md

- Per-state retention periods
- Cron-style scheduling

```elixir
config :my_app, Oban,
  plugins: [{
    Oban.Pro.Plugins.DynamicPruner,
    state_overrides: [
      completed: {:max_age, {1, :day}},
      discarded: {:max_age, {1, :month}}
    ]
  }]
```

#### 5. Additional Pro Features

**Source:** https://oban.pro/

- **Decorators** — Convert functions into background jobs
- **Relay** — Distributed job execution with result awaiting
- **Job chaining** — Sequential task orchestration
- **Structured arguments** — Validation for job args
- **Batched inserts** — Parameterized bulk operations

### Pricing

Pricing not publicly available in documentation. Contact Oban directly via https://oban.pro/

---

## Recent Changes (v2.20)

**Source:** https://github.com/oban-bg/oban/blob/main/CHANGELOG.md and https://hexdocs.pm/oban/changelog.html

### Version 2.20.0 (2025-08-13)

#### New Features

**1. Update Job Function**

`Oban.update_job/2,3` for safely modifying existing jobs:

```elixir
{:ok, updated_job} = Oban.update_job(job_id, %{
  args: %{new_arg: "value"},
  max_attempts: 5,
  priority: 1
})
```

- Transaction-based locking for consistency
- Restricted to curated fields (`:args`, `:max_attempts`, `:meta`, `:priority`, `:queue`, `:scheduled_at`, `:tags`)

**2. Unique State Groups**

Predefined state groups replace manual lists:

```elixir
# Old way (before v2.20)
use Oban.Worker, unique: [states: [:scheduled]]

# New way (v2.20+)
use Oban.Worker, unique: [states: :scheduled]
```

**Groups:** `:all`, `:incomplete`, `:scheduled`, `:successful`

**3. Nested Plugin Supervision**

Plugins run in secondary supervision tree with more lenient restart limits, improving resilience.

**4. Migration V13**

Adds compound indexes for Pruner performance with discarded/cancelled jobs.

**5. Public API: `with_dynamic_repo/2`**

Now exposed for custom plugins and extensions.

#### Bug Fixes

- Worker validation for missing `:fields` when `:keys` specified
- `perform_job/1,2,3` clause generation in testing
- Inline job execution state restrictions
- Crontab range error messaging

### Version 2.20.1 (2025-08-15)

Minor bug fixes for worker validation.

### Version 2.19.0

**Key Features:**

- MySQL support via Dolphin engine
- `oban.install` mix task for simplified setup
- `check_all_queues/1` for gathering queue status
- `delete_job/2` and `delete_all_jobs/2` operations

---

## Additional Resources

### Official Documentation

- **Main Docs:** https://hexdocs.pm/oban/
- **GitHub:** https://github.com/oban-bg/oban
- **Oban Pro:** https://oban.pro/
- **Changelog:** https://hexdocs.pm/oban/changelog.html

### Guides

- **Installation:** https://hexdocs.pm/oban/introduction/installation.html
- **Testing:** https://hexdocs.pm/oban/testing.html
- **Unique Jobs:** https://hexdocs.pm/oban/unique_jobs.html
- **Error Handling:** https://hexdocs.pm/oban/error_handling.html
- **Troubleshooting:** https://hexdocs.pm/oban/troubleshooting.html
- **Periodic Jobs:** https://github.com/oban-bg/oban/blob/main/guides/learning/periodic_jobs.md
- **Reliable Scheduling:** https://github.com/oban-bg/oban/blob/main/guides/recipes/reliable-scheduling.md

### Community Resources

- **Oban Training (Livebook):** https://github.com/oban-bg/oban_training
- **Elixir Forum:** Search for "Oban" on https://elixirforum.com
- **Elixir Merge Articles:** https://elixirmerge.com (search "Oban")

### Telemetry & Monitoring

- **Oban Telemetry:** https://hexdocs.pm/oban/Oban.Telemetry.html
- **OpenTelemetry Integration:** https://hex.pm/packages/opentelemetry_oban
- **Oban Web (Pro):** https://oban.pro/docs/web/ (dashboard for monitoring)

### Blog Posts

- **Oban Creator (Sorentwo):** https://sorentwo.com (search "Oban")
- **Oban Recipes - Unique Jobs:** https://sorentwo.com/2019/07/18/oban-recipes-part-1-unique-jobs

---

## Quick Reference Commands

### IEx Helpers

```elixir
# Verify configuration
Oban.config()

# Check queue status
Oban.check_queue(queue: :default)

# Pause/resume queue
Oban.pause_queue(queue: :default)
Oban.resume_queue(queue: :default)

# Scale queue
Oban.scale_queue(queue: :default, limit: 20)

# Cancel job
Oban.cancel_job(job_id)

# Drain queue (testing)
Oban.drain_queue(queue: :default)
```

### Mix Tasks

```bash
# Install Oban
mix oban.install

# Generate migration
mix ecto.gen.migration upgrade_oban_to_v13

# Run migrations
mix ecto.migrate
```

---

**End of Reference Document**
