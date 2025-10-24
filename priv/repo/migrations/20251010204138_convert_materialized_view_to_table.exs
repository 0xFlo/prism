defmodule GscAnalytics.Repo.Migrations.ConvertMaterializedViewToTable do
  use Ecto.Migration

  def up do
    # Drop the materialized view and its indexes
    execute "DROP MATERIALIZED VIEW IF EXISTS url_lifetime_stats CASCADE"

    # Create a regular table with the same structure
    execute """
    CREATE TABLE url_lifetime_stats (
      account_id INTEGER NOT NULL,
      url TEXT NOT NULL,
      lifetime_clicks BIGINT DEFAULT 0,
      lifetime_impressions BIGINT DEFAULT 0,
      avg_position DOUBLE PRECISION DEFAULT 0.0,
      avg_ctr DOUBLE PRECISION DEFAULT 0.0,
      first_seen_date DATE,
      last_seen_date DATE,
      days_with_data INTEGER DEFAULT 0,
      refreshed_at TIMESTAMP WITHOUT TIME ZONE DEFAULT NOW(),

      PRIMARY KEY (account_id, url)
    )
    """

    # Recreate the indexes
    execute """
    CREATE INDEX idx_lifetime_stats_clicks
    ON url_lifetime_stats(lifetime_clicks DESC)
    """

    execute """
    CREATE INDEX idx_lifetime_stats_impressions
    ON url_lifetime_stats(lifetime_impressions DESC)
    """

    # Create trigram index for URL search if pg_trgm exists
    execute """
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_trgm') THEN
        EXECUTE 'CREATE INDEX idx_lifetime_stats_url_search ON url_lifetime_stats USING gin(url gin_trgm_ops)';
      END IF;
    END $$;
    """

    # Index for filtering by account_id
    execute """
    CREATE INDEX idx_lifetime_stats_account
    ON url_lifetime_stats(account_id)
    """

    # Populate the table with initial data
    execute """
    INSERT INTO url_lifetime_stats (
      account_id, url,
      lifetime_clicks, lifetime_impressions,
      avg_position, avg_ctr,
      first_seen_date, last_seen_date,
      days_with_data, refreshed_at
    )
    SELECT
      account_id,
      url,
      SUM(clicks) as lifetime_clicks,
      SUM(impressions) as lifetime_impressions,

      CASE
        WHEN SUM(impressions) > 0
        THEN SUM(position * impressions) / SUM(impressions)
        ELSE 0.0
      END as avg_position,

      CASE
        WHEN SUM(impressions) > 0
        THEN SUM(clicks)::DOUBLE PRECISION / SUM(impressions)
        ELSE 0.0
      END as avg_ctr,

      MIN(date) as first_seen_date,
      MAX(date) as last_seen_date,
      COUNT(DISTINCT date) as days_with_data,
      NOW() as refreshed_at

    FROM gsc_time_series
    WHERE data_available = true
    GROUP BY account_id, url
    """
  end

  def down do
    # Drop the table
    execute "DROP TABLE IF EXISTS url_lifetime_stats CASCADE"

    # Recreate the materialized view
    execute """
    CREATE MATERIALIZED VIEW url_lifetime_stats AS
    SELECT
      account_id,
      url,
      SUM(clicks) as lifetime_clicks,
      SUM(impressions) as lifetime_impressions,
      CASE
        WHEN SUM(impressions) > 0
        THEN SUM(position * impressions) / SUM(impressions)
        ELSE 0.0
      END as avg_position,
      CASE
        WHEN SUM(impressions) > 0
        THEN SUM(clicks)::DOUBLE PRECISION / SUM(impressions)
        ELSE 0.0
      END as avg_ctr,
      MIN(date) as first_seen_date,
      MAX(date) as last_seen_date,
      COUNT(DISTINCT date) as days_with_data,
      NOW() as refreshed_at
    FROM gsc_time_series
    WHERE data_available = true
    GROUP BY account_id, url
    """

    # Recreate indexes
    execute "CREATE UNIQUE INDEX idx_lifetime_stats_pk ON url_lifetime_stats(account_id, url)"
    execute "CREATE INDEX idx_lifetime_stats_clicks ON url_lifetime_stats(lifetime_clicks DESC)"

    execute "CREATE INDEX idx_lifetime_stats_impressions ON url_lifetime_stats(lifetime_impressions DESC)"

    execute """
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_trgm') THEN
        EXECUTE 'CREATE INDEX idx_lifetime_stats_url_search ON url_lifetime_stats USING gin(url gin_trgm_ops)';
      END IF;
    END $$;
    """
  end
end
