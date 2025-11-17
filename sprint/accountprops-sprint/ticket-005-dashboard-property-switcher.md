# Ticket-005: Dashboard Property Switcher & Context Sync

## Status: TODO
**Priority:** P1
**Estimate:** 1.5 days
**Dependencies:** ticket-003
**Blocks:** ticket-006, ticket-007

## Problem Statement
The dashboard (`DashboardLive`) and related LiveViews currently use `AccountHelpers` to switch between workspaces but assume a single default property per workspace. Users need to switch between saved properties without leaving the page, with clear indication of which property's metrics are shown.

## Acceptance Criteria
- [ ] Property dropdown in dashboard header (in addition to existing account selector)
- [ ] Changing property updates URL (`?property_id=xyz`) and refreshes data
- [ ] All queries filter by selected property
- [ ] Empty state when no active property with link to settings
- [ ] Property selection persists across page refreshes
- [ ] Integration with existing `AccountHelpers` pattern

## Implementation Plan

### 1. Extend AccountHelpers for Property Management

The existing `AccountHelpers` module handles account switching. We need to extend it for properties:

```elixir
# lib/gsc_analytics_web/live/account_helpers.ex

@doc """
Initialize account and property assigns on the socket.
"""
@spec init_account_and_property_assigns(socket(), map()) :: {socket(), map(), map() | nil}
def init_account_and_property_assigns(socket, params \\ %{}) do
  # Existing account initialization
  {socket, account} = init_account_assigns(socket, params)

  # Add property initialization
  properties = Accounts.list_properties(account.id)
  requested_property_id = params |> Map.get("property_id") |> parse_property_param()

  current_property = resolve_current_property(properties, requested_property_id)

  socket =
    socket
    |> assign(:properties, properties)
    |> assign(:current_property, current_property)
    |> assign(:current_property_id, current_property && current_property.id)

  {socket, account, current_property}
end

@doc """
Update the current property selection based on params.
"""
@spec assign_current_property(socket(), map()) :: socket()
def assign_current_property(socket, params \\ %{}) do
  requested_property_id = params |> Map.get("property_id") |> parse_property_param()
  properties = socket.assigns[:properties] || []

  current_property = resolve_current_property(properties, requested_property_id)

  socket
  |> assign(:current_property, current_property)
  |> assign(:current_property_id, current_property && current_property.id)
end

defp parse_property_param(nil), do: nil
defp parse_property_param(value) when is_binary(value), do: value
defp parse_property_param(_), do: nil

defp resolve_current_property([], _), do: nil
defp resolve_current_property(properties, requested_id) do
  cond do
    # Try requested property
    requested_id && property = Enum.find(properties, &(&1.id == requested_id)) ->
      property

    # Fall back to active property
    property = Enum.find(properties, & &1.is_active) ->
      property

    # Fall back to first property
    [property | _] = properties ->
      property

    true ->
      nil
  end
end
```

### 2. Update DashboardLive

```elixir
# lib/gsc_analytics_web/live/dashboard_live.ex

def mount(params, _session, socket) do
  if connected?(socket), do: SyncProgress.subscribe()

  # Use extended helper
  {socket, account, property} = AccountHelpers.init_account_and_property_assigns(socket, params)

  # Only load data if we have a property
  socket =
    if property do
      load_dashboard_data(socket, account.id, property.property_url)
    else
      socket
      |> assign_empty_state()
    end

  {:ok, socket}
end

def handle_params(params, uri, socket) do
  socket = AccountHelpers.assign_current_account(socket, params)
  socket = AccountHelpers.assign_current_property(socket, params)

  account_id = socket.assigns.current_account_id
  property = socket.assigns.current_property

  socket =
    if property do
      load_dashboard_data(socket, account_id, property.property_url)
    else
      assign_empty_state(socket)
    end

  {:noreply, socket}
end

def handle_event("switch_property", %{"property_id" => property_id}, socket) do
  # Use push_patch to update URL without full page reload
  {:noreply,
   push_patch(socket,
     to: Routes.dashboard_path(socket, :index,
       account_id: socket.assigns.current_account_id,
       property_id: property_id
     )
   )}
end

defp load_dashboard_data(socket, account_id, property_url) do
  # Update all data queries to filter by property_url
  result =
    ContentInsights.list_urls(%{
      account_id: account_id,
      property_url: property_url,  # Add this filter
      limit: socket.assigns.limit,
      page: socket.assigns.page,
      sort_by: socket.assigns.sort_by,
      sort_direction: socket.assigns.sort_direction,
      search: socket.assigns.search,
      period_days: socket.assigns.period_days
    })

  stats = SummaryStats.fetch(%{
    account_id: account_id,
    property_url: property_url  # Add this filter
  })

  {site_trends, chart_label} =
    SiteTrends.fetch(socket.assigns.chart_view, %{
      account_id: account_id,
      property_url: property_url,  # Add this filter
      period_days: socket.assigns.period_days
    })

  socket
  |> assign(:urls, result.urls)
  |> assign(:stats, stats)
  |> assign(:site_trends, site_trends)
  |> assign(:site_trends_json, ChartDataPresenter.encode_time_series(site_trends))
  |> assign(:chart_label, chart_label)
  |> assign(:total_count, result.total_count)
  |> assign(:total_pages, result.total_pages)
end

defp assign_empty_state(socket) do
  socket
  |> assign(:urls, [])
  |> assign(:stats, %{total_urls: 0, total_clicks: 0, total_impressions: 0, avg_ctr: 0, avg_position: 0})
  |> assign(:site_trends, [])
  |> assign(:site_trends_json, "[]")
  |> assign(:total_count, 0)
  |> assign(:total_pages, 1)
end
```

