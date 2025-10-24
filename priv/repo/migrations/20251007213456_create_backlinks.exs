defmodule GscAnalytics.Repo.Migrations.CreateBacklinks do
  use Ecto.Migration

  def change do
    create table(:backlinks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Core backlink data
      add :target_url, :text, null: false, comment: "Scrapfly URL receiving the backlink"
      add :source_url, :text, null: false, comment: "Referring page URL containing the link"
      add :source_domain, :string, comment: "Domain extracted from source_url"
      add :anchor_text, :text, comment: "Link anchor text"
      add :first_seen_at, :utc_datetime, comment: "When link was first discovered/published"

      # External data provenance tracking
      # These fields mark this as MANUAL EXTERNAL DATA requiring human import
      add :data_source, :string,
        null: false,
        comment: "Source of backlink data: 'vendor', 'ahrefs', 'moz', etc. - EXTERNAL DATA"

      add :import_batch_id, :string,
        comment: "UUID tracking which import run created this record - MANUAL IMPORT"

      add :imported_at, :utc_datetime,
        comment: "When this data was manually imported (not automated sync) - MANUAL IMPORT"

      add :import_metadata, :map,
        comment: "JSON metadata: {file: 'report.csv', row: 123} - EXTERNAL SOURCE INFO"

      # Standard Ecto timestamps
      timestamps(type: :utc_datetime)
    end

    # Unique constraint: prevent duplicate backlinks
    create unique_index(:backlinks, [:source_url, :target_url],
             name: :backlinks_unique_link,
             comment: "Prevent duplicate backlinks from same source to same target"
           )

    # Performance indexes
    create index(:backlinks, [:target_url],
             comment: "Fast lookup of all backlinks pointing to a URL"
           )

    create index(:backlinks, [:data_source],
             comment: "Filter/group by data source (vendor vs ahrefs vs manual)"
           )

    create index(:backlinks, [:import_batch_id],
             comment: "Track all records from a specific import run"
           )

    create index(:backlinks, [:imported_at], comment: "Find stale data that needs refresh")
  end
end
