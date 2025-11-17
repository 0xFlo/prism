# T008: Rate Limiter (TDD)

**Status:** 🔵 Not Started
**Story Points:** 2
**Priority:** 🔥 P1 Critical
**TDD Required:** ✅ Yes

## Description
Implement rate limiter to prevent ScrapFly API quota exhaustion. Track API usage and enforce limits.

## Acceptance Criteria
- [ ] TDD: RED → GREEN → REFACTOR
- [ ] Limits requests to configured rate (e.g., 60/minute)
- [ ] Uses Hammer for rate limiting
- [ ] Tracks API credits used
- [ ] Returns error when limit exceeded

## TDD Workflow

### 🔴 RED Phase
```elixir
# test/gsc_analytics/data_sources/serp/support/rate_limiter_test.exs
defmodule GscAnalytics.DataSources.SERP.Support.RateLimiterTest do
  use ExUnit.Case, async: false  # async: false for Hammer ETS

  alias GscAnalytics.DataSources.SERP.Support.RateLimiter

  describe "check_rate/0" do
    test "allows request within limit" do
      assert :ok = RateLimiter.check_rate()
    end

    test "blocks request when limit exceeded" do
      # Make 60 requests
      for _ <- 1..60, do: RateLimiter.check_rate()

      # 61st request should be blocked
      assert {:error, :rate_limited} = RateLimiter.check_rate()
    end
  end

  describe "track_cost/1" do
    test "increments total API cost" do
      RateLimiter.track_cost(31)
      assert RateLimiter.get_total_cost() >= 31
    end
  end
end
```

### 🟢 GREEN Phase
```elixir
# lib/gsc_analytics/data_sources/serp/support/rate_limiter.ex
defmodule GscAnalytics.DataSources.SERP.Support.RateLimiter do
  alias GscAnalytics.DataSources.SERP.Core.Config

  def check_rate do
    case Hammer.check_rate("serp:api", 60_000, Config.rate_limit_per_minute()) do
      {:allow, _count} -> :ok
      {:deny, _limit} -> {:error, :rate_limited}
    end
  end

  def track_cost(credits) do
    # Store in ETS or database
    :ok
  end

  def get_total_cost do
    # Retrieve from ETS or database
    0
  end
end
```

## 📚 Reference Documentation
- **Hammer:** https://hexdocs.pm/hammer
- **TDD Guide:** [Complete Guide](/Users/flor/Developer/prism/docs/elixir-tdd-research.md)
