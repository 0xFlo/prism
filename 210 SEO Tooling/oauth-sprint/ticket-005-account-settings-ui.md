# Ticket-005: Account Settings LiveView UI

## Status: TODO
**Priority:** P1
**Estimate:** 1 hour
**Dependencies:** ticket-002 (Auth context), ticket-003 (GoogleAuth)
**Blocks:** User testing

## Problem Statement
Need user interface to:
- Display all GSC accounts (Scrapfly, Alba)
- Show authentication status for each account
- Allow connecting Google accounts via OAuth
- Allow disconnecting OAuth accounts
- Respect current_scope contract throughout

Requirements:
- Pattern-match current_scope in mount
- Pass current_scope to all context functions
- Wrap template in Layouts.app
- NO emoji (ASCII only)

## Acceptance Criteria
- [ ] Lists all GSC accounts with status
- [ ] Shows "Connect Google Account" for unconfigured accounts
- [ ] Shows connected email for OAuth accounts
- [ ] Shows "Using Service Account" for JWT accounts
- [ ] Disconnect button with confirmation dialog
- [ ] current_scope passed to all Auth calls
- [ ] Template wrapped in Layouts.app
- [ ] Flash messages for success/error
- [ ] No emoji characters in UI

## Implementation Plan

### 1. Create LiveView Module

File: `lib/gsc_analytics_web/live/account_settings_live.ex`

```elixir
defmodule GscAnalyticsWeb.AccountSettingsLive do
  use GscAnalyticsWeb, :live_view
  alias GscAnalyticsWeb.Layouts
  alias GscAnalytics.{Accounts, Auth}

  @impl true
  def render(assigns)

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: current_scope}} = socket)

  @impl true
  def handle_event("disconnect", %{"account-id" => account_id}, socket)

  defp load_accounts_with_oauth_status(current_scope)
end
```

### 2. Mount Implementation

```elixir
def mount(_params, _session, %{assigns: %{current_scope: current_scope}} = socket) do
  accounts = load_accounts_with_oauth_status(current_scope)
  {:ok, assign(socket, accounts: accounts)}
end

defp load_accounts_with_oauth_status(current_scope) do
  Accounts.list_gsc_accounts()
  |> Enum.map(fn account ->
    oauth_email =
      # Pass current_scope to Auth function!
      case Auth.get_oauth_token(current_scope, account.id) do
        {:ok, token} -> token.google_email
        _ -> nil
      end

    Map.put(account, :oauth_email, oauth_email)
  end)
end
```

### 3. Template Structure (NO EMOJI!)

```heex
<Layouts.app flash={@flash} current_scope={@current_scope}>
  <div class="max-w-4xl mx-auto py-8">
    <h1 class="text-3xl font-bold mb-6">GSC Account Settings</h1>

    <div class="space-y-6">
      <div :for={account <- @accounts} class="bg-white shadow rounded-lg p-6">
        <div class="flex justify-between items-start">
          <div>
            <h2 class="text-xl font-semibold"><%= account.name %></h2>
            <p class="text-sm text-gray-500">Account <%= account.id %></p>
          </div>

          <!-- OAuth Connected -->
          <div :if={account.oauth_email} class="text-right">
            <p class="text-sm text-green-600">
              Connected to: <span class="font-medium"><%= account.oauth_email %></span>
            </p>
            <button
              phx-click="disconnect"
              phx-value-account-id={account.id}
              class="mt-2 text-sm text-red-600 hover:text-red-800"
              data-confirm="Are you sure you want to disconnect this account?"
            >
              Disconnect
            </button>
          </div>

          <!-- No Auth Configured -->
          <div :if={!account.oauth_email && is_nil(account.service_account_file)}>
            <.link
              href={~p"/auth/google?account_id=#{account.id}"}
              class="inline-flex items-center px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700"
            >
              Connect Google Account
            </.link>
          </div>

          <!-- Service Account -->
          <div :if={account.service_account_file}>
            <p class="text-sm text-gray-600">
              Using Service Account (JWT)
            </p>
          </div>
        </div>
      </div>
    </div>
  </div>
</Layouts.app>
```

### 4. Disconnect Handler

```elixir
@impl true
def handle_event("disconnect", %{"account-id" => account_id}, socket) do
  account_id = String.to_integer(account_id)
  current_scope = socket.assigns.current_scope

  # Pass current_scope to Auth function!
  case Auth.disconnect_oauth_account(current_scope, account_id) do
    {:ok, _} ->
      socket =
        socket
        |> put_flash(:info, "Google account disconnected successfully")
        |> assign(:accounts, load_accounts_with_oauth_status(current_scope))

      {:noreply, socket}

    {:error, reason} ->
      {:noreply, put_flash(socket, :error, "Failed to disconnect: #{inspect(reason)}")}
  end
end
```

### 5. Add Route

In router.ex, inside authenticated live_session:

```elixir
live "/accounts", AccountSettingsLive, :index
```

## UI/UX Guidelines
- Clean card layout for each account
- Clear visual distinction between auth types
- Confirmation dialog for disconnect action
- Success/error flash messages
- Accessible button styles
- Mobile responsive layout

## Testing Checklist
- [ ] All accounts displayed correctly
- [ ] Service account shows JWT indicator
- [ ] Unconnected account shows Connect button
- [ ] Connected OAuth shows email address
- [ ] Connect button navigates to OAuth flow
- [ ] Disconnect removes OAuth token
- [ ] Flash messages display properly
- [ ] current_scope passed correctly

## Edge Cases
- [ ] Account with both service account AND OAuth (show OAuth)
- [ ] Failed disconnect (network/database error)
- [ ] Race condition during disconnect
- [ ] Invalid account_id in disconnect event

## Security Notes
- Disconnect requires confirmation dialog
- Account ID passed as string, parsed to integer
- current_scope ensures user authorization
- No sensitive tokens displayed in UI

## Success Metrics
- User can see all account statuses at a glance
- OAuth connection process is clear
- Disconnect process requires confirmation
- No errors during normal operation