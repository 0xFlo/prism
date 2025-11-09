defmodule GscAnalytics.Repo.Migrations.AddHttpStatusToUrlLifetimeStats do
  use Ecto.Migration

  def change do
    alter table(:url_lifetime_stats) do
      # HTTP Status Crawler fields
      add :http_status, :integer
      add :redirect_url, :text
      add :http_checked_at, :utc_datetime
      add :http_redirect_chain, :map
    end

    # Add indexes for efficient filtering
    create index(:url_lifetime_stats, [:http_status])
    create index(:url_lifetime_stats, [:http_checked_at])

    # Partial index for broken links (4xx/5xx)
    create index(:url_lifetime_stats, [:account_id, :property_url, :http_status],
      where: "http_status >= 400",
      name: :idx_lifetime_stats_broken_links
    )

    # Partial index for redirects
    create index(:url_lifetime_stats, [:account_id, :property_url, :http_status],
      where: "http_status IN (301, 302, 307, 308)",
      name: :idx_lifetime_stats_redirects
    )

    # Partial index for URLs never checked
    create index(:url_lifetime_stats, [:account_id, :property_url],
      where: "http_checked_at IS NULL",
      name: :idx_lifetime_stats_not_checked
    )
  end
end