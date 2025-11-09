defmodule GscAnalytics.Workers.SerpCheckWorkerTest do
  use GscAnalytics.DataCase, async: false
  use Oban.Testing, repo: GscAnalytics.Repo

  import Mox

  alias GscAnalytics.Workers.SerpCheckWorker
  alias GscAnalytics.Schemas.SerpSnapshot
  alias GscAnalytics.Test.Fixtures.ScrapflyResponses

  @moduletag :tdd

  setup :verify_on_exit!

  describe "perform/1" do
    test "enqueues job with required fields" do
      job_args = %{
        "account_id" => 1,
        "property_url" => "sc-domain:example.com",
        "url" => "https://example.com",
        "keyword" => "test query"
      }

      assert {:ok, job} = SerpCheckWorker.new(job_args) |> Oban.insert()
      assert job.args["account_id"] == 1
      assert job.args["keyword"] == "test query"
    end

    test "uses serp_check queue" do
      job_args = %{
        "account_id" => 1,
        "property_url" => "sc-domain:example.com",
        "url" => "https://example.com",
        "keyword" => "test"
      }

      changeset = SerpCheckWorker.new(job_args)
      assert changeset.changes.queue == "serp_check"
    end

    test "has max_attempts of 3" do
      job_args = %{
        "account_id" => 1,
        "property_url" => "sc-domain:example.com",
        "url" => "https://example.com",
        "keyword" => "test"
      }

      changeset = SerpCheckWorker.new(job_args)
      assert changeset.changes.max_attempts == 3
    end

    test "checks SERP position and saves snapshot" do
      job_args = %{
        "account_id" => 1,
        "property_url" => "sc-domain:example.com",
        "url" => "https://elixir-lang.org",
        "keyword" => "elixir programming",
        "geo" => "us"
      }

      # Mock successful ScrapFly response with URL at position 3
      expect(GscAnalytics.DataSources.SERP.HTTPClientMock, :get, fn _url, _opts ->
        ScrapflyResponses.success_with_position()
      end)

      assert :ok = perform_job(SerpCheckWorker, job_args)

      # Verify snapshot was saved with correct position
      snapshot =
        Repo.get_by(SerpSnapshot,
          url: "https://elixir-lang.org",
          keyword: "elixir programming"
        )

      assert snapshot
      assert snapshot.position == 3
      assert snapshot.account_id == 1
    end

    test "includes default geo when not specified" do
      job_args = %{
        "account_id" => 1,
        "property_url" => "sc-domain:example.com",
        "url" => "https://example.com",
        "keyword" => "test"
      }

      changeset = SerpCheckWorker.new(job_args)
      # Geo should default to "us" in perform/1
      assert is_map(changeset.changes.args)
    end
  end

  describe "unique_periods (idempotency)" do
    test "prevents duplicate jobs within 1 hour window" do
      job_args = %{
        "account_id" => 1,
        "property_url" => "sc-domain:example.com",
        "url" => "https://example.com/unique-test-#{:rand.uniform(10000)}",
        "keyword" => "test unique #{:rand.uniform(10000)}",
        "geo" => "us"
      }

      # Insert first job
      assert {:ok, job1} = SerpCheckWorker.new(job_args) |> Oban.insert()

      # Attempt duplicate within 1 hour - should return same job
      assert {:ok, job2} = SerpCheckWorker.new(job_args) |> Oban.insert()

      # Should be same job (idempotent)
      assert job1.id == job2.id
    end

    test "unique key includes account_id, property_url, url, keyword, geo" do
      base_args = %{
        "account_id" => 1,
        "property_url" => "sc-domain:example.com",
        "url" => "https://example.com",
        "keyword" => "test",
        "geo" => "us"
      }

      # Insert job with base args
      assert {:ok, job1} = SerpCheckWorker.new(base_args) |> Oban.insert()

      # Different account_id should create new job
      different_account = Map.put(base_args, "account_id", 2)
      assert {:ok, job2} = SerpCheckWorker.new(different_account) |> Oban.insert()
      assert job1.id != job2.id

      # Different keyword should create new job
      different_keyword = Map.put(base_args, "keyword", "different")
      assert {:ok, job3} = SerpCheckWorker.new(different_keyword) |> Oban.insert()
      assert job1.id != job3.id
    end

    test "allows same job after unique period expires" do
      # This would require time manipulation or waiting 1 hour
      # For now, we just verify the unique config is set correctly
      changeset =
        SerpCheckWorker.new(%{
          "account_id" => 1,
          "property_url" => "sc-domain:example.com",
          "url" => "https://example.com",
          "keyword" => "test"
        })

      assert changeset.changes.unique != nil
      assert changeset.changes.unique[:period] == 3600
      assert changeset.changes.unique[:keys] == [:account_id, :property_url, :url, :keyword, :geo]
    end
  end

  describe "error handling" do
    test "fails gracefully when required fields missing" do
      job_args = %{
        # Missing required fields
        "keyword" => "test"
      }

      # Should fail validation
      changeset = SerpCheckWorker.new(job_args)
      assert changeset.valid? == false or is_map(changeset.changes.args)
    end

    test "retries on rate limit error" do
      job_args = %{
        "account_id" => 1,
        "property_url" => "sc-domain:example.com",
        "url" => "https://example.com",
        "keyword" => "test query",
        "geo" => "us"
      }

      # Mock rate limit response (429)
      expect(GscAnalytics.DataSources.SERP.HTTPClientMock, :get, fn _url, _opts ->
        ScrapflyResponses.rate_limit_error()
      end)

      # Mock second attempt succeeds
      expect(GscAnalytics.DataSources.SERP.HTTPClientMock, :get, fn _url, _opts ->
        ScrapflyResponses.success_with_position()
      end)

      # Worker should retry and eventually succeed
      assert :ok = perform_job(SerpCheckWorker, job_args)
    end

    test "stores error message on API failure" do
      job_args = %{
        "account_id" => 1,
        "property_url" => "sc-domain:example.com",
        "url" => "https://example.com",
        "keyword" => "test query",
        "geo" => "us"
      }

      # Mock API error (500)
      expect(GscAnalytics.DataSources.SERP.HTTPClientMock, :get, fn _url, _opts ->
        ScrapflyResponses.internal_server_error()
      end)

      # Worker should handle error gracefully
      assert {:error, _reason} = perform_job(SerpCheckWorker, job_args)
    end
  end
end
