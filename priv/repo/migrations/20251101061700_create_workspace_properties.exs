defmodule GscAnalytics.Repo.Migrations.CreateWorkspaceProperties do
  use Ecto.Migration

  def up do
    create table(:workspace_properties, primary_key: false) do
      add :id, :uuid,
        primary_key: true,
        null: false,
        default: fragment("md5(random()::text || clock_timestamp()::text)::uuid")

      add :workspace_id, :integer, null: false
      add :property_url, :string, null: false
      add :display_name, :string
      add :is_active, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    # Unique constraint: one workspace cannot have duplicate property URLs
    create unique_index(:workspace_properties, [:workspace_id, :property_url],
             name: :workspace_properties_workspace_property_unique
           )

    # Partial unique index: only one active property per workspace
    # PostgreSQL partial unique index ensures single active property
    create unique_index(:workspace_properties, [:workspace_id],
             where: "is_active = true",
             name: :workspace_properties_single_active
           )

    # Performance index for queries filtering by workspace
    create index(:workspace_properties, [:workspace_id])

    # Performance index for finding active properties
    create index(:workspace_properties, [:workspace_id, :is_active])
  end

  def down do
    drop table(:workspace_properties)
  end
end
