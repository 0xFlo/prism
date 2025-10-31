defmodule GscAnalyticsWeb.AccountSettingsLive do
  use GscAnalyticsWeb, :live_view

  alias GscAnalytics.Accounts
  alias GscAnalytics.Auth
  alias GscAnalytics.Auth.Scope
  alias GscAnalyticsWeb.Layouts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-4xl mx-auto py-8 space-y-6">
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-3xl font-bold text-gray-900">GSC Account Settings</h1>
            <p class="mt-2 text-sm text-gray-600">
              Manage how each Search Console account authenticates with Google.
            </p>
          </div>
        </div>

        <div class="space-y-6">
          <div
            :for={account <- @accounts}
            id={"account-#{account.id}"}
            class="rounded-lg border border-gray-200 bg-white shadow-sm"
          >
            <div class="flex flex-col gap-4 p-6 md:flex-row md:items-start md:justify-between">
              <div>
                <h2 class="text-xl font-semibold text-gray-900">{account.name}</h2>
                <p class="text-sm text-gray-500">
                  Account ID {account.id}
                </p>
              </div>

              <div class="flex flex-col items-start gap-3 text-sm md:items-end">
                <%= if account.oauth_email do %>
                  <div class="text-right">
                    <p class="font-medium text-green-700">Google OAuth Connected</p>
                    <p class="text-gray-600">
                      Email: <span class="font-medium">{account.oauth_email}</span>
                    </p>
                  </div>

                  <button
                    type="button"
                    class="text-sm font-medium text-red-600 hover:text-red-800"
                    phx-click="disconnect"
                    phx-value-account-id={account.id}
                    data-confirm="Are you sure you want to disconnect this Google account?"
                  >
                    Disconnect
                  </button>
                <% else %>
                  <%= if account.service_account_file do %>
                    <p class="text-gray-600">
                      Using configured service account credentials (JWT).
                    </p>
                  <% else %>
                    <.link
                      href={~p"/auth/google?#{[account_id: account.id]}"}
                      class="inline-flex items-center rounded-md bg-blue-600 px-4 py-2 text-sm font-semibold text-white shadow-sm transition hover:bg-blue-700 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-600"
                    >
                      Connect Google Account
                    </.link>
                  <% end %>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %Scope{} = current_scope}} = socket) do
    accounts = load_accounts_with_oauth_status(current_scope)
    {:ok, assign(socket, accounts: accounts)}
  end

  def mount(_params, _session, socket) do
    {:halt, redirect(socket, to: ~p"/users/log-in")}
  end

  @impl true
  def handle_event("disconnect", %{"account-id" => account_id_param}, socket) do
    current_scope = socket.assigns.current_scope

    case parse_account_id(account_id_param) do
      {:ok, account_id} ->
        case Auth.disconnect_oauth_account(current_scope, account_id) do
          {:ok, _} ->
            socket
            |> put_flash(:info, "Google account disconnected successfully.")
            |> refresh_accounts(current_scope)

          {:error, :not_found} ->
            socket
            |> put_flash(:info, "No Google account was connected for that entry.")
            |> refresh_accounts(current_scope)

          {:error, :unauthorized_account} ->
            {:noreply,
             put_flash(socket, :error, "You are not authorized to manage that account.")}

          {:error, reason} ->
            {:noreply,
             put_flash(socket, :error, "Failed to disconnect Google account: #{inspect(reason)}")}
        end

      {:error, _reason} ->
        {:noreply,
         put_flash(socket, :error, "Invalid account identifier. Please refresh and try again.")}
    end
  end

  defp refresh_accounts(socket, current_scope) do
    accounts = load_accounts_with_oauth_status(current_scope)
    {:noreply, assign(socket, accounts: accounts)}
  end

  defp load_accounts_with_oauth_status(%Scope{} = current_scope) do
    Accounts.list_gsc_accounts(current_scope)
    |> Enum.map(fn account ->
      oauth_email =
        case Auth.get_oauth_token(current_scope, account.id) do
          {:ok, token} -> token.google_email
          _ -> nil
        end

      Map.put(account, :oauth_email, oauth_email)
    end)
  end

  defp load_accounts_with_oauth_status(_), do: []

  defp parse_account_id(account_id) when is_integer(account_id) and account_id > 0 do
    {:ok, account_id}
  end

  defp parse_account_id(account_id) when is_binary(account_id) do
    case Integer.parse(account_id) do
      {value, ""} when value > 0 -> {:ok, value}
      _ -> {:error, :invalid_account_id}
    end
  end

  defp parse_account_id(_), do: {:error, :invalid_account_id}
end
