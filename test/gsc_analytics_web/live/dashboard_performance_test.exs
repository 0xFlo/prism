defmodule GscAnalyticsWeb.DashboardLivePerformanceTest do
  use GscAnalyticsWeb.ConnCase

  @moduletag :performance

  import Phoenix.LiveViewTest

  alias GscAnalytics.ContentInsights
  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.{Performance, TimeSeries}
  alias GscAnalytics.Test.QueryCounter

  @account_id 1
  @url_count 250
  @days_of_history 14

  setup :register_and_log_in_user

  describe "ContentInsights query budget" do
    setup [:start_counters, :seed_dataset]

    test "list_urls executes within query budget" do
      QueryCounter.reset()

      result =
        ContentInsights.list_urls(%{
          account_id: @account_id,
          limit: 100,
          page: 1,
          sort_by: "clicks",
          sort_direction: "desc",
          period_days: 30
        })

      analysis = QueryCounter.analyze()

      assert result.total_count == @url_count
      assert length(result.urls) == 100
      assert analysis.total_count <= 6
      assert analysis.n_plus_one == []
    end
  end

  describe "Dashboard LiveView smoke test" do
    setup [:start_counters, :seed_dataset]

    test "initial render stays within limits", %{conn: conn} do
      QueryCounter.reset()

      {time_micros, {:ok, view, html}} =
        :timer.tc(fn -> live(conn, ~p"/dashboard?limit=100") end)

      assert html =~ "GSC Analytics Dashboard"
      assert has_element?(view, "table tbody tr")

      analysis = QueryCounter.analyze()
      # Dashboard loads: URLs list, site trends, summary stats - each with multiple queries
      assert analysis.total_count <= 20, "Expected ≤20 queries, got #{analysis.total_count}"
      assert analysis.n_plus_one == []

      time_ms = time_micros / 1000
      assert time_ms < 1_500
    end
  end

  defp start_counters(_context) do
    QueryCounter.start()
    on_exit(fn -> QueryCounter.stop() end)
    :ok
  end

  defp seed_dataset(_context) do
    seed_dataset(@url_count, @days_of_history)
    QueryCounter.reset()
    :ok
  end

  defp seed_dataset(url_count, days) do
    Repo.delete_all(TimeSeries)
    Repo.delete_all(Performance)
    Repo.delete_all("url_lifetime_stats")

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    today = Date.utc_today()

    {time_series_rows, performance_rows, lifetime_rows} =
      Enum.reduce(1..url_count, {[], [], []}, fn i, {ts_acc, perf_acc, lifetime_acc} ->
        url = "https://example.com/perf-#{i}"
        base_clicks = 40 + rem(i, 30)
        base_impressions = 400 + rem(i * 17, 600)

        daily_rows =
          for offset <- 0..(days - 1) do
            date = Date.add(today, -offset)
            clicks = max(1, base_clicks + rem(offset * i, 25))
            impressions = max(clicks + base_impressions, clicks)
            ctr = clicks / max(impressions, 1)
            position = Float.round(1.0 + rem(i + offset, 12) * 0.6, 2)

            %{
              account_id: @account_id,
              url: url,
              date: date,
              period_type: :daily,
              clicks: clicks,
              impressions: impressions,
              ctr: ctr,
              position: position,
              top_queries: [],
              data_available: true,
              inserted_at: now
            }
          end

        total_clicks = Enum.reduce(daily_rows, 0, fn %{clicks: c}, acc -> acc + c end)

        total_impressions =
          Enum.reduce(daily_rows, 0, fn %{impressions: imp}, acc -> acc + imp end)

        weighted_position =
          Enum.reduce(daily_rows, 0.0, fn %{position: pos, impressions: imp}, acc ->
            acc + pos * imp
          end)

        avg_position =
          if total_impressions > 0 do
            weighted_position / total_impressions
          else
            0.0
          end

        avg_ctr = if total_impressions > 0, do: total_clicks / total_impressions, else: 0.0

        perf_row = %{
          id: Ecto.UUID.generate(),
          account_id: @account_id,
          url: url,
          clicks: total_clicks,
          impressions: total_impressions,
          ctr: avg_ctr,
          position: avg_position,
          date_range_start: Date.add(today, -days + 1),
          date_range_end: today,
          data_available: true,
          fetched_at: now,
          cache_expires_at: DateTime.add(now, 86_400, :second),
          inserted_at: now,
          updated_at: now
        }

        lifetime_row = %{
          account_id: @account_id,
          url: url,
          lifetime_clicks: total_clicks,
          lifetime_impressions: total_impressions,
          avg_position: avg_position,
          avg_ctr: avg_ctr,
          first_seen_date: List.last(daily_rows).date,
          last_seen_date: hd(daily_rows).date,
          days_with_data: length(daily_rows),
          refreshed_at: now
        }

        {
          daily_rows ++ ts_acc,
          [perf_row | perf_acc],
          [lifetime_row | lifetime_acc]
        }
      end)

    time_series_rows
    |> Enum.chunk_every(500)
    |> Enum.each(&Repo.insert_all(TimeSeries, &1))

    performance_rows
    |> Enum.chunk_every(200)
    |> Enum.each(&Repo.insert_all(Performance, &1))

    lifetime_rows
    |> Enum.chunk_every(500)
    |> Enum.each(&Repo.insert_all("url_lifetime_stats", &1))
  end
end
