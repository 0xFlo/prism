defmodule GscAnalytics.UserSettings.WorkspaceManagerTest do
  use GscAnalytics.DataCase, async: true

  alias GscAnalytics.UserSettings.WorkspaceManager
  alias GscAnalytics.{Accounts, Auth, Workspaces}

  describe "parse_account_id/1" do
    test "accepts positive integers" do
      assert {:ok, 123} = WorkspaceManager.parse_account_id(123)
    end

    test "accepts numeric strings" do
      assert {:ok, 42} = WorkspaceManager.parse_account_id("42")
      assert {:error, :invalid_account_id} = WorkspaceManager.parse_account_id("not a number")
    end
  end

  describe "translate_property_error/1" do
    test "returns human messages" do
      assert WorkspaceManager.translate_property_error(:invalid_account_id) =~ "workspace"
      assert WorkspaceManager.translate_property_error(:unauthorized_account) =~ "access"
      assert WorkspaceManager.translate_property_error(:unknown) =~ "Unable"
    end
  end

  describe "changeset_error_message/1" do
    test "flattens Ecto errors" do
      changeset =
        GscAnalytics.Schemas.WorkspaceProperty.changeset(%GscAnalytics.Schemas.WorkspaceProperty{}, %{property_url: nil})

      assert WorkspaceManager.changeset_error_message(changeset) =~ "can't be blank"
    end
  end

  describe "list_accounts/1" do
    setup do
      user = GscAnalytics.AuthFixtures.user_fixture()
      scope = Auth.Scope.for_user(user)

      {:ok, workspace} =
        Workspaces.create_workspace(user.id, %{google_account_email: "test@example.com", name: "main", enabled: true})

      {:ok, _property} =
        Accounts.add_property(workspace.id, %{property_url: "sc-domain:example.com", is_active: true, display_name: "Example"})

      %{scope: scope}
    end

    test "returns accounts with unified properties", %{scope: scope} do
      {accounts, cache} = WorkspaceManager.list_accounts(scope)

      assert length(accounts) == 1
      assert map_size(cache) == 1

      [account] = accounts
      assert account.display_name == "main"
      assert is_list(account.unified_properties)
    end
  end
end
