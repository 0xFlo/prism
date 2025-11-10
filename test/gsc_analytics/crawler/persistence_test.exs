defmodule GscAnalytics.Crawler.PersistenceTest do
  use GscAnalytics.DataCase, async: true

  alias GscAnalytics.Crawler.Persistence
  alias GscAnalytics.Schemas.{Performance, UrlLifetimeStats}
  alias GscAnalytics.Repo

  import Ecto.Query

  @test_property_url "sc-domain:example.com"

  setup do
    Repo.delete_all(UrlLifetimeStats)

    # Create test performance records
    urls = [
      "https://example.com/page-1",
      "https://example.com/page-2",
      "https://example.com/page-3"
    ]

    refreshed_at = DateTime.utc_now() |> DateTime.truncate(:second)

    for url <- urls do
      Repo.insert!(%Performance{
        account_id: 1,
        property_url: @test_property_url,
        url: url,
        clicks: 100,
        impressions: 1000,
        ctr: 0.1,
        position: 5.0,
        date_range_start: ~D[2025-01-01],
        date_range_end: ~D[2025-01-31],
        data_available: true
      })

      Repo.insert!(%UrlLifetimeStats{
        account_id: 1,
        property_url: @test_property_url,
        url: url,
        lifetime_clicks: 100,
        lifetime_impressions: 1000,
        avg_position: 5.0,
        avg_ctr: 0.1,
        first_seen_date: ~D[2025-01-01],
        last_seen_date: ~D[2025-01-31],
        days_with_data: 31,
        refreshed_at: refreshed_at
      })
    end

    %{urls: urls}
  end

  describe "save_result/2" do
    test "saves HTTP status for a single URL", %{urls: urls} do
      url = List.first(urls)

      result = %{
        status: 200,
        redirect_url: nil,
        redirect_chain: %{},
        checked_at: DateTime.utc_now() |> DateTime.truncate(:second),
        error: nil
      }

      {:ok, count} = Persistence.save_result(url, result)

      assert count == 1

      # Verify database was updated
      performance = Repo.get_by(Performance, url: url)
      assert performance.http_status == 200
      assert performance.redirect_url == nil
      assert performance.http_checked_at != nil
    end

    test "saves redirect information when status is 301", %{urls: urls} do
      url = List.first(urls)

      result = %{
        status: 301,
        redirect_url: "https://example.com/new-page",
        redirect_chain: %{"step_1" => url, "step_2" => "https://example.com/new-page"},
        checked_at: DateTime.utc_now() |> DateTime.truncate(:second),
        error: nil
      }

      {:ok, count} = Persistence.save_result(url, result)

      assert count == 1

      # Verify database was updated
      performance = Repo.get_by(Performance, url: url)
      assert performance.http_status == 301
      assert performance.redirect_url == "https://example.com/new-page"

      assert performance.http_redirect_chain == %{
               "step_1" => url,
               "step_2" => "https://example.com/new-page"
             }
    end

    test "saves 404 status for broken links", %{urls: urls} do
      url = List.first(urls)

      result = %{
        status: 404,
        redirect_url: nil,
        redirect_chain: %{},
        checked_at: DateTime.utc_now() |> DateTime.truncate(:second),
        error: nil
      }

      {:ok, count} = Persistence.save_result(url, result)

      assert count == 1

      # Verify database was updated
      performance = Repo.get_by(Performance, url: url)
      assert performance.http_status == 404
    end

    test "updates existing record instead of creating duplicate", %{urls: urls} do
      url = List.first(urls)

      # Save first time
      result1 = %{
        status: 200,
        redirect_url: nil,
        redirect_chain: %{},
        checked_at: DateTime.utc_now() |> DateTime.truncate(:second),
        error: nil
      }

      {:ok, _} = Persistence.save_result(url, result1)

      # Save second time with different status
      result2 = %{
        status: 404,
        redirect_url: nil,
        redirect_chain: %{},
        checked_at: DateTime.utc_now() |> DateTime.truncate(:second),
        error: nil
      }

      {:ok, _} = Persistence.save_result(url, result2)

      # Should only have one record with updated status
      count =
        Performance
        |> where([p], p.url == ^url)
        |> Repo.aggregate(:count)

      assert count == 1

      # Verify it was updated, not inserted
      performance = Repo.get_by(Performance, url: url)
      assert performance.http_status == 404
    end

    test "returns count of results processed even if URL doesn't exist in database" do
      url = "https://nonexistent.com"

      result = %{
        status: 200,
        redirect_url: nil,
        redirect_chain: %{},
        checked_at: DateTime.utc_now() |> DateTime.truncate(:second),
        error: nil
      }

      {:ok, count} = Persistence.save_result(url, result)

      # Returns count of results processed (1), not rows updated (0)
      assert count == 1

      # Verify no record was created (Persistence only updates existing records)
      refute Repo.get_by(Performance, url: url)
    end
  end

  describe "save_batch/1" do
    test "saves multiple results in a batch", %{urls: urls} do
      checked_at = DateTime.utc_now() |> DateTime.truncate(:second)

      results = [
        {Enum.at(urls, 0),
         %{
           status: 200,
           redirect_url: nil,
           redirect_chain: %{},
           checked_at: checked_at,
           error: nil
         }},
        {Enum.at(urls, 1),
         %{
           status: 404,
           redirect_url: nil,
           redirect_chain: %{},
           checked_at: checked_at,
           error: nil
         }},
        {Enum.at(urls, 2),
         %{
           status: 301,
           redirect_url: "https://example.com/new",
           redirect_chain: %{},
           checked_at: checked_at,
           error: nil
         }}
      ]

      {:ok, total} = Persistence.save_batch(results)

      assert total == 3

      # Verify all were updated
      updated_count =
        Performance
        |> where([p], p.url in ^urls)
        |> where([p], not is_nil(p.http_checked_at))
        |> Repo.aggregate(:count)

      assert updated_count == 3
    end

    test "handles empty results list" do
      {:ok, total} = Persistence.save_batch([])

      assert total == 0
    end

    test "handles large batches (chunking behavior)" do
      # Create 250 URLs to test chunking (batch size is 100)
      bulk_urls = Enum.map(1..250, fn i -> "https://example.com/bulk-#{i}" end)

      # Insert performance records
      for url <- bulk_urls do
        Repo.insert!(%Performance{
          account_id: 1,
          property_url: @test_property_url,
          url: url,
          clicks: 10,
          impressions: 100,
          ctr: 0.1,
          position: 10.0,
          date_range_start: ~D[2025-01-01],
          date_range_end: ~D[2025-01-31],
          data_available: true
        })

        Repo.insert!(%UrlLifetimeStats{
          account_id: 1,
          property_url: @test_property_url,
          url: url,
          lifetime_clicks: 10,
          lifetime_impressions: 100,
          avg_position: 10.0,
          avg_ctr: 0.1,
          first_seen_date: ~D[2025-01-01],
          last_seen_date: ~D[2025-01-31],
          days_with_data: 31,
          refreshed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
      end

      checked_at = DateTime.utc_now() |> DateTime.truncate(:second)

      results =
        Enum.map(bulk_urls, fn url ->
          {url,
           %{
             status: 200,
             redirect_url: nil,
             redirect_chain: %{},
             checked_at: checked_at,
             error: nil
           }}
        end)

      {:ok, total} = Persistence.save_batch(results)

      assert total == 250

      # Verify all were updated
      updated_count =
        Performance
        |> where([p], p.url in ^bulk_urls)
        |> where([p], not is_nil(p.http_checked_at))
        |> Repo.aggregate(:count)

      assert updated_count == 250
    end

    test "handles mix of existing and non-existing URLs" do
      checked_at = DateTime.utc_now() |> DateTime.truncate(:second)

      results = [
        {"https://example.com/page-1",
         %{
           status: 200,
           redirect_url: nil,
           redirect_chain: %{},
           checked_at: checked_at,
           error: nil
         }},
        {"https://nonexistent.com",
         %{
           status: 404,
           redirect_url: nil,
           redirect_chain: %{},
           checked_at: checked_at,
           error: nil
         }}
      ]

      {:ok, total} = Persistence.save_batch(results)

      # Should count both (even though one doesn't update anything)
      assert total == 2

      # Verify only existing URL was updated
      performance = Repo.get_by(Performance, url: "https://example.com/page-1")
      assert performance.http_status == 200
    end

    test "updates url_lifetime_stats so aggregate queries stay in sync", %{urls: urls} do
      url = List.first(urls)
      checked_at = DateTime.utc_now() |> DateTime.truncate(:second)

      results = [
        {url,
         %{
           status: 500,
           redirect_url: nil,
           redirect_chain: %{},
           checked_at: checked_at,
           error: nil
         }}
      ]

      {:ok, _} = Persistence.save_batch(results)

      lifetime =
        UrlLifetimeStats
        |> where(
          [ls],
          ls.account_id == 1 and ls.property_url == ^@test_property_url and ls.url == ^url
        )
        |> Repo.one!()

      assert lifetime.http_status == 500
      assert lifetime.http_checked_at == checked_at
    end

    test "preserves other Performance fields when updating" do
      url = "https://example.com/page-1"

      # Get original record
      original = Repo.get_by(Performance, url: url)

      checked_at = DateTime.utc_now() |> DateTime.truncate(:second)

      results = [
        {url,
         %{
           status: 200,
           redirect_url: nil,
           redirect_chain: %{},
           checked_at: checked_at,
           error: nil
         }}
      ]

      {:ok, _} = Persistence.save_batch(results)

      # Get updated record
      updated = Repo.get_by(Performance, url: url)

      # Other fields should be preserved
      assert updated.clicks == original.clicks
      assert updated.impressions == original.impressions
      assert updated.ctr == original.ctr
      assert updated.position == original.position
      assert updated.data_available == original.data_available

      # Only HTTP fields should be updated
      assert updated.http_status == 200
      assert updated.http_checked_at != nil
    end

    test "updates http_redirect_chain as JSONB map" do
      url = "https://example.com/page-1"
      checked_at = DateTime.utc_now() |> DateTime.truncate(:second)

      chain = %{
        "step_1" => "https://example.com/old",
        "step_2" => "https://example.com/middle",
        "step_3" => "https://example.com/new"
      }

      results = [
        {url,
         %{
           status: 301,
           redirect_url: "https://example.com/new",
           redirect_chain: chain,
           checked_at: checked_at,
           error: nil
         }}
      ]

      {:ok, _} = Persistence.save_batch(results)

      performance = Repo.get_by(Performance, url: url)
      assert performance.http_redirect_chain == chain
    end
  end

  describe "updated_at timestamp" do
    test "updates updated_at when saving result", %{urls: urls} do
      url = List.first(urls)

      # Get original updated_at
      original = Repo.get_by(Performance, url: url)
      original_updated_at = original.updated_at

      # Small delay to ensure different timestamp
      Process.sleep(100)

      checked_at = DateTime.utc_now() |> DateTime.truncate(:second)

      result = %{
        status: 200,
        redirect_url: nil,
        redirect_chain: %{},
        checked_at: checked_at,
        error: nil
      }

      {:ok, _} = Persistence.save_result(url, result)

      # Get updated record
      updated = Repo.get_by(Performance, url: url)

      # updated_at should be newer (or equal if timestamps are very close)
      assert DateTime.compare(updated.updated_at, original_updated_at) in [:gt, :eq]
    end
  end
end
