defmodule GscAnalytics.ContentInsights.UrlPerformanceTest do
  use GscAnalytics.DataCase

  alias GscAnalytics.ContentInsights.UrlPerformance
  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.{Backlink, Performance, TimeSeries}

  @account_id 1

  setup do
    Repo.delete_all("url_lifetime_stats")

    today = Date.utc_today()

    Repo.insert_all("url_lifetime_stats", [
      %{
        account_id: @account_id,
        url: "https://example.com/a",
        lifetime_clicks: 120,
        lifetime_impressions: 1000,
        avg_position: 3.5,
        avg_ctr: 0.12,
        first_seen_date: Date.add(today, -300),
        last_seen_date: today,
        days_with_data: 300,
        refreshed_at: DateTime.utc_now()
      },
      %{
        account_id: @account_id,
        url: "https://example.com/b",
        lifetime_clicks: 80,
        lifetime_impressions: 600,
        avg_position: 5.0,
        avg_ctr: 0.1,
        first_seen_date: Date.add(today, -200),
        last_seen_date: today,
        days_with_data: 200,
        refreshed_at: DateTime.utc_now()
      }
    ])

    insert_time_series(@account_id, "https://example.com/a", Date.add(today, -5), %{
      clicks: 20,
      impressions: 150,
      ctr: 0.133,
      position: 3.0
    })

    insert_time_series(@account_id, "https://example.com/a", Date.add(today, -4), %{
      clicks: 15,
      impressions: 120,
      ctr: 0.125,
      position: 2.8
    })

    insert_time_series(@account_id, "https://example.com/b", Date.add(today, -4), %{
      clicks: 10,
      impressions: 90,
      ctr: 0.111,
      position: 4.5
    })

    # Performance records for HTTP status enrichment
    insert_performance(@account_id, "https://example.com/a", %{
      http_status: 200,
      redirect_url: nil,
      http_checked_at: DateTime.utc_now()
    })

    insert_performance(@account_id, "https://example.com/b", %{
      http_status: 301,
      redirect_url: "https://example.com/b/new",
      http_checked_at: DateTime.utc_now()
    })

    # Backlinks for enrichment
    insert_backlink(%{
      target_url: "https://example.com/a",
      source_url: "https://blog.example.com/post-1",
      data_source: "ahrefs",
      first_seen_at: DateTime.utc_now()
    })

    insert_backlink(%{
      target_url: "https://example.com/a",
      source_url: "https://blog.example.com/post-2",
      data_source: "ahrefs",
      first_seen_at: DateTime.utc_now()
    })

    insert_backlink(%{
      target_url: "https://example.com/b",
      source_url: "https://partner.example.com/feature",
      data_source: "vendor",
      first_seen_at: DateTime.utc_now()
    })

    :ok
  end

  test "list/1 returns enriched url data" do
    result = UrlPerformance.list(%{account_id: @account_id, limit: 10, page: 1, period_days: 30})

    assert result.total_count == 2
    assert result.total_pages == 1

    [first | rest] = result.urls
    assert first.url == "https://example.com/a"
    assert first.lifetime_clicks == 120
    assert first.period_clicks > 0
    assert first.backlink_count == 2
    assert first.http_status == 200

    second = Enum.find(rest, &(&1.url == "https://example.com/b"))
    assert second.backlink_count == 1
    assert second.http_status == 301
  end

  test "list/1 filters by search" do
    result =
      UrlPerformance.list(%{
        account_id: @account_id,
        limit: 10,
        page: 1,
        search: "example.com/b"
      })

    assert result.total_count == 1
    assert Enum.map(result.urls, & &1.url) == ["https://example.com/b"]
  end

  defp insert_time_series(account_id, url, date, attrs) do
    %TimeSeries{
      account_id: account_id,
      url: url,
      date: date,
      period_type: :daily,
      clicks: attrs[:clicks],
      impressions: attrs[:impressions],
      ctr: attrs[:ctr],
      position: attrs[:position],
      data_available: true
    }
    |> Repo.insert!()
  end

  defp insert_performance(account_id, url, attrs) do
    %Performance{}
    |> Performance.changeset(%{
      account_id: account_id,
      url: url,
      clicks: 0,
      impressions: 0,
      http_status: attrs[:http_status],
      redirect_url: attrs[:redirect_url],
      http_checked_at: attrs[:http_checked_at]
    })
    |> Repo.insert!()
  end

  defp insert_backlink(attrs) do
    %Backlink{}
    |> Backlink.changeset(%{
      target_url: attrs[:target_url],
      source_url: attrs[:source_url],
      data_source: attrs[:data_source],
      first_seen_at: attrs[:first_seen_at]
    })
    |> Repo.insert!()
  end
end
