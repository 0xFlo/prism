defmodule GscAnalytics.MultiPropertyDataIntegrityTest do
  @moduledoc """
  Regression tests for multi-property data isolation.

  Ensures that data from different properties remains isolated and that
  dashboard queries correctly filter by the selected property.
  """

  use GscAnalytics.DataCase

  import GscAnalytics.AccountsFixtures

  alias GscAnalytics.Accounts
  alias GscAnalytics.ContentInsights
  alias GscAnalytics.Analytics.SummaryStats
  alias GscAnalytics.Schemas.TimeSeries
  alias GscAnalytics.Repo

  describe "property data isolation" do
    test "two properties with same URL store separate records" do
      workspace = workspace_fixture()
      account_id = workspace.id

      # Add two properties for the same account
      {:ok, prop1} =
        Accounts.add_property(account_id, %{
          property_url: "sc-domain:example.com",
          display_name: "Domain Property"
        })

      {:ok, prop2} =
        Accounts.add_property(account_id, %{
          property_url: "https://example.com/",
          display_name: "URL Prefix Property"
        })

      # Insert time series data for the same URL but different properties
      # Both properties might track the same URL "https://example.com/page"
      test_url = "https://example.com/page"
      test_date = ~D[2024-01-01]
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Insert data for property 1
      Repo.insert_all(TimeSeries, [
        %{
          account_id: account_id,
          property_url: prop1.property_url,
          url: test_url,
          date: test_date,
          clicks: 100,
          impressions: 1000,
          ctr: 0.1,
          position: 5.0,
          data_available: true,
          inserted_at: now
        }
      ])

      # Insert data for property 2 with different metrics
      Repo.insert_all(TimeSeries, [
        %{
          account_id: account_id,
          property_url: prop2.property_url,
          url: test_url,
          date: test_date,
          clicks: 200,
          impressions: 2000,
          ctr: 0.1,
          position: 3.0,
          data_available: true,
          inserted_at: now
        }
      ])

      # Query data for property 1
      prop1_data =
        TimeSeries
        |> where([ts], ts.account_id == ^account_id)
        |> where([ts], ts.property_url == ^prop1.property_url)
        |> where([ts], ts.url == ^test_url)
        |> where([ts], ts.date == ^test_date)
        |> Repo.one()

      # Query data for property 2
      prop2_data =
        TimeSeries
        |> where([ts], ts.account_id == ^account_id)
        |> where([ts], ts.property_url == ^prop2.property_url)
        |> where([ts], ts.url == ^test_url)
        |> where([ts], ts.date == ^test_date)
        |> Repo.one()

      # Verify data is isolated
      assert prop1_data.clicks == 100
      assert prop1_data.impressions == 1000
      assert prop1_data.position == 5.0

      assert prop2_data.clicks == 200
      assert prop2_data.impressions == 2000
      assert prop2_data.position == 3.0
    end

    test "summary stats correctly filter by property_url" do
      workspace = workspace_fixture()
      account_id = workspace.id

      # Add two properties
      {:ok, prop1} =
        Accounts.add_property(account_id, %{
          property_url: "sc-domain:example.com"
        })

      {:ok, prop2} =
        Accounts.add_property(account_id, %{
          property_url: "https://example.com/"
        })

      # Insert test data for both properties
      today = Date.utc_today()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Property 1 data
      Repo.insert_all(TimeSeries, [
        %{
          account_id: account_id,
          property_url: prop1.property_url,
          url: "https://example.com/page1",
          date: today,
          clicks: 100,
          impressions: 1000,
          ctr: 0.1,
          position: 5.0,
          data_available: true,
          inserted_at: now
        },
        %{
          account_id: account_id,
          property_url: prop1.property_url,
          url: "https://example.com/page2",
          date: today,
          clicks: 50,
          impressions: 500,
          ctr: 0.1,
          position: 7.0,
          data_available: true,
          inserted_at: now
        }
      ])

      # Property 2 data
      Repo.insert_all(TimeSeries, [
        %{
          account_id: account_id,
          property_url: prop2.property_url,
          url: "https://example.com/page1",
          date: today,
          clicks: 200,
          impressions: 2000,
          ctr: 0.1,
          position: 3.0,
          data_available: true,
          inserted_at: now
        },
        %{
          account_id: account_id,
          property_url: prop2.property_url,
          url: "https://example.com/page3",
          date: today,
          clicks: 300,
          impressions: 3000,
          ctr: 0.1,
          position: 2.0,
          data_available: true,
          inserted_at: now
        }
      ])

      # Fetch stats for property 1
      stats1 =
        SummaryStats.fetch(%{
          account_id: account_id,
          property_url: prop1.property_url
        })

      # Fetch stats for property 2
      stats2 =
        SummaryStats.fetch(%{
          account_id: account_id,
          property_url: prop2.property_url
        })

      # Verify property 1 stats (100 + 50 = 150 clicks)
      assert stats1.current_month.total_clicks == 150
      assert stats1.current_month.total_impressions == 1500
      assert stats1.current_month.total_urls == 2

      # Verify property 2 stats (200 + 300 = 500 clicks)
      assert stats2.current_month.total_clicks == 500
      assert stats2.current_month.total_impressions == 5000
      assert stats2.current_month.total_urls == 2
    end

    test "dashboard queries require property_url filter" do
      workspace = workspace_fixture()
      account_id = workspace.id

      # Add a property
      {:ok, prop} =
        Accounts.add_property(account_id, %{
          property_url: "sc-domain:example.com"
        })

      # Attempting to query without property_url should raise
      assert_raise ArgumentError, ~r/property_url is required/, fn ->
        ContentInsights.list_urls(%{
          account_id: account_id,
          limit: 50,
          page: 1
          # property_url missing
        })
      end

      # Query with property_url should work
      result =
        ContentInsights.list_urls(%{
          account_id: account_id,
          property_url: prop.property_url,
          limit: 50,
          page: 1
        })

      assert is_list(result.urls)
      assert result.page == 1
      assert result.total_pages >= 1
    end

    test "composite primary key prevents data collision" do
      workspace = workspace_fixture()
      account_id = workspace.id

      # Add a property
      {:ok, prop} =
        Accounts.add_property(account_id, %{
          property_url: "sc-domain:example.com"
        })

      test_url = "https://example.com/page"
      test_date = ~D[2024-01-01]
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Insert initial data
      {count1, _} =
        Repo.insert_all(
          TimeSeries,
          [
            %{
              account_id: account_id,
              property_url: prop.property_url,
              url: test_url,
              date: test_date,
              clicks: 100,
              impressions: 1000,
              ctr: 0.1,
              position: 5.0,
              data_available: true,
              inserted_at: now
            }
          ],
          on_conflict: {:replace_all_except, [:inserted_at]},
          conflict_target: [:account_id, :property_url, :url, :date]
        )

      assert count1 == 1

      # Attempt to insert duplicate - should update, not insert new row
      {count2, _} =
        Repo.insert_all(
          TimeSeries,
          [
            %{
              account_id: account_id,
              property_url: prop.property_url,
              url: test_url,
              date: test_date,
              # Different value
              clicks: 200,
              impressions: 2000,
              ctr: 0.1,
              position: 3.0,
              data_available: true,
              inserted_at: now
            }
          ],
          on_conflict: {:replace_all_except, [:inserted_at]},
          conflict_target: [:account_id, :property_url, :url, :date]
        )

      # Should have updated, not inserted a new row
      assert count2 == 1

      # Verify only one row exists and it has the updated values
      data =
        TimeSeries
        |> where([ts], ts.account_id == ^account_id)
        |> where([ts], ts.property_url == ^prop.property_url)
        |> where([ts], ts.url == ^test_url)
        |> where([ts], ts.date == ^test_date)
        |> Repo.all()

      assert length(data) == 1
      # Should have the updated value
      assert hd(data).clicks == 200
    end
  end
end
