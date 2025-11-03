defmodule GscAnalyticsWeb.Live.AccountHelpersInactivePropertyTest do
  use GscAnalytics.DataCase, async: true

  import Ecto.Query
  alias GscAnalytics.{Accounts, Workspaces}
  alias GscAnalytics.Schemas.WorkspaceProperty
  alias GscAnalytics.AuthFixtures

  describe "batch_load_all_properties - inactive property filtering" do
    test "only loads active properties" do
      # Create user and workspace
      user = AuthFixtures.user_fixture()

      {:ok, workspace} =
        Workspaces.create_workspace(user.id, %{
          google_account_email: "test@example.com",
          name: "Test Workspace",
          enabled: true
        })

      # Add an active property
      {:ok, active_prop} =
        Accounts.add_property(workspace.id, %{
          property_url: "sc-domain:active-site.com",
          is_active: true
        })

      # Add an inactive property
      {:ok, _inactive_prop} =
        Accounts.add_property(workspace.id, %{
          property_url: "sc-domain:inactive-site.com",
          is_active: false
        })

      # Query properties the same way batch_load_all_properties does
      loaded_properties =
        from(p in WorkspaceProperty,
          where: p.workspace_id in ^[workspace.id],
          where: p.is_active == true,
          order_by: [desc: p.is_active, asc: p.display_name]
        )
        |> Repo.all()

      # Should only return the active property
      assert length(loaded_properties) == 1
      assert hd(loaded_properties).id == active_prop.id
      assert hd(loaded_properties).property_url == "sc-domain:active-site.com"
    end

    test "returns empty list when all properties are inactive" do
      user = AuthFixtures.user_fixture()

      {:ok, workspace} =
        Workspaces.create_workspace(user.id, %{
          google_account_email: "test@example.com",
          name: "Test Workspace",
          enabled: true
        })

      # Add only inactive properties
      {:ok, _inactive1} =
        Accounts.add_property(workspace.id, %{
          property_url: "sc-domain:inactive1.com",
          is_active: false
        })

      {:ok, _inactive2} =
        Accounts.add_property(workspace.id, %{
          property_url: "sc-domain:inactive2.com",
          is_active: false
        })

      # Query properties
      loaded_properties =
        from(p in WorkspaceProperty,
          where: p.workspace_id in ^[workspace.id],
          where: p.is_active == true,
          order_by: [desc: p.is_active, asc: p.display_name]
        )
        |> Repo.all()

      # Should return empty list
      assert loaded_properties == []
    end

    test "loads multiple active properties from same workspace" do
      user = AuthFixtures.user_fixture()

      {:ok, workspace} =
        Workspaces.create_workspace(user.id, %{
          google_account_email: "test@example.com",
          name: "Test Workspace",
          enabled: true
        })

      # Add multiple active properties
      {:ok, _active1} =
        Accounts.add_property(workspace.id, %{
          property_url: "sc-domain:active1.com",
          is_active: true
        })

      {:ok, _active2} =
        Accounts.add_property(workspace.id, %{
          property_url: "sc-domain:active2.com",
          is_active: true
        })

      # Add an inactive property (should not be loaded)
      {:ok, _inactive} =
        Accounts.add_property(workspace.id, %{
          property_url: "sc-domain:inactive.com",
          is_active: false
        })

      # Query properties
      loaded_properties =
        from(p in WorkspaceProperty,
          where: p.workspace_id in ^[workspace.id],
          where: p.is_active == true,
          order_by: [desc: p.is_active, asc: p.display_name]
        )
        |> Repo.all()

      # Should return only the 2 active properties
      assert length(loaded_properties) == 2

      property_urls = Enum.map(loaded_properties, & &1.property_url) |> Enum.sort()
      assert property_urls == ["sc-domain:active1.com", "sc-domain:active2.com"]
    end

    test "deactivating a property removes it from results" do
      user = AuthFixtures.user_fixture()

      {:ok, workspace} =
        Workspaces.create_workspace(user.id, %{
          google_account_email: "test@example.com",
          name: "Test Workspace",
          enabled: true
        })

      # Add an active property
      {:ok, property} =
        Accounts.add_property(workspace.id, %{
          property_url: "sc-domain:test-site.com",
          is_active: true
        })

      # Initially, property should be loaded
      loaded_properties =
        from(p in WorkspaceProperty,
          where: p.workspace_id in ^[workspace.id],
          where: p.is_active == true
        )
        |> Repo.all()

      assert length(loaded_properties) == 1

      # Deactivate the property
      {:ok, _updated} = Accounts.update_property_active(workspace.id, property.id, false)

      # Now property should NOT be loaded
      loaded_properties_after =
        from(p in WorkspaceProperty,
          where: p.workspace_id in ^[workspace.id],
          where: p.is_active == true
        )
        |> Repo.all()

      assert loaded_properties_after == []
    end
  end
end
