defmodule GscAnalytics.Repo.Migrations.AddPropertyAwareTimeSeriesIndexes do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute """
    CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_time_series_account_property_date
    ON gsc_time_series (account_id, property_url, date DESC, url)
    """

    execute """
    CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_time_series_account_property_date_available
    ON gsc_time_series (account_id, property_url, date DESC)
    INCLUDE (url, clicks, impressions, position)
    WHERE data_available = true
    """
  end

  def down do
    execute "DROP INDEX CONCURRENTLY IF EXISTS idx_time_series_account_property_date_available"
    execute "DROP INDEX CONCURRENTLY IF EXISTS idx_time_series_account_property_date"
  end
end
