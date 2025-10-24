defmodule GscAnalytics.Schemas.Performance do
  @moduledoc """
  Ecto schema for Google Search Console performance data.

  Stores aggregated performance metrics for URLs including clicks,
  impressions, CTR, and average position. Supports multi-tenancy
  through account_id field.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  alias GscAnalytics.DateTime, as: AppDateTime

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "gsc_performance" do
    field :account_id, :integer
    field :url, :string
    field :clicks, :integer, default: 0
    field :impressions, :integer, default: 0
    field :ctr, :float, default: 0.0
    field :position, :float, default: 0.0
    field :date_range_start, :date
    field :date_range_end, :date
    field :top_queries, {:array, :map}, default: []
    field :data_available, :boolean, default: false
    field :error_message, :string

    # Cache management
    field :cache_expires_at, :utc_datetime

    # Metadata
    field :fetched_at, :utc_datetime
    field :processing_time_ms, :integer

    # HTTP Status Crawler fields
    field :http_status, :integer
    field :redirect_url, :string
    field :http_checked_at, :utc_datetime
    field :http_redirect_chain, :map

    has_many :time_series, GscAnalytics.Schemas.TimeSeries,
      foreign_key: :performance_id,
      on_delete: :delete_all

    timestamps(type: :utc_datetime)
  end

  @required_fields [:account_id, :url]
  @optional_fields [
    :clicks,
    :impressions,
    :ctr,
    :position,
    :date_range_start,
    :date_range_end,
    :top_queries,
    :data_available,
    :error_message,
    :cache_expires_at,
    :fetched_at,
    :processing_time_ms,
    :http_status,
    :redirect_url,
    :http_checked_at,
    :http_redirect_chain
  ]

  @doc """
  Creates a changeset for GSC performance data.
  """
  def changeset(performance, attrs) do
    performance
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_url()
    |> validate_metrics()
    |> validate_date_range()
    |> put_cache_expiry()
    |> unique_constraint([:account_id, :url], name: :gsc_performance_account_url_index)
  end

  @doc """
  Creates or updates a performance record.
  """
  def upsert_changeset(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> put_change(:fetched_at, AppDateTime.utc_now())
  end

  # Validations

  defp validate_url(changeset) do
    validate_change(changeset, :url, fn :url, url ->
      case URI.parse(url) do
        %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and not is_nil(host) ->
          []

        _ ->
          [url: "must be a valid HTTP(S) URL"]
      end
    end)
  end

  defp validate_metrics(changeset) do
    changeset
    |> validate_number(:clicks, greater_than_or_equal_to: 0)
    |> validate_number(:impressions, greater_than_or_equal_to: 0)
    |> validate_number(:ctr, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:position, greater_than_or_equal_to: 0.0)
  end

  defp validate_date_range(changeset) do
    case {get_change(changeset, :date_range_start), get_change(changeset, :date_range_end)} do
      {nil, nil} ->
        changeset

      {start_date, end_date} when not is_nil(start_date) and not is_nil(end_date) ->
        if Date.compare(start_date, end_date) == :gt do
          add_error(changeset, :date_range_start, "must be before or equal to end date")
        else
          changeset
        end

      _ ->
        changeset
    end
  end

  defp put_cache_expiry(changeset) do
    utc_now = AppDateTime.utc_now()

    if get_change(changeset, :data_available) == true do
      # Cache for 24 hours if data is available
      expires_at = DateTime.add(utc_now, 24, :hour)
      put_change(changeset, :cache_expires_at, expires_at)
    else
      # Cache for 1 hour if no data (might become available)
      expires_at = DateTime.add(utc_now, 1, :hour)
      put_change(changeset, :cache_expires_at, expires_at)
    end
  end

  # Queries

  @doc """
  Query to get performance data for an account.
  """
  def for_account(query \\ __MODULE__, account_id) do
    from(p in query,
      where: p.account_id == ^account_id
    )
  end

  @doc """
  Query to get non-expired cached data.
  """
  def cached(query \\ __MODULE__) do
    now = AppDateTime.utc_now()

    from(p in query,
      where: p.cache_expires_at > ^now and p.data_available == true
    )
  end

  @doc """
  Query to get URLs needing refresh.
  """
  def needs_refresh(query \\ __MODULE__) do
    now = AppDateTime.utc_now()

    from(p in query,
      where: is_nil(p.cache_expires_at) or p.cache_expires_at <= ^now
    )
  end

  @doc """
  Query to get top performing URLs.
  """
  def top_performing(query \\ __MODULE__, limit \\ 10) do
    from(p in query,
      where: p.data_available == true,
      order_by: [desc: p.clicks],
      limit: ^limit
    )
  end

  @doc """
  Query to get URLs with CTR optimization opportunity.
  """
  def ctr_opportunities(query \\ __MODULE__, min_impressions \\ 100) do
    from(p in query,
      where: p.impressions > ^min_impressions and p.ctr < 0.05,
      order_by: [desc: p.impressions]
    )
  end

  @doc """
  Calculate performance tier based on metrics.
  """
  def performance_tier(%__MODULE__{} = performance) do
    cond do
      performance.clicks > 1000 -> :high
      performance.clicks > 100 -> :medium
      performance.clicks > 10 -> :low
      performance.data_available -> :minimal
      true -> :no_data
    end
  end

  @doc """
  Calculate opportunity score (0-100).
  """
  def opportunity_score(%__MODULE__{} = performance) do
    # Base score from impressions
    impression_score = min(performance.impressions / 1000 * 20, 20)

    # CTR penalty (lower CTR = higher opportunity)
    ctr_penalty =
      if performance.impressions > 100 do
        (0.10 - performance.ctr) * 200
      else
        0
      end

    # Position opportunity (worse position = more opportunity)
    position_score =
      if performance.position > 0 do
        min((performance.position - 1) * 5, 30)
      else
        0
      end

    # Current performance penalty (already performing well = less opportunity)
    performance_penalty = min(performance.clicks / 100 * 10, 30)

    score = impression_score + ctr_penalty + position_score - performance_penalty

    score
    |> max(0)
    |> min(100)
    |> round()
  end

  # ============================================================================
  # HTTP Status Crawler Query Helpers
  # ============================================================================

  @doc """
  Query to get URLs with broken links (4xx/5xx status codes).
  """
  def broken_links(query \\ __MODULE__) do
    from(p in query,
      where: p.http_status >= 400
    )
  end

  @doc """
  Query to get URLs that need HTTP status checking.

  Returns URLs that are either:
  - Never checked (http_checked_at is nil)
  - Stale (checked more than `stale_days` ago)

  ## Options
  - `stale_days` - Number of days before a check is considered stale (default: 7)
  """
  def needs_http_check(query \\ __MODULE__, stale_days \\ 7) do
    alias GscAnalytics.DateTime, as: AppDateTime
    stale_date = DateTime.add(AppDateTime.utc_now(), -stale_days, :day)

    from(p in query,
      where: is_nil(p.http_checked_at) or p.http_checked_at < ^stale_date
    )
  end

  @doc """
  Query to get URLs with redirects (3xx status codes).
  """
  def redirected_urls(query \\ __MODULE__) do
    from(p in query,
      where: p.http_status in [301, 302, 307, 308],
      where: not is_nil(p.redirect_url)
    )
  end
end
