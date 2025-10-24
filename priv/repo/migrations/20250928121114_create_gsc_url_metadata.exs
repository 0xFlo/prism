defmodule GscAnalytics.Repo.Migrations.CreateGscUrlMetadata do
  use Ecto.Migration

  def change do
    create table(:gsc_url_metadata, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :account_id, :integer, null: false
      add :url, :string, null: false
      # "posts", "blog", "docs", "api", "homepage", "pages"
      add :url_type, :string
      # "Fresh", "Recent", "Aging", "Stale"
      add :content_category, :string
      add :publish_date, :date
      add :last_update_date, :date
      add :title, :string
      add :meta_description, :string
      add :word_count, :integer
      add :internal_links_count, :integer
      add :external_links_count, :integer
      add :last_crawled_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:gsc_url_metadata, [:account_id, :url])
    create index(:gsc_url_metadata, [:account_id])
    create index(:gsc_url_metadata, [:url])
    create index(:gsc_url_metadata, [:url_type])
    create index(:gsc_url_metadata, [:content_category])
    create index(:gsc_url_metadata, [:publish_date])
    create index(:gsc_url_metadata, [:last_update_date])
  end
end
