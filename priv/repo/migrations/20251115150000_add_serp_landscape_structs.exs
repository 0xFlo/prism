defmodule GscAnalytics.Repo.Migrations.AddSerpLandscapeStructs do
  use Ecto.Migration

  def change do
    create table(:serp_check_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :account_id, :integer, null: false
      add :property_url, :string, null: false
      add :url, :text, null: false
      add :status, :string, null: false, default: "pending"
      add :keyword_count, :integer, null: false, default: 0
      add :succeeded_count, :integer, null: false, default: 0
      add :failed_count, :integer, null: false, default: 0
      add :estimated_cost, :integer, null: false, default: 0
      add :last_error, :text
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:serp_check_runs, [:account_id, :property_url, :url])
    create index(:serp_check_runs, [:status])

    create table(:serp_check_run_keywords, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :serp_check_run_id,
          references(:serp_check_runs, type: :binary_id, on_delete: :delete_all),
          null: false

      add :keyword, :text, null: false
      add :geo, :string, null: false, default: "us"
      add :status, :string, null: false, default: "pending"
      add :error, :text
      add :completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:serp_check_run_keywords, [:serp_check_run_id])
    create index(:serp_check_run_keywords, [:status])

    alter table(:serp_snapshots) do
      add :serp_check_run_id, references(:serp_check_runs, type: :binary_id)
      add :content_types_present, {:array, :string}, default: []
      add :scrapfly_mentioned_in_ao, :boolean, default: false
      add :scrapfly_citation_position, :integer
    end

    create index(:serp_snapshots, [:account_id, :property_url, :url, :checked_at])
    create index(:serp_snapshots, [:ai_overview_present])
  end
end
