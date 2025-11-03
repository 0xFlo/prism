defmodule GscAnalytics.AccountsFixtures do
  @moduledoc """
  Test helpers for working with account-related fixtures.
  """

  alias GscAnalytics.Auth.Scope
  alias GscAnalytics.Workspaces

  def scope_with_accounts(account_ids) when is_list(account_ids) do
    user = GscAnalytics.AuthFixtures.user_fixture()
    scope = Scope.for_user(user)
    %{scope | account_ids: account_ids}
  end

  def scope_with_accounts(account_id) when is_integer(account_id) do
    scope_with_accounts([account_id])
  end

  @doc """
  Creates a workspace for testing.

  ## Options
    * `:user` - Existing user to associate the workspace with (defaults to creating a new user)
    * `:google_account_email` - Email for the Google account (defaults to "test-<unique>@example.com")
    * `:name` - Workspace name (defaults to the email)
    * `:enabled` - Whether the workspace is enabled (defaults to true)
  """
  def workspace_fixture(attrs \\ []) do
    user = Keyword.get(attrs, :user) || GscAnalytics.AuthFixtures.user_fixture()

    email =
      Keyword.get(attrs, :google_account_email) ||
        "test-#{System.unique_integer([:positive])}@example.com"

    {:ok, workspace} =
      Workspaces.create_workspace(user.id, %{
        google_account_email: email,
        name: Keyword.get(attrs, :name) || email,
        enabled: Keyword.get(attrs, :enabled, true)
      })

    workspace
  end
end
