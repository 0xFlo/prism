defmodule GscAnalytics.Repo.Migrations.AddOauthTokenStatus do
  use Ecto.Migration

  def up do
    # Create enum type for token status
    execute("""
    CREATE TYPE oauth_token_status AS ENUM ('valid', 'invalid', 'expired')
    """)

    alter table(:oauth_tokens) do
      add :status, :oauth_token_status, default: "valid", null: false
      add :last_error, :text
      add :last_validated_at, :utc_datetime_usec
    end

    # Set last_validated_at to inserted_at for existing records
    execute(
      "UPDATE oauth_tokens SET last_validated_at = inserted_at WHERE last_validated_at IS NULL"
    )
  end

  def down do
    alter table(:oauth_tokens) do
      remove :status
      remove :last_error
      remove :last_validated_at
    end

    execute("DROP TYPE oauth_token_status")
  end
end
