# Ticket-007: Testing, Telemetry, and Rollout Guide

## Status: TODO
**Priority:** P2  
**Estimate:** 1 day  
**Dependencies:** ticket-004, ticket-005, ticket-006  
**Blocks:** Release readiness

## Problem Statement
Multi-property support introduces new UX flows and operational paths that need explicit coverage. We also need observability hooks and operator documentation before rollout.

## Acceptance Criteria
- [ ] LiveView tests for settings property picker and dashboard switcher
- [ ] Context tests for property CRUD operations
- [ ] Telemetry events for property lifecycle (add, activate, remove, sync)
- [ ] Migration rollout steps documented

## Implementation Plan

### 1. LiveView Tests

**Best Practice:** Test LiveView UI interactions with declarative API, use Mox for external dependencies.

```elixir
# test/gsc_analytics_web/live/user_live/settings_test.exs

test "displays list of properties", %{conn: conn} do
  workspace = insert(:workspace)
  property1 = insert(:workspace_property, workspace: workspace, display_name: "Main Site", is_active: true)
  property2 = insert(:workspace_property, workspace: workspace, display_name: "Blog")

  {:ok, view, html} = live(conn, ~p"/settings")

  assert html =~ "Main Site"
  assert html =~ "Blog"
  assert html =~ "Active"  # Main Site is active
end

test "setting active property updates UI", %{conn: conn} do
  workspace = insert(:workspace)
  property1 = insert(:workspace_property, workspace: workspace, is_active: true)
  property2 = insert(:workspace_property, workspace: workspace, is_active: false)

  {:ok, view, _html} = live(conn, ~p"/settings")

  # Click "Set Active" on property2
  view
  |> element("button[phx-click='set_active_property'][phx-value-property_id='#{property2.id}']")
  |> render_click()

  # Verify property2 is now active
  html = render(view)
  assert html =~ property2.display_name
  assert html =~ "Active"
end

test "removing property removes it from list", %{conn: conn} do
  workspace = insert(:workspace)
  property = insert(:workspace_property, workspace: workspace)

  {:ok, view, _html} = live(conn, ~p"/settings")

  view
  |> element("button[phx-click='remove_property'][phx-value-property_id='#{property.id}']")
  |> render_click()

  refute render(view) =~ property.display_name
end
```

```elixir
# test/gsc_analytics_web/live/dashboard_live_test.exs

test "switching property updates URL and data", %{conn: conn} do
  workspace = insert(:workspace)
  property1 = insert(:workspace_property, workspace: workspace, property_url: "sc-domain:site1.com")
  property2 = insert(:workspace_property, workspace: workspace, property_url: "sc-domain:site2.com")

  insert(:performance, account_id: workspace.id, property_url: "sc-domain:site1.com", url: "/page1")
  insert(:performance, account_id: workspace.id, property_url: "sc-domain:site2.com", url: "/page2")

  {:ok, view, html} = live(conn, ~p"/dashboard?property_id=#{property1.id}")

  assert html =~ "/page1"
  refute html =~ "/page2"

  # Switch to property2
  view
  |> element("select[phx-change='switch_property']")
  |> render_change(%{"property_id" => property2.id})

  html = render(view)
  assert html =~ "/page2"
  refute html =~ "/page1"

  # Verify URL was updated
  assert_patch(view, ~p"/dashboard?property_id=#{property2.id}")
end
```

### 2. Context Tests

```elixir
# test/gsc_analytics/accounts_test.exs

describe "workspace properties" do
  test "add_property/2 creates property with valid attrs" do
    workspace = insert(:workspace)
    attrs = %{property_url: "sc-domain:example.com", display_name: "Example"}

    assert {:ok, property} = Accounts.add_property(workspace.id, attrs)
    assert property.property_url == "sc-domain:example.com"
    assert property.display_name == "Example"
  end

  test "add_property/2 rejects duplicate property URLs" do
    workspace = insert(:workspace)
    insert(:workspace_property, workspace: workspace, property_url: "sc-domain:example.com")

    assert {:error, changeset} = Accounts.add_property(workspace.id, %{property_url: "sc-domain:example.com"})
    assert "has already been taken" in errors_on(changeset).property_url
  end

  test "set_active_property/2 deactivates other properties" do
    workspace = insert(:workspace)
    property1 = insert(:workspace_property, workspace: workspace, is_active: true)
    property2 = insert(:workspace_property, workspace: workspace, is_active: false)

    {:ok, _} = Accounts.set_active_property(workspace.id, property2.id)

    assert Repo.get!(WorkspaceProperty, property1.id).is_active == false
    assert Repo.get!(WorkspaceProperty, property2.id).is_active == true
  end

  test "get_active_property/1 returns active property" do
    workspace = insert(:workspace)
    active = insert(:workspace_property, workspace: workspace, is_active: true)
    insert(:workspace_property, workspace: workspace, is_active: false)

    assert Accounts.get_active_property(workspace.id).id == active.id
  end
end
```

### 3. Telemetry Events

```elixir
# Emit in Accounts context
def add_property(workspace_id, attrs) do
  result = # ... insert logic

  :telemetry.execute(
    [:workspace, :property, :added],
    %{count: 1},
    %{workspace_id: workspace_id, property_url: attrs[:property_url]}
  )

  result
end

def set_active_property(workspace_id, property_id) do
  result = # ... update logic

  :telemetry.execute(
    [:workspace, :property, :activated],
    %{},
    %{workspace_id: workspace_id, property_id: property_id}
  )

  result
end
```

### 4. Migration Rollout Steps

Add to `CLAUDE.md`:

```markdown
## Multi-Property Migration Rollout

1. **Backup database** before running migrations
2. Run migrations in order:
   - `mix ecto.migrate` (create workspace_properties table)
   - `mix ecto.migrate` (backfill from default_property)
   - `mix ecto.migrate` (add property_url to data tables)
   - `mix ecto.migrate` (backfill property_url in data)
3. Verify backfill: `SELECT COUNT(*) FROM workspace_properties;`
4. Test property switching in settings and dashboard
5. Run first sync with new property system
6. Monitor audit logs for property_url field: `grep "property_url" logs/gsc_audit.log`
```

## Testing Notes
- Use factory fixtures for workspaces and properties
- Mock GSC API with Mox when testing sync
- Run full test suite: `mix test`
- Performance test with multiple properties per workspace
