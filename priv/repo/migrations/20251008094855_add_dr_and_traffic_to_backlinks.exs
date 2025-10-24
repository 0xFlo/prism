defmodule GscAnalytics.Repo.Migrations.AddDrAndTrafficToBacklinks do
  use Ecto.Migration

  def change do
    alter table(:backlinks) do
      add :domain_rating, :integer,
        comment: "Domain Rating (DR) from Ahrefs - SEO metric for domain authority"

      add :domain_traffic, :integer,
        comment: "Estimated monthly organic traffic to the source domain (from Ahrefs)"
    end

    # Add index for filtering/sorting by DR
    create index(:backlinks, [:domain_rating],
             comment: "Filter/sort backlinks by domain authority"
           )
  end
end
