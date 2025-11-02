defmodule GscAnalytics.Repo.Migrations.RemoveSingleActivePropertyConstraint do
  use Ecto.Migration

  def up do
    # Drop the constraint that prevents multiple active properties per workspace
    # This allows users to have multiple properties active simultaneously
    drop_if_exists index(:workspace_properties, [:workspace_id],
                     name: :workspace_properties_single_active
                   )
  end

  def down do
    # Recreate the constraint if rolling back
    # Note: This will fail if multiple active properties exist
    create unique_index(:workspace_properties, [:workspace_id],
             where: "is_active = true",
             name: :workspace_properties_single_active
           )
  end
end
