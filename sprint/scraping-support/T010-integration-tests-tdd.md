# T010: Integration Tests (TDD)

**Status:** 🔵 Not Started
**Story Points:** 2
**Priority:** 🔥 P1 Critical
**TDD Required:** ✅ Yes

## Description
End-to-end integration tests for the complete SERP checking flow.

## Acceptance Criteria
- [ ] TDD: RED → GREEN → REFACTOR
- [ ] Tests full flow: Oban job → Client → Parser → Persistence
- [ ] Mocks ScrapFly API responses
- [ ] Tests error handling paths
- [ ] Tests rate limiting
- [ ] Tests idempotency

## TDD Workflow

### 🔴 RED Phase
```elixir
# test/gsc_analytics/integration/serp_check_integration_test.exs
defmodule GscAnalytics.Integration.SerpCheckIntegrationTest do
  use GscAnalytics.DataCase
  use Oban.Testing, repo: GscAnalytics.Repo

  alias GscAnalytics.Workers.SerpCheckWorker
  alias GscAnalytics.Schemas.SerpSnapshot

  @moduletag :integration

  describe "full SERP check flow" do
    test "enqueues job, calls API, parses, saves snapshot" do
      property_id = Ecto.UUID.generate()

      job_args = %{
        "property_id" => property_id,
        "url" => "https://example.com",
        "keyword" => "test query",
        "account_id" => 1
      }

      # Enqueue job
      assert {:ok, job} = SerpCheckWorker.new(job_args) |> Oban.insert()

      # Process job
      assert :ok = perform_job(SerpCheckWorker, job_args)

      # Verify snapshot saved
      snapshot = Repo.get_by(SerpSnapshot,
        property_id: property_id,
        url: "https://example.com",
        keyword: "test query"
      )

      assert snapshot
      assert snapshot.checked_at
      assert snapshot.geo == "us"
    end

    test "handles API errors gracefully" do
      # Test with invalid keyword
      job_args = %{
        "property_id" => Ecto.UUID.generate(),
        "url" => "https://example.com",
        "keyword" => "",
        "account_id" => 1
      }

      assert {:error, _reason} = perform_job(SerpCheckWorker, job_args)
    end

    test "respects idempotency within 1 hour" do
      property_id = Ecto.UUID.generate()

      job_args = %{
        "property_id" => property_id,
        "url" => "https://example.com",
        "keyword" => "test",
        "account_id" => 1
      }

      # Insert job twice
      {:ok, job1} = SerpCheckWorker.new(job_args) |> Oban.insert()
      {:ok, job2} = SerpCheckWorker.new(job_args) |> Oban.insert()

      # Same job ID (deduplicated)
      assert job1.id == job2.id
    end
  end
end
```

## Definition of Done
- [x] RED → GREEN → REFACTOR
- [ ] End-to-end flow tested
- [ ] Error paths covered
- [ ] Idempotency verified
- [ ] Tests pass

## 📚 Reference Documentation
- **Integration Testing:** [Complete Guide](/Users/flor/Developer/prism/docs/elixir-tdd-research.md)
- **Oban Testing:** https://hexdocs.pm/oban/Oban.Testing.html
