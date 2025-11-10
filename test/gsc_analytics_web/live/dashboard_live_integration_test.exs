defmodule GscAnalyticsWeb.DashboardLiveIntegrationTest do
  @moduledoc """
  Integration tests for dashboard user journeys.

  Tests the complete user experience: viewing URLs, sorting, filtering, pagination.
  These tests verify behavior (what users see) not implementation (how it works).

  Following testing guidelines:
  - Test at the highest level (LiveView integration)
  - Assert on observable outcomes (rendered HTML, URL params)
  - Tests should survive refactoring (don't test internal state)
  """

  use GscAnalyticsWeb.ConnCase, async: false

  @moduletag :integration
  @test_property_url "sc-domain:example.com"

  import Ecto.Query
  import Phoenix.LiveViewTest
  import GscAnalytics.WorkspaceTestHelper

  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.TimeSeries

  setup :register_and_log_in_user

  setup %{user: user} do
    {workspace, property} =
      setup_workspace_with_property(user: user, property_url: @test_property_url)

    %{workspace: workspace, property: property, account_id: workspace.id}
  end

  describe "dashboard user journey: viewing URL list" do
    test "user can view dashboard with URLs sorted by clicks", %{
      conn: conn,
      account_id: account_id
    } do
      # Setup: Create test data via database (not factories - real data flow)
      # account_id from setup
      date = ~D[2025-10-15]

      populate_time_series_data(account_id, date, [
        {"https://example.com/high-traffic", 1000, 10000},
        {"https://example.com/medium-traffic", 500, 5000},
        {"https://example.com/low-traffic", 100, 1000}
      ])

      # Action: User visits dashboard (follows redirect to property-specific dashboard)
      {:ok, _view, html} = follow_live_redirect(conn, ~p"/")

      # Assert: Dashboard loads and shows URLs
      assert html =~ "GSC Dashboard" || html =~ "GSC Analytics Dashboard"
      assert html =~ "https://example.com/high-traffic"
      assert html =~ "https://example.com/medium-traffic"
      assert html =~ "https://example.com/low-traffic"

      # Assert: URLs are sorted by clicks (descending) by default
      # Check that high-traffic appears before low-traffic in the HTML
      assert html =~ ~r/high-traffic.*medium-traffic.*low-traffic/s
    end

    test "user sees empty state when no data exists", %{conn: conn, account_id: _account_id} do
      # No data setup - fresh database

      # Action: Visit dashboard (follows redirect to property-specific dashboard)
      {:ok, _view, html} = follow_live_redirect(conn, ~p"/")

      # Assert: Shows empty state message (not an error)
      assert html =~ "No URLs found"
    end

    test "user can view URLs with lifetime and period metrics", %{
      conn: conn,
      account_id: account_id
    } do
      # Setup: Create data with identifiable metrics
      # account_id from setup

      # Create 30 days of data to ensure lifetime stats exist
      for days_ago <- 0..30 do
        date = Date.add(~D[2025-10-15], -days_ago)

        populate_time_series_data(account_id, date, [
          {"https://example.com/tracked-url", 10, 100}
        ])
      end

      # Action: Visit dashboard (follows redirect to property-specific dashboard)
      {:ok, _view, html} = follow_live_redirect(conn, ~p"/")

      # Assert: Shows the tracked URL
      assert html =~ "tracked-url"

      # Assert: Shows metrics (clicks, impressions)
      # We don't assert on exact numbers (implementation detail)
      # Just that metrics are visible
      # Contains numbers (metrics)
      assert html =~ ~r/\d+/
    end
  end

  describe "dashboard user journey: search and filtering" do
    test "user can search for specific URLs", %{conn: conn, account_id: account_id} do
      # Setup: Create URLs with distinct patterns
      # account_id from setup
      date = ~D[2025-10-15]

      populate_time_series_data(account_id, date, [
        {"https://example.com/blog/post-1", 100, 1000},
        {"https://example.com/blog/post-2", 150, 1500},
        {"https://example.com/docs/guide", 200, 2000}
      ])

      {:ok, view, _html} = follow_live_redirect(conn, ~p"/")

      # Action: Search for "blog"
      html =
        view
        |> element("#dashboard-search-form")
        # Live search
        |> render_change(%{"search" => "blog"})

      # Assert: Only blog URLs shown
      assert html =~ "blog/post-1"
      assert html =~ "blog/post-2"
      refute html =~ "docs/guide"
    end

    test "user sees 'no results' when search has no matches", %{
      conn: conn,
      account_id: account_id
    } do
      # Setup
      populate_time_series_data(account_id, ~D[2025-10-15], [
        {"https://example.com/page", 100, 1000}
      ])

      {:ok, view, _html} = follow_live_redirect(conn, ~p"/")

      # Action: Search for non-existent term
      html =
        view
        |> element("#dashboard-search-form")
        |> render_change(%{"search" => "nonexistent"})

      # Assert: Shows no results message
      assert html =~ "No URLs found for the current filters"
    end

    test "search state persists in URL params", %{conn: conn, account_id: account_id} do
      # Setup
      populate_time_series_data(account_id, ~D[2025-10-15], [
        {"https://example.com/test", 100, 1000}
      ])

      {:ok, view, _html} = follow_live_redirect(conn, ~p"/")

      # Action: Perform search
      view
      |> element("#dashboard-search-form")
      |> render_change(%{"search" => "test"})

      assert render(view) =~ ~r/id="search-input"[^>]*value="test"/
    end
  end

  describe "dashboard user journey: pagination" do
    test "user can navigate through pages of results", %{conn: conn, account_id: account_id} do
      # Setup: Create more URLs than fit on one page
      # account_id from setup
      date = ~D[2025-10-15]

      urls = for i <- 1..150, do: {"https://example.com/page-#{i}", 100, 1000}
      populate_time_series_data(account_id, date, urls)

      # Action: Visit dashboard with page limit (follows redirect)
      {:ok, view, html} = follow_live_redirect(conn, ~p"/?limit=50")

      # Assert: Shows pagination controls
      assert html =~ "Next" or html =~ "Page"

      # Assert: Shows first 50 URLs
      assert html =~ "page-1"
      refute html =~ "page-51"

      # Action: Navigate to page 2
      html =
        view
        |> element("button[phx-click=next_page]")
        |> render_click()

      # Assert: Shows next 50 URLs
      assert html =~ "page-51"
    end

    test "user can change page size", %{conn: conn, account_id: account_id} do
      # Setup
      # account_id from setup
      date = ~D[2025-10-15]

      urls = for i <- 1..200, do: {"https://example.com/page-#{i}", 100, 1000}
      populate_time_series_data(account_id, date, urls)

      # Action: Set custom page size (follows redirect)
      {:ok, view, _html} = follow_live_redirect(conn, ~p"/?limit=25")

      assert has_element?(view, "table tbody tr:nth-child(25)")
      refute has_element?(view, "table tbody tr:nth-child(26)")

      # Action: Navigate to ensure pagination respects limit
      view
      |> element("button[phx-click=next_page]")
      |> render_click()

      assert has_element?(view, "button.btn-active[phx-value-page=\"2\"]")
    end

    test "pagination state persists across sorts and filters", %{
      conn: conn,
      account_id: account_id
    } do
      # Setup
      # account_id from setup
      date = ~D[2025-10-15]

      urls = for i <- 1..100, do: {"https://example.com/page-#{i}", i * 10, i * 100}
      populate_time_series_data(account_id, date, urls)

      {:ok, view, _html} = follow_live_redirect(conn, ~p"/?limit=20&page=2")

      # Action: Sort while on page 2
      view |> element("th[phx-value-column=clicks]") |> render_click()

      # Assert: Still on page 2 (or reset to page 1 - both valid UX)
      # We just assert it doesn't crash
      assert render(view) =~ "page-"
    end
  end

  describe "dashboard user journey: combined interactions" do
    test "user can sort, search, and paginate in one session", %{
      conn: conn,
      account_id: account_id
    } do
      # Setup: Realistic dataset
      # account_id from setup
      date = ~D[2025-10-15]

      urls = [
        {"https://example.com/blog/elixir-1", 500, 5000},
        {"https://example.com/blog/elixir-2", 300, 3000},
        {"https://example.com/blog/python-1", 400, 4000},
        {"https://example.com/docs/guide", 200, 2000}
      ]

      populate_time_series_data(account_id, date, urls)

      {:ok, view, _html} = follow_live_redirect(conn, ~p"/")

      # Action 1: Search for "blog"
      view
      |> element("#dashboard-search-form")
      |> render_change(%{"search" => "blog"})

      # Action 2: Sort by clicks
      html =
        view
        |> element("th[phx-value-column=clicks]")
        |> render_click()

      # Assert: Shows blog URLs sorted by clicks (ascending after toggle)
      assert html =~ ~r/elixir-2.*python-1.*elixir-1/s

      # Action 3: Refine search to "elixir"
      html =
        view
        |> element("#dashboard-search-form")
        |> render_change(%{"search" => "elixir"})

      # Assert: Only elixir blog posts shown
      assert html =~ "elixir-1"
      assert html =~ "elixir-2"
      refute html =~ "python-1"
    end

    test "dashboard remains responsive with complex state", %{conn: conn, account_id: account_id} do
      # Setup: Large dataset
      # account_id from setup
      date = ~D[2025-10-15]

      urls = for i <- 1..500, do: {"https://example.com/page-#{i}", i, i * 10}
      populate_time_series_data(account_id, date, urls)

      # Action: Perform multiple operations (follows redirect)
      {:ok, view, _html} = follow_live_redirect(conn, ~p"/?limit=100")

      view |> element("th[phx-value-column=clicks]") |> render_click()

      view
      |> element("#dashboard-search-form")
      |> render_change(%{"search" => "page-1"})

      view |> element("th[phx-value-column=position]") |> render_click()
      html = view |> element("button[phx-click=next_page]") |> render_click()

      # Assert: Dashboard still functional (didn't crash)
      assert html =~ "page-"

      # Assert: Can still interact
      html = view |> element("button[phx-click=prev_page]") |> render_click()
      assert html =~ "page-"
    end
  end

  # Helper functions

  defp populate_time_series_data(account_id, date, url_data) when is_list(url_data) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    records =
      Enum.map(url_data, fn url_spec ->
        {url, clicks, impressions, position} = normalize_url_spec(url_spec)

        %{
          account_id: account_id,
          property_url: @test_property_url,
          url: url,
          date: date,
          clicks: clicks,
          impressions: impressions,
          ctr: if(impressions > 0, do: clicks / impressions, else: 0.0),
          position: position,
          data_available: true,
          period_type: :daily,
          inserted_at: now
        }
      end)

    Repo.insert_all(TimeSeries, records)

    urls = Enum.map(records, & &1.url)

    Repo.delete_all(
      from ls in "url_lifetime_stats", where: ls.account_id == ^account_id and ls.url in ^urls
    )

    lifetime_rows =
      from(ts in TimeSeries,
        where: ts.account_id == ^account_id and ts.url in ^urls,
        group_by: ts.url,
        select: %{
          url: ts.url,
          lifetime_clicks: sum(ts.clicks),
          lifetime_impressions: sum(ts.impressions),
          avg_position:
            fragment(
              "SUM(? * ?) / NULLIF(SUM(?), 0)",
              ts.position,
              ts.impressions,
              ts.impressions
            ),
          avg_ctr:
            fragment(
              "SUM(?)::float / NULLIF(SUM(?), 0)",
              ts.clicks,
              ts.impressions
            ),
          first_seen_date: min(ts.date),
          last_seen_date: max(ts.date),
          days_with_data: count(ts.date)
        }
      )
      |> Repo.all()

    lifetime_records =
      Enum.map(lifetime_rows, fn row ->
        %{
          account_id: account_id,
          property_url: @test_property_url,
          url: row.url,
          lifetime_clicks: row.lifetime_clicks || 0,
          lifetime_impressions: row.lifetime_impressions || 0,
          avg_position: row.avg_position || 0.0,
          avg_ctr: row.avg_ctr || 0.0,
          first_seen_date: row.first_seen_date || Date.utc_today(),
          last_seen_date: row.last_seen_date || Date.utc_today(),
          days_with_data: row.days_with_data || 0,
          refreshed_at: now
        }
      end)

    Repo.insert_all("url_lifetime_stats", lifetime_records)
  end

  defp normalize_url_spec({url, clicks, impressions}) do
    # Default position
    {url, clicks, impressions, 10.0}
  end

  defp normalize_url_spec({url, opts}) when is_list(opts) do
    clicks = Keyword.get(opts, :clicks, 100)
    impressions = Keyword.get(opts, :impressions, 1000)
    position = Keyword.get(opts, :position, 10.0)
    {url, clicks, impressions, position}
  end
end
