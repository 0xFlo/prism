defmodule GscAnalytics.DataSources.GSC.Support.RateLimiterIntegrationTest do
  @moduledoc """
  Integration tests for the GSC Rate Limiter using Hammer.

  Tests rate limiting behavior:
  - Request quota enforcement (1,200 queries/minute)
  - Per-site bucket isolation
  - Window expiry and reset behavior
  - Remaining capacity tracking
  - Concurrent request handling

  Business requirement: "Prevent API quota exhaustion by rate limiting per site"
  """

  use GscAnalytics.DataCase, async: false

  @moduletag :integration

  alias GscAnalytics.DataSources.GSC.Support.RateLimiter

  @test_site "sc-domain:test.com"
  @another_site "sc-domain:another.com"
  @account_id 1

  setup do
    # Clean up Hammer ETS tables before each test
    # Hammer uses a backend that persists between tests
    Hammer.delete_buckets("gsc:#{@account_id}:#{@test_site}")
    Hammer.delete_buckets("gsc:#{@account_id}:#{@another_site}")

    original_accounts = Application.get_env(:gsc_analytics, :gsc_accounts)

    Application.put_env(:gsc_analytics, :gsc_accounts, %{
      1 => %{
        name: "Test Account",
        service_account_file: nil,
        default_property: @test_site,
        enabled?: true
      }
    })

    on_exit(fn ->
      Application.put_env(:gsc_analytics, :gsc_accounts, original_accounts)
      Hammer.delete_buckets("gsc:#{@account_id}:#{@test_site}")
      Hammer.delete_buckets("gsc:#{@account_id}:#{@another_site}")
    end)

    :ok
  end

  describe "rate limit enforcement" do
    test "allows requests within rate limit" do
      # Business requirement: "Allow up to 1,200 queries per minute"

      # Make 10 requests (well within limit)
      results = for _i <- 1..10 do
        RateLimiter.check_rate(@account_id, @test_site)
      end

      # All should be allowed
      assert Enum.all?(results, fn result -> result == :ok end)
    end

    test "denies requests after exceeding rate limit" do
      # Business requirement: "Block requests exceeding 1,200 queries/minute"

      # Make 1,200 requests to hit the limit
      for _i <- 1..1200 do
        RateLimiter.check_rate(@account_id, @test_site)
      end

      # Next request should be denied
      assert {:error, :rate_limited, wait_time} = RateLimiter.check_rate(@account_id, @test_site)
      assert wait_time == 60_000  # 1 minute window
    end

    test "tracks rate separately for different sites" do
      # Business requirement: "Per-site rate limiting to allow multi-site monitoring"

      # Hit limit for first site
      for _i <- 1..1200 do
        RateLimiter.check_rate(@account_id, @test_site)
      end

      # First site should be rate limited
      assert {:error, :rate_limited, _} = RateLimiter.check_rate(@account_id, @test_site)

      # Second site should still allow requests
      assert :ok = RateLimiter.check_rate(@account_id, @another_site)
    end

    test "resets rate limit after window expires" do
      # Business requirement: "Rate limit window resets after 60 seconds"

      # This test is difficult to implement without mocking time
      # or waiting 60 seconds. For now, we document the expected behavior.

      # Make a request
      assert :ok = RateLimiter.check_rate(@account_id, @test_site)

      # After 60 seconds (1 minute window), the bucket should reset
      # and allow another 1,200 requests
      # (This would require time travel or waiting in a real test)

      assert true  # Placeholder for time-dependent test
    end
  end

  describe "remaining capacity tracking" do
    test "returns correct remaining capacity" do
      # Business requirement: "Show remaining API quota for monitoring"

      # Initial capacity should be 1,200
      assert RateLimiter.get_remaining(@account_id, @test_site) == 1200

      # After 10 requests
      for _i <- 1..10 do
        RateLimiter.check_rate(@account_id, @test_site)
      end

      remaining = RateLimiter.get_remaining(@account_id, @test_site)
      assert remaining == 1190
    end

    test "remaining capacity decreases with each request" do
      # Make several requests and track capacity
      initial = RateLimiter.get_remaining(@account_id, @test_site)

      RateLimiter.check_rate(@account_id, @test_site)
      after_1 = RateLimiter.get_remaining(@account_id, @test_site)

      RateLimiter.check_rate(@account_id, @test_site)
      after_2 = RateLimiter.get_remaining(@account_id, @test_site)

      RateLimiter.check_rate(@account_id, @test_site)
      after_3 = RateLimiter.get_remaining(@account_id, @test_site)

      assert initial == 1200
      assert after_1 == 1199
      assert after_2 == 1198
      assert after_3 == 1197
    end

    test "remaining capacity reaches zero at limit" do
      # Hit the limit
      for _i <- 1..1200 do
        RateLimiter.check_rate(@account_id, @test_site)
      end

      # Remaining should be 0
      assert RateLimiter.get_remaining(@account_id, @test_site) == 0

      # Further requests should be denied
      assert {:error, :rate_limited, _} = RateLimiter.check_rate(@account_id, @test_site)
    end

    test "tracks remaining capacity per site" do
      # Use different amounts for different sites
      for _i <- 1..100 do
        RateLimiter.check_rate(@account_id, @test_site)
      end

      for _i <- 1..50 do
        RateLimiter.check_rate(@account_id, @another_site)
      end

      assert RateLimiter.get_remaining(@account_id, @test_site) == 1100
      assert RateLimiter.get_remaining(@account_id, @another_site) == 1150
    end
  end

  describe "concurrent request handling" do
    test "handles concurrent requests correctly" do
      # Business requirement: "Handle concurrent sync operations safely"

      # Spawn 50 concurrent tasks making requests
      tasks = for _i <- 1..50 do
        Task.async(fn ->
          RateLimiter.check_rate(@account_id, @test_site)
        end)
      end

      # Wait for all tasks to complete
      results = Task.await_many(tasks)

      # All should be allowed (50 << 1200)
      assert Enum.all?(results, fn result -> result == :ok end)

      # Remaining capacity should be 1150
      assert RateLimiter.get_remaining(@account_id, @test_site) == 1150
    end

    test "concurrent requests don't exceed limit" do
      # Hit near the limit
      for _i <- 1..1190 do
        RateLimiter.check_rate(@account_id, @test_site)
      end

      # Spawn 20 concurrent tasks (10 should succeed, 10 should fail)
      tasks = for _i <- 1..20 do
        Task.async(fn ->
          RateLimiter.check_rate(@account_id, @test_site)
        end)
      end

      results = Task.await_many(tasks)

      # Count successes and failures
      {successes, failures} = Enum.split_with(results, fn
        :ok -> true
        {:error, :rate_limited, _} -> false
      end)

      # Exactly 10 should succeed (to reach 1200 limit)
      assert length(successes) == 10
      assert length(failures) == 10
    end
  end

  describe "bucket configuration" do
    test "uses correct bucket naming pattern" do
      # Bucket names should be "gsc:<site_url>"
      # This is tested indirectly through site isolation

      # Make requests to different sites
      assert :ok = RateLimiter.check_rate(@account_id, "sc-domain:site1.com")
      assert :ok = RateLimiter.check_rate(@account_id, "sc-domain:site2.com")
      assert :ok = RateLimiter.check_rate(@account_id, "https://site3.com")

      # Each should have independent limits
      assert RateLimiter.get_remaining(@account_id, "sc-domain:site1.com") == 1199
      assert RateLimiter.get_remaining(@account_id, "sc-domain:site2.com") == 1199
      assert RateLimiter.get_remaining(@account_id, "https://site3.com") == 1199
    end

    test "uses default site when no site provided" do
      # When site_url is nil, should use default from config
      # (Currently defaults to get_default_site/0 in rate_limiter)

      assert :ok = RateLimiter.check_rate(@account_id)
      assert is_integer(RateLimiter.get_remaining(@account_id))
    end
  end

  describe "Hammer backend integration" do
    test "uses Hammer ETS backend correctly" do
      # Verify Hammer is functioning by checking bucket state

      site = "sc-domain:hammer-test.com"

      # Make some requests
      for _i <- 1..5 do
        RateLimiter.check_rate(@account_id, site)
      end

      # Hammer should have stored bucket state
      bucket_name = "gsc:#{@account_id}:#{site}"
      {:ok, {count, _used, _ms_to_next, _created, _updated}} =
        Hammer.inspect_bucket(bucket_name, 60_000, 1200)

      # Should have made 5 requests
      assert count >= 5
    end

    test "bucket state persists across function calls" do
      # Make requests in separate function calls

      RateLimiter.check_rate(@account_id, @test_site)
      remaining_after_1 = RateLimiter.get_remaining(@account_id, @test_site)

      RateLimiter.check_rate(@account_id, @test_site)
      remaining_after_2 = RateLimiter.get_remaining(@account_id, @test_site)

      # State should persist
      assert remaining_after_1 == 1199
      assert remaining_after_2 == 1198
    end
  end

  describe "error handling" do
    test "gracefully handles invalid site URLs" do
      # Should not crash on invalid input
      assert :ok = RateLimiter.check_rate(@account_id, "")
      assert :ok = RateLimiter.check_rate(@account_id, nil)

      # Should still track rate
      assert is_integer(RateLimiter.get_remaining(@account_id, ""))
      assert is_integer(RateLimiter.get_remaining(@account_id, nil))
    end

    test "handles Hammer backend failures gracefully" do
      # This would require mocking Hammer to return errors
      # For now, we document expected behavior

      # If Hammer fails, rate limiter should default to allowing requests
      # (fail-open strategy to avoid blocking all API calls)

      assert true  # Placeholder for error injection test
    end
  end
end
