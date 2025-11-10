defmodule GscAnalytics.AuthTest do
  use GscAnalytics.DataCase

  alias GscAnalytics.Auth

  import GscAnalytics.AuthFixtures
  alias GscAnalytics.Auth.{User, UserToken}

  describe "get_user_by_email/1" do
    test "does not return the user if the email does not exist" do
      refute Auth.get_user_by_email("unknown@example.com")
    end

    test "returns the user if the email exists" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Auth.get_user_by_email(user.email)
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "does not return the user if the email does not exist" do
      refute Auth.get_user_by_email_and_password("unknown@example.com", "hello world!")
    end

    test "does not return the user if the password is not valid" do
      user = user_fixture() |> set_password()
      refute Auth.get_user_by_email_and_password(user.email, "invalid")
    end

    test "returns the user if the email and password are valid" do
      %{id: id} = user = user_fixture() |> set_password()

      assert %User{id: ^id} =
               Auth.get_user_by_email_and_password(user.email, valid_user_password())
    end
  end

  describe "get_user!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Auth.get_user!(-1)
      end
    end

    test "returns the user with the given id" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Auth.get_user!(user.id)
    end
  end

  describe "register_user/1" do
    test "requires email to be set" do
      {:error, changeset} = Auth.register_user(%{})

      assert %{email: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates email when given" do
      {:error, changeset} = Auth.register_user(%{email: "not valid"})

      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "validates maximum values for email for security" do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = Auth.register_user(%{email: too_long})
      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end

    test "validates email uniqueness" do
      %{email: email} = user_fixture()
      {:error, changeset} = Auth.register_user(%{email: email})
      assert "has already been taken" in errors_on(changeset).email

      # Now try with the upper cased email too, to check that email case is ignored.
      {:error, changeset} = Auth.register_user(%{email: String.upcase(email)})
      assert "has already been taken" in errors_on(changeset).email
    end

    test "registers users without password" do
      email = unique_user_email()
      {:ok, user} = Auth.register_user(valid_user_attributes(email: email))
      assert user.email == email
      assert is_nil(user.hashed_password)
      assert is_nil(user.confirmed_at)
      assert is_nil(user.password)
    end
  end

  describe "sudo_mode?/2" do
    test "validates the authenticated_at time" do
      now = DateTime.utc_now()

      assert Auth.sudo_mode?(%User{authenticated_at: DateTime.utc_now()})
      assert Auth.sudo_mode?(%User{authenticated_at: DateTime.add(now, -19, :minute)})
      refute Auth.sudo_mode?(%User{authenticated_at: DateTime.add(now, -21, :minute)})

      # minute override
      refute Auth.sudo_mode?(
               %User{authenticated_at: DateTime.add(now, -11, :minute)},
               -10
             )

      # not authenticated
      refute Auth.sudo_mode?(%User{})
    end
  end

  describe "change_user_email/3" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Auth.change_user_email(%User{})
      assert changeset.required == [:email]
    end
  end

  describe "deliver_user_update_email_instructions/3" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Auth.deliver_user_update_email_instructions(user, "current@example.com", url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "change:current@example.com"
    end
  end

  describe "update_user_email/2" do
    setup do
      user = unconfirmed_user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Auth.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{user: user, token: token, email: email}
    end

    test "updates the email with a valid token", %{user: user, token: token, email: email} do
      assert {:ok, %{email: ^email}} = Auth.update_user_email(user, token)
      changed_user = Repo.get!(User, user.id)
      assert changed_user.email != user.email
      assert changed_user.email == email
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email with invalid token", %{user: user} do
      assert Auth.update_user_email(user, "oops") ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if user email changed", %{user: user, token: token} do
      assert Auth.update_user_email(%{user | email: "current@example.com"}, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if token expired", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])

      assert Auth.update_user_email(user, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "change_user_password/3" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Auth.change_user_password(%User{})
      assert changeset.required == [:password]
    end

    test "allows fields to be set" do
      changeset =
        Auth.change_user_password(
          %User{},
          %{
            "password" => "new valid password"
          },
          hash_password: false
        )

      assert changeset.valid?
      assert get_change(changeset, :password) == "new valid password"
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "oauth token management" do
    import Mox

    alias GscAnalytics.AccountsFixtures
    alias GscAnalytics.Auth.OAuthToken
    alias GscAnalytics.Repo

    setup :verify_on_exit!

    setup do
      user = GscAnalytics.AuthFixtures.user_fixture()
      workspace = AccountsFixtures.workspace_fixture(user: user)
      scope = %GscAnalytics.Auth.Scope{user: user, account_ids: [workspace.id]}
      %{scope: scope, workspace: workspace}
    end

    test "stores and retrieves encrypted OAuth tokens", %{scope: scope, workspace: workspace} do
      attrs = %{
        account_id: workspace.id,
        google_email: "test@example.com",
        refresh_token: "refresh_xyz",
        access_token: "access_abc",
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
        scopes: ["https://www.googleapis.com/auth/webmasters.readonly"]
      }

      {:ok, token} = Auth.store_oauth_token(scope, attrs)

      assert token.access_token == "access_abc"
      assert token.refresh_token == "refresh_xyz"

      raw = Repo.get_by(OAuthToken, account_id: workspace.id)
      refute raw.access_token_encrypted == "access_abc"
      refute raw.refresh_token_encrypted == "refresh_xyz"

      {:ok, fetched} = Auth.get_oauth_token(scope, workspace.id)
      assert fetched.google_email == "test@example.com"
    end

    test "updates an existing OAuth token in place", %{scope: scope, workspace: workspace} do
      attrs = %{
        account_id: workspace.id,
        google_email: "test@example.com",
        refresh_token: "refresh_xyz",
        access_token: "access_abc",
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
        scopes: ["scope-a"]
      }

      {:ok, initial} = Auth.store_oauth_token(scope, attrs)
      {:ok, updated} = Auth.store_oauth_token(scope, Map.put(attrs, :access_token, "new_token"))

      assert initial.id == updated.id
      assert updated.access_token == "new_token"
      assert {:ok, fetched} = Auth.get_oauth_token(scope, workspace.id)
      assert fetched.access_token == "new_token"
    end

    test "disconnects an OAuth account and clears tokens", %{scope: scope, workspace: workspace} do
      attrs = %{
        account_id: workspace.id,
        google_email: "test@example.com",
        refresh_token: "refresh_xyz",
        access_token: "access_abc",
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
        scopes: ["scope-a"]
      }

      {:ok, _} = Auth.store_oauth_token(scope, attrs)
      assert Auth.has_oauth_token?(scope, workspace.id)

      {:ok, _} = Auth.disconnect_oauth_account(scope, workspace.id)
      refute Auth.has_oauth_token?(scope, workspace.id)
    end

    test "rejects access for unauthorized scopes" do
      restricted_scope = AccountsFixtures.scope_with_accounts([1])
      assert {:error, :unauthorized_account} = Auth.get_oauth_token(restricted_scope, 2)
      assert {:error, :unauthorized_account} = Auth.has_oauth_token?(restricted_scope, 2)
    end

    test "handles nil current_scope for system access" do
      assert {:error, :not_found} = Auth.get_oauth_token(nil, 999)
      assert {:error, :missing_account_id} = Auth.store_oauth_token(nil, %{})
    end

    test "refreshes an expired OAuth token via HTTP", %{scope: scope, workspace: workspace} do
      expires_at = DateTime.add(DateTime.utc_now(), -60, :second)

      {:ok, _} =
        Auth.store_oauth_token(scope, %{
          account_id: workspace.id,
          google_email: "test@example.com",
          refresh_token: "refresh_xyz",
          access_token: "expired_token",
          expires_at: expires_at,
          scopes: ["scope-a"]
        })

      expect(GscAnalytics.HTTPClientMock, :post, fn url, opts ->
        assert url == "https://oauth2.googleapis.com/token"
        assert opts[:form][:grant_type] == "refresh_token"

        response = %Req.Response{
          status: 200,
          body: %{
            "access_token" => "new_access_token",
            "expires_in" => 3_600,
            "scope" => "scope-a"
          }
        }

        {:ok, response}
      end)

      {:ok, refreshed} = Auth.refresh_oauth_access_token(scope, workspace.id)
      assert refreshed.access_token == "new_access_token"
      assert refreshed.refresh_token == "refresh_xyz"

      {:ok, stored} = Auth.get_oauth_token(scope, workspace.id)
      assert stored.access_token == "new_access_token"
    end
  end

  describe "update_user_password/2" do
    setup do
      %{user: user_fixture()}
    end

    test "validates password", %{user: user} do
      {:error, changeset} =
        Auth.update_user_password(user, %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{user: user} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Auth.update_user_password(user, %{password: too_long})

      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "updates the password", %{user: user} do
      {:ok, {user, expired_tokens}} =
        Auth.update_user_password(user, %{
          password: "new valid password"
        })

      assert expired_tokens == []
      assert is_nil(user.password)
      assert Auth.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "deletes all tokens for the given user", %{user: user} do
      _ = Auth.generate_user_session_token(user)

      {:ok, {_, _}} =
        Auth.update_user_password(user, %{
          password: "new valid password"
        })

      refute Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "generate_user_session_token/1" do
    setup do
      %{user: user_fixture()}
    end

    test "generates a token", %{user: user} do
      token = Auth.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.context == "session"
      assert user_token.authenticated_at != nil

      # Creating the same token for another user should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%UserToken{
          token: user_token.token,
          user_id: user_fixture().id,
          context: "session"
        })
      end
    end

    test "duplicates the authenticated_at of given user in new token", %{user: user} do
      user = %{user | authenticated_at: DateTime.add(DateTime.utc_now(:second), -3600)}
      token = Auth.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.authenticated_at == user.authenticated_at
      assert DateTime.compare(user_token.inserted_at, user.authenticated_at) == :gt
    end
  end

  describe "get_user_by_session_token/1" do
    setup do
      user = user_fixture()
      token = Auth.generate_user_session_token(user)
      %{user: user, token: token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert {session_user, token_inserted_at} = Auth.get_user_by_session_token(token)
      assert session_user.id == user.id
      assert session_user.authenticated_at != nil
      assert token_inserted_at != nil
    end

    test "does not return user for invalid token" do
      refute Auth.get_user_by_session_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      dt = ~N[2020-01-01 00:00:00]
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: dt, authenticated_at: dt])
      refute Auth.get_user_by_session_token(token)
    end
  end

  describe "get_user_by_magic_link_token/1" do
    setup do
      user = user_fixture()
      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)
      %{user: user, token: encoded_token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert session_user = Auth.get_user_by_magic_link_token(token)
      assert session_user.id == user.id
    end

    test "does not return user for invalid token" do
      refute Auth.get_user_by_magic_link_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Auth.get_user_by_magic_link_token(token)
    end
  end

  describe "login_user_by_magic_link/1" do
    test "confirms user and expires tokens" do
      user = unconfirmed_user_fixture()
      refute user.confirmed_at
      {encoded_token, hashed_token} = generate_user_magic_link_token(user)

      assert {:ok, {user, [%{token: ^hashed_token}]}} =
               Auth.login_user_by_magic_link(encoded_token)

      assert user.confirmed_at
    end

    test "returns user and (deleted) token for confirmed user" do
      user = user_fixture()
      assert user.confirmed_at
      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)
      assert {:ok, {^user, []}} = Auth.login_user_by_magic_link(encoded_token)
      # one time use only
      assert {:error, :not_found} = Auth.login_user_by_magic_link(encoded_token)
    end

    test "raises when unconfirmed user has password set" do
      user = unconfirmed_user_fixture()
      {1, nil} = Repo.update_all(User, set: [hashed_password: "hashed"])
      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)

      assert_raise RuntimeError, ~r/magic link log in is not allowed/, fn ->
        Auth.login_user_by_magic_link(encoded_token)
      end
    end
  end

  describe "delete_user_session_token/1" do
    test "deletes the token" do
      user = user_fixture()
      token = Auth.generate_user_session_token(user)
      assert Auth.delete_user_session_token(token) == :ok
      refute Auth.get_user_by_session_token(token)
    end
  end

  describe "deliver_login_instructions/2" do
    setup do
      %{user: unconfirmed_user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Auth.deliver_login_instructions(user, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "login"
    end
  end

  describe "inspect/2 for the User module" do
    test "does not include password" do
      refute inspect(%User{password: "123456"}) =~ "password: \"123456\""
    end
  end

  describe "OAuth token status management" do
    alias GscAnalytics.Auth.OAuthToken
    alias GscAnalytics.AccountsFixtures

    setup do
      account = AccountsFixtures.workspace_fixture()
      %{account: account}
    end

    test "mark_invalid/2 sets token status to invalid with error message", %{account: account} do
      # Create a valid OAuth token
      {:ok, token} =
        Auth.store_oauth_token(nil, %{
          account_id: account.id,
          google_email: "test@example.com",
          refresh_token: "test_refresh_token",
          access_token: "test_access_token",
          expires_at: DateTime.add(DateTime.utc_now(), 3600),
          scopes: ["https://www.googleapis.com/auth/webmasters.readonly"]
        })

      assert token.status == :valid
      assert is_nil(token.last_error)

      # Mark as invalid
      token_from_db = Repo.get(OAuthToken, token.id)
      changeset = OAuthToken.mark_invalid(token_from_db, "Token has been revoked")
      {:ok, updated_token} = Repo.update(changeset)

      assert updated_token.status == :invalid
      assert updated_token.last_error == "Token has been revoked"
      assert updated_token.last_validated_at != nil
    end

    test "mark_valid/1 clears error and sets status to valid", %{account: account} do
      # Create a valid OAuth token first
      {:ok, token} =
        Auth.store_oauth_token(nil, %{
          account_id: account.id,
          google_email: "test@example.com",
          refresh_token: "test_refresh_token",
          access_token: "test_access_token",
          expires_at: DateTime.add(DateTime.utc_now(), 3600),
          scopes: ["https://www.googleapis.com/auth/webmasters.readonly"]
        })

      # Mark as invalid using mark_invalid
      token_from_db = Repo.get(OAuthToken, token.id)

      {:ok, invalid_token} =
        token_from_db
        |> OAuthToken.mark_invalid("Previous error")
        |> Repo.update()

      assert invalid_token.status == :invalid

      # Mark as valid
      changeset = OAuthToken.mark_valid(invalid_token)
      {:ok, updated_token} = Repo.update(changeset)

      assert updated_token.status == :valid
      assert is_nil(updated_token.last_error)
      assert updated_token.last_validated_at != nil
    end

    test "validate_oauth_token_status/2 returns token status", %{account: account} do
      # Create a token
      {:ok, _token} =
        Auth.store_oauth_token(nil, %{
          account_id: account.id,
          google_email: "test@example.com",
          refresh_token: "test_refresh_token",
          access_token: "test_access_token",
          expires_at: DateTime.add(DateTime.utc_now(), 3600),
          scopes: ["https://www.googleapis.com/auth/webmasters.readonly"]
        })

      # Check status
      assert {:ok, :valid} = Auth.validate_oauth_token_status(nil, account.id)
    end

    test "validate_oauth_token_status/2 returns not_found when no token exists" do
      # Non-existent account
      assert {:error, :not_found} = Auth.validate_oauth_token_status(nil, 99999)
    end

    test "helper functions correctly identify token status", %{account: account} do
      {:ok, token} =
        Auth.store_oauth_token(nil, %{
          account_id: account.id,
          google_email: "test@example.com",
          refresh_token: "test_refresh_token",
          access_token: "test_access_token",
          expires_at: DateTime.add(DateTime.utc_now(), 3600),
          scopes: ["https://www.googleapis.com/auth/webmasters.readonly"]
        })

      token_from_db = Repo.get(OAuthToken, token.id)

      # Test valid token
      assert OAuthToken.valid?(token_from_db)
      refute OAuthToken.invalid?(token_from_db)
      refute OAuthToken.expired?(token_from_db)
      refute OAuthToken.needs_reauth?(token_from_db)

      # Mark as invalid and test
      {:ok, invalid_token} =
        token_from_db
        |> OAuthToken.mark_invalid("Test error")
        |> Repo.update()

      refute OAuthToken.valid?(invalid_token)
      assert OAuthToken.invalid?(invalid_token)
      refute OAuthToken.expired?(invalid_token)
      assert OAuthToken.needs_reauth?(invalid_token)

      # Mark as expired and test
      {:ok, expired_token} =
        invalid_token
        |> OAuthToken.mark_expired()
        |> Repo.update()

      refute OAuthToken.valid?(expired_token)
      refute OAuthToken.invalid?(expired_token)
      assert OAuthToken.expired?(expired_token)
      assert OAuthToken.needs_reauth?(expired_token)
    end

    test "validate_oauth_token_status/2 detects and marks expired tokens", %{account: account} do
      # Create a token with an expired timestamp
      {:ok, token} =
        Auth.store_oauth_token(nil, %{
          account_id: account.id,
          google_email: "test@example.com",
          refresh_token: "test_refresh_token",
          access_token: "test_access_token",
          expires_at: DateTime.add(DateTime.utc_now(), -3600),
          scopes: ["https://www.googleapis.com/auth/webmasters.readonly"],
          status: :valid
        })

      assert token.status == :valid

      # Validate should detect expiration and mark token as expired
      assert {:ok, :expired} = Auth.validate_oauth_token_status(nil, account.id)

      # Verify token was marked as expired in database
      updated_token = Repo.get(OAuthToken, token.id)
      assert updated_token.status == :expired
    end

    test "validate_oauth_token_status/2 returns status immediately for already invalid tokens", %{
      account: account
    } do
      # Create a valid token first
      {:ok, initial_token} =
        Auth.store_oauth_token(nil, %{
          account_id: account.id,
          google_email: "test@example.com",
          refresh_token: "test_refresh_token",
          access_token: "test_access_token",
          expires_at: DateTime.add(DateTime.utc_now(), 3600),
          scopes: ["https://www.googleapis.com/auth/webmasters.readonly"]
        })

      # Manually mark token as invalid in database
      db_token = Repo.get(OAuthToken, initial_token.id)

      {:ok, token} =
        db_token
        |> OAuthToken.mark_invalid("Token revoked")
        |> Repo.update()

      # Should return invalid without database write
      assert {:ok, :invalid} = Auth.validate_oauth_token_status(nil, account.id)

      # Token should remain unchanged (no last_validated_at update)
      updated_token = Repo.get(OAuthToken, token.id)
      assert updated_token.last_validated_at == token.last_validated_at
    end

    test "validate_oauth_token_status/2 returns valid for non-expired valid tokens", %{
      account: account
    } do
      # Create a valid non-expired token
      {:ok, _token} =
        Auth.store_oauth_token(nil, %{
          account_id: account.id,
          google_email: "test@example.com",
          refresh_token: "test_refresh_token",
          access_token: "test_access_token",
          expires_at: DateTime.add(DateTime.utc_now(), 3600),
          scopes: ["https://www.googleapis.com/auth/webmasters.readonly"]
        })

      # Should return valid without updates
      assert {:ok, :valid} = Auth.validate_oauth_token_status(nil, account.id)
    end
  end

  describe "OAuth token integration - invalid_grant handling" do
    alias GscAnalytics.Auth.OAuthToken
    alias GscAnalytics.AccountsFixtures

    setup do
      account = AccountsFixtures.workspace_fixture()
      %{account: account}
    end

    # Note: This test would require mocking the HTTP client to return invalid_grant
    # For now, we document the expected behavior
    @tag :skip
    test "refresh_oauth_access_token marks token invalid on invalid_grant", %{account: account} do
      # Create a token
      {:ok, token} =
        Auth.store_oauth_token(nil, %{
          account_id: account.id,
          google_email: "test@example.com",
          refresh_token: "test_refresh_token",
          access_token: "test_access_token",
          expires_at: DateTime.add(DateTime.utc_now(), -100),
          scopes: ["https://www.googleapis.com/auth/webmasters.readonly"]
        })

      # Mock would return invalid_grant here
      # result = Auth.refresh_oauth_access_token(nil, account.id)
      # assert {:error, :oauth_token_invalid} = result

      # Verify token marked as invalid
      # updated_token = Repo.get(OAuthToken, token.id)
      # assert updated_token.status == :invalid
      # assert updated_token.last_error != nil
    end
  end

  describe "OAuth token integration - Authenticator" do
    alias GscAnalytics.Auth.OAuthToken
    alias GscAnalytics.AccountsFixtures
    alias GscAnalytics.DataSources.GSC.Support.Authenticator

    setup do
      account = AccountsFixtures.workspace_fixture()

      # Start Authenticator GenServer for these tests
      {:ok, _pid} = start_supervised({Authenticator, name: Authenticator})

      %{account: account}
    end

    test "Authenticator.get_token/1 rejects invalid tokens", %{account: account} do
      # Create a valid token first
      {:ok, initial_token} =
        Auth.store_oauth_token(nil, %{
          account_id: account.id,
          google_email: "test@example.com",
          refresh_token: "test_refresh_token",
          access_token: "test_access_token",
          expires_at: DateTime.add(DateTime.utc_now(), 3600),
          scopes: ["https://www.googleapis.com/auth/webmasters.readonly"]
        })

      # Manually mark token as invalid in database
      db_token = Repo.get(OAuthToken, initial_token.id)

      {:ok, _token} =
        db_token
        |> OAuthToken.mark_invalid("Token has been revoked")
        |> Repo.update()

      # Authenticator should reject the token
      assert {:error, :oauth_token_invalid} = Authenticator.get_token(account.id)
    end

    test "Authenticator.get_token/1 rejects expired tokens", %{account: account} do
      # Create a valid token first
      {:ok, initial_token} =
        Auth.store_oauth_token(nil, %{
          account_id: account.id,
          google_email: "test@example.com",
          refresh_token: "test_refresh_token",
          access_token: "test_access_token",
          expires_at: DateTime.add(DateTime.utc_now(), 3600),
          scopes: ["https://www.googleapis.com/auth/webmasters.readonly"]
        })

      # Manually mark token as expired in database
      db_token = Repo.get(OAuthToken, initial_token.id)

      {:ok, _token} =
        db_token
        |> OAuthToken.mark_expired()
        |> Repo.update()

      # Authenticator should reject the token
      assert {:error, :oauth_token_invalid} = Authenticator.get_token(account.id)
    end

    test "Authenticator.get_token/1 accepts valid tokens", %{account: account} do
      # Create a valid token
      {:ok, token} =
        Auth.store_oauth_token(nil, %{
          account_id: account.id,
          google_email: "test@example.com",
          refresh_token: "test_refresh_token",
          access_token: "test_access_token",
          expires_at: DateTime.add(DateTime.utc_now(), 3600),
          scopes: ["https://www.googleapis.com/auth/webmasters.readonly"]
        })

      # Authenticator should return the token
      assert {:ok, access_token} = Authenticator.get_token(account.id)
      assert access_token == token.access_token
    end

    test "store_oauth_token sets status to valid when storing fresh tokens", %{account: account} do
      # Create a token without specifying status
      {:ok, token} =
        Auth.store_oauth_token(nil, %{
          account_id: account.id,
          google_email: "test@example.com",
          refresh_token: "test_refresh_token",
          access_token: "test_access_token",
          expires_at: DateTime.add(DateTime.utc_now(), 3600),
          scopes: ["https://www.googleapis.com/auth/webmasters.readonly"]
        })

      # Status should be automatically set to :valid
      assert token.status == :valid

      # Verify in database as well
      db_token = Repo.get(OAuthToken, token.id)
      assert db_token.status == :valid
    end

    test "store_oauth_token updates invalid tokens to valid status", %{account: account} do
      # Create a valid token first
      {:ok, initial_token} =
        Auth.store_oauth_token(nil, %{
          account_id: account.id,
          google_email: "test@example.com",
          refresh_token: "old_refresh_token",
          access_token: "old_access_token",
          expires_at: DateTime.add(DateTime.utc_now(), 3600),
          scopes: ["https://www.googleapis.com/auth/webmasters.readonly"]
        })

      assert initial_token.status == :valid

      # Manually mark token as invalid in database (simulating token revocation)
      db_token = Repo.get(OAuthToken, initial_token.id)

      {:ok, invalid_token} =
        db_token
        |> OAuthToken.mark_invalid("Token has been expired or revoked.")
        |> Repo.update()

      assert invalid_token.status == :invalid
      assert invalid_token.last_error == "Token has been expired or revoked."

      # Now update with fresh tokens (simulating OAuth re-authentication callback)
      {:ok, updated_token} =
        Auth.store_oauth_token(nil, %{
          account_id: account.id,
          google_email: "test@example.com",
          refresh_token: "new_refresh_token",
          access_token: "new_access_token",
          expires_at: DateTime.add(DateTime.utc_now(), 3600),
          scopes: ["https://www.googleapis.com/auth/webmasters.readonly"]
        })

      # Status should be updated to :valid
      assert updated_token.status == :valid
      assert updated_token.access_token == "new_access_token"
      assert updated_token.refresh_token == "new_refresh_token"

      # Verify this is the same token record (update, not insert)
      assert updated_token.id == invalid_token.id

      # Verify in database
      db_token_after = Repo.get(OAuthToken, updated_token.id)
      assert db_token_after.status == :valid
    end
  end
end
