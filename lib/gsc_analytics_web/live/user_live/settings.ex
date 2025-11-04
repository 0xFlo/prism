defmodule GscAnalyticsWeb.UserLive.Settings do
  use GscAnalyticsWeb, :live_view

  on_mount {GscAnalyticsWeb.UserAuth, :require_sudo_mode}

  alias GscAnalytics.{Accounts, Auth, Workspaces}
  alias GscAnalyticsWeb.Live.AccountHelpers

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_account={@current_account}
      current_account_id={@current_account_id}
      account_options={@account_options}
      current_property={@current_property}
      current_property_id={@current_property_id}
      property_options={@property_options}
    >
      <div class="space-y-10">
        <!-- User Account Section -->
        <section>
          <div class="mb-6">
            <h2 class="text-2xl font-semibold text-gray-900">User Account</h2>
            <p class="mt-1 text-sm text-gray-600">Manage your email and password</p>
          </div>

          <.form
            for={@email_form}
            id="email_form"
            phx-submit="update_email"
            phx-change="validate_email"
          >
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
        </section>
        <!-- Workspace Connections Section -->
        <section id="connections">
          <div class="mb-6 flex items-center justify-between">
            <div>
              <h2 class="text-2xl font-semibold text-gray-900">Workspace Connections</h2>
              <p class="mt-1 text-sm text-gray-600">
                Manage your connected Google accounts. Add more workspaces, reconnect existing accounts, or remove connections.
              </p>
            </div>
            <.link
              href={~p"/auth/google?#{[workspace_id: "new"]}"}
              class="inline-flex items-center gap-2 rounded-md bg-indigo-600 px-4 py-2 text-sm font-semibold text-white shadow-sm transition hover:bg-indigo-700"
            >
              <svg
                class="h-4 w-4"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
                xmlns="http://www.w3.org/2000/svg"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M12 4v16m8-8H4"
                >
                </path>
              </svg>
              Add Workspace
            </.link>
          </div>
          <%= if Enum.any?(@accounts, &(account_requires_action?(&1))) do %>
            <div class="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-700">
              <p class="font-medium">Action required</p>
              <p class="mt-1">
                At least one workspace still needs credentials or a default property. Connect a Google login and pick the Search Console property you plan to sync.
              </p>
            </div>
          <% end %>

          <div class="space-y-6">
            <%= for account <- @accounts do %>
              <div class="rounded-lg border border-gray-200 bg-white shadow-sm">
                <div class="border-b border-gray-100 px-6 py-3">
                  <div class="flex items-center justify-between">
                    <div class="flex items-center gap-3">
                      <h3 class="text-lg font-semibold text-gray-900">
                        <%= if account.oauth do %>
                          {account.oauth.google_email}
                        <% else %>
                          Workspace {account.id}
                        <% end %>
                      </h3>
                      <%= if account.oauth do %>
                        <span class="inline-flex items-center gap-1.5 rounded-full bg-green-100 px-2.5 py-0.5 text-xs font-medium text-green-700">
                          <svg class="h-3 w-3" fill="currentColor" viewBox="0 0 20 20">
                            <path
                              fill-rule="evenodd"
                              d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"
                              clip-rule="evenodd"
                            />
                          </svg>
                          Connected
                        </span>
                      <% else %>
                        <span class="inline-flex items-center rounded-full bg-red-100 px-2.5 py-0.5 text-xs font-medium text-red-700">
                          Not connected
                        </span>
                      <% end %>
                    </div>
                  </div>
                </div>

                <div class="grid gap-6 p-6 md:grid-cols-[minmax(0,1fr)_auto] md:items-start">
                  <div class="space-y-4 text-sm text-gray-700">
                    <%= if account.property_required? do %>
                      <div class="rounded-md border border-amber-200 bg-amber-50 p-3 text-sm text-amber-800">
                        <p class="font-medium">Properties required</p>
                        <p class="mt-1 text-xs">
                          Add and activate at least one Search Console property below to enable sync.
                        </p>
                      </div>
                    <% end %>

                    <%= if account.property_options_error do %>
                      <div class="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-700">
                        {account.property_options_error}
                      </div>
                    <% end %>

                    <.property_controls account={account} />
                  </div>

                  <div class="flex flex-col md:flex-row items-stretch md:items-center gap-2">
                    <%= if account.oauth do %>
                      <.link
                        href={~p"/auth/google?#{[workspace_id: account.id]}"}
                        class="inline-flex items-center justify-center gap-2 rounded-md bg-blue-600 px-3 py-2 text-sm font-semibold text-white shadow-sm transition hover:bg-blue-700"
                      >
                        <svg class="h-4 w-4" fill="currentColor" viewBox="0 0 24 24">
                          <path d="M12.48 10.92v3.28h7.84c-.24 1.84-.853 3.187-1.787 4.133-1.147 1.147-2.933 2.4-6.053 2.4-4.827 0-8.6-3.893-8.6-8.72s3.773-8.72 8.6-8.72c2.6 0 4.507 1.027 5.907 2.347l2.307-2.307C18.747 1.44 16.133 0 12.48 0 5.867 0 .307 5.387.307 12s5.56 12 12.173 12c3.573 0 6.267-1.173 8.373-3.36 2.16-2.16 2.84-5.213 2.84-7.667 0-.76-.053-1.467-.173-2.053H12.48z" />
                        </svg>
                        Change
                      </.link>
                      <button
                        type="button"
                        class="inline-flex items-center justify-center rounded-md border border-gray-300 bg-white px-3 py-2 text-sm font-medium text-gray-700 shadow-sm transition hover:bg-gray-50"
                        phx-click="disconnect_oauth"
                        phx-value-workspace-id={account.id}
                        data-confirm="Disconnect this Google account?"
                      >
                        Disconnect
                      </button>
                      <button
                        type="button"
                        class="inline-flex items-center justify-center rounded-md border border-red-300 bg-white px-3 py-2 text-sm font-medium text-red-700 shadow-sm transition hover:bg-red-50"
                        phx-click="remove_workspace"
                        phx-value-workspace-id={account.id}
                        data-confirm="Remove this workspace? This will delete all associated data."
                      >
                        Remove
                      </button>
                    <% else %>
                      <.link
                        href={~p"/auth/google?#{[workspace_id: account.id]}"}
                        class="inline-flex items-center justify-center gap-2 rounded-md bg-blue-600 px-3 py-2 text-sm font-semibold text-white shadow-sm transition hover:bg-blue-700"
                      >
                        <svg class="h-4 w-4" fill="currentColor" viewBox="0 0 24 24">
                          <path d="M12.48 10.92v3.28h7.84c-.24 1.84-.853 3.187-1.787 4.133-1.147 1.147-2.933 2.4-6.053 2.4-4.827 0-8.6-3.893-8.6-8.72s3.773-8.72 8.6-8.72c2.6 0 4.507 1.027 5.907 2.347l2.307-2.307C18.747 1.44 16.133 0 12.48 0 5.867 0 .307 5.387.307 12s5.56 12 12.173 12c3.573 0 6.267-1.173 8.373-3.36 2.16-2.16 2.84-5.213 2.84-7.667 0-.76-.053-1.467-.173-2.053H12.48z" />
                        </svg>
                        Connect Google
                      </.link>
                      <button
                        type="button"
                        class="inline-flex items-center justify-center rounded-md border border-red-300 bg-white px-3 py-2 text-sm font-medium text-red-700 shadow-sm transition hover:bg-red-50"
                        phx-click="remove_workspace"
                        phx-value-workspace-id={account.id}
                        data-confirm="Remove this workspace? This will delete all associated data."
                      >
                        Remove
                      </button>
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :account, :map, required: true

  defp property_controls(assigns) do
    account = assigns.account

    cond do
      # Show multi-property management when OAuth is connected
      account.can_manage_property? && is_nil(account.property_options_error) ->
        assigns = %{account: account}

        ~H"""
        <div class="space-y-3">
          <div class="flex items-center justify-between">
            <h4 class="text-sm font-semibold text-gray-900">
              Properties
              <%= if not Enum.empty?(@account.active_properties) do %>
                <span class="ml-1.5 text-xs font-normal text-gray-500">
                  ({length(@account.active_properties)} active)
                </span>
              <% end %>
            </h4>
          </div>

          <%= if not Enum.empty?(@account.unified_properties) do %>
            <div class="divide-y divide-gray-200">
              <%= for property <- @account.unified_properties do %>
                <div class={[
                  "flex items-center justify-between py-1.5 transition-opacity",
                  !property.is_active && "opacity-60"
                ]}>
                  <div class="flex items-center gap-3 flex-1 min-w-0">
                    <!-- Toggle Switch -->
                    <button
                      type="button"
                      phx-click="toggle_property"
                      phx-value-account_id={@account.id}
                      phx-value-property_url={property.property_url}
                      phx-value-active={if property.is_active, do: "false", else: "true"}
                      class={[
                        "relative inline-flex h-5 w-9 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-blue-600 focus:ring-offset-2",
                        property.is_active && "bg-blue-600",
                        !property.is_active && "bg-gray-200"
                      ]}
                      role="switch"
                      aria-checked={to_string(property.is_active)}
                    >
                      <span class="sr-only">Toggle {property.label}</span>
                      <span
                        aria-hidden="true"
                        class={[
                          "pointer-events-none inline-block h-4 w-4 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out",
                          property.is_active && "translate-x-4",
                          !property.is_active && "translate-x-0"
                        ]}
                      />
                    </button>

                    <div class="flex-1 min-w-0">
                      <p class="text-xs font-medium text-gray-900 truncate">
                        {property.label}
                      </p>
                      <div class="flex items-center gap-2 mt-1">
                        <%= if property[:has_api_access] == false do %>
                          <span class="inline-flex items-center rounded-full bg-orange-100 px-2 py-0.5 text-[10px] font-medium text-orange-700">
                            Historical Only
                          </span>
                        <% else %>
                          <span class="inline-flex items-center rounded-full bg-green-100 px-2 py-0.5 text-[10px] font-medium text-green-700">
                            Available
                          </span>
                        <% end %>
                        <%= if property.permission_level do %>
                          <span class="text-[10px] text-gray-500">
                            {String.capitalize(property.permission_level)} access
                          </span>
                        <% end %>
                      </div>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          <% else %>
            <p class="text-xs text-gray-500">
              No properties available. Ensure your Google account has Search Console access.
            </p>
          <% end %>
          
        <!-- Note: Legacy config-based properties are no longer shown here -->
        </div>
        """

      is_nil(account.oauth) ->
        ~H"""
        <p class="mt-4 text-xs text-gray-500">
          Connect Google to list available properties.
        </p>
        """

      true ->
        ~H""
    end
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

  def mount(params, _session, socket) do
    # Batch load properties ONCE at the top to avoid duplicate queries
    current_scope = socket.assigns.current_scope
    workspace_ids = Accounts.account_ids_for_user(current_scope.user)
    all_properties = batch_load_properties(workspace_ids)

    # Initialize account helpers (which will load properties internally, but we'll optimize this)
    {socket, _account, _property} =
      AccountHelpers.init_account_and_property_assigns(socket, params)

    user = current_scope.user
    email_changeset = Auth.change_user_email(user, %{}, validate_unique: false)
    password_changeset = Auth.change_user_password(user, %{}, hash_password: false)

    socket =
      socket
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)
      |> assign(:accounts, load_accounts(current_scope, all_properties))
      # Reload AccountHelpers state with cached properties to avoid duplicate query
      |> AccountHelpers.reload_properties_from_cache(all_properties)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # Skip reload since properties were already loaded in mount
    # This prevents duplicate queries in the same request lifecycle
    socket = AccountHelpers.assign_current_account(socket, params, skip_reload: true)
    socket = AccountHelpers.assign_current_property(socket, params, skip_reload: true)
    {:noreply, socket}
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

  def handle_event("switch_property", %{"property_id" => property_id_param}, socket) do
    socket = AccountHelpers.assign_current_property(socket, %{"property_id" => property_id_param})

    query_params =
      %{
        account_id: socket.assigns.current_account_id,
        property_id: socket.assigns.current_property_id
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.into(%{})

    {:noreply, push_patch(socket, to: ~p"/users/settings?#{query_params}")}
  end

  def handle_event("switch_property", _params, socket), do: {:noreply, socket}

  def handle_event("change_account", %{"account_id" => account_id_param}, socket) do
    socket =
      socket
      |> AccountHelpers.assign_current_account(%{"account_id" => account_id_param})
      |> AccountHelpers.assign_current_property(%{})

    query_params =
      %{
        account_id: socket.assigns.current_account_id,
        property_id: socket.assigns.current_property_id
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.into(%{})

    {:noreply, push_patch(socket, to: ~p"/users/settings?#{query_params}")}
  end

  def handle_event("change_account", _params, socket), do: {:noreply, socket}

  def handle_event(
        "save_property",
        %{"account_id" => account_id, "default_property" => property},
        socket
      ) do
    # Note: property here should be the property_id, not property_url
    case Accounts.set_active_property(account_id, property) do
      {:ok, _property} ->
        {:noreply,
         socket
         |> put_flash(:info, "Default Search Console property updated.")
         |> refresh_accounts()}

      {:error, :invalid_property} ->
        {:noreply, put_flash(socket, :error, "Pick a property from the dropdown before saving.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Could not save property: #{changeset_error_message(changeset)}")
         |> refresh_accounts()}

      {:error, :unauthorized_account} ->
        {:noreply, put_flash(socket, :error, "You are not allowed to manage that workspace.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not save property: #{inspect(reason)}")}
    end
  end

  def handle_event("save_property", _params, socket) do
    {:noreply, put_flash(socket, :error, "Missing account information. Please try again.")}
  end

  def handle_event("disconnect_oauth", %{"workspace-id" => workspace_id_param}, socket) do
    current_scope = socket.assigns.current_scope

    case parse_account_id(workspace_id_param) do
      {:ok, workspace_id} ->
        case Auth.disconnect_oauth_account(current_scope, workspace_id) do
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

  def handle_event("remove_workspace", %{"workspace-id" => workspace_id_param}, socket) do
    current_scope = socket.assigns.current_scope
    user_id = current_scope.user.id

    case parse_account_id(workspace_id_param) do
      {:ok, workspace_id} ->
        case Workspaces.fetch_workspace(user_id, workspace_id) do
          {:ok, workspace} ->
            case Workspaces.delete_workspace(workspace) do
              {:ok, _} ->
                {:noreply,
                 socket
                 |> put_flash(:info, "Workspace removed successfully.")
                 |> refresh_accounts()}

              {:error, _changeset} ->
                {:noreply,
                 put_flash(socket, :error, "Failed to remove workspace. Please try again.")}
            end

          {:error, :not_found} ->
            {:noreply,
             socket
             |> put_flash(
               :error,
               "Workspace not found or you don't have permission to remove it."
             )
             |> refresh_accounts()}
        end

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, "Invalid workspace identifier. Please refresh and try again.")}
    end
  end

  # Multi-property management event handlers

  def handle_event(
        "add_property",
        %{"account_id" => account_id_param, "property_url" => property_url} = params,
        socket
      ) do
    case parse_account_id(account_id_param) do
      {:ok, account_id} ->
        # Support both new button-based and old form-based invocations
        display_name = Map.get(params, "display_name", "")

        attrs = %{
          property_url: property_url,
          display_name: if(String.trim(display_name) == "", do: nil, else: display_name)
        }

        case Accounts.add_property(account_id, attrs) do
          {:ok, _property} ->
            {:noreply,
             socket
             |> put_flash(:info, "Property added and activated.")
             |> refresh_accounts()}

          {:error, changeset} ->
            {:noreply,
             socket
             |> put_flash(:error, "Could not add property: #{changeset_error_message(changeset)}")
             |> refresh_accounts()}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Invalid account identifier.")}
    end
  end

  def handle_event(
        "toggle_property_active",
        %{
          "account_id" => account_id_param,
          "property_id" => property_id,
          "active" => desired_state
        },
        socket
      ) do
    case parse_account_id(account_id_param) do
      {:ok, account_id} ->
        normalized_state = desired_state |> to_string() |> String.downcase()
        active? = normalized_state in ["true", "on", "1"]

        case Accounts.update_property_active(account_id, property_id, active?) do
          {:ok, _property} ->
            message = if active?, do: "Property activated.", else: "Property deactivated."

            {:noreply,
             socket
             |> put_flash(:info, message)
             |> refresh_accounts()}

          {:error, :not_found} ->
            {:noreply,
             socket
             |> put_flash(:error, "Property not found.")
             |> refresh_accounts()}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Could not update property: #{inspect(reason)}")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Invalid account identifier.")}
    end
  end

  def handle_event(
        "remove_property",
        %{"account_id" => account_id_param, "property_id" => property_id},
        socket
      ) do
    case parse_account_id(account_id_param) do
      {:ok, account_id} ->
        case Accounts.remove_property(account_id, property_id) do
          {:ok, _property} ->
            {:noreply,
             socket
             |> put_flash(:info, "Property removed.")
             |> refresh_accounts()}

          {:error, :not_found} ->
            {:noreply,
             socket
             |> put_flash(:info, "Property was already removed.")
             |> refresh_accounts()}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Could not remove property: #{inspect(reason)}")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Invalid account identifier.")}
    end
  end

  def handle_event(
        "toggle_property",
        %{
          "account_id" => account_id_param,
          "property_url" => property_url,
          "active" => desired_state
        },
        socket
      ) do
    case parse_account_id(account_id_param) do
      {:ok, account_id} ->
        normalized_state = desired_state |> to_string() |> String.downcase()
        active? = normalized_state in ["true", "on", "1"]

        # Check if property already exists
        case Accounts.get_property_by_url(account_id, property_url) do
          nil ->
            # Property doesn't exist - add it with the desired active state
            attrs = %{property_url: property_url, is_active: active?}

            case Accounts.add_property(account_id, attrs) do
              {:ok, _property} ->
                message =
                  if active?,
                    do: "Property added and activated.",
                    else: "Property added (inactive)."

                {:noreply,
                 socket
                 |> put_flash(:info, message)
                 |> refresh_accounts()}

              {:error, changeset} ->
                {:noreply,
                 socket
                 |> put_flash(
                   :error,
                   "Could not add property: #{changeset_error_message(changeset)}"
                 )
                 |> refresh_accounts()}
            end

          property ->
            # Property exists - update its active state
            case Accounts.update_property_active(account_id, property.id, active?) do
              {:ok, _property} ->
                message = if active?, do: "Property activated.", else: "Property deactivated."

                {:noreply,
                 socket
                 |> put_flash(:info, message)
                 |> refresh_accounts()}

              {:error, reason} ->
                {:noreply,
                 put_flash(socket, :error, "Could not update property: #{inspect(reason)}")}
            end
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Invalid account identifier.")}
    end
  end

  # Batch loading helpers to prevent N+1 queries

  defp batch_load_oauth_tokens(workspace_ids) when is_list(workspace_ids) do
    import Ecto.Query

    alias GscAnalytics.Auth.OAuthToken
    alias GscAnalytics.Repo

    from(t in OAuthToken, where: t.account_id in ^workspace_ids)
    |> Repo.all()
    |> Enum.map(&{&1.account_id, %{google_email: &1.google_email}})
    |> Map.new()
  end

  defp batch_load_properties(workspace_ids) when is_list(workspace_ids) do
    import Ecto.Query

    alias GscAnalytics.Schemas.WorkspaceProperty
    alias GscAnalytics.Repo

    from(p in WorkspaceProperty,
      where: p.workspace_id in ^workspace_ids,
      order_by: [desc: p.is_active, asc: p.display_name]
    )
    |> Repo.all()
    |> Enum.group_by(& &1.workspace_id)
  end

  @spec load_accounts(Auth.Scope.t(), map() | nil) :: [map()]
  defp load_accounts(%Auth.Scope{} = current_scope, preloaded_properties) do
    # Load workspaces from database instead of config
    user_id = current_scope.user.id
    workspaces = Workspaces.list_workspaces(user_id)

    # Batch load all OAuth tokens in a single query
    workspace_ids = Enum.map(workspaces, & &1.id)
    oauth_tokens = batch_load_oauth_tokens(workspace_ids)

    # Use preloaded properties if provided, otherwise batch load
    all_properties =
      case preloaded_properties do
        %{} = properties -> properties
        _ -> batch_load_properties(workspace_ids)
      end

    Enum.map(workspaces, fn account ->
      oauth = Map.get(oauth_tokens, account.id)

      # Get preloaded properties for this account to pass to list_property_options
      saved_properties_for_account = Map.get(all_properties, account.id, [])

      {property_options, property_options_error} =
        if oauth do
          case Accounts.list_property_options(
                 current_scope,
                 account.id,
                 saved_properties_for_account
               ) do
            {:ok, options} ->
              {ensure_included_property(options, account.default_property), nil}

            {:error, reason} ->
              {[], translate_property_error(reason)}
          end
        else
          {[], nil}
        end

      property_label = property_display_label(account.default_property, property_options)

      # Use preloaded properties from batch load
      saved_properties = Map.get(all_properties, account.id, [])
      active_properties = Enum.filter(saved_properties, & &1.is_active)
      active_property = List.first(active_properties)

      # Create a unified property list by merging API properties with saved properties
      saved_by_url = Map.new(saved_properties, fn prop -> {prop.property_url, prop} end)

      unified_properties =
        property_options
        |> Enum.map(fn opt ->
          saved_prop = Map.get(saved_by_url, opt.value)

          %{
            property_url: opt.value,
            label: opt.label,
            permission_level: opt[:permission_level],
            has_api_access: opt[:has_api_access],
            is_saved: not is_nil(saved_prop),
            is_active: if(saved_prop, do: saved_prop.is_active, else: false),
            property_id: if(saved_prop, do: saved_prop.id, else: nil)
          }
        end)
        |> Enum.sort_by(fn prop ->
          # Sort alphabetically by label for stable ordering (no jumping on toggle)
          String.downcase(prop.label || prop.property_url)
        end)

      %{
        id: account.id,
        display_name: account.name,
        oauth: oauth,
        default_property: account.default_property,
        property_options: property_options,
        property_options_error: property_options_error,
        property_label: property_label,
        property_required?: is_nil(account.default_property) && Enum.empty?(active_properties),
        can_manage_property?: not is_nil(oauth),
        property_form: to_form(%{"default_property" => account.default_property || ""}),
        # Multi-property support
        saved_properties: saved_properties,
        active_property: active_property,
        active_properties: active_properties,
        # Unified property list for toggle UI
        unified_properties: unified_properties
      }
    end)
  end

  defp refresh_accounts(socket) do
    # Batch load properties ONCE to avoid duplicate queries
    current_scope = socket.assigns.current_scope
    workspace_ids = Accounts.account_ids_for_user(current_scope.user)
    all_properties = batch_load_properties(workspace_ids)

    socket
    |> assign(:accounts, load_accounts(current_scope, all_properties))
    |> AccountHelpers.reload_properties_from_cache(all_properties)
  end

  defp ensure_included_property(options, property) do
    case property do
      nil ->
        options

      value when is_binary(value) ->
        trimmed = String.trim(value)

        if trimmed == "" or Enum.any?(options, &(&1.value == trimmed)) do
          options
        else
          [
            %{value: trimmed, label: format_property_label(trimmed), permission_level: nil}
            | options
          ]
        end

      _ ->
        options
    end
  end

  defp property_display_label(nil, _options), do: nil

  defp property_display_label(property, options) when is_binary(property) do
    trimmed = String.trim(property)

    options
    |> Enum.find(&(to_string(&1.value) == trimmed))
    |> case do
      %{label: label} when is_binary(label) and label != "" ->
        label

      _ ->
        format_property_label(trimmed)
    end
  end

  defp property_display_label(_property, _options), do: nil

  defp parse_account_id(account_id) when is_integer(account_id) and account_id > 0,
    do: {:ok, account_id}

  defp parse_account_id(account_id) when is_binary(account_id) do
    case Integer.parse(account_id) do
      {value, ""} when value > 0 -> {:ok, value}
      _ -> {:error, :invalid_account_id}
    end
  end

  defp parse_account_id(_), do: {:error, :invalid_account_id}

  defp account_requires_action?(%{oauth: nil}), do: true
  defp account_requires_action?(%{property_required?: true}), do: true
  defp account_requires_action?(_), do: false

  defp translate_property_error(:invalid_account_id),
    do: "Pick a valid workspace before loading properties."

  defp translate_property_error(:unauthorized_account),
    do: "You are not allowed to manage that workspace."

  defp translate_property_error(reason),
    do: "Could not load properties: #{inspect(reason)}"

  defp format_property_label("sc-domain:" <> rest), do: "Domain: #{rest}"

  defp format_property_label(property) when is_binary(property) do
    case URI.parse(property) do
      %URI{scheme: scheme, host: host, path: path} when is_binary(host) ->
        base = "#{scheme}://#{host}"
        if path in [nil, "", "/"], do: base, else: base <> path

      _ ->
        property
    end
  end

  defp format_property_label(property), do: to_string(property)

  defp changeset_error_message(%Ecto.Changeset{} = changeset) do
    changeset.errors
    |> Enum.map(fn {field, {message, _}} -> "#{field} #{message}" end)
    |> Enum.join(", ")
  end
end
