defmodule GscAnalyticsWeb.GoogleAuthController do
  use GscAnalyticsWeb, :controller

  alias GscAnalyticsWeb.GoogleAuth

  def request(conn, params) do
    case parse_workspace_id(params) do
      {:ok, workspace_id} ->
        GoogleAuth.request(conn, workspace_id)

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Invalid workspace identifier.")
        |> redirect(to: ~p"/accounts")
    end
  end

  def callback(conn, params) do
    GoogleAuth.callback(conn, params)
  end

  # Support both workspace_id (new) and account_id (legacy) parameters
  defp parse_workspace_id(%{"workspace_id" => workspace_id}),
    do: normalize_workspace_id(workspace_id)

  defp parse_workspace_id(%{workspace_id: workspace_id}), do: normalize_workspace_id(workspace_id)
  defp parse_workspace_id(%{"account_id" => account_id}), do: normalize_workspace_id(account_id)
  defp parse_workspace_id(%{account_id: account_id}), do: normalize_workspace_id(account_id)
  defp parse_workspace_id(_), do: {:error, :missing_workspace_id}

  # Accept "new" for creating new workspaces
  defp normalize_workspace_id("new"), do: {:ok, "new"}

  defp normalize_workspace_id(workspace_id) when is_integer(workspace_id) and workspace_id > 0 do
    {:ok, workspace_id}
  end

  defp normalize_workspace_id(workspace_id) when is_binary(workspace_id) do
    case Integer.parse(workspace_id) do
      {value, ""} when value > 0 -> {:ok, value}
      _ -> {:error, :invalid_workspace_id}
    end
  end

  defp normalize_workspace_id(_), do: {:error, :invalid_workspace_id}
end
