defmodule GscAnalytics.Repo.Migrations.AddFaviconUrlToWorkspaceProperties do
  use Ecto.Migration

  def up do
    alter table(:workspace_properties) do
      add :favicon_url, :string
    end

    # Backfill favicon URLs for existing properties
    execute """
    UPDATE workspace_properties
    SET favicon_url = 'https://www.google.com/s2/favicons?domain=' ||
      CASE
        WHEN property_url LIKE 'sc-domain:%' THEN REPLACE(property_url, 'sc-domain:', '')
        ELSE SUBSTRING(property_url FROM 'https?://([^/]+)')
      END || '&sz=32'
    WHERE favicon_url IS NULL AND property_url IS NOT NULL
    """
  end

  def down do
    alter table(:workspace_properties) do
      remove :favicon_url
    end
  end
end
