defmodule GscAnalytics.AccountsFixtures do
  @moduledoc """
  Test helpers for working with account-related fixtures.
  """

  alias GscAnalytics.Auth.Scope

  def scope_with_accounts(account_ids) when is_list(account_ids) do
    user = GscAnalytics.AuthFixtures.user_fixture()
    scope = Scope.for_user(user)
    %{scope | account_ids: account_ids}
  end

  def scope_with_accounts(account_id) when is_integer(account_id) do
    scope_with_accounts([account_id])
  end
end
