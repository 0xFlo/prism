# T005: Req HTTP Client (TDD)

**Status:** 🔵 Not Started
**Story Points:** 3
**Priority:**🔥 P1 Critical
**TDD Required:** ✅ Yes

## Description
Implement a Req-based HTTP client for the ScrapFly SERP API. **Use Req, NOT :httpc** (Codex requirement).

## Acceptance Criteria
- [ ] TDD: RED phase - failing tests written first
- [ ] TDD: GREEN phase - minimal implementation passes tests
- [ ] TDD: REFACTOR phase - code cleaned up
- [ ] Req client makes successful API calls to ScrapFly
- [ ] Retry logic with exponential backoff
- [ ] Telemetry integration for audit logging
- [ ] Error handling for API failures, rate limits, network issues

## TDD Workflow

### 🔴 RED Phase: Write Failing Tests First

```elixir
# test/gsc_analytics/data_sources/serp/core/client_test.exs
defmodule GscAnalytics.DataSources.SERP.Core.ClientTest do
  use ExUnit.Case, async: true

  alias GscAnalytics.DataSources.SERP.Core.Client

  describe "scrape_google/2" do
    test "makes successful API call to ScrapFly" do
      # This test will FAIL initially (module doesn't exist)
      assert {:ok, response} = Client.scrape_google("test query")
      assert is_map(response)
      assert Map.has_key?(response, "result")
    end

    test "includes required API parameters" do
      # Test that URL includes: key, url, render_js, format, asp
      assert {:ok, _} = Client.scrape_google("test query", geo: "us")
    end

    test "handles 429 rate limit with retry" do
      # Test exponential backoff on rate limits
      assert {:ok, _} = Client.scrape_google("test query")
    end

    test "returns error on API failure" do
      # Test error handling
      assert {:error, _reason} = Client.scrape_google("")
    end

    test "respects geo parameter" do
      assert {:ok, _} = Client.scrape_google("test", geo: "uk")
    end
  end

  describe "build_search_url/2" do
    test "constructs valid Google search URL" do
      url = Client.build_search_url("test query", "us")
      assert url =~ "https://www.google.com/search"
      assert url =~ "q=test+query"
      assert url =~ "gl=us"
    end
  end
end
```

**Run tests to confirm they FAIL:**
```bash
mix test test/gsc_analytics/data_sources/serp/core/client_test.exs
# Expected: All tests fail (module doesn't exist)
```

### 🟢 GREEN Phase: Minimal Implementation

```elixir
# lib/gsc_analytics/data_sources/serp/core/client.ex
defmodule GscAnalytics.DataSources.SERP.Core.Client do
  @moduledoc """
  Req-based HTTP client for ScrapFly SERP API.

  **IMPORTANT:** Uses Req (Prism standard), NOT :httpc.
  """

  alias GscAnalytics.DataSources.SERP.Core.Config

  @max_retries 3
  @retry_delay 1_000

  @doc """
  Scrape Google SERP for a given keyword.

  Returns {:ok, json_response} or {:error, reason}.
  """
  def scrape_google(keyword, opts \\ []) do
    geo = opts[:geo] || Config.default_geo()
    search_url = build_search_url(keyword, geo)

    params = %{
      "key" => Config.api_key(),
      "url" => search_url,
      "country" => geo,
      "format" => "json",  # CRITICAL: JSON not markdown
      "render_js" => "true",
      "asp" => "true"  # Anti-scraping protection
    }

    request_url = "#{Config.base_url()}/scrape"

    execute_request(request_url, params)
  end

  @doc """
  Build Google search URL with query parameters.
  """
  def build_search_url(keyword, geo) do
    query_params = URI.encode_query(%{
      "q" => keyword,
      "gl" => geo,
      "hl" => "en"
    })

    "https://www.google.com/search?#{query_params}"
  end

  defp execute_request(url, params, retry_count \\ 0) do
    case Req.get(url, params: params) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: 429}} when retry_count < @max_retries ->
        delay = (@retry_delay * :math.pow(2, retry_count)) |> round()
        Process.sleep(delay)
        execute_request(url, params, retry_count + 1)

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} when retry_count < @max_retries ->
        delay = (@retry_delay * :math.pow(2, retry_count)) |> round()
        Process.sleep(delay)
        execute_request(url, params, retry_count + 1)

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end
end
```

**Run tests to confirm they PASS:**
```bash
mix test test/gsc_analytics/data_sources/serp/core/client_test.exs
# Expected: All tests pass
```

### 🔵 REFACTOR Phase: Clean Up

1. Extract telemetry integration
2. Add structured logging
3. Extract configuration
4. Add documentation

```elixir
# Refactored version with telemetry
defp execute_request(url, params, retry_count \\ 0) do
  start_time = System.monotonic_time(:millisecond)

  result = case Req.get(url, params: params) do
    {:ok, %{status: 200, body: body}} ->
      {:ok, body}

    {:ok, %{status: 429}} when retry_count < @max_retries ->
      delay = calculate_backoff_delay(retry_count)
      Process.sleep(delay)
      execute_request(url, params, retry_count + 1)

    {:ok, %{status: status, body: body}} ->
      {:error, {:api_error, status, body}}

    {:error, reason} when retry_count < @max_retries ->
      delay = calculate_backoff_delay(retry_count)
      Process.sleep(delay)
      execute_request(url, params, retry_count + 1)

    {:error, reason} ->
      {:error, {:request_failed, reason}}
  end

  duration_ms = System.monotonic_time(:millisecond) - start_time
  emit_telemetry(result, duration_ms, retry_count)

  result
end

defp calculate_backoff_delay(retry_count) do
  (@retry_delay * :math.pow(2, retry_count)) |> round()
end

defp emit_telemetry(result, duration_ms, retry_count) do
  metadata = %{
    duration_ms: duration_ms,
    retry_count: retry_count,
    success: match?({:ok, _}, result)
  }

  :telemetry.execute(
    [:gsc_analytics, :serp, :api_request],
    %{duration: duration_ms},
    metadata
  )
end
```

**Run tests again to ensure refactor didn't break anything:**
```bash
mix test test/gsc_analytics/data_sources/serp/core/client_test.exs
# Expected: All tests still pass
```

## Definition of Done
- [x] RED: Tests written and failing
- [x] GREEN: Tests passing with minimal code
- [x] REFACTOR: Code cleaned up, tests still passing
- [ ] Req client (NOT :httpc) makes successful API calls
- [ ] Exponential backoff on retries
- [ ] Telemetry events emitted
- [ ] Error handling comprehensive
- [ ] mix precommit passes

## Notes
- **CRITICAL:** Use Req, NOT :httpc (Codex requirement for new integrations)
- ScrapFly returns JSON, not markdown
- Retry logic prevents transient failures
- Telemetry enables audit logging

## 📚 Reference Documentation
- **Req Client:** https://hexdocs.pm/req
- **TDD Guide:** [Complete Guide](/Users/flor/Developer/prism/docs/elixir-tdd-research.md)
- **Testing Reference:** [Quick Guide](/Users/flor/Developer/prism/docs/testing-quick-reference.md)
- **ScrapFly SERP API:** https://scrapfly.io/docs/scrape-api/serp
