defmodule GscAnalyticsWeb.GoogleAuthController do
  use GscAnalyticsWeb, :controller

  alias GscAnalyticsWeb.GoogleAuth

  def request(conn, params) do
    case parse_account_id(params) do
      {:ok, account_id} ->
        GoogleAuth.request(conn, account_id)

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Invalid account identifier.")
        |> redirect(to: ~p"/accounts")
    end
  end

  def callback(conn, params) do
    GoogleAuth.callback(conn, params)
  end

  defp parse_account_id(%{"account_id" => account_id}), do: normalize_account_id(account_id)
  defp parse_account_id(%{account_id: account_id}), do: normalize_account_id(account_id)
  defp parse_account_id(_), do: {:error, :missing_account_id}

  defp normalize_account_id(account_id) when is_integer(account_id) and account_id > 0 do
    {:ok, account_id}
  end

  defp normalize_account_id(account_id) when is_binary(account_id) do
    case Integer.parse(account_id) do
      {value, ""} when value > 0 -> {:ok, value}
      _ -> {:error, :invalid_account_id}
    end
  end

  defp normalize_account_id(_), do: {:error, :invalid_account_id}
end
