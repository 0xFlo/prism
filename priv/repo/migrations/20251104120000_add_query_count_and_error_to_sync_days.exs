defmodule GscAnalytics.Repo.Migrations.AddQueryCountAndErrorToSyncDays do
  use Ecto.Migration

  def change do
    alter table(:gsc_sync_days) do
      add :query_count, :integer, default: 0, null: false
      add :error, :text
    end
  end
end