### 3. Update Dashboard Template

Add property switcher alongside existing account switcher:

```heex
<!-- lib/gsc_analytics_web/live/dashboard_live.html.heex -->

<div class="dashboard-header">
  <div class="flex items-center justify-between mb-6">
    <h1 class="text-2xl font-bold">Dashboard</h1>

    <div class="flex items-center gap-4">
      <!-- Existing account switcher -->
      <%= if length(@account_options) > 1 do %>
        <select phx-change="switch_account" name="account_id" class="form-select rounded-md border-gray-300">
          <%= for {name, id} <- @account_options do %>
            <option value={id} selected={id == @current_account_id}>
              <%= name %>
            </option>
          <% end %>
        </select>
      <% end %>

      <!-- New property switcher -->
      <%= if @properties != [] do %>
        <select phx-change="switch_property" name="property_id" class="form-select rounded-md border-gray-300">
          <%= for property <- @properties do %>
            <option value={property.id} selected={property.id == @current_property_id}>
              <%= property.display_name || property.property_url %>
              <%= if property.is_active do %> ⭐ <% end %>
            </option>
          <% end %>
        </select>
      <% end %>
    </div>
  </div>

  <!-- Property info bar -->
  <%= if @current_property do %>
    <div class="bg-blue-50 border-l-4 border-blue-400 p-4 mb-6">
      <p class="text-sm text-blue-700">
        Showing data for: <strong><%= @current_property.property_url %></strong>
      </p>
    </div>
  <% end %>
</div>

<!-- Empty state when no property -->
<%= if is_nil(@current_property) do %>
  <div class="text-center py-12 bg-gray-50 rounded-lg">
    <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
    </svg>
    <h3 class="mt-2 text-lg font-medium text-gray-900">No property selected</h3>
    <p class="mt-1 text-sm text-gray-500">
      Configure a Search Console property to start viewing analytics.
    </p>
    <div class="mt-6">
      <%= link "Go to Settings", to: Routes.user_settings_path(@socket, :edit),
           class: "inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-blue-600 hover:bg-blue-700" %>
    </div>
  </div>
<% else %>
  <!-- Regular dashboard content -->
  <%= render "_dashboard_content.html", assigns %>
<% end %>
```

### 4. Update Data Query Modules

Update `ContentInsights`, `SummaryStats`, and `SiteTrends` to accept property_url:

```elixir
# lib/gsc_analytics/content_insights.ex

def list_urls(opts \\ %{}) do
  account_id = Map.get(opts, :account_id, 1)
  property_url = Map.get(opts, :property_url)

  base_query =
    from p in Performance,
      where: p.account_id == ^account_id

  # Add property filter if provided
  query =
    if property_url do
      from p in base_query,
        where: p.property_url == ^property_url
    else
      base_query
    end

  # Rest of the query logic...
end
```

## Testing Notes
- Test mount with no `property_id` param defaults to active property
- Test switching properties updates URL and data immediately
- Test with invalid `property_id` shows error or defaults gracefully
- Test empty state when no properties configured
- Test that account switching preserves property selection where possible
- Verify all data queries use property_url filter
- Test performance with multiple properties

## Performance Considerations
- Consider caching property list in socket to avoid repeated DB queries
- Ensure indexes exist on (account_id, property_url) for all data tables
- Monitor query performance with EXPLAIN ANALYZE
- Consider implementing data preloading for common property switches