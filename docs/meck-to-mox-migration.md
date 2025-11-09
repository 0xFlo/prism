# Migration Guide: Meck to Mox

This guide provides a step-by-step approach for migrating GSC Analytics tests from Meck to Mox.

## Why Migrate?

| Aspect | Meck | Mox |
|--------|------|-----|
| Safety | Runtime only, no compile checks | Compile-time contract verification |
| Concurrency | Requires `async: false` | Supports `async: true` |
| Maintenance | Silent failures on API changes | Catches breaking changes at compile |
| Community | Discouraged for new code | Recommended by Elixir core team |
| Performance | Slower (no async) | Faster (async tests) |

**Bottom line:** Mox provides better safety, faster tests, and aligns with Elixir best practices.

## Migration Strategy

### Phase 1: Setup Infrastructure (1-2 hours)

Create the foundation for Mox-based testing.

#### 1.1 Add Mox Dependency

```elixir
# mix.exs
defp deps do
  [
    {:mox, "~> 1.1", only: :test}
  ]
end
```

Run: `mix deps.get`

#### 1.2 Define Behaviours

Create behaviour definitions for external dependencies:

```elixir
# lib/gsc_analytics/data_sources/gsc/core/http_client.ex
defmodule GscAnalytics.DataSources.GSC.Core.HTTPClient do
  @moduledoc """
  Behaviour for HTTP client implementations.
  """

  @callback request(method :: atom(), url :: String.t(), headers :: list(), body :: binary()) ::
              {:ok, map()} | {:error, term()}

  @callback get(url :: String.t(), headers :: list()) ::
              {:ok, map()} | {:error, term()}

  @callback post(url :: String.t(), headers :: list(), body :: binary()) ::
              {:ok, map()} | {:error, term()}
end
```

#### 1.3 Update Real Implementation

```elixir
# lib/gsc_analytics/data_sources/gsc/core/http_client/httpc_adapter.ex
defmodule GscAnalytics.DataSources.GSC.Core.HTTPClient.HttpcAdapter do
  @moduledoc """
  Real HTTP client implementation using Erlang's :httpc.
  """

  @behaviour GscAnalytics.DataSources.GSC.Core.HTTPClient

  @impl true
  def request(method, url, headers, body) do
    # Existing :httpc implementation
    # ...
  end

  @impl true
  def get(url, headers) do
    request(:get, url, headers, "")
  end

  @impl true
  def post(url, headers, body) do
    request(:post, url, headers, body)
  end
end
```

#### 1.4 Add Runtime Configuration

```elixir
# config/config.exs
config :gsc_analytics,
  http_client: GscAnalytics.DataSources.GSC.Core.HTTPClient.HttpcAdapter

# config/test.exs
config :gsc_analytics,
  http_client: GscAnalytics.DataSources.GSC.Core.HTTPClient.Mock
```

#### 1.5 Update Code to Use Configurable Client

```elixir
# lib/gsc_analytics/data_sources/gsc/core/client.ex
defmodule GscAnalytics.DataSources.GSC.Core.Client do
  # Before (hardcoded :httpc)
  defp make_request(url, headers, body) do
    :httpc.request(:post, {url, headers, 'application/json', body}, [], [])
  end

  # After (configurable)
  defp make_request(url, headers, body) do
    http_client().post(url, headers, body)
  end

  defp http_client do
    Application.get_env(:gsc_analytics, :http_client)
  end
end
```

#### 1.6 Define Mocks in test_helper.exs

```elixir
# test/test_helper.exs
ExUnit.start()

# Define mocks
Mox.defmock(
  GscAnalytics.DataSources.GSC.Core.HTTPClient.Mock,
  for: GscAnalytics.DataSources.GSC.Core.HTTPClient
)

Ecto.Adapters.SQL.Sandbox.mode(GscAnalytics.Repo, :manual)
```

### Phase 2: Migrate Tests Module by Module (2-4 hours per module)

Pick one test module to migrate, verify it works, then move to the next.

#### 2.1 Example Migration: Client Tests

**Before (Meck):**

