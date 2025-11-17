# Ticket-003: Refactor Accounts Context for Multi-Property Support

## Status: TODO
**Priority:** P1
**Estimate:** 1 day
**Dependencies:** ticket-002
**Blocks:** ticket-004, ticket-005, ticket-006

## Problem Statement
`GscAnalytics.Accounts` currently manages single `default_property` per workspace through `AccountSetting`. We need to expose APIs that manage many properties (list, add, remove, mark active) while respecting `current_scope` authorization and maintaining backward compatibility.

## Acceptance Criteria
- [ ] New APIs: `list_properties/1`, `add_property/2`, `set_active_property/2`, `remove_property/2`
- [ ] Returns `{:ok, property}` / `{:error, changeset}` tuples consistently
- [ ] Changesets validate URL format and prevent duplicates
- [ ] Backward compatible with existing `gsc_default_property/1` function
- [ ] Integration with existing OAuth and account configuration

## Implementation Plan

### 1. Add Context Functions to GscAnalytics.Accounts

**Important:** The existing Accounts module uses integer account_ids and integrates with config-based accounts. We need to maintain this pattern.

```elixir
# lib/gsc_analytics/accounts.ex
# Add these functions to the existing module:

alias GscAnalytics.Schemas.WorkspaceProperty
alias GscAnalytics.Repo

@doc """
List all properties for a workspace, ordered by is_active desc, then display_name.
"""
def list_properties(account_id) do
  WorkspaceProperty
  |> where(workspace_id: ^account_id)
  |> order_by([p], [desc: p.is_active, asc: p.display_name])
  |> Repo.all()
end

@doc """
Add a new property to a workspace.
Returns {:ok, property} or {:error, changeset}.
"""
def add_property(account_id, attrs) do
  %WorkspaceProperty{}
  |> WorkspaceProperty.changeset(Map.merge(attrs, %{workspace_id: account_id}))
  |> Repo.insert()
end

@doc """
Set a property as active for the workspace.
Automatically deactivates other properties.
"""
def set_active_property(account_id, property_id) do
  Repo.transaction(fn ->
    # Deactivate all properties for this workspace
    from(p in WorkspaceProperty, where: p.workspace_id == ^account_id)
    |> Repo.update_all(set: [is_active: false])

    # Activate the selected property
    property = Repo.get_by!(WorkspaceProperty, id: property_id, workspace_id: account_id)
    property
    |> WorkspaceProperty.changeset(%{is_active: true})
    |> Repo.update!()
  end)
end

@doc """
Remove a property from a workspace.
Returns {:ok, property} or {:error, changeset}.
"""
def remove_property(account_id, property_id) do
  property = Repo.get_by(WorkspaceProperty, id: property_id, workspace_id: account_id)

  case property do
    nil -> {:error, :not_found}
    property -> Repo.delete(property)
  end
end

@doc """
Get the active property for a workspace.
Returns property struct or nil.
"""
def get_active_property(account_id) do
  Repo.get_by(WorkspaceProperty, workspace_id: account_id, is_active: true)
end

@doc """
Get the active property URL for a workspace (backward compatibility).
Falls back to default_property from AccountSetting if no active property.
"""
def get_active_property_url(account_id) do
  case get_active_property(account_id) do
    nil ->
      # Fall back to legacy default_property
      gsc_default_property(account_id)

    property ->
      {:ok, property.property_url}
  end
end
```

### 2. Update Existing Functions for Backward Compatibility

```elixir
# Modify the existing gsc_default_property function to check new properties first:
@spec gsc_default_property(account_id()) :: {:ok, String.t()} | {:error, term()}
def gsc_default_property(account_id) do
  # First check for active property in new system
  case get_active_property(account_id) do
    %WorkspaceProperty{property_url: url} when is_binary(url) ->
      {:ok, url}

    nil ->
      # Fall back to legacy system
      with {:ok, account} <- GSCAccounts.fetch_account(account_id) do
        setting = Repo.get(AccountSetting, account_id)

        case effective_default_property(setting, account.default_property) do
          nil -> {:error, :missing_property}
          property -> {:ok, property}
        end
      end
  end
end

# Update list_property_options to include saved properties
@spec list_property_options(Scope.t() | nil, account_id()) ::
        {:ok, [map()]} | {:error, term()}
def list_property_options(scope, account_id) do
  with {:ok, account_id} <- normalize_account_id(account_id),
       :ok <- Scope.authorize_account(scope, account_id) do
    # Get saved properties
    saved_properties = list_properties(account_id)
    saved_urls = MapSet.new(saved_properties, & &1.property_url)

    # Get available properties from GSC API
    case GSCClient.list_sites(account_id) do
      {:ok, sites} ->
        available =
          sites
          |> Enum.map(&build_property_option/1)
          |> Enum.map(fn opt ->
            Map.put(opt, :is_saved, MapSet.member?(saved_urls, opt.value))
          end)
          |> Enum.sort_by(&property_option_sort_key/1)

        {:ok, available}

      {:error, _} = error ->
        # If API fails, at least return saved properties
        saved = Enum.map(saved_properties, fn prop ->
          %{
            value: prop.property_url,
            label: prop.display_name || infer_property_label(prop.property_url),
            is_saved: true,
            is_active: prop.is_active
          }
        end)
        {:ok, saved}
    end
  end
end
```

### 3. Migration Helper for Initial Data

```elixir
@doc """
Migrate existing default_property to new multi-property system.
Called during deployment to ensure smooth transition.
"""
def migrate_default_properties do
  AccountSetting
  |> where([s], not is_nil(s.default_property))
  |> Repo.all()
  |> Enum.each(fn setting ->
    add_property(setting.account_id, %{
      property_url: setting.default_property,
      display_name: setting.default_property,
      is_active: true
    })
  end)
end
```

### 4. Integration Points

The existing system has several integration points that need updating:

- **AccountHelpers** - Already handles account selection, minimal changes needed
- **OAuth Flow** - Continues to work at workspace level (no changes)
- **Sync Pipeline** - Already accepts `site_url` parameter (minor updates in ticket-006)
- **Settings LiveView** - Major UI updates (ticket-004)
- **Dashboard LiveView** - Property switcher addition (ticket-005)

## Testing Notes
- Test constraint violations (duplicate URLs, invalid formats)
- Test `set_active_property/2` deactivates others atomically
- Test `remove_property/2` with active and inactive properties
- Test backward compatibility with existing `gsc_default_property/1`
- Mock OAuth responses when fetching available properties from Google
- Test fallback behavior when GSC API is unavailable

## Migration Checklist
- [ ] Deploy new schemas and migrations
- [ ] Run `migrate_default_properties/0` in production console
- [ ] Verify existing dashboards continue working
- [ ] Test property switching in staging environment