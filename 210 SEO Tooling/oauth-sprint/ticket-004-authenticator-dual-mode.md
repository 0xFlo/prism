# Ticket-004: Dual-Mode Authenticator (JWT + OAuth)

## Status: TODO
**Priority:** P1
**Estimate:** 1.5 hours
**Dependencies:** ticket-002 (Auth context with OAuth functions)
**Blocks:** ticket-007 (testing)

## Problem Statement
The Authenticator GenServer currently only supports service account JWT authentication. Need to add OAuth support while maintaining backward compatibility:
- Account 1 (Scrapfly) → Continue using JWT service account
- Account 2 (Alba) → Use OAuth refresh tokens
- Automatic detection of auth method per account
- Seamless token refresh for both methods

Critical: Service account auth MUST continue working unchanged.

## Acceptance Criteria
- [ ] Auth method auto-detected per account
- [ ] JWT flow unchanged for Account 1
- [ ] OAuth flow working for Account 2
- [ ] Automatic token refresh for expired OAuth tokens
- [ ] Both methods cache tokens in GenServer state
- [ ] No breaking changes to public API
- [ ] Proper error messages for each auth type

## Implementation Plan

### 1. Add Auth Method Detection

In `lib/gsc_analytics/data_sources/gsc/support/authenticator.ex`:

```elixir
defp get_auth_method(account_id) do
  # Pass nil as current_scope for internal use
  if GscAnalytics.Auth.has_oauth_token?(nil, account_id) do
    :oauth
  else
    :service_account
  end
end
```

### 2. Update maybe_fetch_token to Branch

```elixir
defp maybe_fetch_token(state, account_id, opts \\ []) do
  case get_auth_method(account_id) do
    :service_account ->
      # Rename existing implementation
      fetch_service_account_token(state, account_id, opts)

    :oauth ->
      # New OAuth implementation
      fetch_oauth_token(state, account_id, opts)
  end
end
```

### 3. Implement OAuth Token Fetching

```elixir
defp fetch_oauth_token(state, account_id, _opts) do
  # Pass nil as current_scope for internal authenticator use
  case GscAnalytics.Auth.get_oauth_token(nil, account_id) do
    {:ok, oauth_token} ->
      # oauth_token has decrypted fields from ticket-002!
      if token_expired?(oauth_token.expires_at) do
        # Refresh the token
        case GscAnalytics.Auth.refresh_oauth_access_token(nil, account_id) do
          {:ok, refreshed} ->
            # refreshed.access_token is decrypted and ready to use
            new_state = put_account(state, account_id, %{
              token: refreshed.access_token,
              expires_at: refreshed.expires_at
            })
            {new_state, {:ok, refreshed.access_token}}

          {:error, reason} ->
            Logger.error("OAuth token refresh failed for account #{account_id}: #{inspect(reason)}")
            {state, {:error, {:oauth_refresh_failed, reason}}}
        end
      else
        # Token still valid, cache it
        new_state = put_account(state, account_id, %{
          token: oauth_token.access_token,
          expires_at: oauth_token.expires_at
        })
        {new_state, {:ok, oauth_token.access_token}}
      end

    {:error, :not_found} ->
      {state, {:error, :oauth_not_configured}}
  end
end
```

### 4. Rename Existing Implementation

```elixir
# Rename current maybe_fetch_token implementation
defp fetch_service_account_token(state, account_id, opts) do
  # ... existing JWT logic unchanged ...
end
```

### 5. Update Bootstrap Process

The `handle_continue(:bootstrap_accounts, state)` callback should work for both auth types without changes, as it calls `maybe_fetch_token` which now handles both.

## Testing Plan

### Unit Tests
```elixir
test "detects service account auth method" do
  # Account 1 has service_account_file configured
  assert :service_account == get_auth_method(1)
end

test "detects OAuth auth method" do
  # Store OAuth token for Account 2
  Auth.store_oauth_token(nil, %{account_id: 2, ...})
  assert :oauth == get_auth_method(2)
end

test "fetches JWT token for service account" do
  {:ok, token} = Authenticator.get_token(1)
  assert is_binary(token)
end

test "fetches OAuth token when configured" do
  # Setup OAuth token
  Auth.store_oauth_token(nil, %{account_id: 2, ...})
  {:ok, token} = Authenticator.get_token(2)
  assert is_binary(token)
end

test "refreshes expired OAuth token automatically" do
  # Store expired token
  # Mock refresh response
  # Verify new token returned
end
```

### Integration Testing
- Start authenticator with both accounts configured
- Verify Account 1 uses JWT
- Add OAuth token for Account 2
- Verify Account 2 uses OAuth
- Force token expiry and verify refresh

## Error Scenarios
- [ ] OAuth not configured → {:error, :oauth_not_configured}
- [ ] Refresh token invalid → {:error, {:oauth_refresh_failed, reason}}
- [ ] Service account missing → {:error, :missing_credentials}
- [ ] Network failure during refresh → {:error, {:http_error, ...}}

## Rollback Plan
If OAuth causes issues:
1. Remove get_auth_method function
2. Revert maybe_fetch_token to original
3. Remove fetch_oauth_token function
4. Authenticator continues with JWT only

## Performance Considerations
- Token caching in GenServer state (both auth types)
- Proactive refresh before expiry
- Retry logic for failed refreshes
- No blocking operations in GenServer

## Success Metrics
- Account 1 continues working unchanged
- Account 2 can authenticate via OAuth
- Token refresh happens automatically
- No performance degradation
- Clear error messages for troubleshooting