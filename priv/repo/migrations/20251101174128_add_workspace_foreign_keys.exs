defmodule GscAnalytics.Repo.Migrations.AddWorkspaceForeignKeys do
  use Ecto.Migration

  def up do
    # Add foreign key constraint for workspace_properties.workspace_id
    # This ensures properties are automatically deleted when a workspace is deleted
    execute """
    ALTER TABLE workspace_properties
    ADD CONSTRAINT workspace_properties_workspace_id_fkey
    FOREIGN KEY (workspace_id)
    REFERENCES workspaces(id)
    ON DELETE CASCADE
    """

    # Add foreign key constraint for oauth_tokens.account_id
    # This ensures OAuth tokens are automatically deleted when a workspace is deleted
    execute """
    ALTER TABLE oauth_tokens
    ADD CONSTRAINT oauth_tokens_account_id_fkey
    FOREIGN KEY (account_id)
    REFERENCES workspaces(id)
    ON DELETE CASCADE
    """
  end

  def down do
    # Remove foreign key constraints
    execute "ALTER TABLE workspace_properties DROP CONSTRAINT IF EXISTS workspace_properties_workspace_id_fkey"
    execute "ALTER TABLE oauth_tokens DROP CONSTRAINT IF EXISTS oauth_tokens_account_id_fkey"
  end
end
