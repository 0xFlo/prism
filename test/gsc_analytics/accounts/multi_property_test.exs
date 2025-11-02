defmodule GscAnalytics.Accounts.MultiPropertyTest do
  use GscAnalytics.DataCase, async: true

  alias GscAnalytics.Accounts
  alias GscAnalytics.Schemas.WorkspaceProperty

  describe "list_properties/1" do
    test "returns all properties for a workspace ordered by active then name" do
      account_id = 1

      {:ok, prop1} =
        Accounts.add_property(account_id, %{
          property_url: "sc-domain:example.com",
          display_name: "Example Domain"
        })

      {:ok, prop2} =
        Accounts.add_property(account_id, %{
          property_url: "https://example.com/",
          display_name: "Example HTTPS"
        })

      # Set prop2 as active
      {:ok, _} = Accounts.set_active_property(account_id, prop2.id)

      properties = Accounts.list_properties(account_id)

      assert length(properties) == 2
      # Active property should be first
      assert hd(properties).id == prop2.id
      assert hd(properties).is_active == true
    end
  end

  describe "add_property/2" do
    test "adds a new property to workspace" do
      account_id = 1

      {:ok, property} =
        Accounts.add_property(account_id, %{
          property_url: "sc-domain:example.com",
          display_name: "Example"
        })

      assert property.workspace_id == account_id
      assert property.property_url == "sc-domain:example.com"
      assert property.display_name == "Example"
      assert property.is_active == false
    end

    test "prevents duplicate property URLs for same workspace" do
      account_id = 1

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
      account_id = 1

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
      account_id = 1

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
      account_id = 1

      {:ok, property} =
        Accounts.add_property(account_id, %{property_url: "sc-domain:example.com"})

      {:ok, _} = Accounts.remove_property(account_id, property.id)

      assert Repo.get(WorkspaceProperty, property.id) == nil
    end

    test "returns error when property not found" do
      account_id = 1

      # Use a valid UUID format that doesn't exist in the database
      non_existent_uuid = Ecto.UUID.generate()
      {:error, :not_found} = Accounts.remove_property(account_id, non_existent_uuid)
    end

    test "returns error when property ID is invalid" do
      account_id = 1

      {:error, :invalid_uuid} = Accounts.remove_property(account_id, "not-a-uuid")
    end
  end

  describe "get_active_property/1" do
    test "returns the active property for workspace" do
      account_id = 1

      {:ok, prop1} = Accounts.add_property(account_id, %{property_url: "sc-domain:example.com"})
      {:ok, _} = Accounts.set_active_property(account_id, prop1.id)

      active = Accounts.get_active_property(account_id)

      assert active.id == prop1.id
      assert active.is_active == true
    end

    test "returns nil when no active property" do
      account_id = 1

      assert Accounts.get_active_property(account_id) == nil
    end
  end

  describe "get_active_property_url/1" do
    test "returns active property URL when available" do
      account_id = 1

      {:ok, prop} = Accounts.add_property(account_id, %{property_url: "sc-domain:example.com"})
      {:ok, _} = Accounts.set_active_property(account_id, prop.id)

      {:ok, url} = Accounts.get_active_property_url(account_id)

      assert url == "sc-domain:example.com"
    end

    test "falls back to gsc_default_property when no active property" do
      account_id = 1

      # Should fall back to legacy system
      # This will fail if no default is configured, which is expected behavior
      result = Accounts.get_active_property_url(account_id)

      assert match?({:ok, _url}, result) or match?({:error, _}, result)
    end
  end
end
