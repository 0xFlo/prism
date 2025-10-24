defmodule GscAnalytics.Schemas.SyncDay do
  @moduledoc """
  Tracks per-property, per-day sync completion state so we can skip
  redundant Google Search Console fetches while safely retrying
  incomplete days.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  schema "gsc_sync_days" do
    field :account_id, :integer, primary_key: true
    field :site_url, :string, primary_key: true
    field :date, :date, primary_key: true

    field :status, Ecto.Enum,
      values: [:pending, :running, :complete, :failed, :skipped],
      default: :pending

    field :url_count, :integer, default: 0
    field :last_synced_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @required_fields [:account_id, :site_url, :date, :status]
  @optional_fields [:url_count, :last_synced_at]

  def changeset(sync_day, attrs) do
    sync_day
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:url_count, greater_than_or_equal_to: 0)
    |> unique_constraint([:account_id, :site_url, :date],
      name: :gsc_sync_days_account_id_site_url_date_index
    )
  end
end
