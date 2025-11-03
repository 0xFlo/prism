defmodule GscAnalytics.AccountsTest do
  use GscAnalytics.DataCase

  import GscAnalytics.AccountsFixtures

  alias GscAnalytics.Accounts

  describe "property management" do
    test "returns error when no active property is set" do
      workspace = workspace_fixture()
      account_id = workspace.id

      # Ensure no active properties exist
      properties = Accounts.list_active_properties(account_id)

      Enum.each(properties, fn prop ->
        Accounts.update_property_active(account_id, prop.id, false)
      end)

      assert {:error, :no_active_property} = Accounts.get_active_property_url(account_id)
    end

    test "returns active property url when one is set" do
      workspace = workspace_fixture()
      account_id = workspace.id

      # Add a property (will be active by default)
      {:ok, property} =
        Accounts.add_property(account_id, %{
          property_url: "sc-domain:example.com",
          display_name: "Example Property"
        })

      assert {:ok, "sc-domain:example.com"} = Accounts.get_active_property_url(account_id)
    end

    test "returns an active property when multiple are active" do
      workspace = workspace_fixture()
      account_id = workspace.id

      {:ok, prop1} =
        Accounts.add_property(account_id, %{
          property_url: "sc-domain:example1.com"
        })

      {:ok, prop2} =
        Accounts.add_property(account_id, %{
          property_url: "sc-domain:example2.com"
        })

      # Both are active, should return one of them (ordered by updated_at desc)
      {:ok, url} = Accounts.get_active_property_url(account_id)
      assert url in [prop1.property_url, prop2.property_url]
    end
  end

  describe "display name overrides" do
    test "list_gsc_accounts surfaces stored display names" do
      user = GscAnalytics.AuthFixtures.user_fixture()
      workspace = workspace_fixture(user: user)
      scope = GscAnalytics.Auth.Scope.for_user(user)

      {:ok, _} = Accounts.set_display_name(nil, workspace.id, "Alba Analytics")

      account =
        Accounts.list_gsc_accounts(scope)
        |> Enum.find(&(&1.id == workspace.id))

      assert account.display_name == "Alba Analytics"
    end
  end
end
