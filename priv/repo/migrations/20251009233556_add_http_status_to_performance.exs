defmodule GscAnalytics.Repo.Migrations.AddHttpStatusToPerformance do
  use Ecto.Migration

  def change do
    alter table(:gsc_performance) do
      add :http_status, :integer
      add :redirect_url, :text
      add :http_checked_at, :utc_datetime
      add :http_redirect_chain, :map
    end

    create index(:gsc_performance, [:http_status])
    create index(:gsc_performance, [:http_checked_at])
  end
end