```elixir
defmodule GscAnalytics.DataSources.GSC.Core.ClientTest do
  use GscAnalytics.DataCase, async: false  # Can't be async with Meck

  import Mock  # Runtime mocking

  alias GscAnalytics.DataSources.GSC.Core.Client

  describe "search_analytics_query/4" do
    test "fetches performance data successfully" do
      mock_response = {
        :ok,
        {
          {'HTTP/1.1', 200, 'OK'},
          [],
          Jason.encode!(%{
            "rows" => [
              %{"keys" => ["https://example.com"], "clicks" => 100}
            ]
          })
        }
      }

      # Runtime mocking with Mock
      with_mock :httpc, [request: fn _, _, _, _ -> mock_response end] do
        result = Client.search_analytics_query(
          "sc-domain:example.com",
          ~D[2024-01-01],
          ~D[2024-01-01],
          1
        )

        assert {:ok, data} = result
        assert length(data["rows"]) == 1
      end
    end

    test "handles API errors" do
      with_mock :httpc, [request: fn _, _, _, _ -> {:error, :timeout} end] do
        result = Client.search_analytics_query(
          "sc-domain:example.com",
          ~D[2024-01-01],
          ~D[2024-01-01],
          1
        )

        assert {:error, _} = result
      end
    end
  end
end
```

**After (Mox):**

```elixir
defmodule GscAnalytics.DataSources.GSC.Core.ClientTest do
  use GscAnalytics.DataCase, async: true  # Now can be async!

  import Mox

  alias GscAnalytics.DataSources.GSC.Core.Client
  alias GscAnalytics.DataSources.GSC.Core.HTTPClient.Mock

  # Verify all expectations were met
  setup :verify_on_exit!

  describe "search_analytics_query/4" do
    test "fetches performance data successfully" do
      # Compile-time safe mocking
      Mock
      |> expect(:post, fn url, _headers, body ->
        # Can assert on inputs
        assert url =~ "searchconsole.googleapis.com"
        assert body =~ "2024-01-01"

        # Return mock response
        {:ok, %{
          "rows" => [
            %{"keys" => ["https://example.com"], "clicks" => 100}
          ]
        }}
      end)

      result = Client.search_analytics_query(
        "sc-domain:example.com",
        ~D[2024-01-01],
        ~D[2024-01-01],
        1
      )

      assert {:ok, data} = result
      assert length(data["rows"]) == 1
    end

    test "handles API errors" do
      Mock
      |> expect(:post, fn _url, _headers, _body ->
        {:error, :timeout}
      end)

      result = Client.search_analytics_query(
        "sc-domain:example.com",
        ~D[2024-01-01],
        ~D[2024-01-01],
        1
      )

      assert {:error, _} = result
    end

    test "retries on rate limit" do
      # Can test multiple calls
      Mock
      |> expect(:post, 3, fn _url, _headers, _body ->
        {:error, {:http_error, 429}}
      end)

      result = Client.search_analytics_query(
        "sc-domain:example.com",
        ~D[2024-01-01],
        ~D[2024-01-01],
        1
      )

      assert {:error, :rate_limited} = result
    end
  end
end
```

#### 2.2 Migration Checklist per Module

- [ ] Identify what's being mocked (e.g., :httpc, external APIs)
- [ ] Create or verify behaviour exists
- [ ] Update module under test to use configurable dependency
- [ ] Replace `with_mock` with Mox `expect` or `stub`
- [ ] Add `setup :verify_on_exit!` to test module
- [ ] Change `async: false` to `async: true` (if safe)
- [ ] Run tests and verify they pass
- [ ] Check test is faster (optional but satisfying!)

### Phase 3: Complex Scenarios

#### 3.1 Testing Authenticator (GenServer)

