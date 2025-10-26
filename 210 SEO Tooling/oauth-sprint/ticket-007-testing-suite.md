# Ticket-007: Test Suite for Dual Authentication

## Status: TODO
**Priority:** P2
**Estimate:** 1.5 hours
**Dependencies:** ticket-004 (Authenticator dual-mode)
**Blocks:** Production deployment

## Problem Statement
Need comprehensive test coverage for:
- OAuth token management functions
- Dual-mode authenticator (JWT + OAuth)
- State token security
- Token refresh logic
- Error scenarios

Must ensure:
- No regression in service account auth
- OAuth works correctly
- Security measures are tested
- Edge cases handled

## Acceptance Criteria
- [ ] Auth context OAuth functions tested
- [ ] Authenticator dual-mode tested
- [ ] GoogleAuth state verification tested
- [ ] Token refresh tested with mocks
- [ ] Integration tests for both auth paths
- [ ] Security tests for CSRF protection
- [ ] All existing tests still pass

## Test Files to Create/Modify

### 1. test/gsc_analytics/auth_test.exs (ADD)

```elixir
describe "OAuth token management" do
  test "stores and retrieves OAuth token with encryption" do
    attrs = %{
      account_id: 2,
      google_email: "test@example.com",
      refresh_token: "refresh_xyz",
      access_token: "access_abc",
      expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
      scopes: ["https://www.googleapis.com/auth/webmasters.readonly"]
    }

    {:ok, token} = Auth.store_oauth_token(nil, attrs)

    # Verify returned token has decrypted fields
    assert token.access_token == "access_abc"
    assert token.refresh_token == "refresh_xyz"

    # Verify stored token is encrypted
    raw_token = Repo.get(OAuthToken, token.id)
    assert raw_token.access_token_encrypted != "access_abc"
  end

  test "updates existing OAuth token" do
    # Store initial token
    {:ok, initial} = Auth.store_oauth_token(nil, %{account_id: 2, ...})

    # Update with new access token
    {:ok, updated} = Auth.store_oauth_token(nil, %{
      account_id: 2,
      access_token: "new_token"
    })

    assert updated.id == initial.id
    assert updated.access_token == "new_token"
  end

  test "disconnects OAuth account" do
    {:ok, _} = Auth.store_oauth_token(nil, %{account_id: 2, ...})
    assert Auth.has_oauth_token?(nil, 2)

    {:ok, _} = Auth.disconnect_oauth_account(nil, 2)
    refute Auth.has_oauth_token?(nil, 2)
  end

  test "handles nil current_scope" do
    # All functions should accept nil for internal use
    assert {:error, :not_found} = Auth.get_oauth_token(nil, 999)
  end
end
```

### 2. test/gsc_analytics/data_sources/gsc/support/authenticator_integration_test.exs (MODIFY)

```elixir
describe "dual authentication mode" do
  setup do
    # Start authenticator
    start_supervised!(Authenticator)
    :ok
  end

  test "uses service account for Account 1" do
    # Account 1 has service_account_file configured
    assert {:ok, token} = Authenticator.get_token(1)
    assert is_binary(token)
    assert String.starts_with?(token, "ya29.") # JWT format
  end

  test "uses OAuth for Account 2 when configured" do
    # Store OAuth token
    {:ok, _} = Auth.store_oauth_token(nil, %{
      account_id: 2,
      google_email: "test@alba.cc",
      refresh_token: "refresh_xyz",
      access_token: "oauth_access_token",
      expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
      scopes: ["https://www.googleapis.com/auth/webmasters.readonly"]
    })

    # Should return OAuth token
    assert {:ok, token} = Authenticator.get_token(2)
    assert token == "oauth_access_token"
  end

  test "returns error when OAuth not configured" do
    # Account 2 has no OAuth and no service account
    assert {:error, :oauth_not_configured} = Authenticator.get_token(2)
  end

  test "refreshes expired OAuth token automatically" do
    # Store expired token
    {:ok, _} = Auth.store_oauth_token(nil, %{
      account_id: 2,
      google_email: "test@alba.cc",
      refresh_token: "refresh_xyz",
      access_token: "expired_token",
      expires_at: DateTime.add(DateTime.utc_now(), -10, :second),
      scopes: ["https://www.googleapis.com/auth/webmasters.readonly"]
    })

    # Mock the refresh request
    expect(ReqMock, :post, fn url, opts ->
      assert url == "https://oauth2.googleapis.com/token"
      assert opts[:form][:grant_type] == "refresh_token"

      {:ok, %Req.Response{
        status: 200,
        body: %{
          "access_token" => "new_fresh_token",
          "expires_in" => 3600,
          "token_type" => "Bearer"
        }
      }}
    end)

    # Should trigger refresh and return new token
    assert {:ok, token} = Authenticator.get_token(2)
    assert token == "new_fresh_token"
  end
end
```

