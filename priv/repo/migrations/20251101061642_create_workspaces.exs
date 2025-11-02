defmodule GscAnalytics.Repo.Migrations.CreateWorkspaces do
  use Ecto.Migration

  def change do
    create table(:workspaces, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string
      add :google_account_email, :string, null: false
      add :default_property, :string
      add :enabled, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:workspaces, [:user_id])
    create unique_index(:workspaces, [:user_id, :google_account_email])
  end
end