```elixir
defmodule GscAnalytics.DataSources.GSC.Support.AuthenticatorTest do
  use ExUnit.Case, async: false  # GenServer with registered name

  import Mox

  alias GscAnalytics.DataSources.GSC.Support.Authenticator
  alias GscAnalytics.DataSources.GSC.Core.HTTPClient.Mock

  setup :verify_on_exit!

  setup do
    # Stop authenticator if running
    if pid = Process.whereis(Authenticator) do
      GenServer.stop(pid)
    end

    :ok
  end

  describe "token refresh" do
    test "requests new token from Google OAuth2" do
      Mock
      |> expect(:post, fn url, _headers, body ->
        assert url == "https://oauth2.googleapis.com/token"
        assert body =~ "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer"

        {:ok, %{
          "access_token" => "ya29.mock_token",
          "expires_in" => 3600
        }}
      end)

      {:ok, _pid} = Authenticator.start_link([])

      # Wait for async token fetch
      assert_receive {:token_refreshed, _token}, 5000
    end

    test "handles token refresh failure" do
      Mock
      |> expect(:post, fn _url, _headers, _body ->
        {:error, :network_error}
      end)

      {:ok, _pid} = Authenticator.start_link([])

      # Should retry or log error
      assert_receive {:token_error, _reason}, 5000
    end
  end
end
```

#### 3.2 Testing Multi-Process Scenarios

```elixir
test "concurrent API calls use same mock" do
  # Allow spawned processes to use mock
  parent = self()

  Mock
  |> expect(:get, 5, fn url ->
    send(parent, {:called, url})
    {:ok, %{data: "test"}}
  end)

  # Spawn multiple processes
  tasks = Enum.map(1..5, fn i ->
    Task.async(fn ->
      allow(Mock, parent, self())
      Client.fetch_url("https://example.com/#{i}")
    end)
  end)

  # All tasks complete successfully
  results = Task.await_many(tasks)
  assert Enum.all?(results, &match?({:ok, _}, &1))

  # Verify all were called
  assert_received {:called, _}
  assert_received {:called, _}
  assert_received {:called, _}
  assert_received {:called, _}
  assert_received {:called, _}
end
```

### Phase 4: Verification and Cleanup

#### 4.1 Remove Meck Dependencies

```elixir
# mix.exs
defp deps do
  [
    # Remove these:
    # {:mock, "~> 0.3.0", only: :test},
    # {:meck, "~> 0.9", only: :test}

    # Keep:
    {:mox, "~> 1.1", only: :test}
  ]
end
```

Run: `mix deps.clean mock meck && mix deps.get`

#### 4.2 Verify Test Performance

```bash
# Before migration
time mix test
# => real: 2m 45s

# After migration (with async: true)
time mix test
# => real: 0m 52s  🎉
```

#### 4.3 Update Documentation

Update CLAUDE.md and testing docs to reflect new mocking strategy:

```markdown
## Mocking Strategy

This project uses **Mox** for all mocking needs:

- Define behaviours for external dependencies
- Configure real vs mock implementation via Application env
- Use `expect/3` in tests for call verification
- Use `stub/3` for general behavior without verification
- All tests can run with `async: true` (except GenServers with registered names)

See `/docs/testing-quick-reference.md` for examples.
```

## Common Migration Patterns

### Pattern 1: Simple Function Mock

**Meck:**
```elixir
with_mock MyModule, [function: fn -> :ok end] do
  result = MyModule.function()
end
```

**Mox:**
```elixir
MyModule.Mock |> expect(:function, fn -> :ok end)
result = MyModule.function()
```

### Pattern 2: Multiple Calls

**Meck:**
```elixir
with_mock MyModule, [function: fn -> :ok end] do
  MyModule.function()
  MyModule.function()
  MyModule.function()
end
```

**Mox:**
```elixir
MyModule.Mock |> expect(:function, 3, fn -> :ok end)
MyModule.function()
MyModule.function()
MyModule.function()
```

### Pattern 3: Asserting Call Arguments

**Meck:**
```elixir
with_mock MyModule, [function: fn arg -> arg end] do
  result = MyModule.function("test")
  assert_called MyModule.function("test")
end
```

**Mox:**
```elixir
MyModule.Mock
|> expect(:function, fn arg ->
  assert arg == "test"
  arg
end)

result = MyModule.function("test")
# Verification happens automatically with verify_on_exit!
```

