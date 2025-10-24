defmodule GscAnalytics.Repo.Migrations.CreateGscSyncDays do
  use Ecto.Migration

  def change do
    create table(:gsc_sync_days, primary_key: false) do
      add :account_id, :integer, null: false
      add :site_url, :string, null: false
      add :date, :date, null: false
      add :status, :string, null: false
      add :url_count, :integer, null: false, default: 0
      add :last_synced_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:gsc_sync_days, [:account_id, :site_url, :date])

    execute(
      "ALTER TABLE gsc_sync_days ADD CONSTRAINT gsc_sync_days_status_check CHECK (status IN ('pending', 'running', 'complete', 'failed', 'skipped'))"
    )
  end
end
