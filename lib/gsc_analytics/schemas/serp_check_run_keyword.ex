defmodule GscAnalytics.Schemas.SerpCheckRunKeyword do
  @moduledoc """
  Individual keyword record that belongs to a SERP check run.

  Tracks per-keyword status so we can render progress, retries, and telemetry.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias GscAnalytics.Schemas.SerpCheckRun

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "serp_check_run_keywords" do
    belongs_to :serp_check_run, SerpCheckRun

    field :keyword, :string
    field :geo, :string, default: "us"
    field :status, Ecto.Enum, values: [:pending, :running, :success, :failed], default: :pending
    field :error, :string
    field :completed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:serp_check_run_id, :keyword, :geo]
  @optional_fields [:status, :error, :completed_at]

  def changeset(keyword, attrs) do
    keyword
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:keyword, min: 1, max: 500)
    |> validate_length(:geo, min: 2, max: 5)
  end
end
