defmodule GscAnalytics.Schemas.WorkspaceProperty do
  @moduledoc """
  Represents a Google Search Console property associated with a workspace.

  A workspace (account) can manage multiple Search Console properties. Each property
  represents a distinct website or domain property in Google Search Console. Properties
  marked as active participate in sync operations and power dashboards. Workspaces can
  activate multiple properties at once when they want to pull data for more than one
  site.

  ## Fields

  * `id` - UUID primary key
  * `workspace_id` - Integer reference to the account/workspace (matches account_id throughout the system)
  * `property_url` - The Search Console property URL (e.g., "sc-domain:example.com" or "https://example.com/")
  * `display_name` - Optional human-friendly name for the property
  * `is_active` - Boolean flag indicating if this is the currently active property for the workspace
  * `inserted_at` / `updated_at` - Standard Ecto timestamps

  ## Constraints

  * Each workspace can only have one property URL saved once (unique constraint)
  * Each workspace can store multiple active properties
  * Property URL is required and must not be empty

  ## Examples

      # Create a new property
      %WorkspaceProperty{}
      |> WorkspaceProperty.changeset(%{
        workspace_id: 1,
        property_url: "sc-domain:example.com",
        display_name: "Example.com (Domain Property)",
        is_active: true
      })
      |> Repo.insert()

      # Find active property for a workspace
      Repo.get_by(WorkspaceProperty, workspace_id: 1, is_active: true)
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          workspace_id: pos_integer() | nil,
          property_url: String.t() | nil,
          display_name: String.t() | nil,
          is_active: boolean(),
          favicon_url: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "workspace_properties" do
    field :workspace_id, :integer
    field :property_url, :string
    field :display_name, :string
    field :is_active, :boolean, default: false
    field :favicon_url, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating workspace properties.

  ## Required fields
  * `workspace_id` - Must be a positive integer
  * `property_url` - Must be a non-empty string

  ## Optional fields
  * `display_name` - Human-friendly label
  * `is_active` - Defaults to false

  ## Validations
  * Workspace ID must be greater than 0
  * Property URL must be present and non-empty after trimming
  * Display name is trimmed and converted to nil if empty
  """
  def changeset(property, attrs) do
    property
    |> cast(attrs, [:workspace_id, :property_url, :display_name, :is_active, :favicon_url])
    |> validate_required([:workspace_id, :property_url])
    |> validate_number(:workspace_id, greater_than: 0)
    |> trim_and_validate(:property_url)
    |> trim_optional(:display_name)
    |> maybe_generate_favicon_url()
    |> generate_uuid_if_new()
    |> unique_constraint([:workspace_id, :property_url],
      name: :workspace_properties_workspace_property_unique,
      message: "This property is already saved for this workspace"
    )
  end

  defp maybe_generate_favicon_url(changeset) do
    # Only generate favicon URL if not explicitly provided and property_url is present
    case {get_change(changeset, :favicon_url), get_field(changeset, :property_url)} do
      {nil, property_url} when is_binary(property_url) ->
        favicon_url = GscAnalytics.Helpers.FaviconFetcher.get_favicon_url(property_url)
        put_change(changeset, :favicon_url, favicon_url)

      _ ->
        changeset
    end
  end

  defp generate_uuid_if_new(changeset) do
    case get_field(changeset, :id) do
      nil -> put_change(changeset, :id, Ecto.UUID.generate())
      _id -> changeset
    end
  end

  defp trim_and_validate(changeset, field) do
    changeset
    |> update_change(field, &String.trim/1)
    |> validate_required([field])
    |> validate_length(field, min: 1)
  end

  defp trim_optional(changeset, field) do
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
