defmodule GscAnalytics.Integration.SerpCheckIntegrationTest do
  use GscAnalytics.DataCase, async: false
  use Oban.Testing, repo: GscAnalytics.Repo

  alias GscAnalytics.Workers.SerpCheckWorker
  alias GscAnalytics.Schemas.SerpSnapshot
  alias GscAnalytics.DataSources.SERP.Support.RateLimiter

  @moduletag :integration
  @moduletag :tdd

  setup do
    # Reset rate limiter for each test
    RateLimiter.reset_rate_limit(1)
    :ok
  end

  describe "full SERP check flow" do
    @tag :skip
    test "enqueues job, calls API, parses, saves snapshot" do
      # This test requires mocking ScrapFly API or real API key
      # Skipping for now - requires API mock setup
      job_args = %{
        "account_id" => 1,
        "property_url" => "sc-domain:example.com",
        "url" => "https://example.com",
        "keyword" => "test query",
        "geo" => "us"
      }

      # Enqueue job
      assert {:ok, _job} = SerpCheckWorker.new(job_args) |> Oban.insert()

      # Process job
      assert :ok = perform_job(SerpCheckWorker, job_args)

      # Verify snapshot saved
      snapshot =
        Repo.get_by(SerpSnapshot,
          account_id: 1,
          property_url: "sc-domain:example.com",
          url: "https://example.com",
          keyword: "test query"
        )

      assert snapshot
      assert snapshot.checked_at
      assert snapshot.geo == "us"
      assert snapshot.api_cost == Decimal.new("36")
    end

    @tag :skip
    test "handles API errors gracefully" do
      # This test requires mocking ScrapFly API
      # Skipping for now
      job_args = %{
        "account_id" => 1,
        "property_url" => "sc-domain:example.com",
        "url" => "https://example.com",
        "keyword" => "",
        "geo" => "us"
      }

      assert {:error, _reason} = perform_job(SerpCheckWorker, job_args)
    end

    test "respects idempotency within 1 hour" do
      job_args = %{
        "account_id" => 1,
        "property_url" => "sc-domain:example.com",
        "url" => "https://example.com/unique-#{:rand.uniform(10000)}",
        "keyword" => "test unique #{:rand.uniform(10000)}",
        "geo" => "us"
      }

      # Insert job twice
      {:ok, job1} = SerpCheckWorker.new(job_args) |> Oban.insert()
      {:ok, job2} = SerpCheckWorker.new(job_args) |> Oban.insert()

      # Same job ID (deduplicated)
      assert job1.id == job2.id
    end

    test "different geo creates separate job" do
      base_args = %{
        "account_id" => 1,
        "property_url" => "sc-domain:example.com",
        "url" => "https://example.com/geo-#{:rand.uniform(10000)}",
        "keyword" => "test geo #{:rand.uniform(10000)}"
      }

      # Insert job with default geo (us)
      job_us = Map.put(base_args, "geo", "us")
      {:ok, job1} = SerpCheckWorker.new(job_us) |> Oban.insert()

      # Insert job with different geo (uk)
      job_uk = Map.put(base_args, "geo", "uk")
      {:ok, job2} = SerpCheckWorker.new(job_uk) |> Oban.insert()

      # Different jobs (not deduplicated)
      assert job1.id != job2.id
    end
  end

  describe "rate limiting integration" do
    test "rate limiter tracks requests per account" do
      # Check initial state
      assert RateLimiter.get_remaining_quota(1) > 0

      # Track some API cost
      assert :ok = RateLimiter.track_cost(1, 36)
      assert RateLimiter.get_total_cost(1) == 36

      # Track more cost
      assert :ok = RateLimiter.track_cost(1, 36)
      assert RateLimiter.get_total_cost(1) == 72
    end

    @tag :skip
    test "worker respects rate limits" do
      # This would require exhausting rate limit and verifying {:snooze, 60} response
      # Skipping for now - requires rate limit simulation
      :ok
    end
  end

  describe "error handling integration" do
    @tag :skip
    test "stores error message on API failure" do
      # This requires mocking Client to return error
      # Skipping for now
      :ok
    end

    @tag :skip
    test "retries on transient errors" do
      # This requires mocking Client to return transient error then success
      # Skipping for now
      :ok
    end
  end

  describe "data persistence integration" do
    @tag :skip
    test "saves full snapshot with all fields" do
      # This requires real API call or comprehensive mock
      # Skipping for now
      :ok
    end

    @tag :skip
    test "can query latest snapshot for URL" do
      # This requires creating snapshots first
      # Skipping for now
      :ok
    end
  end
end
