defmodule GscAnalyticsWeb.UserLive.Settings do
  use GscAnalyticsWeb, :live_view

  on_mount {GscAnalyticsWeb.UserAuth, :require_sudo_mode}

  alias GscAnalytics.{Accounts, Auth}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="text-center">
        <.header>
          Account Settings
          <:subtitle>Manage your account email address and password settings</:subtitle>
        </.header>
      </div>

      <.form for={@email_form} id="email_form" phx-submit="update_email" phx-change="validate_email">
        <.input
          field={@email_form[:email]}
          type="email"
          label="Email"
          autocomplete="username"
          required
        />
        <.button variant="primary" phx-disable-with="Changing...">Change Email</.button>
      </.form>

      <div class="divider" />

      <.form
        for={@password_form}
        id="password_form"
        action={~p"/users/update-password"}
        method="post"
        phx-change="validate_password"
        phx-submit="update_password"
        phx-trigger-action={@trigger_submit}
      >
        <input
          name={@password_form[:email].name}
          type="hidden"
          id="hidden_user_email"
          autocomplete="username"
          value={@current_email}
        />
        <.input
          field={@password_form[:password]}
          type="password"
          label="New password"
          autocomplete="new-password"
          required
        />
        <.input
          field={@password_form[:password_confirmation]}
          type="password"
          label="Confirm new password"
          autocomplete="new-password"
        />
        <.button variant="primary" phx-disable-with="Saving...">
          Save Password
        </.button>
      </.form>

      <div id="connections" class="mt-12 space-y-6">
        <div class="text-center md:text-left">
          <h2 class="text-2xl font-semibold text-gray-900">Search Console Connections</h2>
          <p class="mt-2 text-sm text-gray-600">
            Connect whichever Google login owns the Search Console properties you plan to sync. Each workspace can use a personal connection or fall back to its built-in service account when available.
          </p>
        </div>

        <%= if Enum.any?(@accounts, &(account_requires_action?(&1))) do %>
          <div class="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-700">
            <p class="font-medium">Action required</p>
            <p class="mt-1">
              At least one workspace has no service-account fallback. Connect a Google login that can access the relevant Search Console properties.
            </p>
          </div>
        <% end %>

        <div class="space-y-6">
          <%= for account <- @accounts do %>
            <div class="rounded-lg border border-gray-200 bg-white shadow-sm">
              <div class="flex flex-col gap-4 border-b border-gray-100 p-6 md:flex-row md:items-center md:justify-between">
                <div>
                  <h3 class="text-lg font-semibold text-gray-900">{account.display_name}</h3>
                  <p class="text-sm text-gray-500">Workspace ID {account.id}</p>
                </div>

                <div>
                  <%= cond do %>
                    <% account.oauth -> %>
                      <span class="inline-flex items-center rounded-full bg-green-100 px-3 py-1 text-sm font-semibold text-green-700">
                        Connected
                      </span>
                    <% account.requires_oauth? -> %>
                      <span class="inline-flex items-center rounded-full bg-red-100 px-3 py-1 text-sm font-semibold text-red-700">
                        Needs connection
                      </span>
                    <% true -> %>
                      <span class="inline-flex items-center rounded-full bg-gray-100 px-3 py-1 text-sm font-semibold text-gray-700">
                        Using service account
                      </span>
                  <% end %>
                </div>
              </div>

              <div class="grid gap-6 p-6 md:grid-cols-[minmax(0,1fr)_auto] md:items-center">
                <div class="space-y-3 text-sm text-gray-700">
                  <%= if account.oauth do %>
                    <p>
                      Connected as <span class="font-semibold"><%= account.oauth.google_email %></span>.
                      Access tokens refresh automatically every hour.
                    </p>
                    <%= if account.service_account? do %>
                      <p class="text-xs text-gray-500">
                        The built-in service account remains available as a fallback if you disconnect.
                      </p>
                    <% end %>
                  <% else %>
                    <%= if account.requires_oauth? do %>
                      <p class="font-semibold text-red-700">
                        No Google credentials are active yet. Connect a Google login that has Search Console access for this workspace.
                      </p>
                    <% else %>
                      <p>
                        Currently using the built-in service account. Connect a Google login if you prefer to manage credentials directly.
                      </p>
                    <% end %>
                  <% end %>

                  <%= if account.default_property do %>
                    <p class="text-xs text-gray-500">
                      Default Search Console property:
                      <code class="rounded bg-gray-100 px-1 py-0.5 text-xs text-gray-600"><%= account.default_property %></code>
                    </p>
                  <% end %>

                  <%= if account.service_account? && !account.requires_oauth? do %>
                    <p class="text-xs text-gray-500">
                      Service account path:
                      <code class="rounded bg-gray-100 px-1 py-0.5 text-xs text-gray-600">
                        <%= display_service_account_path(account) %>
                      </code>
                    </p>
                  <% end %>
                </div>

                <div class="flex flex-col items-stretch gap-3 md:items-end">
                  <%= if account.oauth do %>
                    <button
                      type="button"
                      class="inline-flex items-center justify-center rounded-md border border-gray-200 px-4 py-2 text-sm font-semibold text-gray-700 shadow-sm transition hover:border-gray-300 hover:text-gray-900 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-600"
                      phx-click="disconnect_oauth"
                      phx-value-account-id={account.id}
                      data-confirm="Disconnect this Google account?"
                    >
                      Disconnect
                    </button>
                    <.link
                      href={~p"/auth/google?#{[account_id: account.id]}"}
                      class="inline-flex items-center justify-center rounded-md bg-blue-600 px-4 py-2 text-sm font-semibold text-white shadow-sm transition hover:bg-blue-700 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-600"
                    >
                      Replace Google Account
                    </.link>
                  <% else %>
                    <.link
                      href={~p"/auth/google?#{[account_id: account.id]}"}
                      class={
                        connect_button_classes(account.requires_oauth?)
                      }
                    >
                      Connect Google Account
                    </.link>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Auth.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, "Email changed successfully.")

        {:error, _} ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Auth.change_user_email(user, %{}, validate_unique: false)
    password_changeset = Auth.change_user_password(user, %{}, hash_password: false)

    socket =
      socket
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)
      |> assign(:accounts, load_accounts(socket.assigns.current_scope))

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_scope.user
      |> Auth.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Auth.sudo_mode?(user)

    case Auth.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Auth.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        info = "A link to confirm your email change has been sent to the new address."
        {:noreply, socket |> put_flash(:info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"user" => user_params} = params

    password_form =
      socket.assigns.current_scope.user
      |> Auth.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Auth.sudo_mode?(user)

    case Auth.change_user_password(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end

  def handle_event("disconnect_oauth", %{"account-id" => account_id_param}, socket) do
    current_scope = socket.assigns.current_scope

    case parse_account_id(account_id_param) do
      {:ok, account_id} ->
        case Auth.disconnect_oauth_account(current_scope, account_id) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Google account disconnected successfully.")
             |> refresh_accounts()}

          {:error, :not_found} ->
            {:noreply,
             socket
             |> put_flash(:info, "No Google account was connected for that entry.")
             |> refresh_accounts()}

          {:error, :unauthorized_account} ->
            {:noreply,
             socket
             |> put_flash(:error, "You are not authorized to manage that account.")}

          {:error, reason} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "Failed to disconnect Google account: #{inspect(reason)}"
             )}
        end

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, "Invalid account identifier. Please refresh and try again.")}
    end
  end

  defp load_accounts(%Auth.Scope{} = current_scope) do
    Accounts.list_gsc_accounts(current_scope)
    |> Enum.map(fn account ->
      service_account? = service_account_configured?(account.service_account_file)
      oauth =
        case Auth.get_oauth_token(current_scope, account.id) do
          {:ok, token} -> %{google_email: token.google_email}
          _ -> nil
        end

      %{
        id: account.id,
        name: account.name,
        display_name: display_name(account.name, account.id),
        oauth: oauth,
        service_account?: service_account?,
        requires_oauth?: not service_account?,
        service_account_file: account.service_account_file,
        default_property: fetch_default_property(current_scope, account.id)
      }
    end)
  end

  defp load_accounts(_), do: []

  defp refresh_accounts(socket) do
    assign(socket, :accounts, load_accounts(socket.assigns.current_scope))
  end

  defp parse_account_id(account_id) when is_integer(account_id) and account_id > 0,
    do: {:ok, account_id}

  defp parse_account_id(account_id) when is_binary(account_id) do
    case Integer.parse(account_id) do
      {value, ""} when value > 0 -> {:ok, value}
      _ -> {:error, :invalid_account_id}
    end
  end

  defp parse_account_id(_), do: {:error, :invalid_account_id}

  defp service_account_configured?(nil), do: false
  defp service_account_configured?(path) when is_binary(path), do: String.trim(path) != ""
  defp service_account_configured?(_), do: false

  defp display_service_account_path(%{service_account_file: nil}), do: "n/a"
  defp display_service_account_path(%{service_account_file: path}) when is_binary(path), do: path
  defp display_service_account_path(_), do: "n/a"

  defp connect_button_classes(true) do
    "inline-flex items-center justify-center rounded-md bg-red-600 px-4 py-2 text-sm font-semibold text-white shadow-sm transition hover:bg-red-700 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-600"
  end

  defp connect_button_classes(false) do
    "inline-flex items-center justify-center rounded-md bg-blue-600 px-4 py-2 text-sm font-semibold text-white shadow-sm transition hover:bg-blue-700 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-600"
  end

  defp account_requires_action?(%{requires_oauth?: true, oauth: nil}), do: true
  defp account_requires_action?(_), do: false

  defp display_name(name, id) when is_binary(name) do
    case String.trim(name) do
      "" -> "Workspace #{id}"
      trimmed -> trimmed
    end
  end

  defp display_name(_name, id), do: "Workspace #{id}"

  defp fetch_default_property(current_scope, account_id) do
    case Accounts.gsc_default_property(current_scope, account_id) do
      {:ok, property} when is_binary(property) and property != "" -> property
      _ -> nil
    end
  end
end
