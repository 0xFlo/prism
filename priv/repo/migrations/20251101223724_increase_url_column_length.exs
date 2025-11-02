defmodule GscAnalytics.Repo.Migrations.IncreaseUrlColumnLength do
  @moduledoc """
  Increases the URL column length from varchar(255) to varchar(2048) in all GSC tables.

  This fixes the "value too long for type character varying(255)" error that occurs
  when syncing URLs with long query parameters from Google Search Console.

  Affected tables:
  - gsc_time_series (primary key column - needs constraint recreation)
  - gsc_performance
  - gsc_url_metadata
  - gsc_weekly_metrics

  Note: url_lifetime_stats already uses TEXT type and doesn't need modification.
  """
  use Ecto.Migration

  def up do
    # 1. gsc_time_series (URL is part of composite primary key)
    # Must drop and recreate the primary key constraint
    execute "ALTER TABLE gsc_time_series DROP CONSTRAINT gsc_time_series_pkey"

    execute """
    ALTER TABLE gsc_time_series
    ALTER COLUMN url TYPE varchar(2048)
    """

    execute """
    ALTER TABLE gsc_time_series
    ADD CONSTRAINT gsc_time_series_pkey
    PRIMARY KEY (account_id, property_url, url, date)
    """

    # 2. gsc_performance (regular URL column)
    execute """
    ALTER TABLE gsc_performance
    ALTER COLUMN url TYPE varchar(2048)
    """

    # 3. gsc_url_metadata (regular URL column)
    execute """
    ALTER TABLE gsc_url_metadata
    ALTER COLUMN url TYPE varchar(2048)
    """

    # 4. gsc_weekly_metrics (regular URL column)
    execute """
    ALTER TABLE gsc_weekly_metrics
    ALTER COLUMN url TYPE varchar(2048)
    """
  end

  def down do
    # WARNING: Downgrading may fail if any URLs exceed 255 characters
    # In that case, you'll need to manually truncate or delete those rows first

    # 1. gsc_time_series
    execute "ALTER TABLE gsc_time_series DROP CONSTRAINT gsc_time_series_pkey"

    execute """
    ALTER TABLE gsc_time_series
    ALTER COLUMN url TYPE varchar(255)
    """

    execute """
    ALTER TABLE gsc_time_series
    ADD CONSTRAINT gsc_time_series_pkey
    PRIMARY KEY (account_id, property_url, url, date)
    """

    # 2. gsc_performance
    execute """
    ALTER TABLE gsc_performance
    ALTER COLUMN url TYPE varchar(255)
    """

    # 3. gsc_url_metadata
    execute """
    ALTER TABLE gsc_url_metadata
    ALTER COLUMN url TYPE varchar(255)
    """

    # 4. gsc_weekly_metrics
    execute """
    ALTER TABLE gsc_weekly_metrics
    ALTER COLUMN url TYPE varchar(255)
    """
  end
end
