defmodule GscAnalytics.Schemas.PropertyDailyMetric do
  @moduledoc """
  Aggregated per-day site metrics for each account + property combination.

  Populated by the GSC sync pipeline so dashboard queries can read a small
  pre-summarised table instead of rescanning `gsc_time_series`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  schema "property_daily_metrics" do
    field :account_id, :integer
    field :property_url, :string
    field :date, :date
    field :clicks, :integer, default: 0
    field :impressions, :integer, default: 0
    field :ctr, :float, default: 0.0
    field :position, :float, default: 0.0
    field :urls_count, :integer, default: 0
    field :data_available, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(daily_metric, attrs) do
    daily_metric
    |> cast(attrs, [
      :account_id,
      :property_url,
      :date,
      :clicks,
      :impressions,
      :ctr,
      :position,
      :urls_count,
      :data_available
    ])
    |> validate_required([:account_id, :property_url, :date])
  end
end
