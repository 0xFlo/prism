defmodule GscAnalytics.Repo.Migrations.CreateUrlLifetimeStats do
  use Ecto.Migration

  def up do
    # Create the materialized view for lifetime statistics
    execute """
    CREATE MATERIALIZED VIEW url_lifetime_stats AS
    SELECT
      account_id,
      url,

      -- Lifetime totals
      SUM(clicks) as lifetime_clicks,
      SUM(impressions) as lifetime_impressions,

      -- Weighted average position (weighted by impressions for accuracy)
      -- This gives more weight to positions with more impressions
      CASE
        WHEN SUM(impressions) > 0
        THEN SUM(position * impressions) / SUM(impressions)
        ELSE 0.0
      END as avg_position,

      -- Average CTR
      CASE
        WHEN SUM(impressions) > 0
        THEN SUM(clicks)::DOUBLE PRECISION / SUM(impressions)
        ELSE 0.0
      END as avg_ctr,

      -- Temporal bounds
      MIN(date) as first_seen_date,
      MAX(date) as last_seen_date,
      COUNT(DISTINCT date) as days_with_data,

      -- Metadata
      NOW() as refreshed_at

    FROM gsc_time_series
    WHERE data_available = true
    GROUP BY account_id, url
    """

    # Create unique index for primary key behavior
    execute """
    CREATE UNIQUE INDEX idx_lifetime_stats_pk
    ON url_lifetime_stats(account_id, url)
    """

    # Create index for sorting by clicks (most common sort)
    execute """
    CREATE INDEX idx_lifetime_stats_clicks
    ON url_lifetime_stats(lifetime_clicks DESC)
    """

    # Create index for sorting by impressions
    execute """
    CREATE INDEX idx_lifetime_stats_impressions
    ON url_lifetime_stats(lifetime_impressions DESC)
    """

    # Create trigram index for URL pattern searching (if pg_trgm extension exists)
    execute """
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_trgm') THEN
        EXECUTE 'CREATE INDEX idx_lifetime_stats_url_search ON url_lifetime_stats USING gin(url gin_trgm_ops)';
      END IF;
    END $$;
    """

    # Create additional performance indexes on time_series if they don't exist
    # These will speed up period aggregations
    execute """
    CREATE INDEX IF NOT EXISTS idx_ts_period_agg
    ON gsc_time_series(account_id, date DESC)
    INCLUDE (url, clicks, impressions, position)
    WHERE data_available = true
    """

    execute """
    CREATE INDEX IF NOT EXISTS idx_ts_site_trends
    ON gsc_time_series(account_id, date)
    INCLUDE (clicks, impressions, position)
    WHERE data_available = true
    """

    # Initial population of the materialized view
    execute "REFRESH MATERIALIZED VIEW url_lifetime_stats"
  end

  def down do
    # Drop the indexes first
    execute "DROP INDEX IF EXISTS idx_lifetime_stats_pk"
    execute "DROP INDEX IF EXISTS idx_lifetime_stats_clicks"
    execute "DROP INDEX IF EXISTS idx_lifetime_stats_impressions"
    execute "DROP INDEX IF EXISTS idx_lifetime_stats_url_search"

    # Drop the new TimeSeries indexes
    execute "DROP INDEX IF EXISTS idx_ts_period_agg"
    execute "DROP INDEX IF EXISTS idx_ts_site_trends"

    # Drop the materialized view
    execute "DROP MATERIALIZED VIEW IF EXISTS url_lifetime_stats"
  end
end
