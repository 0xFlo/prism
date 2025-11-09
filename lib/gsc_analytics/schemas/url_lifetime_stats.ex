defmodule GscAnalytics.Schemas.UrlLifetimeStats do
  @moduledoc """
  Ecto schema for the url_lifetime_stats materialized view.

  This view aggregates lifetime metrics from the time_series table and serves
  as the primary source for URL performance data. It includes HTTP status
  tracking fields that are managed by the crawler system.

  ## Important Fields

  ### Core Performance Metrics
  - `lifetime_clicks`: Total clicks across all time
  - `lifetime_impressions`: Total impressions across all time
  - `avg_position`: Weighted average position
  - `avg_ctr`: Average click-through rate

  ### HTTP Status Fields (Managed by Crawler)
  - `http_status`: Current HTTP status code (200, 404, etc.)
  - `http_checked_at`: Last HTTP check timestamp
  - `redirect_url`: Final URL after redirects
  - `http_redirect_chain`: Complete redirect path

  ### Data Availability
  URLs are included in this view when they have actual GSC performance data
  (clicks or impressions). The crawler filters to these URLs to focus on
  SEO-relevant pages.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @primary_key false
  schema "url_lifetime_stats" do
    field :account_id, :integer, primary_key: true
    field :property_url, :string, primary_key: true
    field :url, :string, primary_key: true

    # Lifetime metrics from GSC
    field :lifetime_clicks, :integer, default: 0
    field :lifetime_impressions, :integer, default: 0
    field :avg_position, :float, default: 0.0
    field :avg_ctr, :float, default: 0.0
    field :first_seen_date, :date
    field :last_seen_date, :date
    field :days_with_data, :integer, default: 0
    field :refreshed_at, :utc_datetime

    # HTTP Status fields (managed by crawler)
    field :http_status, :integer
    field :redirect_url, :string
    field :http_checked_at, :utc_datetime
    field :http_redirect_chain, :map
  end

  # Query Helpers

  @doc """
  Query to get stats for an account.
  """
  def for_account(query \\ __MODULE__, account_id) do
    from(u in query, where: u.account_id == ^account_id)
  end

  @doc """
  Query to get stats for a specific property.
  """
  def for_property(query \\ __MODULE__, property_url) do
    from(u in query, where: u.property_url == ^property_url)
  end

  @doc """
  Query to get URLs with traffic (clicks or impressions).
  Equivalent to data_available flag in Performance schema.
  """
  def with_traffic(query \\ __MODULE__) do
    from(u in query,
      where: u.lifetime_clicks > 0 or u.lifetime_impressions > 0
    )
  end

  @doc """
  Query to get URLs that need HTTP status checking.

  Returns URLs that are either:
  - Never checked (http_checked_at is nil)
  - Stale (checked more than `stale_days` ago)
  """
  def needs_http_check(query \\ __MODULE__, stale_days \\ 7) do
    alias GscAnalytics.DateTime, as: AppDateTime
    stale_date = DateTime.add(AppDateTime.utc_now(), -stale_days, :day)

    from(u in query,
      where: is_nil(u.http_checked_at) or u.http_checked_at < ^stale_date
    )
  end

  @doc """
  Query to get URLs with broken links (4xx/5xx status codes).
  """
  def broken_links(query \\ __MODULE__) do
    from(u in query, where: u.http_status >= 400)
  end

  @doc """
  Query to get URLs with redirects (3xx status codes).
  """
  def redirected_urls(query \\ __MODULE__) do
    from(u in query,
      where: u.http_status in [301, 302, 307, 308],
      where: not is_nil(u.redirect_url)
    )
  end

  @doc """
  Query to get top performing URLs.
  """
  def top_performing(query \\ __MODULE__, limit \\ 10) do
    from(u in query,
      order_by: [desc: u.lifetime_clicks],
      limit: ^limit
    )
  end

  @doc """
  Update changeset for HTTP status fields only.
  Used by the crawler to update status without touching metrics.
  """
  def http_status_changeset(stats, attrs) do
    stats
    |> cast(attrs, [:http_status, :redirect_url, :http_checked_at, :http_redirect_chain])
    |> validate_number(:http_status, greater_than_or_equal_to: 100, less_than: 600)
    |> validate_length(:redirect_url, max: 2048)
  end
end