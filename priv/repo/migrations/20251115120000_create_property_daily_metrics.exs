defmodule GscAnalytics.Repo.Migrations.CreatePropertyDailyMetrics do
  use Ecto.Migration

  def up do
    create table(:property_daily_metrics, primary_key: false) do
      add :account_id, :bigint, null: false
      add :property_url, :string, null: false
      add :date, :date, null: false

      add :clicks, :bigint, null: false, default: 0
      add :impressions, :bigint, null: false, default: 0
      add :ctr, :float, null: false, default: 0.0
      add :position, :float, null: false, default: 0.0
      add :urls_count, :integer, null: false, default: 0
      add :data_available, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:property_daily_metrics, [:account_id, :property_url, :date],
             name: :property_daily_metrics_account_property_date_index
           )

    create index(:property_daily_metrics, [:property_url, :date])
    create index(:property_daily_metrics, [:account_id, :date])

    execute("""
    INSERT INTO property_daily_metrics (
      account_id,
      property_url,
      date,
      clicks,
      impressions,
      ctr,
      position,
      urls_count,
      data_available,
      inserted_at,
      updated_at
    )
    SELECT
      account_id,
      property_url,
      date,
      SUM(clicks) AS clicks,
      SUM(impressions) AS impressions,
      CASE
        WHEN SUM(impressions) > 0
        THEN SUM(clicks)::DOUBLE PRECISION / SUM(impressions)
        ELSE 0.0
      END AS ctr,
      CASE
        WHEN SUM(impressions) > 0
        THEN SUM(position * impressions) / SUM(impressions)
        ELSE 0.0
      END AS position,
      COUNT(DISTINCT url) AS urls_count,
      BOOL_OR(data_available) AS data_available,
      NOW(),
      NOW()
    FROM gsc_time_series
    GROUP BY account_id, property_url, date
    """)
  end

  def down do
    drop table(:property_daily_metrics)
  end
end
