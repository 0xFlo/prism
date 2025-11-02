# Ticket-004: Settings LiveView Property Picker UX

## Status: TODO
**Priority:** P1
**Estimate:** 1 day
**Dependencies:** ticket-003
**Blocks:** ticket-007

## Problem Statement
The current settings page (UserLive.Settings) shows account connections but only allows selecting one default property via a simple dropdown. We need a richer UX that manages multiple properties with add/remove/activate capabilities while maintaining the existing user settings (email/password) functionality.

## Acceptance Criteria
- [ ] Display list of saved properties with active property highlighted
- [ ] Users can add properties from available GSC list
- [ ] Users can remove saved properties
- [ ] Users can set any saved property as active
- [ ] Empty state when no properties configured with helpful guidance
- [ ] All interactions via LiveView events (no page reload)
- [ ] Maintain existing email/password settings functionality

## Implementation Plan

### 1. Update Settings LiveView

**Note:** The existing settings LiveView at `/lib/gsc_analytics_web/live/user_live/settings.ex` already has account connection UI. We need to extend it for multi-property management.

```elixir
# lib/gsc_analytics_web/live/user_live/settings.ex

def mount(_params, _session, socket) do
  # Existing mount logic...

  # Load properties for each account
  accounts_with_properties =
    socket.assigns.accounts
    |> Enum.map(fn account ->
      properties = Accounts.list_properties(account.id)
      Map.put(account, :properties, properties)
    end)

  {:ok,
   socket
   |> assign(:accounts, accounts_with_properties)
   |> assign(:show_property_modal, false)
   |> assign(:modal_account_id, nil)
   |> assign(:available_properties, [])}
end

# Event handlers for property management
def handle_event("show_add_property", %{"account_id" => account_id}, socket) do
  account_id = String.to_integer(account_id)

  # Fetch available properties from GSC API
  case Accounts.list_property_options(socket.assigns.current_scope, account_id) do
    {:ok, properties} ->
      {:noreply,
       socket
       |> assign(:show_property_modal, true)
       |> assign(:modal_account_id, account_id)
       |> assign(:available_properties, properties)}

    {:error, _reason} ->
      {:noreply, put_flash(socket, :error, "Failed to fetch available properties")}
  end
end

def handle_event("add_property", %{"property_url" => url, "display_name" => name}, socket) do
  account_id = socket.assigns.modal_account_id
  attrs = %{property_url: url, display_name: name}

  case Accounts.add_property(account_id, attrs) do
    {:ok, _property} ->
      # Reload account properties
      accounts_with_properties = reload_accounts_with_properties(socket)

      {:noreply,
       socket
       |> assign(:accounts, accounts_with_properties)
       |> assign(:show_property_modal, false)
       |> put_flash(:info, "Property added successfully")}

    {:error, changeset} ->
      {:noreply, put_flash(socket, :error, format_errors(changeset))}
  end
end

def handle_event("set_active_property", %{"account_id" => account_id, "property_id" => property_id}, socket) do
  account_id = String.to_integer(account_id)

  case Accounts.set_active_property(account_id, property_id) do
    {:ok, _property} ->
      accounts_with_properties = reload_accounts_with_properties(socket)

      {:noreply,
       socket
       |> assign(:accounts, accounts_with_properties)
       |> put_flash(:info, "Active property updated")}

    {:error, _reason} ->
      {:noreply, put_flash(socket, :error, "Failed to update property")}
  end
end

def handle_event("remove_property", %{"account_id" => account_id, "property_id" => property_id}, socket) do
  account_id = String.to_integer(account_id)

  case Accounts.remove_property(account_id, property_id) do
    {:ok, _} ->
      accounts_with_properties = reload_accounts_with_properties(socket)

      {:noreply,
       socket
       |> assign(:accounts, accounts_with_properties)
       |> put_flash(:info, "Property removed")}

    {:error, :not_found} ->
      {:noreply, put_flash(socket, :error, "Property not found")}
  end
end

defp reload_accounts_with_properties(socket) do
  Accounts.list_gsc_accounts(socket.assigns.current_scope)
  |> Enum.map(fn account ->
    properties = Accounts.list_properties(account.id)
    Map.put(account, :properties, properties)
  end)
end
```

### 2. Update Settings Template

Extend the existing template to show properties for each workspace:

