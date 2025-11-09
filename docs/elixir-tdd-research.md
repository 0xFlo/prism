# Elixir and Phoenix TDD Best Practices Research

**Research Date:** 2025-11-08
**Project:** GSC Analytics (Phoenix LiveView)

## Table of Contents

1. [Elixir TDD Patterns](#elixir-tdd-patterns)
2. [Mocking and Stubbing](#mocking-and-stubbing)
3. [Test Coverage](#test-coverage)
4. [Phoenix-Specific Testing](#phoenix-specific-testing)
5. [Property-Based Testing](#property-based-testing)
6. [Additional Best Practices](#additional-best-practices)
7. [Resources and References](#resources-and-references)

---

## 1. Elixir TDD Patterns

### Red-Green-Refactor Workflow

The Red-Green-Refactor cycle is fundamental to TDD in Elixir:

1. **Red**: Write a failing test first
2. **Green**: Write the minimum code to make the test pass
3. **Refactor**: Improve code design without changing behavior

**Source:** [SoftwarePatternsLexicon.com - Mastering TDD with ExUnit](https://softwarepatternslexicon.com/patterns-elixir/21/1/)

### Why Elixir Excels at TDD

Elixir has several features that make it excellent for TDD:

- **Fast test runner**: ExUnit with `async: true` runs test modules concurrently
- **Built-in testing framework**: ExUnit ships with Elixir, no external dependencies
- **Ecto Sandbox**: Allows concurrent database testing with transaction isolation
- **Functional nature**: Pure functions are easier to test with predictable outputs

**Source:** [Podium Engineering - Why Elixir Excels at TDD](https://medium.com/podium-engineering/test-driven-development-why-elixir-excels-at-tdd-8b5f1a51aee3)

### ExUnit Best Practices

#### Test Organization

Use `describe` blocks to group related tests:

```elixir
defmodule MyModuleTest do
  use ExUnit.Case

  describe "function_name/2" do
    test "typical case" do
      assert function_name(input, opts) == expected
    end

    test "edge case: empty input" do
      assert function_name("", opts) == ""
    end

    test "error case: invalid input" do
      assert_raise ArgumentError, fn ->
        function_name(nil, opts)
      end
    end
  end
end
```

**Pattern:** Use `describe` for the function name and arity, then use `test` for each specific behavior.

**Source:** [ElixirForum - TDD Best Practices](https://elixirforum.com/t/good-elixir-tdd-resources/17482)

#### Test Principles

- **Keep tests small and focused**: One piece of functionality per test
- **Test edge cases and error conditions**: Improve code robustness
- **Use descriptive test names**: Make failures easy to understand
- **Run tests frequently**: Catch issues early in development

**Source:** [SoftwarePatternsLexicon.com - Mastering TDD](https://softwarepatternslexicon.com/patterns-elixir/21/1/)

### When to Use TDD vs Other Approaches

**Use TDD when:**
- Building complex business logic requiring careful specification
- Working on critical functionality that must be correct
- Refactoring existing code to ensure no regressions
- Learning a new domain or technology

**Skip TDD when:**
- Prototyping or exploring solutions
- The requirements are highly uncertain
- Building simple CRUD operations
- Time constraints are severe (though this often backfires)

**Source:** [ElixirForum - TDD Resources](https://elixirforum.com/t/good-elixir-tdd-resources/17482)

---

## 2. Mocking and Stubbing

### Mox Library (Official Recommendation)

Mox is the recommended mocking library for Elixir, created by José Valim.

#### Key Principles

1. **No ad-hoc mocks**: Only create mocks based on behaviours
2. **No dynamic module generation**: Mocks defined at compile-time
3. **Concurrency support**: Tests using the same mock can use `async: true`
4. **Contract-based**: Catches API changes at compilation time

**Source:** [HexDocs - Mox](https://hexdocs.pm/mox/Mox.html)

#### Setup Pattern

```elixir
# 1. Define a behaviour
defmodule MyApp.HTTPClient do
  @callback get(url :: String.t()) :: {:ok, map()} | {:error, term()}
end

# 2. Real implementation
defmodule MyApp.HTTPClient.Real do
  @behaviour MyApp.HTTPClient

  def get(url) do
    # Real HTTP call
  end
end

# 3. Define mock in test_helper.exs
Mox.defmock(MyApp.HTTPClient.Mock, for: MyApp.HTTPClient)

# 4. Configure mock per test
test "fetches data successfully" do
  MyApp.HTTPClient.Mock
  |> expect(:get, fn url -> {:ok, %{data: "test"}} end)

  assert MyApp.fetch_data() == {:ok, %{data: "test"}}
end
```

**Source:** [Elixir School - Mox](https://elixirschool.com/en/lessons/testing/mox)

#### Best Practices

- **Define mocks in test_helper.exs or setup_all**: Not per test
- **Use `expect` for specific call assertions**: Verifies the mock was called
- **Use `stub` for general behavior**: When you don't care about call verification
- **Configure at runtime, define at compile-time**: Mox.defmock in test_helper.exs

**Source:** [Flatiron Labs - Elixir Test Mocking with Mox](https://medium.com/flatiron-labs/elixir-test-mocking-with-mox-b825a955143f)

### Meck Library (What We're Using)

Meck is an Erlang library that provides runtime module mocking.

#### Key Characteristics

- **Runtime mocking**: Uses metaprogramming to replace module functions
- **More flexible**: Can mock any module without behaviour definition
- **Less safe**: No compile-time contract verification
- **No async support**: Tests must use `async: false`

**Source:** [AppSignal - Introduction to Mocking Tools](https://blog.appsignal.com/2023/04/11/an-introduction-to-mocking-tools-for-elixir.html)

#### When to Use Meck

- **Legacy projects**: Where refactoring to behaviours is impractical
- **Quick prototypes**: Where setup overhead isn't justified
- **Third-party modules**: That you can't easily wrap with behaviours

**Community Warning:** "Runtime mocking is just wrong and takes away all the functional part of Elixir"

**Source:** [Stack Overflow - Testing GenServers](https://stackoverflow.com/questions/33018952/what-is-the-idiomatic-testing-strategy-for-genservers-in-elixir)

### Mox vs Meck Comparison (2024)

| Feature | Mox | Meck |
|---------|-----|------|
| Safety | ✅ Compile-time contract verification | ❌ Runtime only |
| Concurrency | ✅ Supports async: true | ❌ Requires async: false |
| Setup | More upfront (behaviours required) | Quick and dirty |
| Maintenance | Easier (catches breaking changes) | Brittle (silent failures) |
| Community | ✅ Recommended by core team | ⚠️ Discouraged for new code |

**Recommendation:** For new code, always prefer Mox. Only use Meck for legacy code or when refactoring to behaviours is impractical.

**Source:** [AppSignal - Mocking Tools Comparison](https://blog.appsignal.com/2023/04/11/an-introduction-to-mocking-tools-for-elixir.html)

### Testing GenServers and Workers

#### Direct Callback Testing

Test the `handle_*` functions directly without starting the GenServer:

```elixir
test "handle_call returns correct state" do
  state = %{count: 0}
  assert {:reply, 0, %{count: 0}} = MyServer.handle_call(:get, self(), state)
end
```

**Benefits:**
- Fast (no process startup)
- Isolated (no side effects)
- Clear (tests business logic only)

**Source:** [Stack Overflow - Testing GenServers](https://stackoverflow.com/questions/33018952/what-is-the-idiomatic-testing-strategy-for-genservers-in-elixir)

#### Integration Testing with Started GenServer

```elixir
test "GenServer maintains state across calls" do
  {:ok, pid} = MyServer.start_link([])
  assert :ok = MyServer.increment(pid)
  assert :ok = MyServer.increment(pid)
  assert 2 = MyServer.get(pid)
end
```

**When to use:** Testing process lifecycle, message ordering, or supervision.

**Source:** [FreshCode - Testing GenServers](https://www.freshcodeit.com/blog/how-to-design-and-test-elixir-genservers)

---

## 3. Test Coverage

### ExCoveralls Setup

ExCoveralls integrates with ExUnit to provide code coverage metrics.

#### Installation

```elixir
# mix.exs
def project do
  [
    test_coverage: [tool: ExCoveralls],
    preferred_cli_env: [
      coveralls: :test,
      "coveralls.detail": :test,
      "coveralls.post": :test,
      "coveralls.html": :test
    ]
  ]
end

defp deps do
  [
    {:excoveralls, "~> 0.18", only: :test}
  ]
end
```

**Source:** [GitHub - ExCoveralls](https://github.com/parroty/excoveralls)

#### Configuration

Create `coveralls.json` in project root:

```json
{
  "coverage_options": {
    "minimum_coverage": 80
  },
  "skip_files": [
    "test/",
    "lib/my_app_web/views/",
    "lib/my_app_web/channels/user_socket.ex",
    "lib/my_app_web/gettext.ex",
    "lib/my_app_web/endpoint.ex"
  ]
}
```

**Source:** [DEV.to - Coverage Report for Elixir & Phoenix](https://dev.to/berviantoleo/coverage-report-for-elixir-phoenix-92p)

#### Running Coverage Reports

```bash
# Terminal output
mix coveralls

# Detailed per-file breakdown
mix coveralls.detail

# HTML report
mix coveralls.html

# For CI (exits with status 1 if below minimum)
mix coveralls.json
```

**Source:** [Hex.pm - ExCoveralls](https://hex.pm/packages/excoveralls)

### Coverage Goals and Metrics

#### Recommended Thresholds

- **General applications**: 80-85% coverage
- **Critical business logic**: 90-95% coverage
- **Open source libraries**: 95%+ coverage
- **Prototype/MVP**: 60-70% acceptable

**Important:** Coverage percentage is a metric, not a goal. 100% coverage doesn't guarantee bug-free code.

**Source:** [Christian Blavier - Boost Your Test Coverage](https://www.christianblavier.com/boost-your-test-coverage-with-elixir/)

#### What to Test vs What to Skip

**High Priority:**
- Business logic in contexts
- Critical data transformations
- Authentication/authorization
- API boundaries
- Complex algorithms

**Lower Priority:**
- Phoenix-generated boilerplate
- Views and templates (covered by integration tests)
- Simple data structures
- Configuration files

**Source:** [Experimenting with Code - Code Hygiene](https://experimentingwithcode.com/code-hygiene-with-elixir-part-1/)

### Testing Strategies by Code Type

| Code Type | Strategy | Coverage Target |
|-----------|----------|-----------------|
| Pure functions | Unit tests | 95%+ |
| GenServers | Unit (callbacks) + Integration | 85%+ |
| Contexts | Integration tests | 90%+ |
| Controllers | Integration/Feature tests | 80%+ |
| LiveViews | Feature tests + Component tests | 80%+ |
| Workers/Jobs | Unit tests with mocks | 90%+ |

**Source:** [Multiple sources - synthesized best practices]

---

## 4. Phoenix-Specific Testing

### Testing LiveViews (2024 Best Practices)

#### Core Principles

1. **Test from the user's perspective**: Focus on interface behavior, not internal state
2. **Keep LiveViews thin**: Move business logic to contexts
3. **Use data-* attributes**: Make tests resilient to UI changes

**Source:** [Testing LiveView](https://www.testingliveview.com/)

#### Basic LiveView Test Pattern

```elixir
defmodule MyAppWeb.DashboardLiveTest do
  use MyAppWeb.ConnCase
  import Phoenix.LiveViewTest

  test "loads dashboard and displays data", %{conn: conn} do
    # Mount the LiveView
    {:ok, view, html} = live(conn, ~p"/dashboard")

    # Assert initial render
    assert html =~ "Dashboard"

    # Simulate user interaction
    view
    |> element("#filter-form")
    |> render_change(%{filter: %{status: "active"}})

    # Assert updated state
    assert has_element?(view, "[data-test-id='active-items']")
  end
end
```

**Source:** [HexDocs - Phoenix.LiveViewTest](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveViewTest.html)

#### Key Testing Functions

- **live/2**: Mount LiveView in connected state
- **render_click/2**: Simulate click events
- **render_submit/2**: Submit forms
- **render_change/2**: Simulate form changes (phx-change)
- **has_element?/2**: Check if element exists
- **element/2**: Find element for interaction

**Source:** [Medium - Testing Phoenix LiveView](https://medium.com/@michaelmunavu83/testing-phoenix-live-view-7851ccca6e37)

#### Testing Component Functions

Two approaches:

```elixir
# 1. Using render_component/3
test "metric card displays correct data" do
  result = render_component(MetricCard, value: 100, label: "Clicks")
  assert result =~ "100"
  assert result =~ "Clicks"
end

# 2. Using ~H sigil with rendered_to_string/1
test "metric card with ~H" do
  assigns = %{value: 100, label: "Clicks"}
  html = rendered_to_string(~H"""
    <.metric_card value={@value} label={@label} />
  """)
  assert html =~ "100"
end
```

**Source:** [Hex Shift - Confident Testing in Phoenix LiveView](https://hexshift.medium.com/confident-testing-in-phoenix-liveview-real-world-strategies-for-ui-stability-f7f6d55b4e0f)

#### LiveView Testing Anti-Patterns

❌ **Don't test internal assigns directly**:
```elixir
# Bad
assert view.assigns.urls == [...]
```

✅ **Do test rendered output**:
```elixir
# Good
assert has_element?(view, "[data-url='example.com']")
```

❌ **Don't couple tests to text content**:
```elixir
# Bad - breaks if copy changes
assert html =~ "Click here to continue"
```

✅ **Do use data attributes**:
```elixir
# Good
assert has_element?(view, "[data-test-id='continue-button']")
```

**Source:** [Fredrik Teschke - Test Smarter, Not Harder](https://ftes.de/articles/2024-10-16-phoenix-test-smarter-not-harder)

### Testing Controllers

Use `ConnCase` for controller tests:

```elixir
defmodule MyAppWeb.DashboardControllerTest do
  use MyAppWeb.ConnCase

  describe "export/2" do
    test "exports CSV with filtered data", %{conn: conn} do
      # Setup data
      insert(:performance, url: "example.com")

      # Make request
      conn = get(conn, ~p"/dashboard/export?format=csv")

      # Assert response
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/csv"]
      assert conn.resp_body =~ "example.com"
    end
  end
end
```

**Source:** [What Did I Learn - Testing Phoenix Models and Controllers](https://whatdidilearn.info/2018/04/01/testing-phoenix-models-and-controllers.html)

### Testing Contexts (Integration vs Unit)

Phoenix contexts should be tested as **integration tests** that exercise the full stack without the web layer.

```elixir
defmodule MyApp.ContentTest do
  use MyApp.DataCase

  alias MyApp.Content

  describe "list_urls/1" do
    test "returns all urls for account" do
      account = insert(:account)
      url1 = insert(:url, account: account)
      url2 = insert(:url, account: account)
      other_url = insert(:url)  # Different account

      result = Content.list_urls(account.id)

      assert length(result) == 2
      assert url1 in result
      assert url2 in result
      refute other_url in result
    end

    test "filters by status" do
      account = insert(:account)
      active = insert(:url, account: account, status: :active)
      inactive = insert(:url, account: account, status: :inactive)

      result = Content.list_urls(account.id, status: :active)

      assert [active] == result
    end
  end
end
```

**Key Points:**
- Test contexts away from the web layer
- Use integration tests as primary testing strategy
- Add unit tests for edge cases and complex logic
- Focus on the public API, not internal helpers

**Source:** [ElixirForum - Contexts and Testing](https://elixirforum.com/t/contexts-and-testing/9687)

### The Phoenix Testing Pyramid

```
     /\
    /  \  E2E Tests (few)
   /    \  - Full browser tests
  /------\  - Critical user flows
 /        \
/  LiveView Tests (some)
|  - Feature-level
|  - User interactions
|----------
|
| Context Tests (many)
| - Integration tests
| - Business logic
|------------------
|
| Unit Tests (most)
| - Pure functions
| - Utilities
| - Helpers
```

**Distribution:**
- 60-70%: Unit tests (fast, isolated)
- 20-30%: Context/Integration tests (medium speed)
- 10-15%: LiveView/Feature tests (slower)
- 5%: E2E tests (slowest, most brittle)

**Source:** [German Velasco - Phoenix Testing Pyramid](https://www.germanvelasco.com/blog/phoenix-testing-pyramid)

---

## 5. Property-Based Testing

### StreamData Library

StreamData brings property-based testing to Elixir, allowing you to test code properties over many generated inputs.

#### When to Use Property-Based Testing

**Use when:**
- Testing invariants that should always hold
- Validating parsers and serializers
- Testing pure functions with clear properties
- Finding edge cases you haven't thought of

**Skip when:**
- Testing business logic with complex requirements
- Output is non-deterministic by design
- Properties are hard to express clearly
- You're new to the codebase (start with example-based tests)

**Source:** [Elixir Blog - StreamData](http://elixir-lang.org/blog/2017/10/31/stream-data-property-based-testing-and-data-generation-for-elixir/)

#### Basic Pattern

```elixir
use ExUnitProperties

property "binary concatenation always starts with first binary" do
  check all bin1 <- binary(),
            bin2 <- binary() do
    assert String.starts_with?(bin1 <> bin2, bin1)
  end
end
```

**Source:** [Elixir School - StreamData](https://elixirschool.com/en/lessons/testing/stream_data)

#### Background Job Testing Example

```elixir
defmodule MyApp.SyncWorkerTest do
  use ExUnit.Case
  use ExUnitProperties

  property "syncing handles all date ranges correctly" do
    check all start_date <- date(),
              end_date <- date(),
              start_date <= end_date,
              max_runs: 50 do
      result = MyApp.SyncWorker.sync_range(start_date, end_date)

      # Properties to verify:
      assert {:ok, stats} = result
      assert stats.start_date == start_date
      assert stats.end_date == end_date
      assert stats.days_synced == Date.diff(end_date, start_date) + 1
    end
  end
end
```

#### Key Features

- **Automatic shrinking**: When a test fails, StreamData finds the smallest input that causes failure
- **Configurable runs**: Default 100 runs, use `max_runs:` to adjust
- **Reproducible**: Failed cases can be replayed with the same seed
- **Generators**: Rich library of data generators (integer, string, list, map, etc.)

**Source:** [HexDocs - ExUnitProperties](https://hexdocs.pm/stream_data/ExUnitProperties.html)

### Property-Based Testing Mindset

Property-based testing forces you to think about **what guarantees your code provides** rather than specific examples.

**Example-based thinking:**
- "String.duplicate('a', 3) should return 'aaa'"
- "String.duplicate('b', 0) should return ''"

**Property-based thinking:**
- "String.duplicate(s, n) should always return a string of length n * byte_size(s)"
- "String.duplicate(s, n) should contain s exactly n times"

**Benefits:**
- Discovers edge cases you didn't consider
- Documents code properties clearly
- Confidence increases over time (different values each run)

**Source:** [Flipay - Property-Based Testing Mindset](https://medium.com/flipay/https-medium-com-neofelisho-property-based-testing-is-a-mindset-97d91a328dc)

---

## 6. Additional Best Practices

### Async Testing with ExUnit

#### When to Use async: true

```elixir
defmodule MyApp.UtilsTest do
  use ExUnit.Case, async: true  # ✅ Safe - pure functions

  test "formats date correctly" do
    assert MyApp.Utils.format_date(~D[2024-01-01]) == "2024-01-01"
  end
end
```

**Requirements for async: true:**
- No shared mutable state
- No global process registration
- Database uses sandbox mode with transactions
- No external service calls (or properly mocked)

**Source:** [DockYard - Understanding Test Concurrency](https://dockyard.com/blog/2019/02/13/understanding-test-concurrency-in-elixir)

#### async: false Required When

- Using global state (ETS, Application env, etc.)
- Testing GenServers with registered names
- Using Meck or Mock library (not Mox)
- Testing supervision trees
- Using `:shared` sandbox mode

**Source:** [Medium - Asynchronous Testing with Mox](https://medium.com/socialcom/asynchronous-testing-in-elixir-with-mox-6ba6f40462f2)

#### Test Performance

Tests in the same module never run concurrently, but different async modules run concurrently:

```elixir
# Module A (async: true) - runs concurrently with B
# Module B (async: true) - runs concurrently with A
# Module C (async: false) - runs alone

# Use --partitions for additional parallelization
mix test --partitions 4
```

**Source:** [Bartosz Górka - Faster Test Execution](https://bartoszgorka.com/faster-test-execution-in-elixir)

### Setup and Fixtures

#### Using setup and setup_all

```elixir
defmodule MyAppTest do
  use ExUnit.Case

  # Runs once per module (before any tests)
  setup_all do
    # Expensive setup
    {:ok, shared_data: compute_expensive_data()}
  end

  # Runs before each test
  setup do
    # Clean state for each test
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(MyApp.Repo)
    {:ok, user: insert(:user)}
  end

  test "uses setup data", %{user: user, shared_data: data} do
    assert user.id
    assert data
  end
end
```

**Source:** [HexDocs - ExUnit.Callbacks](https://hexdocs.pm/ex_unit/ExUnit.Callbacks.html)

#### Named Setup Pattern

```elixir
defmodule MyAppTest do
  use ExUnit.Case

  setup [:create_user, :create_post]

  defp create_user(_context) do
    {:ok, user: insert(:user)}
  end

  defp create_post(%{user: user}) do
    {:ok, post: insert(:post, user: user)}
  end

  test "has user and post", %{user: user, post: post} do
    assert post.user_id == user.id
  end
end
```

**Benefits:**
- Composable: Mix and match setup functions
- Readable: Clear what each test needs
- Reusable: Share setup across tests

**Source:** [Medium - Cleaner Test Organization](https://mreigen.medium.com/elixir-a-cleaner-way-to-organize-tests-using-exunits-named-setup-8abb43971ca4)

### Test Factories with ExMachina

#### Basic Setup

```elixir
# test/support/factory.ex
defmodule MyApp.Factory do
  use ExMachina.Ecto, repo: MyApp.Repo

  def user_factory do
    %MyApp.User{
      email: sequence(:email, &"user#{&1}@example.com"),
      password_hash: Bcrypt.hash_pwd_salt("password123"),
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
  end

  def post_factory do
    %MyApp.Post{
      title: "Test Post",
      content: "Test content",
      user: build(:user),  # ✅ Use build for associations
      published: true
    }
  end
end
```

**Source:** [GitHub - ExMachina](https://github.com/thoughtbot/ex_machina)

#### Best Practices

**✅ Do:**
- Use `sequence` for unique values
- Use `build` for associations (not `insert`)
- Provide sensible defaults for incidental data
- Randomize incidental data with Faker

**❌ Don't:**
- Use `insert` in factory definitions (performance issues)
- Create complex data trees in factories
- Rely on factory defaults for intentional test data

```elixir
# ❌ Bad - hides intentional data
test "user can edit own post" do
  post = insert(:post)  # Who's the user?
  # ...
end

# ✅ Good - explicit about what matters
test "user can edit own post" do
  user = insert(:user)
  post = insert(:post, user: user, title: "My Post")
  # ...
end
```

**Source:** [Brooklin Myers - Maintainable Test Factories](https://brooklinmyers.medium.com/how-to-build-maintainable-test-factories-in-elixir-and-phoenix-84312998f7e7)

#### Intentional vs Incidental Data

**Intentional data:** Values that matter for the test
**Incidental data:** Values needed but not important for the test

```elixir
test "filters posts by status" do
  # Intentional: status is what we're testing
  published = insert(:post, status: :published, title: "Any")
  draft = insert(:post, status: :draft, title: "Any")

  # Incidental: title doesn't matter, randomize it
  result = MyApp.list_posts(status: :published)
  assert [published] == result
end
```

**Source:** [AppSignal - Test Factories and Fixtures](https://blog.appsignal.com/2023/02/28/an-introduction-to-test-factories-and-fixtures-for-elixir.html)

### Ecto Sandbox Mode

#### How It Works

The sandbox wraps each test in a database transaction that gets rolled back after the test, providing:

- **Isolation**: Each test has clean state
- **Speed**: Rollback is faster than truncation
- **Concurrency**: Multiple tests can run simultaneously

**Source:** [HexDocs - Ecto.Adapters.SQL.Sandbox](https://hexdocs.pm/ecto_sql/Ecto.Adapters.SQL.Sandbox.html)

#### Configuration

```elixir
# config/test.exs
config :my_app, MyApp.Repo,
  pool: Ecto.Adapters.SQL.Sandbox

# test/test_helper.exs
Ecto.Adapters.SQL.Sandbox.mode(MyApp.Repo, :manual)

# test/support/data_case.ex
setup tags do
  pid = Ecto.Adapters.SQL.Sandbox.start_owner!(MyApp.Repo, shared: not tags[:async])
  on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  :ok
end
```

**Source:** [HexDocs - Testing with Ecto](https://hexdocs.pm/ecto/testing-with-ecto.html)

#### Multi-Process Testing

When tests spawn processes that access the database:

```elixir
test "async process can access database" do
  # Allow spawned process to use test's connection
  task = Task.async(fn ->
    Ecto.Adapters.SQL.Sandbox.allow(MyApp.Repo, self(), task_pid)
    MyApp.fetch_data()
  end)

  Task.await(task)
end
```

**Source:** [HexDocs - Ecto SQL Sandbox](https://hexdocs.pm/ecto_sql/Ecto.Adapters.SQL.Sandbox.html)

### Doctests

#### When to Use Doctests

**✅ Use for:**
- Simple, pure functions with clear examples
- Public API documentation that must stay current
- Functions with predictable outputs

**❌ Avoid for:**
- Functions with side effects
- Functions that print to stdout
- Non-deterministic functions (random, time-based)
- Complex setup requirements

**Source:** [HexDocs - Doctests](https://hexdocs.pm/elixir/docs-tests-and-with.html)

#### Syntax

```elixir
defmodule MyApp.Utils do
  @doc """
  Formats a date as YYYY-MM-DD.

  ## Examples

      iex> MyApp.Utils.format_date(~D[2024-01-15])
      "2024-01-15"

      iex> MyApp.Utils.format_date(~D[2024-12-31])
      "2024-12-31"
  """
  def format_date(date) do
    Date.to_string(date)
  end
end

# In test file
defmodule MyApp.UtilsTest do
  use ExUnit.Case
  doctest MyApp.Utils
end
```

**Source:** [Elixir School - Testing](https://elixirschool.com/en/lessons/testing/basics)

#### Best Practices

- **Update promptly**: Change doctests when function changes
- **Cover edge cases**: Include boundary conditions
- **Keep simple**: Doctests aren't a replacement for unit tests
- **Use for docs first**: Focus on helping users, testing is secondary

**Source:** [Inspired Consulting - Elixir Doctests](https://inspired.consulting/en/technology/elixir-doctests)

### ExUnit Tags and Test Organization

#### Tag Types

```elixir
defmodule MyAppTest do
  use ExUnit.Case

  # Module-level tag (all tests)
  @moduletag :integration

  describe "feature A" do
    # Describe-level tag (all tests in block)
    @describetag :slow

    # Individual test tag
    @tag :external
    test "calls external API" do
      # ...
    end
  end
end
```

**Source:** [Medium - Test Organization in ExUnit](https://medium.com/@ukchukx/test-organization-in-exunit-62475fbbaebf)

#### Filtering Tests

```bash
# Run only tagged tests
mix test --only integration
mix test --only slow

# Exclude tagged tests
mix test --exclude external
mix test --exclude slow

# In test_helper.exs
ExUnit.configure(exclude: [external: true, slow: true])
```

**Source:** [Living in the Past - ExUnit Patterns](https://www.livinginthepast.org/blog/exunit-tags-test-setup/)

#### Common Tag Patterns

```elixir
# Performance tests (opt-in)
@tag :performance
test "handles large dataset" do
  # ...
end

# Skipped/pending tests
@tag :skip
test "future feature" do
  # ...
end

# CI-only tests
@tag :ci_only
test "integration with external service" do
  # ...
end
```

**Source:** [HexDocs - ExUnit.Case](https://hexdocs.pm/ex_unit/ExUnit.Case.html)

### Testing Background Jobs (Oban)

#### Testing Modes

```elixir
# config/test.exs
config :my_app, Oban,
  testing: :inline  # Execute jobs immediately

# OR
  testing: :manual  # Enqueue but don't execute
```

**Source:** [HexDocs - Oban.Testing](https://hexdocs.pm/oban/Oban.Testing.html)

#### Unit Testing Workers

```elixir
defmodule MyApp.SyncWorkerTest do
  use MyApp.DataCase, async: true
  use Oban.Testing, repo: MyApp.Repo

  alias MyApp.SyncWorker

  test "syncs data successfully" do
    # Test the perform function directly
    args = %{"site" => "example.com", "date" => "2024-01-01"}
    assert :ok = perform_job(SyncWorker, args)

    # Verify side effects
    assert Repo.exists?(from p in Performance, where: p.date == ^~D[2024-01-01])
  end
end
```

**Source:** [milmazz - Oban Testing](https://milmazz.uno/article/2022/02/21/oban-testing-your-workers-and-configuration/)

#### Asserting Job Enqueue

```elixir
test "enqueues sync job" do
  MyApp.schedule_sync("example.com")

  assert_enqueued worker: SyncWorker, args: %{site: "example.com"}
  assert_enqueued worker: SyncWorker, args: %{site: "example.com"}, queue: :default

  # With scheduled_at
  future = DateTime.add(DateTime.utc_now(), 3600, :second)
  assert_enqueued worker: SyncWorker, scheduled_at: future
end
```

**Source:** [Elixir Drops - Testing Oban Workers](https://elixirdrops.net/d/oZjxdXQw)

### Code Quality Tools Integration

#### Credo (Static Analysis)

```elixir
# mix.exs
defp deps do
  [
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
  ]
end

# .credo.exs
%{
  configs: [
    %{
      name: "default",
      strict: true,
      checks: [
        {Credo.Check.Readability.ModuleDoc, false},  # Disable if needed
      ]
    }
  ]
}
```

**Usage:**
```bash
mix credo               # Run with default checks
mix credo --strict      # Stricter analysis
mix credo suggest       # Show improvement suggestions
```

**Source:** [GitHub - Credo](https://github.com/rrrene/credo)

#### Dialyzer (Type Analysis)

```elixir
# mix.exs
defp deps do
  [
    {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
  ]
end
```

**Usage:**
```bash
mix dialyzer                    # First run (slow, builds PLT)
mix dialyzer                    # Subsequent runs (fast)
mix dialyzer --format short     # Concise output
```

**Source:** [SoftwarePatternsLexicon - Static Analysis](https://softwarepatternslexicon.com/patterns-elixir/21/7/)

#### Quality Check Alias

```elixir
# mix.exs
def project do
  [
    aliases: aliases()
  ]
end

defp aliases do
  [
    quality: [
      "compile --warnings-as-errors",
      "format --check-formatted",
      "credo --strict",
      "dialyzer",
      "test"
    ]
  ]
end
```

**Source:** [Leandro Cesquini - Enforcing Code Quality](https://leandrocp.com.br/2019/06/enforcing-code-quality-in-elixir/)

### Common Testing Anti-Patterns

#### Testing Implementation Details

```elixir
# ❌ Bad - tests how it works
test "increments counter" do
  assert {:ok, state} = MyServer.handle_call(:increment, self(), %{count: 0})
  assert state.count == 1
end

# ✅ Good - tests what it does
test "increments counter" do
  {:ok, pid} = MyServer.start_link([])
  assert :ok = MyServer.increment(pid)
  assert 1 = MyServer.get_count(pid)
end
```

#### Over-Mocking

```elixir
# ❌ Bad - mocks pure functions
test "calculates total" do
  Math.Mock |> expect(:add, fn a, b -> a + b end)
  assert Calculator.total([1, 2, 3]) == 6
end

# ✅ Good - use real implementations for pure functions
test "calculates total" do
  assert Calculator.total([1, 2, 3]) == 6
end
```

**Principle:** Don't isolate from purely functional, well-tested dependencies.

**Source:** [Testing Elixir Book - Best Practices]

#### Shared State Between Tests

```elixir
# ❌ Bad - shared module attribute
defmodule MyAppTest do
  use ExUnit.Case
  @user insert(:user)  # Runs at compile time, shared across tests!

  test "user has email" do
    assert @user.email
  end
end

# ✅ Good - fresh state per test
defmodule MyAppTest do
  use ExUnit.Case

  setup do
    {:ok, user: insert(:user)}
  end

  test "user has email", %{user: user} do
    assert user.email
  end
end
```

#### Testing Too Much in One Test

```elixir
# ❌ Bad - tests multiple behaviors
test "user flow" do
  user = insert(:user)
  assert user.email  # Email validation
  {:ok, session} = Auth.login(user)
  assert session.token  # Login
  {:ok, updated} = Accounts.update(user, %{name: "New"})
  assert updated.name == "New"  # Update
end

# ✅ Good - separate tests for each behavior
test "user has valid email", %{user: user} do
  assert user.email
end

test "login creates session", %{user: user} do
  assert {:ok, session} = Auth.login(user)
  assert session.token
end

test "update changes user name", %{user: user} do
  assert {:ok, updated} = Accounts.update(user, %{name: "New"})
  assert updated.name == "New"
end
```

---

## 7. Resources and References

### Books

1. **Testing Elixir** by Andrea Leopardi & Jeffrey Matthias
   - Publisher: Pragmatic Bookshelf
   - Coverage: Comprehensive guide to testing Elixir applications
   - Topics: ExUnit, Mox, StreamData, Phoenix testing, Ecto testing
   - URL: https://pragprog.com/titles/lmelixir/testing-elixir/

2. **Test-Driven Development with Phoenix** (Free Online Book)
   - Author: Community-maintained
   - URL: https://www.tddphoenix.com/the-what-the-why-and-the-how/

### Official Documentation

1. **ExUnit**
   - HexDocs: https://hexdocs.pm/ex_unit/ExUnit.html
   - API Reference: https://hexdocs.pm/ex_unit/api-reference.html

2. **Phoenix Testing Guide**
   - Introduction to Testing: https://hexdocs.pm/phoenix/testing.html
   - LiveView Testing: https://hexdocs.pm/phoenix_live_view/Phoenix.LiveViewTest.html

3. **Ecto Testing**
   - Testing with Ecto: https://hexdocs.pm/ecto/testing-with-ecto.html
   - SQL Sandbox: https://hexdocs.pm/ecto_sql/Ecto.Adapters.SQL.Sandbox.html

4. **Mox**
   - Documentation: https://hexdocs.pm/mox/Mox.html
   - GitHub: https://github.com/dashbitco/mox

5. **StreamData**
   - Documentation: https://hexdocs.pm/stream_data/
   - Blog: http://elixir-lang.org/blog/2017/10/31/stream-data-property-based-testing-and-data-generation-for-elixir/

### Libraries

1. **Testing Frameworks**
   - ExUnit (built-in): Testing framework
   - ExUnitProperties: Property-based testing with StreamData
   - Wallaby: Browser automation and E2E testing

2. **Mocking**
   - Mox: https://hex.pm/packages/mox (recommended)
   - Mimic: https://hex.pm/packages/mimic (alternative)
   - Hammox: https://hex.pm/packages/hammox (Mox + Hammock)

3. **Test Data**
   - ExMachina: https://hex.pm/packages/ex_machina
   - Faker: https://hex.pm/packages/faker
   - StreamData: https://hex.pm/packages/stream_data

4. **Coverage**
   - ExCoveralls: https://hex.pm/packages/excoveralls
   - MixTest.Coverage: Built-in coverage

5. **Background Jobs**
   - Oban.Testing: https://hexdocs.pm/oban/Oban.Testing.html

6. **Code Quality**
   - Credo: https://hex.pm/packages/credo
   - Dialyxir: https://hex.pm/packages/dialyxir
   - Sobelow: https://hex.pm/packages/sobelow (security)

### Community Resources

1. **Elixir Forum**
   - TDD Best Practices: https://elixirforum.com/t/good-elixir-tdd-resources/17482
   - Testing Discussions: https://elixirforum.com/c/elixir-questions/testing/

2. **Blogs and Articles**
   - DockYard Blog: https://dockyard.com/blog (testing series)
   - AppSignal Blog: https://blog.appsignal.com/ (Elixir testing guides)
   - SmartLogic Blog: https://smartlogic.io/blog/ (testing patterns)

3. **Tutorials**
   - Elixir School: https://elixirschool.com/en/lessons/testing/basics
   - Alchemist.Camp: https://alchemist.camp/episodes/elixir-tdd-ex_unit
   - ElixirCasts: https://elixircasts.io/ (video tutorials)

4. **Style Guides**
   - Nimble ExUnit Guide: https://nimblehq.co/compass/development/code-conventions/elixir/ex-unit/

### Conference Talks

1. **Testing Oban Jobs From the Inside Out** by Parker Selbert
   - Speaker Deck: https://speakerdeck.com/sorentwo/testing-oban-jobs-from-the-inside-out

2. **Testing LiveView** (various talks)
   - Search: ElixirConf testing sessions

### GitHub Examples

1. **Phoenix Framework**
   - Tests: https://github.com/phoenixframework/phoenix/tree/main/test
   - Good examples of testing patterns

2. **Oban**
   - Tests: https://github.com/oban-bg/oban/tree/main/test
   - Background job testing examples

3. **Ecto**
   - Tests: https://github.com/elixir-ecto/ecto/tree/main/test
   - Database testing patterns

### Quick Reference Cheat Sheet

```elixir
# Test structure
use ExUnit.Case, async: true
describe "function/arity" do
  setup [:setup_function]
  test "behavior", %{context: value} do
    assert result == expected
  end
end

# Common assertions
assert value
refute value
assert_raise ExceptionType, fn -> code() end
assert_receive message, timeout
assert_received message

# LiveView testing
{:ok, view, html} = live(conn, ~p"/path")
view |> element("#id") |> render_click()
assert has_element?(view, "[data-test-id='foo']")

# Mox
expect(Mock, :function, fn args -> result end)
stub(Mock, :function, fn args -> result end)

# Ecto
Ecto.Adapters.SQL.Sandbox.checkout(Repo)
Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)

# Tags
@moduletag :integration
@describetag :slow
@tag :skip
mix test --only integration --exclude slow

# Oban
use Oban.Testing, repo: Repo
assert_enqueued worker: Worker, args: %{key: "value"}
perform_job(Worker, args)
```

---

## Summary and Recommendations for GSC Analytics Project

Based on this research, here are specific recommendations for the GSC Analytics Phoenix project:

### 1. Migrate from Meck to Mox

**Priority:** P2 Medium

**Rationale:**
- Mox provides compile-time safety and supports async tests
- Better aligns with Elixir best practices
- Catches breaking changes early

**Action Items:**
1. Create behaviours for external dependencies (GSC API client, HTTP client)
2. Define Mox mocks in test_helper.exs
3. Gradually replace Meck usage in tests
4. Enable async: true on migrated test modules

### 2. Enhance Test Coverage Strategy

**Current:** Project has good test coverage (97.4% pass rate mentioned)

**Recommendations:**
1. Set up ExCoveralls with minimum coverage threshold (80%)
2. Use tags to separate performance tests (already implemented)
3. Focus coverage efforts on:
   - Core.Sync pipeline modules
   - Core.Persistence (data integrity)
   - Support.Authenticator (security critical)

### 3. Improve LiveView Testing

**Pattern to adopt:**

```elixir
# Use data attributes for stability
<tr :for={url <- @urls} :key={url.url} data-test-id={"url-row-#{url.url}"}>

# In tests
assert has_element?(view, "[data-test-id='url-row-example.com']")
```

**Benefits:**
- Tests survive UI copy changes
- More resilient to refactoring
- Clearer test intent

### 4. Add Property-Based Tests for Sync Operations

**Use StreamData for:**

```elixir
property "sync handles all valid date ranges" do
  check all start_date <- date_between(~D[2020-01-01], ~D[2024-12-31]),
            days <- integer(1..90),
            end_date = Date.add(start_date, days) do

    assert {:ok, _stats} = Core.Sync.sync_date_range(
      "sc-domain:test.com",
      start_date,
      end_date
    )
  end
end
```

**Benefits:**
- Discovers edge cases in date handling
- Tests GSC API pagination under various conditions
- Validates data integrity across different ranges

### 5. Background Job Testing

Since the project may add background jobs for automated syncing:

```elixir
# If using Oban
defmodule GscAnalytics.DailySyncWorkerTest do
  use GscAnalytics.DataCase, async: true
  use Oban.Testing, repo: GscAnalytics.Repo

  test "syncs yesterday's data" do
    assert :ok = perform_job(DailySyncWorker, %{})

    yesterday = Date.add(Date.utc_today(), -1)
    assert Repo.exists?(from t in TimeSeries, where: t.date == ^yesterday)
  end
end
```

### 6. Test Organization

**Current structure is good, consider:**

```elixir
# Tag slow external API tests
@moduletag :external

# Tag tests requiring full pipeline
@describetag :integration

# Run fast unit tests during development
mix test --exclude external --exclude integration

# Run full suite in CI
mix test
```

### 7. Enhance DataCase for Better Test Helpers

```elixir
# test/support/data_case.ex
defmodule GscAnalytics.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias GscAnalytics.Repo
      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import GscAnalytics.DataCase

      # Add project-specific helpers
      import GscAnalytics.Factory  # If using ExMachina
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(GscAnalytics.Repo,
      shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  # Helper for date-based test data
  def yesterday, do: Date.add(Date.utc_today(), -1)
  def days_ago(n), do: Date.add(Date.utc_today(), -n)
end
```

### 8. Documentation with Doctests

Add doctests to public API functions:

```elixir
defmodule GscAnalytics.DataSources.GSC.Core.Sync do
  @doc """
  Syncs Google Search Console data for a date range.

  ## Examples

      iex> alias GscAnalytics.DataSources.GSC.Core.Sync
      iex> {:ok, stats} = Sync.sync_date_range(
      ...>   "sc-domain:test.com",
      ...>   ~D[2024-01-01],
      ...>   ~D[2024-01-31]
      ...> )
      iex> stats.days_synced
      31

  """
  def sync_date_range(site_url, start_date, end_date) do
    # ...
  end
end
```

---

## Final Thoughts

Testing in Elixir/Phoenix is a first-class concern with excellent tooling:

- **ExUnit** provides a solid foundation with async testing
- **Mox** enables safe, concurrent mocking
- **Ecto Sandbox** allows fast, isolated database tests
- **LiveView testing** supports feature-level verification
- **Property-based testing** discovers edge cases
- **Coverage tools** ensure thoroughness

The key is to:
1. Write tests that reflect user/system behavior, not implementation
2. Use the right tool for the job (unit vs integration vs feature tests)
3. Leverage Elixir's concurrency for fast test suites
4. Think in properties and invariants, not just examples
5. Keep tests maintainable by avoiding over-mocking and implementation coupling

**Research compiled by:** Claude Code
**For project:** GSC Analytics Phoenix LiveView Application
**Date:** 2025-11-08
