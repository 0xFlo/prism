defmodule GscAnalytics.Repo.Migrations.CreateGscTimeSeries do
  use Ecto.Migration

  def change do
    create table(:gsc_time_series, primary_key: false) do
      add :account_id, :integer, primary_key: true, null: false
      add :url, :string, primary_key: true, null: false
      add :date, :date, primary_key: true, null: false

      add :period_type, :string, default: "daily", null: false
      add :clicks, :integer, default: 0
      add :impressions, :integer, default: 0
      add :ctr, :float, default: 0.0
      add :position, :float, default: 0.0
      add :top_queries, {:array, :map}, default: []
      add :data_available, :boolean, default: false
      add :performance_id, :binary_id

      add :inserted_at, :utc_datetime, null: false
    end

    create index(:gsc_time_series, [:account_id])
    create index(:gsc_time_series, [:url])
    create index(:gsc_time_series, [:date])
    create index(:gsc_time_series, [:data_available])
    create index(:gsc_time_series, [:performance_id])

    # Ensure valid period types
    create constraint(:gsc_time_series, :valid_period_type,
             check: "period_type IN ('daily', 'weekly', 'monthly')"
           )
  end
end
