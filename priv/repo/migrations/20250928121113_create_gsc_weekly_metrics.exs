defmodule GscAnalytics.Repo.Migrations.CreateGscWeeklyMetrics do
  use Ecto.Migration

  def change do
    create table(:gsc_weekly_metrics, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :account_id, :integer, null: false
      add :url, :string, null: false
      add :week_number, :integer, null: false
      add :week_start, :date, null: false
      add :clicks, :integer, default: 0
      add :impressions, :integer, default: 0
      add :ctr, :float, default: 0.0
      add :position, :float, default: 0.0
      add :data_available, :boolean, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:gsc_weekly_metrics, [:account_id, :url, :week_start])
    create index(:gsc_weekly_metrics, [:account_id])
    create index(:gsc_weekly_metrics, [:url])
    create index(:gsc_weekly_metrics, [:week_number])
    create index(:gsc_weekly_metrics, [:week_start])
  end
end
