defmodule GscAnalytics.DataSources.SERP.Core.PersistenceTest do
  use GscAnalytics.DataCase, async: true

  alias GscAnalytics.DataSources.SERP.Core.Persistence
  alias GscAnalytics.Schemas.SerpSnapshot

  describe "save_snapshot/1" do
    test "saves valid snapshot to database" do
      attrs = %{
        account_id: 1,
        property_url: "sc-domain:example.com",
        url: "https://example.com",
        keyword: "test query",
        position: 3,
        competitors: [
          %{"position" => 1, "url" => "https://competitor.com", "title" => "Title"}
        ],
        serp_features: ["featured_snippet"],
        raw_response: %{"result" => %{}},
        geo: "us",
        checked_at: DateTime.utc_now(),
        api_cost: Decimal.new("36")
      }

      assert {:ok, snapshot} = Persistence.save_snapshot(attrs)
      assert snapshot.account_id == 1
      assert snapshot.property_url == "sc-domain:example.com"
      assert snapshot.position == 3
      assert length(snapshot.competitors) == 1
      assert "featured_snippet" in snapshot.serp_features
    end

    test "returns error for invalid data" do
      attrs = %{
        # Missing required fields
        url: "https://example.com"
      }

      assert {:error, changeset} = Persistence.save_snapshot(attrs)
      refute changeset.valid?
    end

    test "stores raw_response as JSONB" do
      raw_response = %{
        "result" => %{
          "status" => "DONE",
          "extracted_data" => %{"data" => %{}}
        }
      }

      attrs = %{
        account_id: 1,
        property_url: "sc-domain:example.com",
        url: "https://example.com",
        keyword: "test",
        raw_response: raw_response,
        checked_at: DateTime.utc_now()
      }

      assert {:ok, snapshot} = Persistence.save_snapshot(attrs)
      assert snapshot.raw_response == raw_response
    end

    test "allows nil position when URL not found" do
      attrs = %{
        account_id: 1,
        property_url: "sc-domain:example.com",
        url: "https://example.com",
        keyword: "test",
        position: nil,
        checked_at: DateTime.utc_now()
      }

      assert {:ok, snapshot} = Persistence.save_snapshot(attrs)
      assert is_nil(snapshot.position)
    end
  end

  describe "latest_for_url/3" do
    setup do
      # Insert old snapshot
      {:ok, old_snapshot} =
        Persistence.save_snapshot(%{
          account_id: 1,
          property_url: "sc-domain:example.com",
          url: "https://example.com",
          keyword: "test",
          position: 5,
          checked_at: DateTime.add(DateTime.utc_now(), -2, :day)
        })

      # Insert recent snapshot
      {:ok, recent_snapshot} =
        Persistence.save_snapshot(%{
          account_id: 1,
          property_url: "sc-domain:example.com",
          url: "https://example.com",
          keyword: "test",
          position: 3,
          checked_at: DateTime.utc_now()
        })

      %{old: old_snapshot, recent: recent_snapshot}
    end

    test "returns most recent snapshot for URL", %{recent: recent} do
      result =
        Persistence.latest_for_url(1, "sc-domain:example.com", "https://example.com")

      assert result.id == recent.id
      assert result.position == 3
    end

    test "returns nil when no snapshot exists" do
      result = Persistence.latest_for_url(1, "sc-domain:example.com", "https://notfound.com")
      assert is_nil(result)
    end

    test "filters by account_id and property_url" do
      # Insert snapshot for different account
      Persistence.save_snapshot(%{
        account_id: 2,
        property_url: "sc-domain:other.com",
        url: "https://example.com",
        keyword: "test",
        position: 10,
        checked_at: DateTime.utc_now()
      })

      result =
        Persistence.latest_for_url(1, "sc-domain:example.com", "https://example.com")

      assert result.account_id == 1
      assert result.property_url == "sc-domain:example.com"
    end
  end

  describe "snapshots_for_property/2" do
    setup do
      # Insert multiple snapshots
      for i <- 1..15 do
        Persistence.save_snapshot(%{
          account_id: 1,
          property_url: "sc-domain:example.com",
          url: "https://example.com/page#{i}",
          keyword: "test #{i}",
          position: i,
          checked_at: DateTime.add(DateTime.utc_now(), -i, :hour)
        })
      end

      :ok
    end

    test "returns snapshots for property" do
      results = Persistence.snapshots_for_property(1, "sc-domain:example.com")

      assert length(results) > 0
      assert Enum.all?(results, &(&1.property_url == "sc-domain:example.com"))
    end

    test "limits results to 100 by default" do
      results = Persistence.snapshots_for_property(1, "sc-domain:example.com")

      assert length(results) <= 100
    end

    test "accepts custom limit" do
      results =
        Persistence.snapshots_for_property(1, "sc-domain:example.com", limit: 5)

      assert length(results) == 5
    end

    test "orders by checked_at desc (most recent first)" do
      results =
        Persistence.snapshots_for_property(1, "sc-domain:example.com", limit: 5)

      positions = Enum.map(results, & &1.position)
      # Positions should be 1,2,3,4,5 (most recent = position 1)
      assert positions == [1, 2, 3, 4, 5]
    end

    test "only returns snapshots with position" do
      # Insert snapshot without position
      Persistence.save_snapshot(%{
        account_id: 1,
        property_url: "sc-domain:example.com",
        url: "https://notfound.com",
        keyword: "missing",
        position: nil,
        checked_at: DateTime.utc_now()
      })

      results = Persistence.snapshots_for_property(1, "sc-domain:example.com")

      assert Enum.all?(results, &(not is_nil(&1.position)))
    end
  end

  describe "delete_old_snapshots/1" do
    setup do
      # Insert old snapshots (8 days ago)
      for i <- 1..3 do
        Persistence.save_snapshot(%{
          account_id: 1,
          property_url: "sc-domain:example.com",
          url: "https://example.com/old#{i}",
          keyword: "old",
          checked_at: DateTime.add(DateTime.utc_now(), -8, :day)
        })
      end

      # Insert recent snapshots (2 days ago)
      for i <- 1..2 do
        Persistence.save_snapshot(%{
          account_id: 1,
          property_url: "sc-domain:example.com",
          url: "https://example.com/recent#{i}",
          keyword: "recent",
          checked_at: DateTime.add(DateTime.utc_now(), -2, :day)
        })
      end

      :ok
    end

    test "deletes snapshots older than N days" do
      {deleted_count, _} = Persistence.delete_old_snapshots(7)

      assert deleted_count == 3
    end

    test "keeps snapshots newer than N days" do
      Persistence.delete_old_snapshots(7)

      remaining = Repo.all(SerpSnapshot)
      assert length(remaining) == 2
      assert Enum.all?(remaining, &(&1.keyword == "recent"))
    end
  end
end
