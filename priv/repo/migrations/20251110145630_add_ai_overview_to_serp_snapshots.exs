defmodule GscAnalytics.Repo.Migrations.AddAiOverviewToSerpSnapshots do
  use Ecto.Migration

  def change do
    alter table(:serp_snapshots) do
      # AI Overview data
      add :ai_overview_present, :boolean, default: false
      add :ai_overview_text, :text
      add :ai_overview_citations, {:array, :map}, default: []
    end

    # Add index for queries filtering by AI Overview presence
    create index(:serp_snapshots, [:account_id, :ai_overview_present])
  end
end
