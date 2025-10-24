defmodule GscAnalytics.Repo.Migrations.AddPerformanceIndexes do
  use Ecto.Migration

  def up do
    # Critical index for TimeSeries lookups (used in every query)
    create_if_not_exists index(:gsc_time_series, [:account_id, :url, :date],
                           name: :idx_time_series_lookup
                         )

    # Index for aggregation queries (speeds up SUM, AVG operations)
    create_if_not_exists index(
                           :gsc_time_series,
                           [:account_id, :url, :date, :clicks, :impressions],
                           name: :idx_time_series_aggregation
                         )

    # Index for date range queries
    create_if_not_exists index(:gsc_time_series, [:account_id, :date],
                           name: :idx_time_series_date_range
                         )

    # Critical index for Performance lookups
    create_if_not_exists index(:gsc_performance, [:account_id, :url],
                           name: :idx_performance_lookup
                         )

    # Index for dashboard queries (sorting by clicks/impressions)
    create_if_not_exists index(:gsc_performance, [:account_id, :clicks],
                           name: :idx_performance_clicks
                         )

    create_if_not_exists index(:gsc_performance, [:account_id, :impressions],
                           name: :idx_performance_impressions
                         )

    # Index for SyncDay tracking
    create_if_not_exists index(:gsc_sync_days, [:account_id, :site_url, :date, :status],
                           name: :idx_sync_day_status
                         )
  end

  def down do
    drop_if_exists index(:gsc_time_series, [:account_id, :url, :date],
                     name: :idx_time_series_lookup
                   )

    drop_if_exists index(:gsc_time_series, [:account_id, :url, :date, :clicks, :impressions],
                     name: :idx_time_series_aggregation
                   )

    drop_if_exists index(:gsc_time_series, [:account_id, :date],
                     name: :idx_time_series_date_range
                   )

    drop_if_exists index(:gsc_performance, [:account_id, :url], name: :idx_performance_lookup)
    drop_if_exists index(:gsc_performance, [:account_id, :clicks], name: :idx_performance_clicks)

    drop_if_exists index(:gsc_performance, [:account_id, :impressions],
                     name: :idx_performance_impressions
                   )

    drop_if_exists index(:gsc_sync_days, [:account_id, :site_url, :date, :status],
                     name: :idx_sync_day_status
                   )
  end
end
