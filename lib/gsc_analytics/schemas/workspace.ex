defmodule GscAnalytics.Schemas.Workspace do
  @moduledoc """
  Represents a user's Google Search Console workspace.

  A workspace is a connection to a Google account that provides access to Search Console data.
  Each workspace is tied to a specific Google account (identified by email) and can have multiple
  properties (websites/domains) associated with it.

  ## Authentication

  Workspaces use OAuth 2.0 for authentication. The OAuth token is stored separately in the
  `oauth_tokens` table and linked via `account_id` (which is the workspace_id).

  ## Fields

  * `id` - Auto-incrementing integer primary key (also used as account_id in other tables)
  * `user_id` - Reference to the user who owns this workspace
  * `name` - User-defined name for the workspace (e.g., "Personal Sites", "Work Account")
  * `google_account_email` - Email address of the connected Google account
  * `default_property` - Default Search Console property URL for this workspace
  * `enabled` - Whether this workspace is active for sync operations
  * `inserted_at` / `updated_at` - Standard Ecto timestamps

  ## Constraints

  * Each user can only connect a Google account once (unique constraint on user_id + google_account_email)
  * Google account email is required and must not be empty
  * Name is optional but recommended for clarity when managing multiple workspaces

  ## Examples

      # Create a new workspace
      %Workspace{}
      |> Workspace.changeset(%{
        user_id: user.id,
        name: "Personal Sites",
        google_account_email: "user@gmail.com",
        default_property: "sc-domain:example.com",
        enabled: true
      })
      |> Repo.insert()

      # Find all workspaces for a user
      Repo.all(from w in Workspace, where: w.user_id == ^user_id and w.enabled == true)
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias GscAnalytics.Auth.User
  alias GscAnalytics.Schemas.WorkspaceProperty

  @type t :: %__MODULE__{}

  schema "workspaces" do
    field :name, :string
    field :google_account_email, :string
    field :default_property, :string
    field :enabled, :boolean, default: true

    belongs_to :user, User
    has_many :properties, WorkspaceProperty, foreign_key: :workspace_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a workspace.

  ## Required fields
  - user_id
  - google_account_email

  ## Optional fields
  - name (defaults to Google account email if not provided)
  - default_property
  - enabled (defaults to true)
  """
  def changeset(workspace, attrs) do
    workspace
    |> cast(attrs, [:user_id, :name, :google_account_email, :default_property, :enabled])
    |> validate_required([:user_id, :google_account_email])
    |> validate_format(:google_account_email, ~r/@/, message: "must be a valid email address")
    |> maybe_set_default_name()
    |> unique_constraint([:user_id, :google_account_email],
      name: :workspaces_user_id_google_account_email_index,
      message: "This Google account is already connected to your account"
    )
  end

  defp maybe_set_default_name(changeset) do
    case get_field(changeset, :name) do
      nil ->
        email = get_field(changeset, :google_account_email)
        put_change(changeset, :name, email)

      _name ->
        changeset
    end
  end
end
