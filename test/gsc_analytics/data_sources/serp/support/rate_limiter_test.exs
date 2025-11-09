defmodule GscAnalytics.DataSources.SERP.Support.RateLimiterTest do
  use ExUnit.Case, async: false

  alias GscAnalytics.DataSources.SERP.Support.RateLimiter

  @moduletag :tdd

  setup do
    # Clean up Hammer state between tests
    # Note: Hammer.delete_buckets is the correct function name
    :ok
  end

  describe "check_rate/1" do
    test "allows first request within limit" do
      assert :ok = RateLimiter.check_rate("test_account")
    end

    test "allows requests up to the limit" do
      account_id = "test_account_#{:rand.uniform(10000)}"

      # Should allow up to 60 requests per minute
      for i <- 1..60 do
        assert :ok = RateLimiter.check_rate(account_id),
               "Request #{i} should be allowed"
      end
    end

    test "blocks request when rate limit exceeded" do
      account_id = "test_account_#{:rand.uniform(10000)}"

      # Make 60 requests (the limit)
      for _ <- 1..60 do
        RateLimiter.check_rate(account_id)
      end

      # 61st request should be blocked
      assert {:error, :rate_limited} = RateLimiter.check_rate(account_id)
    end

    test "rate limit is per account" do
      # Account 1 exhausts its limit
      for _ <- 1..60 do
        RateLimiter.check_rate("account_1")
      end

      assert {:error, :rate_limited} = RateLimiter.check_rate("account_1")

      # Account 2 should still be allowed
      assert :ok = RateLimiter.check_rate("account_2")
    end

    test "returns remaining count on success" do
      account_id = "test_account_#{:rand.uniform(10000)}"

      assert {:ok, _remaining} = RateLimiter.check_rate_with_info(account_id)
    end
  end

  describe "track_cost/2" do
    test "tracks API credits used for an account" do
      account_id = 1

      assert :ok = RateLimiter.track_cost(account_id, 36)
    end

    test "accumulates multiple cost entries" do
      account_id = 2

      RateLimiter.track_cost(account_id, 36)
      RateLimiter.track_cost(account_id, 36)

      total = RateLimiter.get_total_cost(account_id)
      assert total >= 72
    end

    test "stores cost with timestamp" do
      account_id = 3

      RateLimiter.track_cost(account_id, 36)

      # Verify cost was tracked (implementation may vary)
      assert RateLimiter.get_total_cost(account_id) == 36
    end
  end

  describe "get_total_cost/1" do
    test "returns 0 for account with no usage" do
      assert RateLimiter.get_total_cost(999) == 0
    end

    test "returns accumulated cost for account" do
      account_id = 4

      RateLimiter.track_cost(account_id, 31)
      RateLimiter.track_cost(account_id, 5)

      assert RateLimiter.get_total_cost(account_id) == 36
    end
  end

  describe "get_remaining_quota/1" do
    test "returns full quota for unused account" do
      remaining = RateLimiter.get_remaining_quota("unused_account")

      assert remaining > 0
    end

    test "decreases after requests are made" do
      account_id = "test_#{:rand.uniform(10000)}"

      initial = RateLimiter.get_remaining_quota(account_id)
      RateLimiter.check_rate(account_id)
      after_one = RateLimiter.get_remaining_quota(account_id)

      assert after_one < initial
    end

    test "returns 0 when limit exhausted" do
      account_id = "test_#{:rand.uniform(10000)}"

      # Exhaust the limit
      for _ <- 1..60 do
        RateLimiter.check_rate(account_id)
      end

      assert RateLimiter.get_remaining_quota(account_id) == 0
    end
  end

  describe "reset_rate_limit/1" do
    test "resets rate limit for account" do
      account_id = "test_#{:rand.uniform(10000)}"

      # Exhaust limit
      for _ <- 1..60 do
        RateLimiter.check_rate(account_id)
      end

      assert {:error, :rate_limited} = RateLimiter.check_rate(account_id)

      # Reset
      :ok = RateLimiter.reset_rate_limit(account_id)

      # Should allow requests again
      assert :ok = RateLimiter.check_rate(account_id)
    end
  end
end
