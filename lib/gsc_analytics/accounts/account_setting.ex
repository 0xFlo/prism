defmodule GscAnalytics.Accounts.AccountSetting do
  @moduledoc """
  Persistence layer for runtime overrides applied to configured GSC workspaces.

  This table lets operators adjust display metadata (for example renaming
  `Workspace 2` after connecting OAuth) and, critically, store the default
  Search Console property chosen through the UI.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:account_id, :integer, autogenerate: false}

  schema "gsc_account_settings" do
    field :display_name, :string
    field :default_property, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:account_id, :display_name, :default_property])
    |> validate_required([:account_id])
    |> validate_number(:account_id, greater_than: 0)
    |> maybe_trim_change(:display_name)
    |> maybe_trim_change(:default_property)
    |> unique_constraint(:account_id)
  end

  defp maybe_trim_change(changeset, field) do
    case get_change(changeset, field) do
      nil ->
        changeset

      value when is_binary(value) ->
        trimmed = String.trim(value)
        put_change(changeset, field, if(trimmed == "", do: nil, else: trimmed))

      _other ->
        changeset
    end
  end
end
