defmodule GscAnalytics.Repo.Migrations.AddAccountDateIndexes do
  use Ecto.Migration

  def change do
    create_if_not_exists index(:gsc_time_series, [:account_id, :date])
    create_if_not_exists index(:gsc_performance, [:account_id, :fetched_at])
  end
end
