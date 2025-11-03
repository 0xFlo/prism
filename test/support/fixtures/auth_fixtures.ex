defmodule GscAnalytics.AuthFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `GscAnalytics.Auth` context.
  """

  import Ecto.Query

  alias GscAnalytics.Auth
  alias GscAnalytics.Auth.Scope

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email()
    })
  end

  def unconfirmed_user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Auth.register_user()

    user
  end

  def user_fixture(attrs \\ %{}) do
    user = unconfirmed_user_fixture(attrs)

    token =
      extract_user_token(fn url ->
        Auth.deliver_login_instructions(user, url)
      end)

    {:ok, {user, _expired_tokens}} =
      Auth.login_user_by_magic_link(token)

    user
  end

  def user_scope_fixture do
    user = user_fixture()
    user_scope_fixture(user)
  end

  def user_scope_fixture(user) do
    Scope.for_user(user)
  end

  def set_password(user) do
    {:ok, {user, _expired_tokens}} =
      Auth.update_user_password(user, %{password: valid_user_password()})

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    GscAnalytics.Repo.update_all(
      from(t in Auth.UserToken,
        where: t.token == ^token
      ),
      set: [authenticated_at: authenticated_at]
    )
  end

  def generate_user_magic_link_token(user) do
    {encoded_token, user_token} = Auth.UserToken.build_email_token(user, "login")
    GscAnalytics.Repo.insert!(user_token)
    {encoded_token, user_token.token}
  end

  def offset_user_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    GscAnalytics.Repo.update_all(
      from(ut in Auth.UserToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end

  @doc """
  Creates an OAuth token for testing.

  ## Options
    * `:workspace` - Workspace struct (required if not passed as first arg)
    * `:access_token` - OAuth access token (defaults to random)
    * `:refresh_token` - OAuth refresh token (defaults to random)
    * `:expires_at` - Token expiration (defaults to 1 hour from now)
    * `:scopes` - OAuth scopes (defaults to webmasters.readonly)
    * `:google_email` - Google account email (defaults to workspace email)
  """
  def oauth_token_fixture(workspace, attrs \\ []) do
    user = workspace.user || user_fixture()
    scope = %Scope{user: user, account_ids: [workspace.id]}

    token_attrs = %{
      account_id: workspace.id,
      access_token: Keyword.get(attrs, :access_token, "test_token_#{:rand.uniform(100_000)}"),
      refresh_token: Keyword.get(attrs, :refresh_token, "test_refresh_#{:rand.uniform(100_000)}"),
      expires_at:
        Keyword.get(attrs, :expires_at, DateTime.add(DateTime.utc_now(), 3600, :second)),
      scopes:
        Keyword.get(attrs, :scopes, ["https://www.googleapis.com/auth/webmasters.readonly"]),
      google_email: Keyword.get(attrs, :google_email, workspace.google_account_email)
    }

    {:ok, token} = Auth.store_oauth_token(scope, token_attrs)
    token
  end
end
