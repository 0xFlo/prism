defmodule GscAnalyticsWeb.Live.AccountHelpersPropertyAssociationTest do
  @moduledoc """
  Regression tests to ensure properties are correctly associated with their workspaces
  in dropdown options. This prevents the bug where properties appeared with wrong
  Google account prefixes.
  """
  use GscAnalytics.DataCase, async: true

  import GscAnalytics.AuthFixtures

  alias GscAnalytics.{Accounts, Auth, Workspaces}

  describe "property-to-workspace association" do
    test "properties are correctly associated with their workspace IDs in the database" do
      user = user_fixture()

      {:ok, workspace1} =
        Workspaces.create_workspace(user.id, %{
          google_account_email: "user1@example.com",
          name: "user1@example.com",
          enabled: true
        })

      {:ok, workspace2} =
        Workspaces.create_workspace(user.id, %{
          google_account_email: "user2@example.com",
          name: "user2@example.com",
          enabled: true
        })

      # Create properties for each workspace
      {:ok, prop1} =
        Accounts.add_property(workspace1.id, %{
          property_url: "sc-domain:workspace1.com",
          is_active: true
        })

      {:ok, prop2} =
        Accounts.add_property(workspace2.id, %{
          property_url: "sc-domain:workspace2.com",
          is_active: true
        })

      # Verify properties are stored with correct workspace_id
      workspace1_props = Accounts.list_properties(workspace1.id)
      workspace2_props = Accounts.list_properties(workspace2.id)

      # Each workspace should only have its own property
      assert length(workspace1_props) == 1
      assert length(workspace2_props) == 1

      assert hd(workspace1_props).property_url == "sc-domain:workspace1.com"
      assert hd(workspace1_props).workspace_id == workspace1.id

      assert hd(workspace2_props).property_url == "sc-domain:workspace2.com"
      assert hd(workspace2_props).workspace_id == workspace2.id

      # Properties should NOT appear in the wrong workspace's list
      workspace1_urls = Enum.map(workspace1_props, & &1.property_url)
      workspace2_urls = Enum.map(workspace2_props, & &1.property_url)

      refute "sc-domain:workspace2.com" in workspace1_urls
      refute "sc-domain:workspace1.com" in workspace2_urls
    end

    test "list_active_properties returns only properties for the specified workspace" do
      user = user_fixture()

      {:ok, workspace1} =
        Workspaces.create_workspace(user.id, %{
          google_account_email: "ws1@example.com",
          name: "Workspace 1",
          enabled: true
        })

      {:ok, workspace2} =
        Workspaces.create_workspace(user.id, %{
          google_account_email: "ws2@example.com",
          name: "Workspace 2",
          enabled: true
        })

      # Create multiple properties for each
      {:ok, _} =
        Accounts.add_property(workspace1.id, %{
          property_url: "sc-domain:ws1-site1.com",
          is_active: true
        })

      {:ok, _} =
        Accounts.add_property(workspace1.id, %{
          property_url: "sc-domain:ws1-site2.com",
          is_active: true
        })

      {:ok, _} =
        Accounts.add_property(workspace2.id, %{
          property_url: "sc-domain:ws2-site1.com",
          is_active: true
        })

      {:ok, _} =
        Accounts.add_property(workspace2.id, %{
          property_url: "sc-domain:ws2-site2.com",
          is_active: true
        })

      # Verify list_active_properties filters correctly
      ws1_active = Accounts.list_active_properties(workspace1.id)
      ws2_active = Accounts.list_active_properties(workspace2.id)

      assert length(ws1_active) == 2
      assert length(ws2_active) == 2

      ws1_urls = Enum.map(ws1_active, & &1.property_url)
      ws2_urls = Enum.map(ws2_active, & &1.property_url)

      # Workspace 1 should only have its own properties
      assert "sc-domain:ws1-site1.com" in ws1_urls
      assert "sc-domain:ws1-site2.com" in ws1_urls
      refute "sc-domain:ws2-site1.com" in ws1_urls
      refute "sc-domain:ws2-site2.com" in ws1_urls

      # Workspace 2 should only have its own properties
      assert "sc-domain:ws2-site1.com" in ws2_urls
      assert "sc-domain:ws2-site2.com" in ws2_urls
      refute "sc-domain:ws1-site1.com" in ws2_urls
      refute "sc-domain:ws1-site2.com" in ws2_urls
    end

    test "inactive properties are not returned by list_active_properties" do
      user = user_fixture()

      {:ok, workspace} =
        Workspaces.create_workspace(user.id, %{
          google_account_email: "test@example.com",
          name: "Test Workspace",
          enabled: true
        })

      {:ok, active_prop} =
        Accounts.add_property(workspace.id, %{
          property_url: "sc-domain:active.com",
          is_active: true
        })

      {:ok, inactive_prop} =
        Accounts.add_property(workspace.id, %{
          property_url: "sc-domain:inactive.com",
          is_active: false
        })

      # Only active properties should be returned
      active_properties = Accounts.list_active_properties(workspace.id)
      all_properties = Accounts.list_properties(workspace.id)

      assert length(all_properties) == 2
      assert length(active_properties) == 1

      assert hd(active_properties).property_url == "sc-domain:active.com"
      assert hd(active_properties).is_active == true
    end

    test "multiple active properties can exist per workspace" do
      # Regression test for the constraint that was preventing multiple active properties
      user = user_fixture()

      {:ok, workspace} =
        Workspaces.create_workspace(user.id, %{
          google_account_email: "test@example.com",
          name: "Test Workspace",
          enabled: true
        })

      # Should be able to create multiple active properties
      {:ok, prop1} =
        Accounts.add_property(workspace.id, %{
          property_url: "sc-domain:site1.com",
          is_active: true
        })

      {:ok, prop2} =
        Accounts.add_property(workspace.id, %{
          property_url: "sc-domain:site2.com",
          is_active: true
        })

      {:ok, prop3} =
        Accounts.add_property(workspace.id, %{
          property_url: "sc-domain:site3.com",
          is_active: true
        })

      active_properties = Accounts.list_active_properties(workspace.id)

      # All three should be active
      assert length(active_properties) == 3

      active_urls = Enum.map(active_properties, & &1.property_url)
      assert "sc-domain:site1.com" in active_urls
      assert "sc-domain:site2.com" in active_urls
      assert "sc-domain:site3.com" in active_urls
    end
  end
end
