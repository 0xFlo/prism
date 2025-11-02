#!/usr/bin/env elixir
#
# populate_performance.exs - Aggregate time series data into performance summaries
#
# This script fixes the empty dashboard issue by creating performance records
# from existing time series data. Run with: mix run populate_performance.exs

alias GscAnalytics.Repo
alias GscAnalytics.GSC.Schemas.{TimeSeries, Performance}
alias GscAnalytics.DateTime, as: AppDateTime
import Ecto.Query

defmodule DataPopulator do
  @moduledoc """
  Populates the gsc_performance table by aggregating existing gsc_time_series data.
  """

  def populate_performance_data do
    IO.puts("🔄 Starting performance data population...")

    # Get count of existing records
    existing_count = Repo.aggregate(Performance, :count, :id)
    time_series_count = Repo.aggregate(TimeSeries, :count)

    IO.puts("📊 Current state:")
    IO.puts("   - Performance records: #{existing_count}")
    IO.puts("   - Time series records: #{time_series_count}")

    if time_series_count == 0 do
      IO.puts("❌ No time series data found. Run sync first.")
      {:error, :no_data}
    else
      # Clear existing performance data to avoid conflicts
      if existing_count > 0 do
        IO.puts("🗑️  Clearing existing performance records...")
        Repo.delete_all(Performance)
      end

      # Query time series data grouped by account_id, property, and URL
      IO.puts("📈 Aggregating time series data...")

      aggregated_data =
        from(ts in TimeSeries,
          where: ts.data_available == true,
          group_by: [ts.account_id, ts.property_url, ts.url],
          select: %{
            account_id: ts.account_id,
            property_url: ts.property_url,
            url: ts.url,
            total_clicks: sum(ts.clicks),
            total_impressions: sum(ts.impressions),
            avg_ctr: avg(ts.ctr),
            avg_position: avg(ts.position),
            min_date: min(ts.date),
            max_date: max(ts.date),
            data_available: true
          }
        )
        |> Repo.all()

      IO.puts("🎯 Found #{length(aggregated_data)} unique URLs to aggregate")

      # Create performance records
      now = AppDateTime.utc_now()

      performance_records =
        Enum.map(aggregated_data, fn data ->
          # Calculate CTR from totals (more accurate than averaging daily CTRs)
          calculated_ctr =
            if data.total_impressions > 0 do
              data.total_clicks / data.total_impressions
            else
              0.0
            end

          %{
            account_id: data.account_id,
            property_url: data.property_url,
            url: data.url,
            clicks: data.total_clicks,
            impressions: data.total_impressions,
            ctr: calculated_ctr,
            position: Float.round(data.avg_position || 0.0, 2),
            date_range_start: data.min_date,
            date_range_end: data.max_date,
            data_available: true,
            fetched_at: now,
            inserted_at: now,
            updated_at: now
          }
        end)

      # Batch insert performance records
      IO.puts("💾 Inserting #{length(performance_records)} performance records...")

      {inserted_count, _} = Repo.insert_all(Performance, performance_records)

      IO.puts("✅ Successfully populated #{inserted_count} performance records!")

      # Show some stats
      show_summary_stats()

      {:ok, inserted_count}
    end
  end

  defp show_summary_stats do
    IO.puts("\n📊 Performance Summary:")

    stats =
      from(p in Performance,
        where: p.data_available == true,
        select: %{
          total_urls: count(p.id),
          total_clicks: sum(p.clicks),
          total_impressions: sum(p.impressions),
          avg_position: avg(p.position)
        }
      )
      |> Repo.one()

    if stats.total_clicks && stats.total_impressions do
      avg_ctr = Float.round(stats.total_clicks / stats.total_impressions * 100, 2)

      IO.puts("   - Total URLs: #{stats.total_urls}")
      IO.puts("   - Total Clicks: #{stats.total_clicks}")
      IO.puts("   - Total Impressions: #{stats.total_impressions}")
      IO.puts("   - Average CTR: #{avg_ctr}%")
      IO.puts("   - Average Position: #{Float.round(stats.avg_position || 0.0, 2)}")
    end

    # Show top 5 performing URLs
    top_urls =
      from(p in Performance,
        where: p.data_available == true,
        order_by: [desc: p.clicks],
        limit: 5,
        select: %{url: p.url, clicks: p.clicks, impressions: p.impressions}
      )
      |> Repo.all()

    if length(top_urls) > 0 do
      IO.puts("\n🏆 Top 5 URLs by clicks:")

      Enum.each(top_urls, fn url_data ->
        truncated_url =
          if String.length(url_data.url) > 60 do
            String.slice(url_data.url, 0, 57) <> "..."
          else
            url_data.url
          end

        IO.puts(
          "   - #{url_data.clicks} clicks, #{url_data.impressions} impressions | #{truncated_url}"
        )
      end)
    end
  end
end

# Run the population
case DataPopulator.populate_performance_data() do
  {:ok, _count} ->
    IO.puts("\n🎉 Success! Dashboard should now show data.")
    IO.puts("   Visit: http://localhost:4000/dashboard")

  {:error, reason} ->
    IO.puts("\n❌ Failed: #{reason}")
    System.halt(1)
end
