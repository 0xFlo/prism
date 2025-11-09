# Phoenix and Ecto Official Documentation Research

**Date**: 2025-11-08
**Purpose**: Background job patterns, database operations, telemetry, and testing best practices
**Sources**: Official Phoenix and Ecto documentation (hexdocs.pm), Phoenix Framework blog, community resources

---

## Table of Contents

1. [Background Jobs and Scheduled Tasks](#background-jobs-and-scheduled-tasks)
2. [Ecto Database Operations](#ecto-database-operations)
3. [Phoenix Telemetry Integration](#phoenix-telemetry-integration)
4. [Testing Patterns](#testing-patterns)
5. [Phoenix 1.7/1.8 Updates](#phoenix-1718-updates)
6. [Performance Optimization](#performance-optimization)
7. [Migration Best Practices](#migration-best-practices)

---

## Background Jobs and Scheduled Tasks

### Official Guidance

Phoenix does not have built-in background job infrastructure. The framework relies on Elixir/OTP primitives and third-party libraries.

**Source**: Community consensus from Stack Overflow, Elixir Forum discussions (2017-2024)

### Three Primary Approaches

#### 1. Task Module (Simple Async Operations)

For fire-and-forget operations like sending emails:

```elixir
Task.start(fn ->
  MyApp.Mailer.send_welcome_email(user)
end)
```

**Limitations**:
- No retry logic
- No persistence
- Process dies on error

**Best Practice**: Use `Task.Supervisor` for supervised tasks in production.

#### 2. GenServer Pattern (Periodic Tasks)

For scheduled recurring work:

```elixir
defmodule MyApp.PeriodicWorker do
  use GenServer

  @interval :timer.minutes(5)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_work()
    {:ok, state}
  end

  @impl true
  def handle_info(:work, state) do
    perform_work()
    schedule_work()
    {:noreply, state}
  end

  defp schedule_work do
    Process.send_after(self(), :work, @interval)
  end

  defp perform_work do
    # Your periodic work here
  end
end
```

**Key Points**:
- Use `Process.send_after/3` instead of `:timer.send_interval/2` to prevent queue overflow
- Always schedule next run AFTER work completes (prevents overlap)
- Add to supervision tree in `application.ex`

**Source**: Stack Overflow (2016-2024), Elixir Forum discussions

#### 3. Oban (Database-Backed Jobs)

For production-grade background jobs with persistence, retries, and scheduling:

```elixir
# Add to mix.exs
{:oban, "~> 2.18"}

# Configure in config.exs
config :my_app, Oban,
  repo: MyApp.Repo,
  queues: [default: 10, mailers: 20, exports: 5],
  plugins: [Oban.Plugins.Pruner]

# Define a worker
defmodule MyApp.Workers.EmailWorker do
  use Oban.Worker, queue: :mailers, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    user = MyApp.Accounts.get_user!(user_id)
    MyApp.Mailer.send_welcome_email(user)
    :ok
  end
end

# Enqueue job
%{user_id: user.id}
|> MyApp.Workers.EmailWorker.new()
|> Oban.insert()
```

**Source**: Oban documentation, AppSignal blog (2020)

### Best Practices for Background Jobs

From **"Best Practices for Background Jobs in Elixir"** (AppSignal Blog, 2020):

#### 1. Implement a Kill Switch

Enable rapid disabling without redeployment:

```elixir
def run do
  return if !enabled?()
  # job logic
end

defp enabled? do
  # Check Redis flag, database record, or config
  Application.get_env(:my_app, :job_enabled, true)
end
```

**Why**: Prevents disasters during outages (e.g., sending duplicate emails).

#### 2. Always Use Batching

Process records in chunks:

```elixir
@batch_size 100

defp get_users do
  MyApp.User
  |> where(confirmation_email_sent: false)
  |> limit(^@batch_size)
  |> MyApp.Repo.all()
end
```

**Why**: Protects against unexpected data growth overwhelming the system.

#### 3. Prevent Overlapping Executions

With GenServer:
```elixir
def handle_info(:poll, state) do
  perform_work()
  Process.send_after(self(), :poll, @period)  # Schedule AFTER completion
  {:noreply, state}
end
```

With Quantum:
```elixir
config :my_app, MyApp.Scheduler,
  jobs: [
    {"*/5 * * * *", {MyApp.Job, :run, []}, overlap: false}
  ]
```

#### 4. Provide Manual Execution Mode

Support debugging with explicit locking:

```elixir
def run do
  lock("example_job", fn ->
    get_users() |> Enum.each(&process_user/1)
  end)
end

def run_manually(users) when is_list(users) do
  lock("example_job", fn ->
    users |> Enum.each(&process_user/1)
  end)
end

defp lock(key, fun) do
  # Use distributed lock (e.g., redis_mutex, Redlock)
  Mutex.under(MyApp.Mutex, key, fun)
end
```

### Supervision Tree Integration

Add GenServers to `lib/my_app/application.ex`:

```elixir
def start(_type, _args) do
  children = [
    MyApp.Repo,
    {Phoenix.PubSub, name: MyApp.PubSub},

    # Background workers
    {MyApp.PeriodicWorker, []},
    {MyApp.AnotherWorker, name: MyApp.AnotherWorker},

    MyAppWeb.Endpoint
  ]

  opts = [strategy: :one_for_one, name: MyApp.Supervisor]
  Supervisor.start_link(children, opts)
end
```

**Critical Best Practice**: Always use `{Module, args}` tuple format. Using bare module names (`Module` instead of `{Module, []}`) can cause silent startup failures if `child_spec/1` isn't implemented.

**Source**: Project CLAUDE.md

---

## Ecto Database Operations

### Repo.insert_all - Bulk Inserts

**Official Source**: https://hexdocs.pm/ecto/Ecto.Repo.html

#### Basic Usage

```elixir
entries = [
  %{title: "Post 1", body: "Content", inserted_at: DateTime.utc_now(), updated_at: DateTime.utc_now()},
  %{title: "Post 2", body: "Content", inserted_at: DateTime.utc_now(), updated_at: DateTime.utc_now()}
]

{count, results} = Repo.insert_all(Post, entries)
```

#### Key Limitations

From official docs:

> - Autogenerated values like `Ecto.UUID` and timestamps won't be autogenerated
> - Timestamps must be set explicitly
> - Cannot insert across multiple tables; associations not supported
> - No changeset validation (this is by design for performance)

#### Returning Inserted Records

```elixir
{2, posts} = Repo.insert_all(Post, entries, returning: [:id, :title])
```

#### Using Query Sources

Insert aggregated data from queries:

```elixir
query = from p in Post,
  join: c in assoc(p, :comments),
  select: %{
    author_id: p.author_id,
    posts: count(p.id, :distinct),
    interactions: sum(p.likes) + count(c.id)
  },
  group_by: p.author_id

Repo.insert_all(AuthorStats, query)
```

#### Upsert Operations

```elixir
# Replace all fields on conflict
Repo.insert_all(
  Post,
  [%{id: 1, title: "New Title", version: 2}],
  conflict_target: [:id],
  on_conflict: :replace_all
)

# Replace specific fields
Repo.insert_all(
  Post,
  entries,
  conflict_target: [:id],
  on_conflict: {:replace, [:title, :body, :updated_at]}
)

# Conditional update
conflict_query = from(p in Post,
  update: [set: [
    title: fragment("EXCLUDED.title"),
    version: fragment("EXCLUDED.version")
  ]],
  where: fragment("EXCLUDED.version > ?", p.version)
)

Repo.insert_all(
  Post,
  entries,
  conflict_target: [:id],
  on_conflict: conflict_query
)
```

#### PostgreSQL Parameter Limits

**Critical**: PostgreSQL has a hard limit of **65,535 parameters** per query.

```elixir
# BAD: 5000 records × 14 fields = 70,000 params (exceeds limit)
Repo.insert_all(Performance, generate_records(5000))

# GOOD: Batch into chunks
generate_records(5000)
|> Enum.chunk_every(4000)
|> Enum.each(&Repo.insert_all(Performance, &1))
```

**Safe batch size**: `(65,535 / field_count) * 0.9`

**Source**: Project performance tests

#### Placeholders for Large Data

Reduce wire traffic with repeated values:

```elixir
placeholders = %{blob: large_blob_of_text()}
entries = [
  %{title: "v1", body: {:placeholder, :blob}},
  %{title: "v2", body: {:placeholder, :blob}}
]
Repo.insert_all(Post, entries, placeholders: placeholders)
```

### Transaction Handling

**Official Source**: https://hexdocs.pm/ecto/Ecto.Repo.html

#### Modern transact/2 Function

Replaces deprecated `transaction/2`:

```elixir
# Basic transaction
Repo.transact(fn ->
  alice = Repo.insert!(alice_changeset)
  bob = Repo.insert!(bob_changeset)
  {:ok, [alice, bob]}
end)

# With repo argument
Repo.transact(fn repo ->
  repo.insert!(changeset)
end)
```

#### Nested Transactions

From official docs:

> "Nested calls execute without additional wrapping. If an inner transaction rolls back, the entire outer transaction is aborted."

```elixir
{:error, :rollback} =
  Repo.transact(fn ->
    {:error, :posting_not_allowed} =
      Repo.transact(fn ->
        Repo.rollback(:posting_not_allowed)
      end)
  end)
```

#### Ecto.Multi for Complex Operations

**Official Source**: https://hexdocs.pm/ecto/Ecto.Multi.html

Best practice for composable transactions:

```elixir
alias Ecto.Multi

Multi.new()
|> Multi.insert(:post, post_changeset)
|> Multi.insert(:log, Log.changeset(%Log{}, %{action: "create"}))
|> Multi.run(:notify, fn _repo, %{post: post} ->
  send_notification(post)
  {:ok, post}
end)
|> Repo.transact()
```

**Result handling**:

```elixir
case result do
  {:ok, %{post: post, log: log, notify: _}} ->
    # All operations succeeded

  {:error, failed_op, failed_value, changes_so_far} ->
    # One operation failed; transaction rolled back
end
```

**Real-world example** (Password reset):

```elixir
defmodule PasswordManager do
  def reset(account, params) do
    Multi.new()
    |> Multi.update(:account, Account.password_reset_changeset(account, params))
    |> Multi.insert(:log, Log.password_reset_changeset(account, params))
    |> Multi.delete_all(:sessions, Ecto.assoc(account, :sessions))
  end
end

Repo.transact(PasswordManager.reset(account, params))
```

**Key advantages**:
- Decouples transaction definition from execution
- Supports testing without database (via `to_list/1`)
- Automatic rollback on any failure
- Access to previous step results in later steps

#### When to Use Multi vs. Simple Transactions

From official docs:

> "Ecto.Multi is particularly useful when the set of operations is dynamic. For most other use cases, using regular control flow within Repo.transact(fun) and returning {:ok, result} or {:error, reason} is more straightforward."

### Query Optimization and N+1 Prevention

**Official Source**: https://hexdocs.pm/ecto/Ecto.Query.html

#### Preload Strategies

**Separate queries (default)**:
```elixir
Repo.all from p in Post, preload: [:comments]
```
Executes: 1 query for posts + 1 query for all comments

**Joined preloading**:
```elixir
Repo.all from p in Post,
  join: c in assoc(p, :comments),
  where: c.published_at > p.updated_at,
  preload: [comments: c]
```
Executes: 1 query fetching both posts and comments

#### When to Use Joins vs. Separate Queries

From official docs:

> "A good default is to only use joins in preloads if you're already joining the associations in the main query."

**Trade-offs**:
- **Joins**: Reduce round trips, but can duplicate data in result set
- **Separate queries**: No duplication, but multiple database calls

#### Dynamic Preloading with Subqueries

```elixir
# Preload with custom ordering
comments_query = from c in Comment, order_by: c.published_at
Repo.all from p in Post, preload: [comments: ^comments_query]

# Limit preloaded associations (top 5 per post)
ranking_query = from c in Comment,
  select: %{id: c.id, row_number: over(row_number(), :posts_partition)},
  windows: [posts_partition: [partition_by: :post_id, order_by: :popularity]]

comments_query = from c in Comment,
  join: r in subquery(ranking_query),
  on: c.id == r.id and r.row_number <= 5

Repo.all from p in Post, preload: [comments: ^comments_query]
```

#### Query Composition

Ecto queries are composable:

```elixir
query = from u in User, where: u.age > 18
query = from u in query, select: u.name
query = from u in query, order_by: u.created_at
Repo.all(query)
```

#### Dynamic Filtering

```elixir
# Bindingless approach (data-driven)
filters = [country: "USA", name: "New York"]
from(City, where: ^filters)

# Or-based filtering
from(c in City, where: [country: "Sweden"], or_where: ^filters)
```

### Connection Pooling

**Official Source**: https://hexdocs.pm/phoenix/ecto.html, DBConnection documentation

#### Configuration

```elixir
# config/dev.exs
config :my_app, MyApp.Repo,
  username: "postgres",
  password: "postgres",
  database: "myapp_dev",
  hostname: "localhost",
  pool_size: 10  # Default
```

#### How Pooling Works

From documentation:

> "Ecto keeps a pool of connections to the database using db_connection. When you initiate a query, a connection from this pool is borrowed, used to execute the query, and returned to the pool after completion."

#### Sizing Guidelines

**Default**: `pool_size: 10`

**Total connections**: `instances × pool_size`

Example: 3 app instances × 10 connections = 30 database connections

**Best practices**:
1. Start with defaults
2. Monitor for "connection not available" errors
3. Optimize slow queries before increasing pool size
4. Increase `:queue_target` and `:queue_interval` for bursty workloads
5. Be cautious: larger pools increase memory and can degrade database performance

**Source**: Stack Overflow discussions, DBConnection docs

#### Checkout for Multiple Operations

Reuse connection across multiple queries:

```elixir
Repo.transact(fn ->
  Repo.checked_out?() #=> true
  # All queries use same connection
  Repo.all(Post)
  Repo.all(Comment)
end)
```

---

## Phoenix Telemetry Integration

**Official Source**: https://hexdocs.pm/phoenix/telemetry.html

### Overview

From official docs:

> "The `:telemetry` library allows you to emit events at various stages of an application's lifecycle with the ability to aggregate them as metrics and send data to reporting destinations."

### Event Structure

**Three components**:
1. **Name**: List identifier (e.g., `[:phoenix, :endpoint, :stop]`)
2. **Measurements**: Map of numeric values (e.g., `%{duration: 1234}`)
3. **Metadata**: Context data (e.g., `%{conn: %Plug.Conn{}}`)

### Telemetry Supervisor Setup

```elixir
# lib/my_app_web/telemetry.ex
defmodule MyAppWeb.Telemetry do
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

  def metrics do
    [
      # Request duration
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}),

      # Route-specific duration
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}),

      # VM metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  defp periodic_measurements do
    [
      {MyApp, :measure_users, []},
      {:process_info,
        event: [:my_app, :my_server],
        name: MyApp.MyServer,
        keys: [:message_queue_len, :memory]}
    ]
  end
end
```

Add to supervision tree:

```elixir
# lib/my_app/application.ex
children = [
  MyAppWeb.Telemetry,
  MyApp.Repo,
  MyAppWeb.Endpoint
]
```

### Five Metric Types

**Official docs**:

> "`Telemetry.Metrics` ships with five metric type functions"

```elixir
# Counter - counts occurrences
counter("phoenix.endpoint.stop.duration")

# Distribution - histogram with buckets
distribution("phoenix.endpoint.stop.duration")

# Summary - statistical aggregation (mean, percentiles)
summary("phoenix.endpoint.stop.duration",
  unit: {:native, :millisecond})

# Last Value - most recent measurement
last_value("my_app.users.total")

# Gauge - instantaneous measurement
gauge("my_app.memory.usage")
```

### Tagging and Filtering

**Group by route**:
```elixir
summary("phoenix.router_dispatch.stop.duration",
  tags: [:route],
  unit: {:native, :millisecond})
```

**Extract HTTP method from metadata**:
```elixir
summary("phoenix.router_dispatch.stop.duration",
  tags: [:method, :route],
  tag_values: &get_and_put_http_method/1,
  unit: {:native, :millisecond})

defp get_and_put_http_method(%{conn: %{method: method}} = metadata) do
  Map.put(metadata, :method, method)
end
```

**LiveView mount metrics**:
```elixir
summary("phoenix.live_view.mount.stop.duration",
  unit: {:native, :millisecond},
  tags: [:view, :connected?],
  tag_values: &live_view_metric_tag_values/1)

defp live_view_metric_tag_values(metadata) do
  metadata
  |> Map.put(:view, inspect(metadata.socket.view))
  |> Map.put(:connected?, get_connection_status(
      Phoenix.LiveView.connected?(metadata.socket)))
end
```

### Custom Events

**Emitting events**:

```elixir
:telemetry.execute(
  [:my_app, :users],
  %{total: MyApp.users_count()},
  %{}
)
```

**Complete GenServer example**:

```elixir
defmodule MyApp.MyServer do
  use GenServer

  @prefix [:my_app, :my_server, :call]

  def start_link(fun) do
    GenServer.start_link(__MODULE__, fun, name: __MODULE__)
  end

  def call!, do: GenServer.call(__MODULE__, :called)

  @impl true
  def init(fun) when is_function(fun, 0), do: {:ok, fun}

  @impl true
  def handle_call(:called, _from, fun) do
    result = telemetry_span(fun)
    {:reply, result, fun}
  end

  defp telemetry_span(fun) do
    start_time = emit_start()

    try do
      fun.()
    catch
      kind, reason ->
        stacktrace = System.stacktrace()
        duration = System.monotonic_time() - start_time
        emit_exception(duration, kind, reason, stacktrace)
        :erlang.raise(kind, reason, stacktrace)
    else
      result ->
        duration = System.monotonic_time() - start_time
        emit_stop(duration)
        result
    end
  end

  defp emit_start do
    start_time_mono = System.monotonic_time()
    :telemetry.execute(@prefix ++ [:start], %{system_time: System.system_time()}, %{})
    start_time_mono
  end

  defp emit_stop(duration) do
    :telemetry.execute(@prefix ++ [:stop], %{duration: duration}, %{})
  end

  defp emit_exception(duration, kind, reason, stacktrace) do
    :telemetry.execute(
      @prefix ++ [:exception],
      %{duration: duration},
      %{kind: kind, reason: reason, stacktrace: stacktrace}
    )
  end
end
```

**Corresponding metrics**:

```elixir
def metrics do
  [
    last_value("my_app.my_server.memory", unit: :byte),
    last_value("my_app.my_server.message_queue_len"),
    summary("my_app.my_server.call.stop.duration"),
    counter("my_app.my_server.call.exception")
  ]
end
```

### Periodic Measurements

```elixir
defp periodic_measurements do
  [
    {MyApp, :measure_users, []},
    {:process_info,
      event: [:my_app, :my_server],
      name: MyApp.MyServer,
      keys: [:message_queue_len, :memory]}
  ]
end
```

Implement measurement function:

```elixir
defmodule MyApp do
  def measure_users do
    :telemetry.execute(
      [:my_app, :users],
      %{total: MyApp.users_count()},
      %{}
    )
  end
end
```

### Reporters

**Available options**:
- `Telemetry.Metrics.ConsoleReporter` - Development logging
- `Phoenix.LiveDashboard` - Real-time UI visualization
- Community: StatsD, Prometheus, DataDog, InfluxDB, etc.

### Project-Specific Pattern

From project CLAUDE.md:

```elixir
# lib/gsc_analytics/data_sources/gsc/telemetry/audit_logger.ex
defmodule GscAnalytics.DataSources.GSC.Telemetry.AuditLogger do
  require Logger

  def handle_event([:gsc_analytics, :api, :request], measurements, metadata, _config) do
    log_entry = %{
      ts: DateTime.utc_now() |> DateTime.to_iso8601(),
      event: "api.request",
      measurements: %{
        duration_ms: measurements.duration_ms,
        rows: measurements.rows
      },
      metadata: %{
        operation: metadata.operation,
        site_url: metadata.site_url,
        date: metadata.date,
        rate_limited: metadata.rate_limited
      }
    }

    Logger.info(JSON.encode!(log_entry), [domain: [:gsc, :audit]])
  end
end

# Attach handlers in application.ex
:telemetry.attach_many(
  "gsc-audit-logger",
  [
    [:gsc_analytics, :api, :request],
    [:gsc_analytics, :sync, :complete],
    [:gsc_analytics, :auth, :token_refresh]
  ],
  &GscAnalytics.DataSources.GSC.Telemetry.AuditLogger.handle_event/4,
  nil
)
```

---

## Testing Patterns

### DataCase for Database Tests

**Official Source**: https://hexdocs.pm/phoenix/testing_contexts.html

#### Basic Setup

```elixir
# test/support/data_case.ex
defmodule MyApp.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias MyApp.Repo
      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import MyApp.DataCase
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(MyApp.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end
end
```

#### Test Configuration

```elixir
# config/test.exs
config :my_app, MyApp.Repo,
  username: "postgres",
  password: "postgres",
  database: "myapp_test",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox

# test/test_helper.exs
Ecto.Adapters.SQL.Sandbox.mode(MyApp.Repo, :manual)
ExUnit.start()
```

### SQL Sandbox

**Official Source**: https://hexdocs.pm/ecto_sql/Ecto.Adapters.SQL.Sandbox.html

#### How It Works

From official docs:

> "The sandbox works by wrapping each test in a transaction. When the test completes, the transaction is rolled back, effectively erasing all data created in the test."

#### Ownership Modes

**Manual Mode**:
```elixir
Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
```
Tests must explicitly checkout connections.

**Shared Mode**:
```elixir
setup do
  :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
end
```
All processes automatically use the test's connection.

#### Async Testing

```elixir
defmodule MyApp.MyTest do
  use MyApp.DataCase, async: true  # Enable async

  test "creates post" do
    assert %Post{} = Repo.insert!(%Post{title: "Test"})
  end
end
```

**Important**: Only PostgreSQL supports concurrent async tests. MySQL's transaction implementation can cause deadlocks.

#### Multi-Process Testing

**Allowances approach** (async-safe):
```elixir
test "worker queries database" do
  worker = Process.whereis(MyApp.Worker)
  Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), worker)
  GenServer.call(MyApp.Worker, :run_query)
end
```

**Shared mode approach** (async: false):
```elixir
setup do
  :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
end
```

#### LiveView Testing with start_owner!

For processes that outlive the test:

```elixir
setup tags do
  pid = Ecto.Adapters.SQL.Sandbox.start_owner!(MyApp.Repo, shared: not tags[:async])
  on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  :ok
end
```

**Why**: Separates connection owner from test process, preventing "owner exited" errors.

#### Common Issues

**"Owner Exited" Error**:

Cause: Test process finished while client still uses connection.

Solutions:
- Use synchronous calls (`GenServer.call` not `cast`)
- Use `start_supervised!` for test processes
- Add `on_exit` callbacks for dynamic supervisors:

```elixir
on_exit(fn ->
  for {_, pid, _, _} <- DynamicSupervisor.which_children(Supervisor) do
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, _, _, _}, :infinity
  end
end)
```

**Ownership Timeout**:

For long-running tests or debugging:

```elixir
# In config
config :my_app, MyApp.Repo,
  ownership_timeout: 300_000  # 5 minutes

# Per-checkout
Ecto.Adapters.SQL.Sandbox.checkout(Repo, ownership_timeout: 300_000)
```

#### Deadlock Prevention

From official docs:

> "Use unique test data to dramatically reduce contention. Some teams report test suites running 2x to 3x faster."

**Bad**:
```elixir
def insert_user do
  Repo.insert!(%User{email: "test@example.com"})
end
```

**Good**:
```elixir
def insert_user do
  unique_email = "test-#{System.unique_integer([:positive])}@example.com"
  Repo.insert!(%User{email: unique_email})
end
```

### Test Organization

```elixir
describe "posts" do
  test "list_posts/0 returns all posts" do
    post = post_fixture()
    assert Blog.list_posts() == [post]
  end

  test "get_post!/1 returns the post with given id" do
    post = post_fixture()
    assert Blog.get_post!(post.id) == post
  end
end
```

### Schema Validation Testing

```elixir
defmodule MyApp.Blog.PostTest do
  use MyApp.DataCase, async: true
  alias MyApp.Blog.Post

  test "title must be at least two characters long" do
    changeset = Post.changeset(%Post{}, %{title: "I"})
    assert %{title: ["should be at least 2 character(s)"]} = errors_on(changeset)
  end
end
```

### Automated Database Setup

```elixir
# mix.exs
defp aliases do
  [
    "test": ["ecto.create --quiet", "ecto.migrate", "test"]
  ]
end
```

From official docs:

> "This automates database creation and migration before test execution."

---

## Phoenix 1.7/1.8 Updates

### Phoenix 1.7 Key Features

**Official Source**: https://phoenixframework.org/blog/phoenix-1.7-final-released

#### Verified Routes

Compile-time route verification using `~p` sigil:

```elixir
# Old style (named routes)
Routes.user_path(conn, :show, user)

# New style (verified routes)
~p"/users/#{user}"
```

**Benefits**:
- Routes appear as readable URLs
- Compiler warns about non-existent routes
- No reverse-lookup needed
- Reduced cognitive overhead

**Query strings**:
```elixir
~p"/posts?page=#{page}"
~p"/posts?#{%{page: 1, sort: "asc"}}"
```

**Setup**:
```elixir
use Phoenix.VerifiedRoutes,
  router: AppWeb.Router,
  endpoint: AppWeb.Endpoint
```

#### Unified HEEx Templates

Function components for both controllers and LiveView:

```elixir
# Old: Separate view modules
defmodule MyAppWeb.PostView do
  use MyAppWeb, :view
end

# New: Function components
defmodule MyAppWeb.PostHTML do
  use MyAppWeb, :html

  attr :post, :map, required: true
  def show(assigns) do
    ~H"""
    <h1>{@post.title}</h1>
    """
  end
end
```

#### Built-in Tailwind Support

Generated apps include Tailwind CSS by default with automatic compilation.

#### LiveView Streams

Efficient handling of large collections:

```elixir
def mount(_params, _session, socket) do
  {:ok, stream(socket, :posts, [])}
end

def handle_params(params, _uri, socket) do
  posts = Blog.list_posts(params)
  {:noreply, stream(socket, :posts, posts, reset: true)}
end
```

Template:
```heex
<tbody id="posts" phx-update="stream">
  <tr :for={{dom_id, post} <- @streams.posts} id={dom_id}>
    <td>{post.title}</td>
  </tr>
</tbody>
```

**Source**: Phoenix 1.7 release blog, hexdocs.pm/phoenix_live_view

### Phoenix 1.8 Key Features

**Official Source**: https://www.phoenixframework.org/blog/phoenix-1-8-released

#### AGENTS.md for LLM Development

New apps include guidance for AI-assisted development.

#### Scopes for Secure Data Access

First-class pattern for multi-tenancy:

```elixir
# Scope struct threads user/org context
defmodule MyApp.Scope do
  defstruct [:user_id, :org_id]
end

# Context functions accept scope
def list_posts(%Scope{user_id: user_id}) do
  from(p in Post, where: p.user_id == ^user_id)
  |> Repo.all()
end
```

All generators (`phx.gen.live`, `phx.gen.html`, `phx.gen.json`) now use scopes.

#### Magic Link Authentication

`phx.gen.auth` defaults to passwordless login:

```bash
mix phx.gen.auth Accounts User users
```

Includes `require_sudo_mode` plug for sensitive operations.

#### daisyUI Integration

Flexible component system on Tailwind:
- Light/dark themes by default
- Built-in theme toggle
- Optional (leaves no footprints if removed)

#### Security Improvements

Updated CSP headers:
```elixir
put_secure_browser_headers(conn)
# Sets: content-security-policy: base-uri 'self'; frame-ancestors 'self';
```

Deprecated headers removed: `x-download-options`, `x-frame-options`

#### Requirements

- Erlang/OTP 25+ required
- Backwards compatible with few deprecations

---

## Performance Optimization

### Task.async_stream for Concurrency

**Official Source**: https://hexdocs.pm/elixir/Task.html

#### Basic Usage

```elixir
strings = ["long string", "longer string", "many strings"]
stream = Task.async_stream(strings, fn text ->
  text |> String.codepoints() |> Enum.count()
end)
results = Enum.to_list(stream)
# [{:ok, 11}, {:ok, 13}, {:ok, 12}]
```

#### Concurrency Configuration

```elixir
Task.async_stream(
  collection,
  MyModule,
  :expensive_function,
  [],
  max_concurrency: System.schedulers_online() * 2,
  timeout: 30_000,
  ordered: false
)
|> Stream.run()  # For side effects only
```

**Options**:
- `:max_concurrency` - Concurrent tasks (default: `System.schedulers_online/0`)
- `:ordered` - Maintain input order (default: `true`; costs memory)
- `:timeout` - Per-task timeout in ms (default: `5000`)
- `:on_timeout` - `:exit` (kill caller) or `:kill_task` (return `{:exit, :timeout}`)
- `:zip_input_on_exit` - Include input in exit tuples

#### Error Handling

Results are always tuples:
```elixir
{:ok, value}  # Success
{:exit, reason}  # Task failed/timed out
{:exit, {input, reason}}  # With :zip_input_on_exit
```

#### Critical Performance Warning

From official docs:

> "Unbound async with take can over-process"

**Problem**:
```elixir
1..100
|> Task.async_stream(fn i -> expensive_work(i) end)
|> Enum.take(10)
# Processes ~16 items, returns 10
```

**Solutions**:
1. Limit input: `Stream.take(enumerable, 10) |> Task.async_stream(...)`
2. Tune `:max_concurrency`
3. Set concurrency as factor of desired results

#### Project Example

From project CLAUDE.md:

```elixir
def fetch_batch_performance(site_url, urls, date, opts \\ []) do
  max_concurrency = Keyword.get(opts, :max_concurrency, 10)

  urls
  |> Task.async_stream(
    fn url ->
      case Client.search_analytics_query(site_url, url, date, date) do
        {:ok, data} -> {:ok, url, data}
        {:error, reason} -> {:error, url, reason}
      end
    end,
    max_concurrency: max_concurrency,
    timeout: 30_000,
    ordered: false
  )
  |> Enum.to_list()
end
```

### LiveView Streams for Large Lists

**Official Source**: https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html

#### When to Use

From documentation:

> "Streams by default for any kind of collection is a good intuition to have - you should use streams any time you don't want to hold the list of items in memory, which is most times."

#### Memory Benefits

- Items temporary; freed immediately after render
- No full collection in server memory
- Only diffs sent to client
- Surgically precise updates

#### Basic Setup

```elixir
def mount(_params, _session, socket) do
  {:ok, stream(socket, :songs, [])}
end

def handle_event("add_song", %{"song" => song_params}, socket) do
  song = Music.create_song!(song_params)
  {:noreply, stream_insert(socket, :songs, song)}
end
```

Template:
```heex
<table>
  <tbody id="songs" phx-update="stream">
    <tr :for={{dom_id, song} <- @streams.songs} id={dom_id} :key={song.id}>
      <td>{song.title}</td>
    </tr>
  </tbody>
</table>
```

**Required**:
- `phx-update="stream"` on parent container
- `:key` attribute for optimal change tracking
- Tuple destructuring: `{dom_id, item}`

#### Limiting Streams

Prevent overwhelming clients:

```elixir
# Keep last 10 items when appending
stream(socket, :songs, songs, at: -1, limit: -10)

# Keep first 10 items when prepending
stream(socket, :songs, songs, at: 0, limit: 10)
```

From docs:

> "This prevents the server from overwhelming the client with new results while also opening up powerful features like virtualized infinite scrolling."

#### Stream Operations

```elixir
# Insert
stream_insert(socket, :songs, song, at: 0)

# Delete
stream_delete(socket, :songs, song)
stream_delete_by_dom_id(socket, :songs, "songs-123")

# Reset
stream(socket, :songs, [], reset: true)
stream(socket, :songs, new_songs, reset: true)
```

### Ecto Query Performance

#### Preload Optimization

Use joins only when already filtering:

```elixir
# Default (separate queries)
posts = Repo.all(from p in Post, preload: [:comments])

# Joined preload (when filtering comments)
posts = Repo.all(
  from p in Post,
    join: c in assoc(p, :comments),
    where: c.published == true,
    preload: [comments: c]
)
```

#### Subquery Preloading

Limit associations efficiently:

```elixir
top_comments = from c in Comment, order_by: [desc: c.score], limit: 5
posts = Repo.all(from p in Post, preload: [comments: ^top_comments])
```

---

## Migration Best Practices

**Official Source**: https://hexdocs.pm/ecto_sql/Ecto.Migration.html

### Reversible Operations

Use `change/0` for automatic rollback:

```elixir
def change do
  create table("products") do
    add :name, :string
    add :price, :decimal

    timestamps()
  end
end
```

**Important**: Not all operations are reversible. From docs:

> "Trying to rollback a non-reversible command will raise an `Ecto.MigrationError`."

### Non-Reversible Operations

```elixir
# BAD: Can't rollback (unknown type)
def change do
  alter table("posts") do
    remove :title
  end
end

# GOOD: Reversible with type
def change do
  alter table("posts") do
    remove :title, :string, default: ""
  end
end
```

### Concurrent Index Creation

For large tables in production:

```elixir
defmodule MyRepo.Migrations.CreateIndexes do
  use Ecto.Migration
  @disable_ddl_transaction true  # Required for concurrency

  def change do
    create index("posts", [:slug], concurrently: true)
  end
end
```

**Configuration** (PostgreSQL):
```elixir
config :app, App.Repo, migration_lock: :pg_advisory_lock
```

### Deferred Constraint Validation

Avoid full table scans:

```elixir
def change do
  create constraint("products", "price_must_be_positive",
    check: "price > 0",
    validate: false  # Defer validation
  )
end

# Later migration
def change do
  execute "ALTER TABLE products VALIDATE CONSTRAINT price_must_be_positive", ""
end
```

### Foreign Key Options

```elixir
create table("comments") do
  add :post_id, references("posts",
    on_delete: :delete_all,  # Cascade deletes
    on_update: :update_all,  # Cascade updates
    validate: false  # Defer validation (PostgreSQL)
  )
end
```

**on_delete options**:
- `:nothing` (default)
- `:delete_all` - Cascade delete
- `:nilify_all` - Set to NULL
- `:restrict` - Prevent deletion
- `{:nilify, [:col1, :col2]}` - Nullify specific columns

### Modifying Foreign Key Constraints

```elixir
def change do
  alter table("comments") do
    modify :post_id, references(:posts, on_delete: :delete_all),
      from: references(:posts, on_delete: :nothing)
  end
end
```

### Upsert-Friendly Unique Indexes

PostgreSQL 15+ null handling:

```elixir
# Allow multiple NULL values
create index("products", [:sku, :category_id], unique: true)

# Treat NULLs as equal (PostgreSQL 15+ only)
create index("products", [:sku, :category_id],
  unique: true,
  nulls_distinct: false
)

# Workaround for older versions
create index("products", [:sku, :category_id], unique: true)
create index("products", [:sku],
  unique: true,
  where: "category_id IS NULL"
)
```

### Partial Indexes

Filter index for specific conditions:

```elixir
create index("products", [:user_id],
  where: "price = 0",
  name: :free_products_index
)
```

### Index Types

```elixir
# GIN index for full-text search
create index("products", ["(to_tsvector('english', name))"],
  name: :products_name_vector,
  using: "GIN"
)

# Expression index
create index("products", ["(lower(name))"],
  name: :products_lower_name_index
)
```

### Comments for Documentation

```elixir
def change do
  create table("weather", comment: "Hourly weather data") do
    add :city, :string, comment: "City name"
    add :temp, :integer, comment: "Temperature in Celsius"
  end

  create index("weather", [:city], comment: "City lookup index")

  create constraint("weather", "temp_range",
    check: "temp BETWEEN -100 AND 100",
    comment: "Valid temperature range"
  )
end
```

### Rollback Strategy

Always provide explicit rollback for complex operations:

```elixir
def up do
  create table("posts")
  create index("posts", [:slug])
end

def down do
  drop index("posts", [:slug])
  drop table("posts")
end
```

### Best Practices Summary

From official docs and community resources:

1. **Keep migrations small** - Easier to debug and rollback
2. **Use `change/0`** - Reduces boilerplate for reversible operations
3. **Test rollbacks** - Ensure `down/0` completeness
4. **Avoid long locks** - Defer validations with `validate: false`
5. **Document with comments** - Aid future maintenance
6. **Use concurrent operations** - For large tables in production
7. **Consider null handling** - PostgreSQL 15+ `nulls_distinct` option
8. **Validate foreign keys later** - PostgreSQL-specific optimization

**Advanced resource**: [Safe Ecto Migrations](https://fly.io/phoenix-files/safe-ecto-migrations/)

---

## Summary of Key Sources

### Official Documentation
- **Phoenix Guides**: https://hexdocs.pm/phoenix/
- **Ecto Documentation**: https://hexdocs.pm/ecto/
- **Ecto.Repo**: https://hexdocs.pm/ecto/Ecto.Repo.html
- **Ecto.Multi**: https://hexdocs.pm/ecto/Ecto.Multi.html
- **Ecto.Migration**: https://hexdocs.pm/ecto_sql/Ecto.Migration.html
- **Phoenix.Telemetry**: https://hexdocs.pm/phoenix/telemetry.html
- **Phoenix.VerifiedRoutes**: https://hexdocs.pm/phoenix/Phoenix.VerifiedRoutes.html
- **Phoenix.LiveView**: https://hexdocs.pm/phoenix_live_view/
- **Task**: https://hexdocs.pm/elixir/Task.html
- **SQL Sandbox**: https://hexdocs.pm/ecto_sql/Ecto.Adapters.SQL.Sandbox.html

### Official Blogs
- **Phoenix 1.7 Release**: https://phoenixframework.org/blog/phoenix-1.7-final-released
- **Phoenix 1.8 Release**: https://www.phoenixframework.org/blog/phoenix-1-8-released
- **LiveView 0.19 (Streams)**: https://www.phoenixframework.org/blog/phoenix-liveview-0.19-released

### Community Resources
- **AppSignal Blog**: "Best Practices for Background Jobs in Elixir" (2020)
- **Stack Overflow**: Various threads on GenServer, background jobs, pooling
- **Elixir Forum**: Background job discussions (2016-2024)

### Project-Specific
- **CLAUDE.md**: Project conventions and patterns
- **Performance tests**: PostgreSQL parameter limits, batch sizing

---

## Recommended Next Steps

Based on this research, consider:

1. **Background Jobs**: Implement Oban for production-grade job processing
2. **Telemetry**: Expand audit logging to cover more operations
3. **Testing**: Add performance tests for critical paths
4. **Migrations**: Review for concurrent index creation opportunities
5. **Queries**: Audit for N+1 issues using preload analysis
6. **LiveView**: Consider streams for large collections (500+ items)

---

**End of Research Document**
