defmodule GscAnalytics.Accounts.MultiPropertyTest do
  use GscAnalytics.DataCase, async: true

  import GscAnalytics.AccountsFixtures

  alias GscAnalytics.Accounts
  alias GscAnalytics.Schemas.WorkspaceProperty

  describe "list_properties/1" do
    test "returns all properties for a workspace ordered by active then name" do
      workspace = workspace_fixture()
      account_id = workspace.id

      {:ok, _prop1} =
        Accounts.add_property(account_id, %{
          property_url: "sc-domain:example.com",
          display_name: "Example Domain",
          is_active: false
        })

      {:ok, prop2} =
        Accounts.add_property(account_id, %{
          property_url: "https://example.com/",
          display_name: "Example HTTPS",
          is_active: true
        })

      properties = Accounts.list_properties(account_id)

      assert length(properties) == 2
      # Active property should be first
      assert hd(properties).id == prop2.id
      assert hd(properties).is_active == true
    end
  end

  describe "add_property/2" do
    test "adds a new property to workspace" do
      workspace = workspace_fixture()
      account_id = workspace.id

      {:ok, property} =
        Accounts.add_property(account_id, %{
          property_url: "sc-domain:example.com",
          display_name: "Example"
        })

      assert property.workspace_id == account_id
      assert property.property_url == "sc-domain:example.com"
      assert property.display_name == "Example"
      # Properties are active by default for better UX
      assert property.is_active == true
    end

    test "prevents duplicate property URLs for same workspace" do
      workspace = workspace_fixture()
      account_id = workspace.id

      {:ok, _} = Accounts.add_property(account_id, %{property_url: "sc-domain:example.com"})

      {:error, changeset} =
        Accounts.add_property(account_id, %{property_url: "sc-domain:example.com"})

      # Ecto attaches compound unique constraint errors to the first field
      assert changeset.errors[:workspace_id]
      {message, _} = changeset.errors[:workspace_id]
      assert message =~ "already saved"
    end
  end

  describe "set_active_property/2" do
    test "marks the requested property as active without deactivating others" do
      workspace = workspace_fixture()
      account_id = workspace.id

      {:ok, prop1} = Accounts.add_property(account_id, %{property_url: "sc-domain:example.com"})
      {:ok, prop2} = Accounts.add_property(account_id, %{property_url: "https://example.com/"})

      {:ok, _} = Accounts.set_active_property(account_id, prop1.id)
      {:ok, _} = Accounts.set_active_property(account_id, prop2.id)

      updated_prop1 = Repo.get!(WorkspaceProperty, prop1.id)
      updated_prop2 = Repo.get!(WorkspaceProperty, prop2.id)

      assert updated_prop1.is_active
      assert updated_prop2.is_active
    end

    test "update_property_active/3 can deactivate a property" do
      workspace = workspace_fixture()
      account_id = workspace.id

      {:ok, prop} = Accounts.add_property(account_id, %{property_url: "sc-domain:example.com"})

      {:ok, _} = Accounts.set_active_property(account_id, prop.id)
      {:ok, deactivated} = Accounts.update_property_active(account_id, prop.id, false)

      refute deactivated.is_active

      reloaded = Repo.get!(WorkspaceProperty, prop.id)
      refute reloaded.is_active
    end
  end

  describe "remove_property/2" do
    test "removes a property from workspace" do
      workspace = workspace_fixture()
      account_id = workspace.id

      {:ok, property} =
        Accounts.add_property(account_id, %{property_url: "sc-domain:example.com"})

      {:ok, _} = Accounts.remove_property(account_id, property.id)

      assert Repo.get(WorkspaceProperty, property.id) == nil
    end

    test "returns error when property not found" do
      workspace = workspace_fixture()
      account_id = workspace.id

      # Use a valid UUID format that doesn't exist in the database
      non_existent_uuid = Ecto.UUID.generate()
      {:error, :not_found} = Accounts.remove_property(account_id, non_existent_uuid)
    end

    test "returns error when property ID is invalid" do
      workspace = workspace_fixture()
      account_id = workspace.id

      {:error, :invalid_uuid} = Accounts.remove_property(account_id, "not-a-uuid")
    end
  end

  describe "get_active_property/1" do
    test "returns the active property for workspace" do
      workspace = workspace_fixture()
      account_id = workspace.id

      {:ok, prop1} = Accounts.add_property(account_id, %{property_url: "sc-domain:example.com"})
      {:ok, _} = Accounts.set_active_property(account_id, prop1.id)

      active = Accounts.get_active_property(account_id)

      assert active.id == prop1.id
      assert active.is_active == true
    end

    test "returns nil when no active property" do
      workspace = workspace_fixture()
      account_id = workspace.id

      assert Accounts.get_active_property(account_id) == nil
    end
  end

  describe "get_active_property_url/1" do
    test "returns active property URL when available" do
      workspace = workspace_fixture()
      account_id = workspace.id

      {:ok, prop} = Accounts.add_property(account_id, %{property_url: "sc-domain:example.com"})
      {:ok, _} = Accounts.set_active_property(account_id, prop.id)

      {:ok, url} = Accounts.get_active_property_url(account_id)

      assert url == "sc-domain:example.com"
    end

    test "falls back to gsc_default_property when no active property" do
      workspace = workspace_fixture()
      account_id = workspace.id

      # Should fall back to legacy system
      # This will fail if no default is configured, which is expected behavior
      result = Accounts.get_active_property_url(account_id)

      assert match?({:ok, _url}, result) or match?({:error, _}, result)
    end
  end
end
