defmodule GscAnalytics.Schemas.SerpSnapshotTest do
  use GscAnalytics.DataCase, async: true

  alias GscAnalytics.Schemas.SerpSnapshot

  describe "changeset/2" do
    test "valid attributes" do
      attrs = %{
        account_id: 1,
        property_url: "sc-domain:example.com",
        url: "https://example.com",
        keyword: "test query",
        checked_at: DateTime.utc_now()
      }

      changeset = SerpSnapshot.changeset(%SerpSnapshot{}, attrs)
      assert changeset.valid?
    end

    test "requires account_id" do
      attrs = %{
        property_url: "sc-domain:example.com",
        url: "https://example.com",
        keyword: "test",
        checked_at: DateTime.utc_now()
      }

      changeset = SerpSnapshot.changeset(%SerpSnapshot{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).account_id
    end

    test "requires property_url" do
      attrs = %{
        account_id: 1,
        url: "https://example.com",
        keyword: "test",
        checked_at: DateTime.utc_now()
      }

      changeset = SerpSnapshot.changeset(%SerpSnapshot{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).property_url
    end

    test "requires url" do
      attrs = %{
        account_id: 1,
        property_url: "sc-domain:example.com",
        keyword: "test",
        checked_at: DateTime.utc_now()
      }

      changeset = SerpSnapshot.changeset(%SerpSnapshot{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).url
    end

    test "requires keyword" do
      attrs = %{
        account_id: 1,
        property_url: "sc-domain:example.com",
        url: "https://example.com",
        checked_at: DateTime.utc_now()
      }

      changeset = SerpSnapshot.changeset(%SerpSnapshot{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).keyword
    end

    test "requires checked_at" do
      attrs = %{
        account_id: 1,
        property_url: "sc-domain:example.com",
        url: "https://example.com",
        keyword: "test"
      }

      changeset = SerpSnapshot.changeset(%SerpSnapshot{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).checked_at
    end

    test "validates URL format" do
      attrs = %{
        account_id: 1,
        property_url: "sc-domain:example.com",
        url: "not-a-url",
        keyword: "test",
        checked_at: DateTime.utc_now()
      }

      changeset = SerpSnapshot.changeset(%SerpSnapshot{}, attrs)
      refute changeset.valid?
      assert "must be a valid HTTP(S) URL" in errors_on(changeset).url
    end

    test "validates position range - too low" do
      attrs = %{
        account_id: 1,
        property_url: "sc-domain:example.com",
        url: "https://example.com",
        keyword: "test",
        position: 0,
        checked_at: DateTime.utc_now()
      }

      changeset = SerpSnapshot.changeset(%SerpSnapshot{}, attrs)
      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).position
    end

    test "validates position range - too high" do
      attrs = %{
        account_id: 1,
        property_url: "sc-domain:example.com",
        url: "https://example.com",
        keyword: "test",
        position: 101,
        checked_at: DateTime.utc_now()
      }

      changeset = SerpSnapshot.changeset(%SerpSnapshot{}, attrs)
      refute changeset.valid?
      assert "must be less than or equal to 100" in errors_on(changeset).position
    end

    test "validates keyword length - too short" do
      attrs = %{
        account_id: 1,
        property_url: "sc-domain:example.com",
        url: "https://example.com",
        keyword: "",
        checked_at: DateTime.utc_now()
      }

      changeset = SerpSnapshot.changeset(%SerpSnapshot{}, attrs)
      refute changeset.valid?
    end

    test "validates geo location" do
      attrs = %{
        account_id: 1,
        property_url: "sc-domain:example.com",
        url: "https://example.com",
        keyword: "test",
        geo: "invalid_geo",
        checked_at: DateTime.utc_now()
      }

      changeset = SerpSnapshot.changeset(%SerpSnapshot{}, attrs)
      refute changeset.valid?
      assert "must be one of:" <> _ = List.first(errors_on(changeset).geo)
    end

    test "accepts valid geo locations" do
      valid_geos = ["us", "uk", "ca", "au"]

      for geo <- valid_geos do
        attrs = %{
          account_id: 1,
          property_url: "sc-domain:example.com",
          url: "https://example.com",
          keyword: "test",
          geo: geo,
          checked_at: DateTime.utc_now()
        }

        changeset = SerpSnapshot.changeset(%SerpSnapshot{}, attrs)
        assert changeset.valid?, "Expected #{geo} to be valid"
      end
    end

    test "accepts optional fields" do
      attrs = %{
        account_id: 1,
        property_url: "sc-domain:example.com",
        url: "https://example.com",
        keyword: "test",
        position: 5,
        serp_features: ["featured_snippet", "people_also_ask"],
        competitors: [%{"url" => "https://competitor.com", "position" => 3}],
        raw_response: %{"organic_results" => []},
        api_cost: Decimal.new("31.5"),
        error_message: nil,
        checked_at: DateTime.utc_now()
      }

      changeset = SerpSnapshot.changeset(%SerpSnapshot{}, attrs)
      assert changeset.valid?
    end
  end

  describe "query helpers" do
    test "for_property/2 returns query filtered by property_url" do
      query = SerpSnapshot.for_property("sc-domain:example.com")
      assert %Ecto.Query{} = query
    end

    test "for_account_and_property/3 returns query filtered by both" do
      query = SerpSnapshot.for_account_and_property(1, "sc-domain:example.com")
      assert %Ecto.Query{} = query
    end

    test "for_url/2 returns query filtered by url" do
      query = SerpSnapshot.for_url("https://example.com")
      assert %Ecto.Query{} = query
    end

    test "latest_for_url/4 returns query for latest snapshot" do
      query =
        SerpSnapshot.latest_for_url(1, "sc-domain:example.com", "https://example.com")

      assert %Ecto.Query{} = query
    end

    test "with_position/1 returns query for snapshots with position" do
      query = SerpSnapshot.with_position()
      assert %Ecto.Query{} = query
    end

    test "recent/2 returns query for recent snapshots" do
      query = SerpSnapshot.recent(7)
      assert %Ecto.Query{} = query
    end

    test "older_than/2 returns query for old snapshots" do
      query = SerpSnapshot.older_than(30)
      assert %Ecto.Query{} = query
    end
  end

  describe "data helpers" do
    test "migrate_competitors normalizes entries" do
      competitors = [%{"url" => "https://Example.com/path", "position" => "2", "title" => " Title "}]

      [normalized] = SerpSnapshot.migrate_competitors(competitors)
      assert normalized["domain"] == "example.com"
      assert normalized["position"] == 2
      assert normalized["schema_version"] == SerpSnapshot.competitor_schema_version()
    end

    test "content_types_from_competitors deduplicates values" do
      competitors = [
        %{"content_type" => "Reddit"},
        %{content_type: "reddit"},
        %{content_type: "forum"}
      ]

      assert SerpSnapshot.content_types_from_competitors(competitors) == ["reddit", "forum"]
    end

    test "scrapfly_citation_stats detects brand mentions" do
      citations = [%{"domain" => "scrapfly.io", "position" => 3}]
      assert SerpSnapshot.scrapfly_citation_stats(citations) == {true, 3}

      assert SerpSnapshot.scrapfly_citation_stats(nil) == {false, nil}
    end
  end
end
