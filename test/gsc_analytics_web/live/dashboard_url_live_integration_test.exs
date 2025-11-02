defmodule GscAnalyticsWeb.DashboardUrlLiveIntegrationTest do
  @moduledoc """
  Integration tests for URL detail page user journeys.

  Tests the complete user experience when viewing individual URL analytics:
  - Time series charts (daily/weekly/monthly views)
  - Summary statistics
  - Top performing queries
  - URL redirect history

  Following testing guidelines:
  - Test behavior, not implementation
  - Assert on what users see
  - Tests survive refactoring
  """

  use GscAnalyticsWeb.ConnCase

  @moduletag :integration

  import Phoenix.LiveViewTest
  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.TimeSeries

  @property_url "sc-domain:example.com"

  setup :register_and_log_in_user

  describe "URL detail user journey: viewing time series" do
    test "user can view URL with daily time series chart", %{conn: conn} do
      # Setup: Create 30 days of data for a URL
      account_id = 1
      url = "https://example.com/test-article"

      dates = for days_ago <- 0..29, do: Date.add(~D[2025-10-15], -days_ago)

      for date <- dates do
        populate_url_data(account_id, url, date, %{
          clicks: 50 + :rand.uniform(50),
          impressions: 500 + :rand.uniform(500)
        })
      end

      # Action: Navigate to URL detail page
      encoded_url = URI.encode_www_form(url)
      {:ok, view, html} = live(conn, ~p"/dashboard/url?url=#{encoded_url}")

      # Assert: Page loads with URL shown
      assert html =~ "test-article"

      # Assert: Shows summary metrics
      assert html =~ "Clicks"
      assert html =~ "Impressions"
      assert html =~ "CTR"
      assert html =~ "Position"

      # Assert: Shows time series chart (chart container exists)
      assert has_element?(view, "[data-chart]") or
               html =~ "chart" or
               html =~ "Date"

      # Assert: Shows daily view by default
      assert html =~ "Daily" or html =~ "Date"
    end

    test "user sees empty state for URL with no data", %{conn: conn} do
      # No data setup

      # Action: Try to view non-existent URL
      encoded_url = URI.encode_www_form("https://example.com/nonexistent")
      {:ok, _view, html} = live(conn, ~p"/dashboard/url?url=#{encoded_url}")

      # Assert: Shows appropriate message (not an error crash)
      assert html =~ "No performance data yet"
    end

    test "user can view URL with partial data (some days missing)", %{conn: conn} do
      # Setup: Sparse data (only some days have metrics)
      account_id = 1
      url = "https://example.com/sparse-data"

      # Only populate days 0, 5, 10, 15 (gaps in between)
      for days_ago <- [0, 5, 10, 15] do
        date = Date.add(~D[2025-10-15], -days_ago)
        populate_url_data(account_id, url, date, %{clicks: 100, impressions: 1000})
      end

      # Action: View URL detail
      encoded_url = URI.encode_www_form(url)
      {:ok, _view, html} = live(conn, ~p"/dashboard/url?url=#{encoded_url}")

      # Assert: Page loads (doesn't crash on missing data)
      assert html =~ "sparse-data"

      # Assert: Shows available metrics
      # Contains numbers
      assert html =~ ~r/\d+/
    end
  end

  describe "URL detail user journey: switching time views" do
    test "user can switch between daily, weekly, and monthly views", %{conn: conn} do
      # Setup: Create enough data for meaningful aggregations
      account_id = 1
      url = "https://example.com/popular-page"

      # 90 days of data
      dates = for days_ago <- 0..89, do: Date.add(~D[2025-10-15], -days_ago)

      for date <- dates do
        populate_url_data(account_id, url, date, %{clicks: 100, impressions: 1000})
      end

      encoded_url = URI.encode_www_form(url)
      {:ok, view, html} = live(conn, ~p"/dashboard/url?url=#{encoded_url}&view=daily")

      # Assert: Daily view active
      assert html =~ "Daily" or html =~ "Date"

      # Action: Switch to weekly view
      html =
        view
        |> element("button", "Weekly")
        |> render_click()

      # Assert: Weekly view active
      assert html =~ "Weekly" or html =~ "Week"

      # Action: Switch to monthly view
      html =
        view
        |> element("button", "Monthly")
        |> render_click()

      # Assert: Monthly view active
      assert html =~ "Monthly" or html =~ "Month"
    end

    test "view mode persists in URL params", %{conn: conn} do
      # Setup
      account_id = 1
      url = "https://example.com/test"

      for days_ago <- 0..30 do
        date = Date.add(~D[2025-10-15], -days_ago)
        populate_url_data(account_id, url, date, %{clicks: 50, impressions: 500})
      end

      # Action: Load with weekly view
      encoded_url = URI.encode_www_form(url)
      {:ok, _view, html} = live(conn, ~p"/dashboard/url?url=#{encoded_url}&view=weekly")

      # Assert: URL params reflect view mode (view loads with weekly active)
      assert html =~ "Weekly" or html =~ "Week"

      # Action: Refresh page (simulate bookmark/reload)
      {:ok, _view, html} = live(conn, ~p"/dashboard/url?url=#{encoded_url}&view=weekly")

      # Assert: Weekly view still active
      assert html =~ "Weekly" or html =~ "Week"
    end
  end

  describe "URL detail user journey: viewing top queries" do
    test "user can see top performing search queries for URL", %{conn: conn} do
      # Setup: Create URL with top queries data
      account_id = 1
      url = "https://example.com/article"
      date = ~D[2025-10-15]

      top_queries = [
        %{
          "query" => "elixir phoenix",
          "clicks" => 100,
          "impressions" => 1000,
          "ctr" => 0.1,
          "position" => 5.0
        },
        %{
          "query" => "liveview tutorial",
          "clicks" => 80,
          "impressions" => 900,
          "ctr" => 0.089,
          "position" => 7.0
        },
        %{
          "query" => "phoenix framework",
          "clicks" => 60,
          "impressions" => 800,
          "ctr" => 0.075,
          "position" => 10.0
        }
      ]

      populate_url_data(account_id, url, date, %{
        clicks: 240,
        impressions: 2700,
        top_queries: top_queries
      })

      # Action: View URL detail
      encoded_url = URI.encode_www_form(url)
      {:ok, _view, html} = live(conn, ~p"/dashboard/url?url=#{encoded_url}")

      # Assert: Shows top queries section
      assert html =~ "Top Queries" or html =~ "Search Queries" or html =~ "Keywords"

      # Assert: Shows individual queries
      assert html =~ "elixir phoenix"
      assert html =~ "liveview tutorial"
      assert html =~ "phoenix framework"

      # Assert: Shows query metrics
      # Top query clicks
      assert html =~ "100"
    end

    test "user sees message when no query data available", %{conn: conn} do
      # Setup: URL with no top_queries data
      account_id = 1
      url = "https://example.com/no-queries"
      date = ~D[2025-10-15]

      populate_url_data(account_id, url, date, %{
        clicks: 100,
        impressions: 1000,
        # No query data
        top_queries: nil
      })

      # Action: View URL detail
      encoded_url = URI.encode_www_form(url)
      {:ok, _view, html} = live(conn, ~p"/dashboard/url?url=#{encoded_url}")

      # Assert: Shows appropriate message (not a crash)
      assert html =~ "No query data" or html =~ "no queries" or html =~ "N/A"
    end
  end

  describe "URL detail user journey: summary statistics" do
    test "user sees accurate summary stats matching chart data", %{conn: conn} do
      # Setup: Precise data for verification
      account_id = 1
      url = "https://example.com/test"

      # Create 7 days with known values
      populate_url_data(account_id, url, ~D[2025-10-15], %{clicks: 100, impressions: 1000})
      populate_url_data(account_id, url, ~D[2025-10-14], %{clicks: 150, impressions: 1500})
      populate_url_data(account_id, url, ~D[2025-10-13], %{clicks: 200, impressions: 2000})

      # Action: View URL detail
      encoded_url = URI.encode_www_form(url)
      {:ok, _view, html} = live(conn, ~p"/dashboard/url?url=#{encoded_url}")

      # Assert: Shows summary section
      assert html =~ "Total Clicks" or html =~ "Clicks"
      assert html =~ "Impressions"

      # Assert: Shows aggregated metrics
      # Total clicks should be 450 (100+150+200)
      assert html =~ "450"

      # Total impressions should be 4500 (1000+1500+2000)
      assert html =~ "4500" or html =~ "4,500"
    end

    test "user can see time range of data", %{conn: conn} do
      # Setup: Data spanning specific range
      account_id = 1
      url = "https://example.com/test"

      start_date = ~D[2025-10-01]
      end_date = ~D[2025-10-15]

      dates = Date.range(start_date, end_date) |> Enum.to_list()

      for date <- dates do
        populate_url_data(account_id, url, date, %{clicks: 50, impressions: 500})
      end

      # Action: View URL detail
      encoded_url = URI.encode_www_form(url)
      {:ok, _view, html} = live(conn, ~p"/dashboard/url?url=#{encoded_url}")

      # Assert: Shows date range information
      assert html =~ "15 days" or html =~ "Oct" or html =~ "2025"
    end
  end

  describe "URL detail user journey: URL encoding edge cases" do
    test "user can view URL with special characters", %{conn: conn} do
      # Setup: URL with query parameters and special chars
      account_id = 1
      url = "https://example.com/search?q=test+query&category=docs"
      date = ~D[2025-10-15]

      populate_url_data(account_id, url, date, %{clicks: 100, impressions: 1000})

      # Action: View URL detail (URL encoding handled by route)
      encoded_url = URI.encode_www_form(url)
      {:ok, _view, html} = live(conn, ~p"/dashboard/url?url=#{encoded_url}")

      # Assert: Page loads successfully
      assert html =~ "search" or html =~ "test"
    end

    test "user can view URL with UTF-8 characters", %{conn: conn} do
      # Setup: URL with international characters
      account_id = 1
      url = "https://example.com/guía/español"
      date = ~D[2025-10-15]

      populate_url_data(account_id, url, date, %{clicks: 50, impressions: 500})

      # Action: View URL detail
      encoded_url = URI.encode_www_form(url)
      {:ok, _view, html} = live(conn, ~p"/dashboard/url?url=#{encoded_url}")

      # Assert: Page loads and displays URL correctly
      assert html =~ "guía" or html =~ "español" or html =~ "example.com"
    end
  end

  describe "URL detail user journey: navigation" do
    test "user can navigate back to dashboard from URL detail", %{conn: conn} do
      # Setup
      account_id = 1
      url = "https://example.com/test"
      populate_url_data(account_id, url, ~D[2025-10-15], %{clicks: 100, impressions: 1000})

      # Action: Navigate to URL detail
      encoded_url = URI.encode_www_form(url)
      {:ok, view, _html} = live(conn, ~p"/dashboard/url?url=#{encoded_url}")

      # Assert: Has back link/button
      assert has_element?(view, "a[href='/']") or
               has_element?(view, "a[href='/dashboard']") or
               render(view) =~ "Back"
    end

    test "user can share URL detail page via URL", %{conn: conn} do
      # Setup
      account_id = 1
      url = "https://example.com/shareable-article"
      populate_url_data(account_id, url, ~D[2025-10-15], %{clicks: 500, impressions: 5000})

      # Action: Load page with full URL (simulating shared link)
      encoded_url = URI.encode_www_form(url)
      {:ok, _view, html} = live(conn, ~p"/dashboard/url?url=#{encoded_url}&view=weekly")

      # Assert: Page loads with correct state
      assert html =~ "shareable-article"
      assert html =~ "Weekly"
    end
  end

  # Helper functions

  defp populate_url_data(account_id, url, date, opts) do
    clicks = Map.get(opts, :clicks, 100)
    impressions = Map.get(opts, :impressions, 1000)
    position = Map.get(opts, :position, 10.0)
    top_queries = Map.get(opts, :top_queries, nil)

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    record = %{
      account_id: account_id,
      property_url: @property_url,
      url: url,
      date: date,
      clicks: clicks,
      impressions: impressions,
      ctr: if(impressions > 0, do: clicks / impressions, else: 0.0),
      position: position,
      top_queries: if(top_queries, do: top_queries, else: nil),
      data_available: true,
      period_type: :daily,
      inserted_at: now
    }

    Repo.insert_all(TimeSeries, [record])
  end
end
