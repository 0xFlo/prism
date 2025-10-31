defmodule GscAnalytics.AccountsTest do
  use GscAnalytics.DataCase

  alias GscAnalytics.Accounts
  alias GscAnalytics.AccountsFixtures

  describe "default property management" do
    test "returns config fallback when no override exists" do
      assert {:ok, "sc-domain:scrapfly.io"} = Accounts.gsc_default_property(1)
    end

    test "stores overrides and surfaces them in lookups" do
      assert {:error, _} = Accounts.gsc_default_property(2)

      assert {:ok, _setting} =
               Accounts.set_default_property(nil, 2, "https://example.com/")

      assert {:ok, "https://example.com/"} = Accounts.gsc_default_property(2)

      accounts = Accounts.list_gsc_accounts()
      account = Enum.find(accounts, &(&1.id == 2))

      assert account.default_property == "https://example.com/"
      assert account.default_property_source == :user
    end

    test "requires authorization when scope is provided" do
      scope = AccountsFixtures.scope_with_accounts(1)

      assert {:error, :unauthorized_account} =
               Accounts.set_default_property(scope, 2, "https://forbidden.example/")
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