```heex
<!-- In the existing Search Console Connections section -->
<%= for account <- @accounts do %>
  <div class="rounded-lg border border-gray-200 bg-white shadow-sm">
    <!-- Existing account header... -->

    <!-- Properties section -->
    <div class="border-t border-gray-100 p-6">
      <div class="flex items-center justify-between mb-4">
        <h4 class="font-semibold text-gray-900">Search Console Properties</h4>
        <button
          phx-click="show_add_property"
          phx-value-account_id={account.id}
          class="btn-secondary text-sm">
          Add Property
        </button>
      </div>

      <%= if account.properties == [] do %>
        <div class="text-center py-8 bg-gray-50 rounded-lg">
          <p class="text-gray-600">No properties configured</p>
          <p class="text-sm text-gray-500 mt-2">
            Add a Search Console property to start tracking metrics
          </p>
        </div>
      <% else %>
        <div class="space-y-2">
          <%= for property <- account.properties do %>
            <div class="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
              <div>
                <p class="font-medium">
                  <%= property.display_name %>
                  <%= if property.is_active do %>
                    <span class="ml-2 px-2 py-1 text-xs bg-green-100 text-green-800 rounded">Active</span>
                  <% end %>
                </p>
                <p class="text-sm text-gray-600"><%= property.property_url %></p>
              </div>

              <div class="flex gap-2">
                <%= unless property.is_active do %>
                  <button
                    phx-click="set_active_property"
                    phx-value-account_id={account.id}
                    phx-value-property_id={property.id}
                    class="text-sm text-blue-600 hover:text-blue-800">
                    Set Active
                  </button>
                <% end %>

                <button
                  phx-click="remove_property"
                  phx-value-account_id={account.id}
                  phx-value-property_id={property.id}
                  phx-confirm="Are you sure you want to remove this property?"
                  class="text-sm text-red-600 hover:text-red-800">
                  Remove
                </button>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
  </div>
<% end %>

<!-- Property Selection Modal -->
<%= if @show_property_modal do %>
  <div class="fixed inset-0 bg-gray-500 bg-opacity-75 flex items-center justify-center z-50">
    <div class="bg-white rounded-lg p-6 max-w-2xl w-full max-h-[80vh] overflow-y-auto">
      <h3 class="text-lg font-semibold mb-4">Add Search Console Property</h3>

      <form phx-submit="add_property">
        <div class="space-y-4">
          <div>
            <label class="block text-sm font-medium text-gray-700">Property URL</label>
            <select name="property_url" class="mt-1 block w-full rounded-md border-gray-300">
              <%= for property <- @available_properties do %>
                <option value={property.value} disabled={property.is_saved}>
                  <%= property.label %>
                  <%= if property.is_saved do %> (Already added) <% end %>
                </option>
              <% end %>
            </select>
          </div>

          <div>
            <label class="block text-sm font-medium text-gray-700">Display Name</label>
            <input type="text" name="display_name" class="mt-1 block w-full rounded-md border-gray-300"
                   placeholder="Optional friendly name">
          </div>
        </div>

        <div class="mt-6 flex justify-end gap-3">
          <button type="button" phx-click="cancel_add_property" class="btn-secondary">
            Cancel
          </button>
          <button type="submit" class="btn-primary">
            Add Property
          </button>
        </div>
      </form>
    </div>
  </div>
<% end %>
```

### 3. CSS Classes for Property States

Add these utility classes for visual feedback:

```css
/* In app.css or component styles */
.property-card {
  @apply p-3 bg-gray-50 rounded-lg hover:bg-gray-100 transition-colors;
}

.property-active {
  @apply bg-green-50 border border-green-200;
}

.property-badge {
  @apply px-2 py-1 text-xs rounded font-medium;
}
```

## Testing Notes
- Test rendering with 0, 1, and multiple properties per account
- Test setting active property updates UI immediately
- Test removing active property handles gracefully (warn user)
- Test duplicate property URLs show error message
- Test modal interactions and form validation
- Verify existing email/password settings continue working
- Test with multiple workspaces/accounts

## UI/UX Considerations
- Show clear visual distinction for active property
- Confirm before removing properties (especially active ones)
- Display helpful empty states with next steps
- Show loading states during API calls
- Group properties by workspace clearly
- Consider pagination if many properties (future enhancement)