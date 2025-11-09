# Elixir/Phoenix Testing Quick Reference

Quick lookup guide for common testing patterns in the GSC Analytics project.

## Table of Contents

- [Test Structure](#test-structure)
- [Assertions](#assertions)
- [LiveView Testing](#liveview-testing)
- [Mocking with Mox](#mocking-with-mox)
- [Database Testing](#database-testing)
- [Async Testing](#async-testing)
- [Common Patterns](#common-patterns)

---

## Test Structure

### Basic Test Module

```elixir
defmodule GscAnalytics.MyModuleTest do
  use GscAnalytics.DataCase, async: true

  alias GscAnalytics.MyModule

  describe "function_name/2" do
    test "handles typical case" do
      assert MyModule.function_name(arg1, arg2) == expected
    end

    test "handles edge case: empty input" do
      assert MyModule.function_name("", arg2) == ""
    end
  end
end
```

### With Setup

```elixir
defmodule GscAnalytics.MyModuleTest do
  use GscAnalytics.DataCase, async: true

  setup do
    user = insert(:user)
    account = insert(:account, user: user)
    {:ok, user: user, account: account}
  end

  test "uses setup data", %{user: user, account: account} do
    assert account.user_id == user.id
  end
end
```

### Named Setup (Composable)

```elixir
setup [:create_account, :create_urls]

defp create_account(_context) do
  {:ok, account: insert(:account)}
end

defp create_urls(%{account: account}) do
  urls = insert_list(3, :performance, account: account)
  {:ok, urls: urls}
end
```

---

## Assertions

### Basic Assertions

```elixir
# Truthy/falsy
assert value
assert value == expected
refute value
refute value == unexpected

# Pattern matching
assert {:ok, result} = function_call()
assert %{key: value} = map

# Equality
assert actual == expected
assert_in_delta 3.14, result, 0.01  # Float comparison
```

### Error Assertions

```elixir
# Raises exception
assert_raise ArgumentError, fn ->
  MyModule.function(invalid_arg)
end

# With message match
assert_raise ArgumentError, ~r/invalid/, fn ->
  MyModule.function(invalid_arg)
end
```

### Message Assertions

```elixir
# Received (already in mailbox)
send(self(), :message)
assert_received :message

# Will receive (wait for it)
Task.async(fn -> send(pid, :message) end)
assert_receive :message, 1000  # Wait 1 second

# Pattern matching
assert_received {:ok, %{data: data}}
assert_receive {:complete, _}, 5000
```

### Ecto Assertions

```elixir
# Record exists
assert Repo.exists?(from u in User, where: u.email == "test@example.com")

# Count
assert Repo.aggregate(User, :count) == 5

# Specific query
query = from u in User, where: u.status == :active
assert [%User{}, %User{}] = Repo.all(query)
```

---

## LiveView Testing

### Basic LiveView Test

```elixir
defmodule GscAnalyticsWeb.DashboardLiveTest do
  use GscAnalyticsWeb.ConnCase
  import Phoenix.LiveViewTest

  test "loads dashboard", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/dashboard")

    assert html =~ "Dashboard"
    assert has_element?(view, "[data-test-id='metrics']")
  end
end
```

### User Interactions

```elixir
test "filters results", %{conn: conn} do
  {:ok, view, _html} = live(conn, ~p"/dashboard")

  # Click
  view |> element("#filter-button") |> render_click()

  # Form change
  view
  |> element("#filter-form")
  |> render_change(%{filter: %{status: "active"}})

  # Form submit
  view
  |> element("#search-form")
  |> render_submit(%{query: "example.com"})

  # Verify result
  assert has_element?(view, "[data-url='example.com']")
end
```

### Element Checks

```elixir
# Element exists
assert has_element?(view, "#my-id")
assert has_element?(view, "[data-test-id='foo']")
assert has_element?(view, "button", "Click Me")

# Element doesn't exist
refute has_element?(view, "#missing")

# Find element
element = view |> element("#my-form")
```

### Testing Components

```elixir
# Using render_component
result = render_component(MyComponent, value: 100, label: "Test")
assert result =~ "100"

# Using ~H sigil
assigns = %{value: 100, label: "Test"}
html = rendered_to_string(~H"""
  <.my_component value={@value} label={@label} />
""")
assert html =~ "100"
```

### PubSub Updates

```elixir
test "receives real-time updates", %{conn: conn} do
  {:ok, view, _html} = live(conn, ~p"/dashboard")

  # Trigger PubSub broadcast
  Phoenix.PubSub.broadcast(
    GscAnalytics.PubSub,
    "sync:progress",
    {:progress, %{completed: 10}}
  )

  # LiveView updates automatically
  assert render(view) =~ "10 completed"
end
```

---

## Mocking with Mox

### Setup (test_helper.exs)

```elixir
# Define mocks
Mox.defmock(GscAnalytics.HTTPClient.Mock, for: GscAnalytics.HTTPClient)

# Allow async tests to use mocks
Application.put_env(:gsc_analytics, :http_client, GscAnalytics.HTTPClient.Mock)
```

### Using Mocks in Tests

```elixir
defmodule GscAnalytics.SyncTest do
  use GscAnalytics.DataCase, async: true
  import Mox

  # Verify mocks were called (important!)
  setup :verify_on_exit!

  test "syncs data from API" do
    # expect: Verifies function was called
    GscAnalytics.HTTPClient.Mock
    |> expect(:get, fn url ->
      assert url =~ "searchconsole"
      {:ok, %{data: [%{url: "example.com"}]}}
    end)

    assert {:ok, _result} = GscAnalytics.Sync.sync_yesterday()
  end

  test "handles API errors" do
    GscAnalytics.HTTPClient.Mock
    |> expect(:get, fn _url -> {:error, :timeout} end)

    assert {:error, :api_error} = GscAnalytics.Sync.sync_yesterday()
  end
end
```

### Stub vs Expect

```elixir
# stub: Just provide return value (no call verification)
stub(Mock, :function, fn _args -> :ok end)

# expect: Provide return value AND verify it was called once
expect(Mock, :function, fn _args -> :ok end)

# expect with call count
expect(Mock, :function, 3, fn _args -> :ok end)
```

### Allow for Multi-Process

```elixir
test "async task uses mock" do
  Mock |> expect(:get, fn _url -> {:ok, %{}} end)

  task = Task.async(fn ->
    # Allow task to use test's mock
    allow(Mock, self(), task_pid)
    MyModule.fetch_data()
  end)

  Task.await(task)
end
```

---

## Database Testing

### Sandbox Checkout (Automatic in DataCase)

```elixir
# Already configured in test/support/data_case.ex
setup tags do
  pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: not tags[:async])
  on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  :ok
end
```

### Testing Queries

```elixir
test "queries performance data" do
  # Insert test data
  account = insert(:account)
  url1 = insert(:performance, account: account, clicks: 100)
  url2 = insert(:performance, account: account, clicks: 50)

  # Query
  result = GscAnalytics.ContentInsights.list_urls(account.id, sort_by: :clicks)

  # Assert
  assert [^url1, ^url2] = result
end
```

### Testing Changesets

```elixir
test "validates required fields" do
  changeset = Performance.changeset(%Performance{}, %{})

  refute changeset.valid?
  assert "can't be blank" in errors_on(changeset).url
  assert "can't be blank" in errors_on(changeset).date
end

test "validates URL format" do
  changeset = Performance.changeset(%Performance{}, %{url: "not-a-url"})

  assert "invalid format" in errors_on(changeset).url
end
```

### Testing Associations

```elixir
test "loads associations" do
  account = insert(:account)
  performance = insert(:performance, account: account)

  loaded = Repo.preload(performance, :account)

  assert loaded.account.id == account.id
end
```

---

## Async Testing

### When to Use async: true

```elixir
# ✅ Safe for async
defmodule GscAnalytics.UtilsTest do
  use ExUnit.Case, async: true  # Pure functions

  test "formats date" do
    assert GscAnalytics.Utils.format_date(~D[2024-01-01]) == "2024-01-01"
  end
end

# ✅ Safe for async (with Ecto Sandbox)
defmodule GscAnalytics.ContentInsightsTest do
  use GscAnalytics.DataCase, async: true  # Database in sandbox mode

  test "lists URLs" do
    account = insert(:account)
    assert [] = GscAnalytics.ContentInsights.list_urls(account.id)
  end
end

# ❌ NOT safe for async
defmodule GscAnalytics.AuthenticatorTest do
  use ExUnit.Case, async: false  # GenServer with registered name

  test "refreshes token" do
    # Tests GenServer registered as :authenticator
  end
end
```

### When async: false Required

- Testing GenServers with registered names
- Global process state (ETS, Application env)
- External service calls (unless properly mocked with Mox)
- File system operations
- Using Meck (runtime mocking)

---

## Common Patterns

### Testing GenServers

```elixir
# Unit test (just callbacks)
test "handle_call increments counter" do
  state = %{count: 0}
  assert {:reply, 1, %{count: 1}} = MyServer.handle_call(:increment, self(), state)
end

# Integration test (with started server)
test "server maintains state" do
  {:ok, pid} = MyServer.start_link([])
  assert 1 = MyServer.increment(pid)
  assert 2 = MyServer.increment(pid)
  assert 2 = MyServer.get_count(pid)
end
```

### Testing Background Jobs (Oban)

```elixir
defmodule GscAnalytics.DailySyncWorkerTest do
  use GscAnalytics.DataCase, async: true
  use Oban.Testing, repo: GscAnalytics.Repo

  # Test worker directly
  test "performs sync" do
    args = %{"site" => "sc-domain:example.com"}
    assert :ok = perform_job(DailySyncWorker, args)
  end

  # Test job was enqueued
  test "enqueues sync job" do
    GscAnalytics.schedule_daily_sync()

    assert_enqueued worker: DailySyncWorker
    assert_enqueued worker: DailySyncWorker, queue: :default
  end
end
```

### Testing with Dates/Times

```elixir
test "syncs yesterday's data" do
  # Use fixed dates for consistency
  yesterday = ~D[2024-01-15]

  # If testing "today", inject the date
  assert {:ok, stats} = Sync.sync_yesterday(as_of: ~D[2024-01-16])
  assert stats.date == yesterday
end

test "handles date ranges" do
  start_date = ~D[2024-01-01]
  end_date = ~D[2024-01-31]

  {:ok, stats} = Sync.sync_date_range("site", start_date, end_date)
  assert stats.days_synced == 31
end
```

### Testing Rate Limiting

```elixir
test "respects rate limit" do
  # Make multiple requests
  results = Enum.map(1..10, fn _ ->
    RateLimiter.check_rate("site_key", 5, :timer.seconds(1))
  end)

  # First 5 succeed
  assert Enum.take(results, 5) == List.duplicate(:ok, 5)

  # Rest are rate limited
  assert Enum.drop(results, 5) == List.duplicate({:error, :rate_limited}, 5)
end
```

### Testing with Tags

```elixir
# In test file
@moduletag :integration

describe "slow operations" do
  @describetag :slow

  @tag :external
  test "calls external API" do
    # ...
  end

  @tag timeout: 60_000  # 60 second timeout
  test "long running operation" do
    # ...
  end
end

# Run commands
mix test                          # All tests
mix test --only integration       # Only integration
mix test --exclude slow           # Skip slow tests
mix test --exclude external       # Skip external calls
```

### Property-Based Testing

```elixir
use ExUnitProperties

property "date range always includes start and end" do
  check all start_date <- date(),
            days <- integer(0..365),
            end_date = Date.add(start_date, days) do

    result = Sync.sync_date_range("site", start_date, end_date)

    assert {:ok, stats} = result
    assert stats.start_date == start_date
    assert stats.end_date == end_date
  end
end
```

### Doctests

```elixir
defmodule GscAnalytics.Utils do
  @moduledoc """
  Utility functions for the application.
  """

  @doc """
  Formats a date as YYYY-MM-DD.

  ## Examples

      iex> GscAnalytics.Utils.format_date(~D[2024-01-15])
      "2024-01-15"

  """
  def format_date(date) do
    Date.to_string(date)
  end
end

# In test file
defmodule GscAnalytics.UtilsTest do
  use ExUnit.Case
  doctest GscAnalytics.Utils
end
```

---

## Running Tests

### Basic Commands

```bash
# Run all tests
mix test

# Run specific file
mix test test/gsc_analytics/sync_test.exs

# Run specific test line
mix test test/gsc_analytics/sync_test.exs:42

# Run failed tests only
mix test --failed

# Run with coverage
mix coveralls
mix coveralls.html  # HTML report

# Watch mode (requires mix_test_watch)
mix test.watch
```

### With Filters

```bash
# Include/exclude by tag
mix test --only integration
mix test --exclude slow
mix test --exclude external --exclude slow

# With pattern matching
mix test --only describe:"sync_date_range/3"

# Verbose output
mix test --trace

# Run on multiple cores
mix test --partitions 4
```

### Debugging Tests

```bash
# Show test durations
mix test --slowest 10

# Maximum detail
mix test --trace --seed 0 --max-failures 1

# With IEx for debugging
iex -S mix test --trace
```

---

## Quick Fixes

### Flaky Tests

```elixir
# ❌ Flaky - depends on timing
test "async process completes" do
  Task.start(fn -> do_work() end)
  assert completed?()  # Might not be done yet!
end

# ✅ Fixed - wait for completion
test "async process completes" do
  task = Task.async(fn -> do_work() end)
  assert :ok = Task.await(task)
end
```

### Database Pollution

```elixir
# ❌ Bad - data persists across tests
setup_all do
  insert(:user, email: "test@example.com")
  :ok
end

# ✅ Good - fresh data per test
setup do
  {:ok, user: insert(:user)}
end
```

### Over-Mocking

```elixir
# ❌ Don't mock pure functions
Math.Mock |> expect(:add, fn a, b -> a + b end)

# ✅ Use real implementation
assert Calculator.total([1, 2, 3]) == 6
```

---

## Resources

- [Full Research Doc](/Users/flor/Developer/prism/docs/elixir-tdd-research.md)
- [ExUnit Docs](https://hexdocs.pm/ex_unit/ExUnit.html)
- [Phoenix Testing](https://hexdocs.pm/phoenix/testing.html)
- [Mox Docs](https://hexdocs.pm/mox/Mox.html)
- [Testing Elixir Book](https://pragprog.com/titles/lmelixir/testing-elixir/)

---

**Last Updated:** 2025-11-08
