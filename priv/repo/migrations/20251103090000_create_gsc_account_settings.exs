defmodule GscAnalytics.Repo.Migrations.CreateGscAccountSettings do
  use Ecto.Migration

  def change do
    create table(:gsc_account_settings) do
      add :account_id, :integer, null: false
      add :display_name, :string
      add :default_property, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:gsc_account_settings, [:account_id])
  end
end