### Pattern 4: Different Responses Per Call

**Meck:**
```elixir
:meck.new(MyModule, [:passthrough])
:meck.sequence(:function, [
  {:ok, 1},
  {:ok, 2},
  {:error, :fail}
])
```

**Mox:**
```elixir
MyModule.Mock
|> expect(:function, fn -> {:ok, 1} end)
|> expect(:function, fn -> {:ok, 2} end)
|> expect(:function, fn -> {:error, :fail} end)
```

## Troubleshooting

### Issue: "No mock found for module"

**Problem:**
```elixir
test "my test" do
  Mock |> expect(:function, fn -> :ok end)
  # Error: undefined function Mock.expect/2
end
```

**Solution:** Mock not defined in test_helper.exs
```elixir
# test/test_helper.exs
Mox.defmock(MyApp.Mock, for: MyApp.Behaviour)
```

### Issue: "Expected function/2 to be called once but it wasn't"

**Problem:**
```elixir
test "calls function" do
  Mock |> expect(:function, fn -> :ok end)
  # Test ends without calling function
end
# Error: Expected function/2 to be called once but it wasn't
```

**Solution:** You set an expectation but didn't call it
```elixir
test "calls function" do
  Mock |> expect(:function, fn -> :ok end)
  MyModule.do_work()  # This must call function/2
end
```

### Issue: "Process started but mock not allowed"

**Problem:**
```elixir
test "spawned process uses mock" do
  Mock |> expect(:get, fn -> :ok end)
  Task.async(fn -> MyModule.fetch() end)
  # Error: Mock not allowed for process
end
```

**Solution:** Use `allow/3` to share mock with spawned process
```elixir
test "spawned process uses mock" do
  parent = self()
  Mock |> expect(:get, fn -> :ok end)

  Task.async(fn ->
    allow(Mock, parent, self())
    MyModule.fetch()
  end)
end
```

### Issue: Tests slower after migration

**Problem:** Forgot to enable async

**Solution:**
```elixir
# Change this:
use GscAnalytics.DataCase, async: false

# To this:
use GscAnalytics.DataCase, async: true
```

## Rollout Plan

### Week 1: Foundation
- [ ] Add Mox dependency
- [ ] Create HTTPClient behaviour
- [ ] Create HTTPClient.HttpcAdapter implementation
- [ ] Update Core.Client to use configurable client
- [ ] Define HTTPClient.Mock in test_helper.exs
- [ ] Migrate 1 simple test module to verify setup

### Week 2: Core Modules
- [ ] Migrate Core.Client tests
- [ ] Migrate Core.Sync tests
- [ ] Migrate Core.Persistence tests
- [ ] Verify tests still pass and are faster

### Week 3: Support Modules
- [ ] Migrate Support.Authenticator tests
- [ ] Migrate Support.QueryPaginator tests
- [ ] Migrate Support.BatchProcessor tests

### Week 4: Cleanup
- [ ] Remove Meck/Mock dependencies
- [ ] Update documentation
- [ ] Run full test suite
- [ ] Verify performance improvements
- [ ] Celebrate! 🎉

## Benefits Realized

After full migration, you'll have:

- ✅ **Faster tests**: async: true means tests run in parallel
- ✅ **Safer tests**: Compile-time contract verification catches API changes
- ✅ **Better feedback**: Mox errors are clearer than runtime failures
- ✅ **Easier debugging**: Expectations show what was expected vs called
- ✅ **Future-proof**: Using recommended Elixir patterns

## References

- [Mox Documentation](https://hexdocs.pm/mox/Mox.html)
- [Elixir School - Mox](https://elixirschool.com/en/lessons/testing/mox)
- [Testing Quick Reference](/Users/flor/Developer/prism/docs/testing-quick-reference.md)
- [Full TDD Research](/Users/flor/Developer/prism/docs/elixir-tdd-research.md)

---

**Document Version:** 1.0
**Last Updated:** 2025-11-08
**Estimated Migration Time:** 2-3 weeks for full codebase
