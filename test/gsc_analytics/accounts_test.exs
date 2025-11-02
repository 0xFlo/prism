defmodule GscAnalytics.AccountsTest do
  use GscAnalytics.DataCase

  alias GscAnalytics.Accounts
  alias GscAnalytics.AccountsFixtures

  describe "property management" do
    test "returns error when no active property is set" do
      account_id = 1
      assert {:error, :no_active_property} = Accounts.get_active_property_url(account_id)
    end

    test "returns active property url when one is set" do
      account_id = 1

      # Add a property and set it as active
      {:ok, property} =
        Accounts.add_property(account_id, %{
          property_url: "sc-domain:example.com",
          display_name: "Example Property"
        })

      {:ok, _} = Accounts.set_active_property(account_id, property.id)

      assert {:ok, "sc-domain:example.com"} = Accounts.get_active_property_url(account_id)
    end

    test "returns the most recently activated property when multiple are active" do
      account_id = 1

      {:ok, prop1} = Accounts.add_property(account_id, %{property_url: "sc-domain:example1.com"})
      {:ok, prop2} = Accounts.add_property(account_id, %{property_url: "sc-domain:example2.com"})

      {:ok, _} = Accounts.set_active_property(account_id, prop1.id)
      {:ok, _} = Accounts.set_active_property(account_id, prop2.id)

      assert {:ok, "sc-domain:example2.com"} = Accounts.get_active_property_url(account_id)
    end
  end

  describe "display name overrides" do
    test "list_gsc_accounts surfaces stored display names" do
      {:ok, _} = Accounts.set_display_name(nil, 2, "Alba Analytics")

      account =
        Accounts.list_gsc_accounts()
        |> Enum.find(&(&1.id == 2))

      assert account.display_name == "Alba Analytics"
    end
  end
end
