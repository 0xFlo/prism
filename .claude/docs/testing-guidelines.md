# Testing Guidelines

Quick reference for testing patterns in GSC Analytics, focused on progress tracking and sync functionality.

## Test Organization

Mirror `lib/` structure in `test/`:
```
lib/gsc_analytics/data_sources/gsc/support/sync_progress.ex
test/gsc_analytics/data_sources/gsc/support/sync_progress_test.exs
```

## Async vs Sync Tests

**Use `async: false` for:**
- GenServer tests (SyncProgress)
- PubSub tests
- Database tests with shared state
- LiveView tests that modify GenServer state

**Use `async: true` for:**
- Pure function tests
- Isolated controller tests
- Read-only database queries

## Testing Progress Tracking

### Pattern: GenServer with PubSub

```elixir
defmodule MyGenServerTest do
  use GscAnalytics.DataCase, async: false
  alias Phoenix.PubSub

  setup do
    # Subscribe to broadcasts
    :ok = PubSub.subscribe(GscAnalytics.PubSub, "gsc_sync_progress")
    :ok
  end

  test "broadcasts progress updates" do
    job_id = SyncProgress.start_job(%{total_steps: 5})

    # Verify broadcast received
    assert_receive {:sync_progress, %{type: :started, job: job}}
    assert job.total_steps == 5
  end
end
```

**Critical**: Always include `:step` parameter when calling `day_completed/2`:
```elixir
# ✅ Correct - includes step number
SyncProgress.day_completed(job_id, %{step: 1, status: :ok})

# ❌ Wrong - missing step, progress stays at 0%
SyncProgress.day_completed(job_id, %{status: :ok})
```

### Pattern: LiveView with Real-time Updates

```elixir
defmodule MyLiveViewTest do
  use GscAnalyticsWeb.ConnCase, async: false

  test "updates when job progresses", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/dashboard/sync")

    # Trigger progress
    job_id = SyncProgress.start_job(%{total_steps: 4})
    SyncProgress.day_completed(job_id, %{step: 1, status: :ok})

    # Verify UI updated
    assert render(view) =~ "25.0%"  # 1/4 = 25%
  end
end
```

## Fake GSC Client Pattern

```elixir
defmodule MyTest.FakeClient do
  def fetch_all_urls_for_date(_, _, _date) do
    {:ok, %{"rows" => [%{"keys" => ["https://test.com"], "clicks" => 1}]}}
  end

  def fetch_query_batch(_, requests, _operation) do
    responses = Enum.map(requests, fn req ->
      %{id: req.id, status: 200, body: %{"rows" => []}}
    end)
    {:ok, responses, 1}
  end
end

# Use in tests
setup do
  original = Application.get_env(:gsc_analytics, :gsc_client)
  Application.put_env(:gsc_analytics, :gsc_client, MyTest.FakeClient)
  on_exit(fn -> Application.put_env(:gsc_analytics, :gsc_client, original) end)
  :ok
end
```

## Common Pitfalls

### 1. Missing Step Parameter (The 0% Bug)
**Problem**: Progress stays at 0% because `completed_steps` never increments.

**Solution**: Always pass `step:` parameter:
```elixir
SyncProgress.day_completed(job_id, %{
  date: date,
  step: step_number,  # ← Required!
  status: :ok
})
```

### 2. Calculating Percent in GenServer
**Problem**: Tests expect `state.percent` but it's calculated in LiveView.

**Solution**: Use helper function in tests:
```elixir
use GscAnalytics.SyncTestHelpers  # imports calculate_percent/1

assert calculate_percent(state) == 50.0
```

### 3. PubSub Message Leakage
**Problem**: Messages from previous tests interfere with current test.

**Solution**: Flush messages in setup:
```elixir
setup do
  flush_progress_messages()  # from SyncTestHelpers
  :ok
end
```

### 4. Race Conditions in LiveView Tests
**Problem**: Asserting on HTML before PubSub message processed.

**Solution**: Use `render/1` which waits for updates:
```elixir
# ✅ Good - render/1 processes pending messages
assert render(view) =~ "50.0%"

# ❌ Risky - might miss async update
{:ok, _view, html} = live(conn, path)
assert html =~ "50.0%"  # May not have updated yet
```

## Test Helpers

Located in `test/support/sync_test_helpers.ex`:

```elixir
# Calculate percentage like LiveView does
calculate_percent(job)

# Subscribe to progress broadcasts
subscribe_to_progress()

# Assert event received
assert_progress_event(:step_completed, timeout: 100)

# Clean up messages between tests
flush_progress_messages()
```

## Quick Checklist

Before committing tests:
- [ ] `async: false` for GenServer/PubSub tests
- [ ] `:step` parameter included in all `day_completed` calls
- [ ] PubSub messages flushed in setup
- [ ] Progress percentage calculated with helper function
- [ ] Fake clients restore original config in `on_exit`
- [ ] All tests pass: `mix test`

## Running Tests

```bash
# All tests
mix test

# Specific file
mix test test/path/to/test_file.exs

# Specific test line
mix test test/path/to/test_file.exs:42

# With trace
mix test --trace

# Failed tests only
mix test --failed
```
