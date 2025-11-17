defmodule GscAnalytics.Repo.Migrations.ConvertPropertyDailyMetricsTimestampsToUtc do
  use Ecto.Migration

  def up do
    alter table(:property_daily_metrics) do
      modify :inserted_at, :utc_datetime, from: :naive_datetime_usec, null: false
      modify :updated_at, :utc_datetime, from: :naive_datetime_usec, null: false
    end
  end

  def down do
    alter table(:property_daily_metrics) do
      modify :inserted_at, :naive_datetime_usec, from: :utc_datetime, null: false
      modify :updated_at, :naive_datetime_usec, from: :utc_datetime, null: false
    end
  end
end
