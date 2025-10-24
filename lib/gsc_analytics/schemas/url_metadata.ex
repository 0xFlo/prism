defmodule GscAnalytics.Schemas.UrlMetadata do
  @moduledoc """
  Schema for URL metadata including content age, type, and update tracking.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "gsc_url_metadata" do
    field :account_id, :integer
    field :url, :string
    # posts, pages, docs, homepage
    field :url_type, :string
    field :publish_date, :date
    field :last_update_date, :date
    # Fresh, Recent, Aging, Stale
    field :content_category, :string
    field :needs_update, :boolean, default: false
    field :update_reason, :string
    # P1, P2, P3
    field :update_priority, :string
    field :title, :string
    field :meta_description, :string
    field :word_count, :integer
    field :internal_links_count, :integer
    field :external_links_count, :integer
    field :last_crawled_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @required_fields [:account_id, :url]
  @optional_fields [
    :url_type,
    :publish_date,
    :last_update_date,
    :content_category,
    :needs_update,
    :update_reason,
    :update_priority,
    :title,
    :meta_description,
    :word_count,
    :internal_links_count,
    :external_links_count,
    :last_crawled_at
  ]

  def changeset(metadata, attrs) do
    metadata
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> determine_url_type()
    |> calculate_content_category()
    |> unique_constraint([:account_id, :url])
  end

  # Determine URL type from path patterns
  defp determine_url_type(changeset) do
    case get_change(changeset, :url) do
      nil ->
        changeset

      url ->
        type =
          cond do
            String.contains?(url, "/blog/posts/") -> "posts"
            String.contains?(url, "/blog/") -> "blog"
            String.contains?(url, "/docs/") -> "docs"
            String.contains?(url, "/api/") -> "api"
            String.ends_with?(url, "/") && String.length(URI.parse(url).path) <= 1 -> "homepage"
            true -> "pages"
          end

        put_change(changeset, :url_type, type)
    end
  end

  # Calculate content category based on age
  defp calculate_content_category(changeset) do
    case get_change(changeset, :last_update_date) || get_change(changeset, :publish_date) do
      nil ->
        changeset

      date ->
        days_old = Date.diff(Date.utc_today(), date)

        category =
          cond do
            days_old <= 30 -> "Fresh"
            days_old <= 90 -> "Recent"
            days_old <= 180 -> "Aging"
            true -> "Stale"
          end

        put_change(changeset, :content_category, category)
    end
  end

  # Query helpers
  def needs_update(query \\ __MODULE__) do
    from m in query, where: m.needs_update == true
  end

  def by_priority(query \\ __MODULE__, priority) do
    from m in query, where: m.update_priority == ^priority
  end

  def by_type(query \\ __MODULE__, type) do
    from m in query, where: m.url_type == ^type
  end

  def aging_content(query \\ __MODULE__) do
    from m in query, where: m.content_category in ["Aging", "Stale"]
  end
end
