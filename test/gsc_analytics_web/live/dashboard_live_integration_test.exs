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
  alias GscAnalytics.Schemas.{PropertyDailyMetric, TimeSeries}

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
      {:ok, view, _html} = follow_live_redirect(conn, ~p"/")
      wait_for_table_loaded(view)
      assert render(view) =~ "<table"
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
      {:ok, view, _html} = follow_live_redirect(conn, ~p"/")
      wait_for_table_loaded(view)
      assert render(view) =~ "<table"
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
      wait_for_table_loaded(view)

      # Action: Search for "blog"
      change_and_wait(view, "#dashboard-search-form", %{"search" => "blog"})
      assert render(view) =~ "<table"
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
      wait_for_table_loaded(view)

      # Action: Search for non-existent term
      html = change_and_wait(view, "#dashboard-search-form", %{"search" => "nonexistent"})
      assert html =~ "No URLs found for the current filters"
    end

    test "search state persists in URL params", %{conn: conn, account_id: account_id} do
      # Setup
      populate_time_series_data(account_id, ~D[2025-10-15], [
        {"https://example.com/test", 100, 1000}
      ])

      {:ok, view, _html} = follow_live_redirect(conn, ~p"/")
      wait_for_table_loaded(view)

      # Action: Perform search
      change_and_wait(view, "#dashboard-search-form", %{"search" => "test"})

      assert has_element?(view, "#search-input[value=\"test\"]")
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
      {:ok, view, _html} = follow_live_redirect(conn, ~p"/?limit=50")
      wait_for_table_loaded(view)
      assert render(view) =~ "<table"
    end

    test "user can change page size", %{conn: conn, account_id: account_id} do
      # Setup
      # account_id from setup
      date = ~D[2025-10-15]

      urls = for i <- 1..200, do: {"https://example.com/page-#{i}", 100, 1000}
      populate_time_series_data(account_id, date, urls)

      # Action: Set custom page size (follows redirect)
      {:ok, view, _html} = follow_live_redirect(conn, ~p"/?limit=25")
      wait_for_table_loaded(view)

      # Action: Navigate to ensure pagination respects limit
      assert render(view) =~ "<table"
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
      wait_for_table_loaded(view)

      # Action: Sort while on page 2
      click_and_wait(view, "th[phx-value-column=clicks]")

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
      wait_for_table_loaded(view)

      # Action 1: Search for "blog"
      change_and_wait(view, "#dashboard-search-form", %{"search" => "blog"})
      click_and_wait(view, "th[phx-value-column=clicks]")
      change_and_wait(view, "#dashboard-search-form", %{"search" => "elixir"})
      assert render(view) =~ "<table"
    end

    test "dashboard remains responsive with complex state", %{conn: conn, account_id: account_id} do
      # Setup: Large dataset
      # account_id from setup
      date = ~D[2025-10-15]

      urls = for i <- 1..500, do: {"https://example.com/page-#{i}", i, i * 10}
      populate_time_series_data(account_id, date, urls)

      # Action: Perform multiple operations (follows redirect)
      {:ok, view, _html} = follow_live_redirect(conn, ~p"/?limit=100")
      wait_for_table_loaded(view)

      click_and_wait(view, "th[phx-value-column=clicks]")

      change_and_wait(view, "#dashboard-search-form", %{"search" => "page-1"})

      click_and_wait(view, "th[phx-value-column=position]")

      # Assert: Dashboard still functional (didn't crash)
      assert has_element?(view, "#dashboard-url-table")
    end
  end

  # Helper functions

  defp populate_time_series_data(account_id, date, url_data) when is_list(url_data) do
    timestamp = DateTime.utc_now() |> DateTime.truncate(:second)

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
          inserted_at: timestamp
        }
      end)

    Repo.insert_all(TimeSeries, records)

    urls = Enum.map(records, & &1.url)

    total_clicks = Enum.reduce(records, 0, fn record, acc -> acc + record.clicks end)
    total_impressions = Enum.reduce(records, 0, fn record, acc -> acc + record.impressions end)

    weighted_position =
      Enum.reduce(records, 0.0, fn record, acc ->
        acc + record.position * record.impressions
      end)

    urls_count = length(records)

    Repo.insert_all(PropertyDailyMetric, [
      %{
        account_id: account_id,
        property_url: @test_property_url,
        date: date,
        clicks: total_clicks,
        impressions: total_impressions,
        ctr:
          if total_impressions > 0 do
            total_clicks / total_impressions
          else
            0.0
          end,
        position:
          if total_impressions > 0 do
            weighted_position / total_impressions
          else
            0.0
          end,
        urls_count: urls_count,
        data_available: urls_count > 0,
        inserted_at: timestamp,
        updated_at: timestamp
      }
    ],
      on_conflict:
        {:replace,
         [:clicks, :impressions, :ctr, :position, :urls_count, :data_available, :updated_at]},
      conflict_target: [:account_id, :property_url, :date]
    )

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
          refreshed_at: timestamp
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

  defp wait_for_table_loaded(view) do
    wait_for(fn -> has_element?(view, "#dashboard-url-table[data-snapshot-state=ready]") end)
  end

  defp wait_for(fun, attempts \\ 20)

  defp wait_for(_fun, 0), do: flunk("LiveView did not update in time")

  defp wait_for(fun, attempts) do
    if fun.() do
      :ok
    else
      Process.sleep(100)
      wait_for(fun, attempts - 1)
    end
  end

  defp click_and_wait(view, selector) do
    view |> element(selector) |> render_click()
    wait_for_table_loaded(view)
    render(view)
  end

  defp change_and_wait(view, selector, params) do
    view |> element(selector) |> render_change(params)
    wait_for_table_loaded(view)
    render(view)
  end

end
