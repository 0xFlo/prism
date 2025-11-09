defmodule GscAnalytics.Repo.Migrations.CreateSerpSnapshots do
  use Ecto.Migration

  def change do
    create table(:serp_snapshots, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Multi-tenancy and property identification
      # Following existing pattern: account_id (integer) + property_url (string)
      add :account_id, :integer, null: false
      add :property_url, :string, null: false

      # URL being checked
      add :url, :string, null: false

      # SERP Data
      add :keyword, :string, null: false
      add :position, :integer
      add :serp_features, {:array, :string}, default: []
      add :competitors, {:array, :map}, default: []
      add :raw_response, :map

      # Metadata
      add :geo, :string, default: "us"
      add :checked_at, :utc_datetime, null: false
      add :api_cost, :decimal, precision: 10, scale: 2
      add :error_message, :text

      timestamps(type: :utc_datetime, updated_at: false)
    end

    # Indexes for query performance
    create index(:serp_snapshots, [:account_id, :property_url])
    create index(:serp_snapshots, [:property_url, :url, :keyword])
    create index(:serp_snapshots, [:checked_at])
    create index(:serp_snapshots, [:position])

    # Composite index for latest snapshot queries
    create index(:serp_snapshots, [:account_id, :property_url, :url, :keyword, :checked_at])
  end
end
