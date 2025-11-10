defmodule GscAnalyticsWeb.PropertyContext do
  @moduledoc """
  Shared helpers for resolving the active workspace property outside of LiveViews.

  Controllers or public pages can call these functions to look up a property
  that belongs to the current authenticated scope, falling back to the user's
  default workspace selection when `property_id` is not provided.
  """

  alias GscAnalytics.Accounts
  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.WorkspaceProperty
  alias Phoenix.LiveView.Socket

  @type scope :: map() | nil
  @type property_id :: String.t() | nil

  @doc """
  Fetch the property struct for the given scope.

  - When `property_id` is present, ensure the property exists and belongs to the
    user; otherwise return an error.
  - When `property_id` is nil/blank, fall back to the user's default workspace
    and its active property.
  """
  @spec fetch_property(scope() | Socket.t(), property_id()) ::
          {:ok, WorkspaceProperty.t()}
          | {:error, :unauthenticated | :not_found | :unauthorized | :no_accounts | :no_property}
  def fetch_property(nil, _property_id), do: {:error, :unauthenticated}

  def fetch_property(%Socket{} = socket, property_id) do
    scope = Map.get(socket.assigns, :current_scope)
    fetch_property(scope, property_id)
  end

  def fetch_property(%{user: _user} = scope, property_id) when is_binary(property_id) do
    with %WorkspaceProperty{} = property <- Repo.get(WorkspaceProperty, property_id),
         true <- authorized_workspace?(scope, property.workspace_id) do
      {:ok, property}
    else
      nil -> {:error, :not_found}
      false -> {:error, :unauthorized}
    end
  end

  def fetch_property(scope, property_id) when property_id in [nil, ""],
    do: default_property(scope)

  @doc """
  Returns the default property id for the given scope, if any.
  """
  @spec default_property_id(scope()) :: String.t() | nil
  def default_property_id(scope) do
    with {:ok, property} <- default_property(scope) do
      property.id
    else
      _ -> nil
    end
  end

  @doc """
  Builds the canonical dashboard path for a scope using its default property (if available).
  """
  @spec default_dashboard_path(scope()) :: String.t()
  def default_dashboard_path(scope) do
    property_id = default_property_id(scope)

    case property_id do
      nil -> "/users/settings"
      id -> GscAnalyticsWeb.PropertyRoutes.dashboard_path(id)
    end
  end

  defp default_property(scope) do
    case Accounts.list_gsc_accounts(scope) do
      [] ->
        {:error, :no_accounts}

      accounts ->
        accounts
        |> Enum.find_value(fn account ->
          case Accounts.get_active_property(account.id) do
            nil -> nil
            property -> {:ok, property}
          end
        end)
        |> case do
          nil -> {:error, :no_property}
          {:ok, property} -> {:ok, property}
        end
    end
  end

  defp authorized_workspace?(scope, workspace_id) do
    Accounts.list_gsc_accounts(scope)
    |> Enum.any?(fn account -> account.id == workspace_id end)
  end
end
