# T009: Oban SERP Worker (TDD)

**Status:** 🔵 Not Started
**Story Points:** 3
**Priority:** 🔥 P1 Critical
**TDD Required:** ✅ Yes

## Description
Implement Oban worker for async SERP checking with **idempotency via unique_periods** (Codex requirement).

## Acceptance Criteria
- [ ] TDD: RED → GREEN → REFACTOR
- [ ] Worker calls ScrapFly API via Client
- [ ] Parses response via Parser
- [ ] Saves snapshot via Persistence
- [ ] **Uses unique_periods to prevent duplicate API calls**
- [ ] Broadcasts progress via PubSub

## TDD Workflow

### 🔴 RED Phase
```elixir
# test/gsc_analytics/workers/serp_check_worker_test.exs
defmodule GscAnalytics.Workers.SerpCheckWorkerTest do
  use GscAnalytics.DataCase
  use Oban.Testing, repo: GscAnalytics.Repo

  alias GscAnalytics.Workers.SerpCheckWorker

  describe "perform/1" do
    test "checks SERP position and saves snapshot" do
      job_args = %{
        "property_id" => Ecto.UUID.generate(),
        "url" => "https://example.com",
        "keyword" => "test query",
        "account_id" => 1
      }

      assert :ok = perform_job(SerpCheckWorker, job_args)

      # Verify snapshot saved
      snapshot = Repo.get_by(SerpSnapshot,
        url: "https://example.com",
        keyword: "test query"
      )
      assert snapshot
    end

    test "prevents duplicate jobs with unique_periods" do
      job_args = %{
        "property_id" => Ecto.UUID.generate(),
        "url" => "https://example.com",
        "keyword" => "test",
        "account_id" => 1
      }

      # Insert first job
      assert {:ok, job1} = SerpCheckWorker.new(job_args) |> Oban.insert()

      # Attempt duplicate within 1 hour
      assert {:ok, job2} = SerpCheckWorker.new(job_args) |> Oban.insert()

      # Should be same job (idempotent)
      assert job1.id == job2.id
    end
  end
end
```

### 🟢 GREEN Phase
```elixir
# lib/gsc_analytics/workers/serp_check_worker.ex
defmodule GscAnalytics.Workers.SerpCheckWorker do
  use Oban.Worker,
    queue: :serp_check,
    priority: 2,
    max_attempts: 3,
    unique: [
      period: {1, :hour},
      keys: [:property_id, :url, :keyword, :geo],
      states: [:available, :scheduled, :executing]
    ]

  alias GscAnalytics.DataSources.SERP.Core.{Client, Parser, Persistence}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    property_id = args["property_id"]
    url = args["url"]
    keyword = args["keyword"]
    geo = args["geo"] || "us"

    # Call ScrapFly API
    with {:ok, json_response} <- Client.scrape_google(keyword, geo: geo),
         parsed <- Parser.parse_serp(json_response, url),
         snapshot_attrs <- build_snapshot_attrs(args, parsed, json_response),
         {:ok, _snapshot} <- Persistence.save_snapshot(snapshot_attrs) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_snapshot_attrs(args, parsed, raw_response) do
    %{
      account_id: args["account_id"],
      property_id: args["property_id"],
      url: args["url"],
      keyword: args["keyword"],
      position: parsed.position,
      competitors: parsed.competitors,
      serp_features: parsed.serp_features,
      raw_response: raw_response,
      geo: args["geo"] || "us",
      checked_at: DateTime.utc_now(),
      api_cost: Decimal.new("31")  # Base + JS + residential proxy
    }
  end
end
```

## Definition of Done
- [x] RED → GREEN → REFACTOR
- [ ] Worker processes jobs async
- [ ] **unique_periods prevents duplicates**
- [ ] Error handling and retries
- [ ] Tests pass

## 📚 Reference Documentation
- **Oban Workers:** [Reference Guide](/Users/flor/Developer/prism/docs/OBAN_REFERENCE.md)
- **Oban unique_periods:** https://hexdocs.pm/oban/Oban.Worker.html#module-unique-jobs
- **TDD Guide:** [Complete Guide](/Users/flor/Developer/prism/docs/elixir-tdd-research.md)
