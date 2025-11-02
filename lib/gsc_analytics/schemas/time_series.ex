defmodule GscAnalytics.Schemas.TimeSeries do
  @moduledoc """
  Ecto schema for time-series GSC performance data.

  Stores daily or weekly performance snapshots for trend analysis
  and historical tracking. Supports PostgreSQL table partitioning
  by date for optimal performance at scale.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  # Composite primary key
  @primary_key false

  schema "gsc_time_series" do
    field :account_id, :integer, primary_key: true
    field :property_url, :string, primary_key: true
    field :url, :string, primary_key: true
    field :date, :date, primary_key: true
    field :period_type, Ecto.Enum, values: [:daily, :weekly, :monthly], default: :daily
    field :clicks, :integer, default: 0
    field :impressions, :integer, default: 0
    field :ctr, :float, default: 0.0
    field :position, :float, default: 0.0
    field :top_queries, {:array, :map}, default: []
    field :data_available, :boolean, default: false

    # Reference to parent performance record
    belongs_to :performance, GscAnalytics.Schemas.Performance,
      foreign_key: :performance_id,
      type: :binary_id

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @required_fields [:account_id, :property_url, :url, :date]
  @optional_fields [
    :period_type,
    :clicks,
    :impressions,
    :ctr,
    :position,
    :top_queries,
    :data_available,
    :performance_id
  ]

  @doc """
  Creates a changeset for time-series data.
  """
  def changeset(time_series, attrs) do
    time_series
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_url_lengths()
    |> validate_metrics()
    |> validate_date_not_future()
  end

  @doc """
  Creates a batch insert changeset for multiple time-series records.
  """
  def batch_changeset(records) when is_list(records) do
    Enum.map(records, fn record ->
      %__MODULE__{}
      |> changeset(record)
      |> apply_action(:insert)
    end)
  end

  # Validations

  defp validate_url_lengths(changeset) do
    changeset
    |> validate_length(:url,
      max: 2048,
      message: "URL too long (maximum 2048 characters)"
    )
    |> validate_length(:property_url,
      max: 255,
      message: "Property URL too long (maximum 255 characters)"
    )
  end

  defp validate_metrics(changeset) do
    changeset
    |> validate_number(:clicks, greater_than_or_equal_to: 0)
    |> validate_number(:impressions, greater_than_or_equal_to: 0)
    |> validate_number(:ctr, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:position, greater_than_or_equal_to: 0.0)
  end

  defp validate_date_not_future(changeset) do
    case get_change(changeset, :date) do
      nil ->
        changeset

      date ->
        if Date.compare(date, Date.utc_today()) == :gt do
          add_error(changeset, :date, "cannot be in the future")
        else
          changeset
        end
    end
  end

  # Queries

  @doc """
  Query time-series data for a specific account.
  """
  def for_account(query \\ __MODULE__, account_id) do
    from(ts in query,
      where: ts.account_id == ^account_id
    )
  end

  @doc """
  Query time-series data for a specific property.
  """
  def for_property(query \\ __MODULE__, property_url) do
    from(ts in query,
      where: ts.property_url == ^property_url
    )
  end

  @doc """
  Query time-series data for an account and property.
  """
  def for_account_and_property(query \\ __MODULE__, account_id, property_url) do
    from(ts in query,
      where: ts.account_id == ^account_id and ts.property_url == ^property_url
    )
  end

  @doc """
  Query time-series data for a specific URL.
  """
  def for_url(query \\ __MODULE__, url) do
    from(ts in query,
      where: ts.url == ^url
    )
  end

  @doc """
  Query time-series data within a date range.
  """
  def in_date_range(query \\ __MODULE__, start_date, end_date) do
    from(ts in query,
      where: ts.date >= ^start_date and ts.date <= ^end_date
    )
  end

  @doc """
  Query to aggregate metrics by period.
  """
  def aggregate_by_period(query \\ __MODULE__, period \\ :weekly) do
    case period do
      :daily ->
        from(ts in query,
          group_by: [ts.account_id, ts.url, ts.date],
          select: %{
            account_id: ts.account_id,
            url: ts.url,
            date: ts.date,
            clicks: sum(ts.clicks),
            impressions: sum(ts.impressions),
            avg_ctr: avg(ts.ctr),
            avg_position: avg(ts.position)
          }
        )

      :weekly ->
        from(ts in query,
          group_by: [
            ts.account_id,
            ts.url,
            fragment("DATE_TRUNC('week', ?)", ts.date)
          ],
          select: %{
            account_id: ts.account_id,
            url: ts.url,
            week_start: fragment("DATE_TRUNC('week', ?)", ts.date),
            clicks: sum(ts.clicks),
            impressions: sum(ts.impressions),
            avg_ctr: avg(ts.ctr),
            avg_position: avg(ts.position)
          }
        )

      :monthly ->
        from(ts in query,
          group_by: [
            ts.account_id,
            ts.url,
            fragment("DATE_TRUNC('month', ?)", ts.date)
          ],
          select: %{
            account_id: ts.account_id,
            url: ts.url,
            month_start: fragment("DATE_TRUNC('month', ?)", ts.date),
            clicks: sum(ts.clicks),
            impressions: sum(ts.impressions),
            avg_ctr: avg(ts.ctr),
            avg_position: avg(ts.position)
          }
        )
    end
  end

  @doc """
  Calculate trend direction and strength for a URL.
  """
  def calculate_trend(query \\ __MODULE__, url, days \\ 30) do
    end_date = Date.utc_today()
    start_date = Date.add(end_date, -days)

    from(ts in query,
      where: ts.url == ^url,
      where: ts.date >= ^start_date,
      where: ts.date <= ^end_date,
      order_by: [asc: ts.date],
      select: %{
        date: ts.date,
        clicks: ts.clicks,
        impressions: ts.impressions,
        position: ts.position
      }
    )
  end

  @doc """
  Find URLs with significant traffic changes.
  """
  def traffic_changes(query \\ __MODULE__, threshold_percent \\ 20) do
    # Compare last 7 days to previous 7 days
    today = Date.utc_today()
    last_week_start = Date.add(today, -7)
    prev_week_start = Date.add(today, -14)
    prev_week_end = Date.add(today, -8)

    from(ts in query,
      join: prev in __MODULE__,
      on: prev.account_id == ts.account_id and prev.url == ts.url,
      where: ts.date >= ^last_week_start and ts.date <= ^today,
      where: prev.date >= ^prev_week_start and prev.date <= ^prev_week_end,
      group_by: [ts.account_id, ts.url],
      # Minimum traffic threshold
      having: sum(ts.clicks) > 10,
      select: %{
        account_id: ts.account_id,
        url: ts.url,
        recent_clicks: sum(ts.clicks),
        previous_clicks: sum(prev.clicks),
        change_percent:
          fragment(
            "ROUND(((SUM(?) - SUM(?)) / NULLIF(SUM(?), 0)::numeric) * 100, 2)",
            ts.clicks,
            prev.clicks,
            prev.clicks
          )
      },
      where:
        fragment(
          "ABS((SUM(?) - SUM(?)) / NULLIF(SUM(?), 0)::numeric) > ?",
          ts.clicks,
          prev.clicks,
          prev.clicks,
          ^(threshold_percent / 100)
        )
    )
  end

  @doc """
  Generate weekly rollup data from daily records.
  """
  def weekly_rollup(query \\ __MODULE__) do
    from(ts in query,
      where: ts.period_type == :daily,
      group_by: [
        ts.account_id,
        ts.url,
        fragment("DATE_TRUNC('week', ?)", ts.date)
      ],
      select: %{
        account_id: ts.account_id,
        url: ts.url,
        date: fragment("DATE_TRUNC('week', ?)::date", ts.date),
        period_type: :weekly,
        clicks: sum(ts.clicks),
        impressions: sum(ts.impressions),
        ctr: avg(ts.ctr),
        position: avg(ts.position),
        data_available: fragment("BOOL_OR(?)", ts.data_available)
      }
    )
  end
end
