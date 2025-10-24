defmodule GscAnalytics.Repo.Migrations.CreateGscPerformance do
  use Ecto.Migration

  def change do
    create table(:gsc_performance, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :account_id, :integer, null: false
      add :url, :string, null: false
      add :clicks, :integer, default: 0
      add :impressions, :integer, default: 0
      add :ctr, :float, default: 0.0
      add :position, :float, default: 0.0
      add :date_range_start, :date
      add :date_range_end, :date
      add :top_queries, {:array, :map}, default: []
      add :data_available, :boolean, default: false
      add :error_message, :string
      add :cache_expires_at, :utc_datetime
      add :fetched_at, :utc_datetime
      add :processing_time_ms, :integer

      timestamps(type: :utc_datetime)
    end

    create unique_index(:gsc_performance, [:account_id, :url],
             name: :gsc_performance_account_url_index
           )

    create index(:gsc_performance, [:data_available])
    create index(:gsc_performance, [:cache_expires_at])
    create index(:gsc_performance, [:clicks])
  end
end
