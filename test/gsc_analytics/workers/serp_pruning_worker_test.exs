defmodule GscAnalytics.Workers.SerpPruningWorkerTest do
  use GscAnalytics.DataCase, async: false
  use Oban.Testing, repo: GscAnalytics.Repo

  alias GscAnalytics.Workers.SerpPruningWorker
  alias GscAnalytics.Schemas.SerpSnapshot

  describe "perform/1" do
    test "enqueues pruning job successfully" do
      assert {:ok, job} = SerpPruningWorker.new(%{}) |> Oban.insert()
      assert job.queue == "maintenance"
      assert job.priority == 3
    end

    test "deletes snapshots older than 7 days" do
      now = DateTime.utc_now()
      eight_days_ago = DateTime.add(now, -8, :day)
      six_days_ago = DateTime.add(now, -6, :day)

      # Insert old snapshot (should be deleted)
      old_snapshot = %{
        account_id: 1,
        property_url: "sc-domain:example.com",
        url: "https://example.com/old",
        keyword: "old query",
        position: 5,
        competitors: [],
        serp_features: [],
        raw_response: %{},
        geo: "us",
        checked_at: eight_days_ago,
        api_cost: Decimal.new("36")
      }

      {:ok, _old} = Repo.insert(SerpSnapshot.changeset(%SerpSnapshot{}, old_snapshot))

      # Insert recent snapshot (should NOT be deleted)
      recent_snapshot = %{
        account_id: 1,
        property_url: "sc-domain:example.com",
        url: "https://example.com/recent",
        keyword: "recent query",
        position: 3,
        competitors: [],
        serp_features: [],
        raw_response: %{},
        geo: "us",
        checked_at: six_days_ago,
        api_cost: Decimal.new("36")
      }

      {:ok, _recent} = Repo.insert(SerpSnapshot.changeset(%SerpSnapshot{}, recent_snapshot))

      # Run pruning
      assert :ok = perform_job(SerpPruningWorker, %{})

      # Verify old snapshot was deleted
      assert Repo.get_by(SerpSnapshot, url: "https://example.com/old") == nil

      # Verify recent snapshot still exists
      assert Repo.get_by(SerpSnapshot, url: "https://example.com/recent") != nil
    end

    test "handles empty database gracefully" do
      assert :ok = perform_job(SerpPruningWorker, %{})
    end
  end
end
