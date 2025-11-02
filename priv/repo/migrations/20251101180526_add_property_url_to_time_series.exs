defmodule GscAnalytics.Repo.Migrations.AddPropertyUrlToTimeSeries do
  use Ecto.Migration

  def up do
    # Add property_url column to gsc_time_series table
    alter table(:gsc_time_series) do
      add :property_url, :string, null: true
    end

    # Backfill property_url from workspace default_property
    # For existing records, set property_url to the workspace's default_property
    execute """
    UPDATE gsc_time_series ts
    SET property_url = w.default_property
    FROM workspaces w
    WHERE ts.account_id = w.id
      AND ts.property_url IS NULL
    """

    # Make property_url NOT NULL after backfill
    alter table(:gsc_time_series) do
      modify :property_url, :string, null: false
    end

    # Drop the old primary key constraint
    execute "ALTER TABLE gsc_time_series DROP CONSTRAINT gsc_time_series_pkey"

    # Recreate primary key with property_url included
    execute """
    ALTER TABLE gsc_time_series
    ADD CONSTRAINT gsc_time_series_pkey
    PRIMARY KEY (account_id, property_url, url, date)
    """

    # Add index for property_url queries
    create index(:gsc_time_series, [:property_url])
    create index(:gsc_time_series, [:account_id, :property_url])
  end

  def down do
    # Remove indexes
    drop_if_exists index(:gsc_time_series, [:account_id, :property_url])
    drop_if_exists index(:gsc_time_series, [:property_url])

    # Drop the new primary key
    execute "ALTER TABLE gsc_time_series DROP CONSTRAINT gsc_time_series_pkey"

    # Recreate old primary key without property_url
    execute """
    ALTER TABLE gsc_time_series
    ADD CONSTRAINT gsc_time_series_pkey
    PRIMARY KEY (account_id, url, date)
    """

    # Remove property_url column
    alter table(:gsc_time_series) do
      remove :property_url
    end
  end
end
