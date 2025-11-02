defmodule GscAnalytics.Workspaces do
  @moduledoc """
  Context for managing user workspaces (Google Search Console account connections).

  A workspace represents a connection to a Google account via OAuth 2.0. Each workspace
  can have multiple properties (Search Console sites) associated with it.

  This module provides functions for creating, listing, updating, and deleting workspaces.
  """

  import Ecto.Query

  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.Workspace

  @type workspace_id :: pos_integer()

  @doc """
  Returns all workspaces for a given user.

  ## Options

  * `:enabled_only` - If true, only return enabled workspaces (default: false)

  ## Examples

      iex> list_workspaces(user_id)
      [%Workspace{}, ...]

      iex> list_workspaces(user_id, enabled_only: true)
      [%Workspace{enabled: true}, ...]
  """
  @spec list_workspaces(integer(), keyword()) :: [Workspace.t()]
  def list_workspaces(user_id, opts \\ []) do
    enabled_only = Keyword.get(opts, :enabled_only, false)

    query = from w in Workspace, where: w.user_id == ^user_id

    query =
      if enabled_only do
        from w in query, where: w.enabled == true
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Gets a single workspace by ID.

  Returns `nil` if the workspace does not exist.

  ## Examples

      iex> get_workspace(123)
      %Workspace{}

      iex> get_workspace(456)
      nil
  """
  @spec get_workspace(workspace_id()) :: Workspace.t() | nil
  def get_workspace(id) do
    Repo.get(Workspace, id)
  end

  @doc """
  Gets a single workspace by ID, raising if not found.

  ## Examples

      iex> get_workspace!(123)
      %Workspace{}

      iex> get_workspace!(456)
      ** (Ecto.NoResultsError)
  """
  @spec get_workspace!(workspace_id()) :: Workspace.t()
  def get_workspace!(id) do
    Repo.get!(Workspace, id)
  end

  @doc """
  Gets a workspace by ID and user_id (for authorization).

  Returns `{:ok, workspace}` if found and owned by user, `{:error, :not_found}` otherwise.

  ## Examples

      iex> fetch_workspace(user_id, workspace_id)
      {:ok, %Workspace{}}

      iex> fetch_workspace(user_id, other_users_workspace_id)
      {:error, :not_found}
  """
  @spec fetch_workspace(integer(), workspace_id()) :: {:ok, Workspace.t()} | {:error, :not_found}
  def fetch_workspace(user_id, workspace_id) do
    query = from w in Workspace, where: w.id == ^workspace_id and w.user_id == ^user_id

    case Repo.one(query) do
      nil -> {:error, :not_found}
      workspace -> {:ok, workspace}
    end
  end

  @doc """
  Creates a new workspace for a user.

  ## Examples

      iex> create_workspace(user_id, %{
      ...>   name: "Personal Sites",
      ...>   google_account_email: "user@gmail.com",
      ...>   default_property: "sc-domain:example.com"
      ...> })
      {:ok, %Workspace{}}

      iex> create_workspace(user_id, %{google_account_email: "invalid"})
      {:error, %Ecto.Changeset{}}
  """
  @spec create_workspace(integer(), map()) :: {:ok, Workspace.t()} | {:error, Ecto.Changeset.t()}
  def create_workspace(user_id, attrs) do
    attrs_with_user = Map.put(attrs, :user_id, user_id)

    %Workspace{}
    |> Workspace.changeset(attrs_with_user)
    |> Repo.insert()
  end

  @doc """
  Updates a workspace.

  ## Examples

      iex> update_workspace(workspace, %{name: "New Name"})
      {:ok, %Workspace{}}

      iex> update_workspace(workspace, %{google_account_email: "invalid"})
      {:error, %Ecto.Changeset{}}
  """
  @spec update_workspace(Workspace.t(), map()) ::
          {:ok, Workspace.t()} | {:error, Ecto.Changeset.t()}
  def update_workspace(%Workspace{} = workspace, attrs) do
    workspace
    |> Workspace.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a workspace.

  This will cascade delete associated properties and OAuth tokens.

  ## Examples

      iex> delete_workspace(workspace)
      {:ok, %Workspace{}}

      iex> delete_workspace(workspace)
      {:error, %Ecto.Changeset{}}
  """
  @spec delete_workspace(Workspace.t()) :: {:ok, Workspace.t()} | {:error, Ecto.Changeset.t()}
  def delete_workspace(%Workspace{} = workspace) do
    Repo.delete(workspace)
  end

  @doc """
  Returns a changeset for tracking workspace changes.

  ## Examples

      iex> change_workspace(workspace)
      %Ecto.Changeset{data: %Workspace{}}
  """
  @spec change_workspace(Workspace.t(), map()) :: Ecto.Changeset.t()
  def change_workspace(%Workspace{} = workspace, attrs \\ %{}) do
    Workspace.changeset(workspace, attrs)
  end

  @doc """
  Returns the first workspace for a user, typically used as a default.

  Returns `nil` if the user has no workspaces.

  ## Examples

      iex> get_default_workspace(user_id)
      %Workspace{}

      iex> get_default_workspace(user_with_no_workspaces_id)
      nil
  """
  @spec get_default_workspace(integer()) :: Workspace.t() | nil
  def get_default_workspace(user_id) do
    query =
      from w in Workspace,
        where: w.user_id == ^user_id and w.enabled == true,
        order_by: [asc: w.inserted_at],
        limit: 1

    Repo.one(query)
  end

  @doc """
  Checks if a Google account email is already connected for a user.

  ## Examples

      iex> google_account_connected?(user_id, "user@gmail.com")
      true

      iex> google_account_connected?(user_id, "new@gmail.com")
      false
  """
  @spec google_account_connected?(integer(), String.t()) :: boolean()
  def google_account_connected?(user_id, google_account_email) do
    query =
      from w in Workspace,
        where: w.user_id == ^user_id and w.google_account_email == ^google_account_email,
        select: count(w.id)

    Repo.one(query) > 0
  end
end
