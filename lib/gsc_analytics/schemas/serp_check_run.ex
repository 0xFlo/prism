defmodule GscAnalytics.Schemas.SerpCheckRun do
  @moduledoc """
  Represents a bulk SERP check run triggered from the dashboard.

  Stores metadata about the run (scope, URL, keyword counts, status) so that
  LiveViews can resume progress state and we can audit ScrapFly usage per run.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias GscAnalytics.Schemas.SerpCheckRunKeyword

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "serp_check_runs" do
    field :account_id, :integer
    field :property_url, :string
    field :url, :string

    field :status, Ecto.Enum,
      values: [:pending, :running, :complete, :partial, :failed],
      default: :pending

    field :keyword_count, :integer, default: 0
    field :succeeded_count, :integer, default: 0
    field :failed_count, :integer, default: 0
    field :estimated_cost, :integer, default: 0
    field :last_error, :string
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec

    has_many :keywords, SerpCheckRunKeyword
    has_many :snapshots, GscAnalytics.Schemas.SerpSnapshot, foreign_key: :serp_check_run_id

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:account_id, :property_url, :url, :keyword_count, :estimated_cost]
  @optional_fields [
    :status,
    :succeeded_count,
    :failed_count,
    :last_error,
    :started_at,
    :finished_at
  ]

  def changeset(run, attrs) do
    run
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:account_id, greater_than: 0)
    |> validate_number(:keyword_count, greater_than: 0)
    |> validate_number(:estimated_cost, greater_than_or_equal_to: 0)
    |> validate_length(:property_url, max: 255)
    |> validate_length(:url, max: 2048)
  end
end
