defmodule GscAnalytics.Repo.Migrations.CreateOauthTokens do
  use Ecto.Migration

  def change do
    create table(:oauth_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :account_id, :integer, null: false
      add :google_email, :string, null: false
      add :refresh_token_encrypted, :binary, null: false
      add :access_token_encrypted, :binary
      add :expires_at, :utc_datetime
      add :scopes, {:array, :string}, default: []

      timestamps(type: :utc_datetime)
    end

    # One Google account per dashboard account
    create unique_index(:oauth_tokens, [:account_id])

    # Lookup by Google email for UI display
    create index(:oauth_tokens, [:google_email])
  end
end
