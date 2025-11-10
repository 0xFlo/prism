defmodule GscAnalytics.Repo.Migrations.AddCompositeIndexForWowQuery do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    # Add composite index to optimize week-over-week growth query
    # This query is the slowest in the dashboard (2-3.5 seconds)
    # The index helps with:
    # 1. Filtering by account_id and property_url
    # 2. DATE_TRUNC('week', date) aggregations
    # 3. Sorting by url for window functions (lag)
    create_if_not_exists index(
                           :gsc_time_series,
                           [:account_id, :property_url, :date, :url],
                           name: :gsc_time_series_wow_query_idx,
                           concurrently: true
                         )
  end
end
