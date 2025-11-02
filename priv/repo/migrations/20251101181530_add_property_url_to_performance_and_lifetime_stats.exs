defmodule GscAnalytics.Repo.Migrations.AddPropertyUrlToPerformanceAndLifetimeStats do
  use Ecto.Migration

  def up do
    # 1. Add property_url to gsc_performance
    alter table(:gsc_performance) do
      add :property_url, :string, null: true
    end

    # Backfill gsc_performance property_url from workspace default_property
    execute """
    UPDATE gsc_performance p
    SET property_url = w.default_property
    FROM workspaces w
    WHERE p.account_id = w.id
      AND p.property_url IS NULL
    """

    # Make property_url NOT NULL
    alter table(:gsc_performance) do
      modify :property_url, :string, null: false
    end

    # Add index for property_url queries
    create index(:gsc_performance, [:property_url])
    create index(:gsc_performance, [:account_id, :property_url])

    # Update unique index to include property_url
    drop_if_exists unique_index(:gsc_performance, [:account_id, :url],
                     name: :gsc_performance_account_url_index
                   )

    create unique_index(:gsc_performance, [:account_id, :property_url, :url],
             name: :gsc_performance_account_property_url_index
           )

    # 2. Add property_url to url_lifetime_stats
    alter table(:url_lifetime_stats) do
      add :property_url, :string, null: true
    end

    # Backfill url_lifetime_stats property_url from workspace default_property
    execute """
    UPDATE url_lifetime_stats ls
    SET property_url = w.default_property
    FROM workspaces w
    WHERE ls.account_id = w.id
      AND ls.property_url IS NULL
    """

    # Make property_url NOT NULL
    alter table(:url_lifetime_stats) do
      modify :property_url, :string, null: false
    end

    # Drop old primary key
    execute "ALTER TABLE url_lifetime_stats DROP CONSTRAINT url_lifetime_stats_pkey"

    # Recreate primary key with property_url
    execute """
    ALTER TABLE url_lifetime_stats
    ADD CONSTRAINT url_lifetime_stats_pkey
    PRIMARY KEY (account_id, property_url, url)
    """

    # Add indexes for property_url queries
    create index(:url_lifetime_stats, [:property_url])
    create index(:url_lifetime_stats, [:account_id, :property_url])
  end

  def down do
    # Remove indexes from url_lifetime_stats
    drop_if_exists index(:url_lifetime_stats, [:account_id, :property_url])
    drop_if_exists index(:url_lifetime_stats, [:property_url])

    # Restore old primary key for url_lifetime_stats
    execute "ALTER TABLE url_lifetime_stats DROP CONSTRAINT url_lifetime_stats_pkey"

    execute """
    ALTER TABLE url_lifetime_stats
    ADD CONSTRAINT url_lifetime_stats_pkey
    PRIMARY KEY (account_id, url)
    """

    # Remove property_url column from url_lifetime_stats
    alter table(:url_lifetime_stats) do
      remove :property_url
    end

    # Remove indexes from gsc_performance
    drop_if_exists unique_index(:gsc_performance, [:account_id, :property_url, :url],
                     name: :gsc_performance_account_property_url_index
                   )

    drop_if_exists index(:gsc_performance, [:account_id, :property_url])
    drop_if_exists index(:gsc_performance, [:property_url])

    # Restore old unique index
    create unique_index(:gsc_performance, [:account_id, :url],
             name: :gsc_performance_account_url_index
           )

    # Remove property_url column from gsc_performance
    alter table(:gsc_performance) do
      remove :property_url
    end
  end
end