### 3. test/gsc_analytics_web/google_auth_test.exs (NEW)

```elixir
defmodule GscAnalyticsWeb.GoogleAuthTest do
  use GscAnalyticsWeb.ConnCase
  alias GscAnalyticsWeb.GoogleAuth

  describe "state token security" do
    test "encodes account_id and user_id in state", %{conn: conn} do
      user = insert(:user)
      conn = assign(conn, :current_scope, %{user: user})

      state = GoogleAuth.generate_state(conn, 2)

      {:ok, data} = Phoenix.Token.verify(
        GscAnalyticsWeb.Endpoint,
        "oauth_state",
        state
      )

      assert data.account_id == 2
      assert data.user_id == user.id
    end

    test "rejects state with wrong user_id", %{conn: conn} do
      user1 = insert(:user)
      user2 = insert(:user)

      # Generate state for user1
      conn1 = assign(build_conn(), :current_scope, %{user: user1})
      state = GoogleAuth.generate_state(conn1, 2)

      # Try to use with user2
      conn2 = assign(build_conn(), :current_scope, %{user: user2})
      assert {:error, :invalid_state} = GoogleAuth.verify_state(state, conn2.assigns.current_scope)
    end

    test "rejects expired state token", %{conn: conn} do
      user = insert(:user)
      conn = assign(conn, :current_scope, %{user: user})

      # Generate state with past timestamp
      state = Phoenix.Token.sign(
        GscAnalyticsWeb.Endpoint,
        "oauth_state",
        %{account_id: 2, user_id: user.id},
        signed_at: System.system_time(:second) - 700  # 11+ minutes ago
      )

      assert {:error, :expired} = GoogleAuth.verify_state(state, conn.assigns.current_scope)
    end
  end

  describe "email extraction" do
    test "extracts email from valid id_token" do
      # Create fake JWT
      header = Base.url_encode64("{\"alg\":\"RS256\"}", padding: false)
      payload = Base.url_encode64("{\"email\":\"test@example.com\"}", padding: false)
      signature = Base.url_encode64("fake_signature", padding: false)

      tokens = %{"id_token" => "#{header}.#{payload}.#{signature}"}

      assert GoogleAuth.extract_email_safely(tokens) == "test@example.com"
    end

    test "handles missing id_token gracefully" do
      tokens = %{"access_token" => "token_only"}
      assert GoogleAuth.extract_email_safely(tokens) == "unknown@oauth.local"
    end

    test "handles malformed id_token" do
      tokens = %{"id_token" => "not_a_jwt"}
      assert GoogleAuth.extract_email_safely(tokens) == "unknown@oauth.local"
    end
  end
end
```

### 4. Test Helpers/Mocks

Create `test/support/req_mock.ex`:

```elixir
defmodule ReqMock do
  def post(url, opts) do
    # Default mock implementation
    {:error, :not_mocked}
  end
end
```

Use in tests with Mox or similar mocking library.

## Testing Checklist

### Unit Tests
- [ ] OAuth token CRUD operations
- [ ] Token encryption/decryption
- [ ] State token generation/verification
- [ ] Email extraction from JWT
- [ ] Expires_at calculation

### Integration Tests
- [ ] Service account auth still works
- [ ] OAuth auth when configured
- [ ] Automatic token refresh
- [ ] Error handling

### Security Tests
- [ ] CSRF protection via state token
- [ ] User ID verification in state
- [ ] State token expiry
- [ ] Token encryption at rest

### Edge Cases
- [ ] Nil current_scope handling
- [ ] Missing OAuth config
- [ ] Expired refresh token
- [ ] Network failures
- [ ] Malformed responses

## Success Metrics
- All new tests pass
- No regression in existing tests
- Code coverage > 80% for OAuth code
- Security vulnerabilities tested
- Mock usage documented