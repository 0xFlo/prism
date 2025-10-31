# Ticket-004: Dual-Mode Authenticator (JWT + OAuth)

## Status: DONE
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
- [x] Auth method auto-detected per account
- [x] JWT flow unchanged for Account 1
- [x] OAuth flow working for Account 2
- [x] Automatic token refresh for expired OAuth tokens
- [x] Both methods cache tokens in GenServer state
- [x] No breaking changes to public API
- [x] Proper error messages for each auth type

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

### 3. Implement OAuth Token Fetching with Proactive Refresh

**Best Practice from Research (Proactive Token Refresh Pattern):**
- Use `Process.send_after/3` to schedule token refresh BEFORE expiry
- Set `refresh_leading_time` to 5 minutes before expiry
- Avoid waiting for 401 errors by refreshing proactively
- Cache tokens with expiry timestamps in GenServer state
- Verify token not expired before returning from get function

**Why proactive refresh:**
Refreshing just before expiry avoids the need to handle 401 errors mid-request. This pattern is used in production systems like ExAws's authentication cache.

```elixir
# Add to module attributes
@refresh_leading_time 300_000  # 5 minutes in milliseconds

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

            # Schedule proactive refresh before expiry
            schedule_token_refresh(refreshed.expires_at, account_id)

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

        # Schedule proactive refresh before expiry
        schedule_token_refresh(oauth_token.expires_at, account_id)

        {new_state, {:ok, oauth_token.access_token}}
      end

    {:error, :not_found} ->
      {state, {:error, :oauth_not_configured}}
  end
end

# Helper to schedule proactive token refresh
defp schedule_token_refresh(expires_at, account_id) do
  time_until_expiry = DateTime.diff(expires_at, DateTime.utc_now(), :millisecond)
  time_until_refresh = max(0, time_until_expiry - @refresh_leading_time)

  Process.send_after(self(), {:refresh_oauth_token, account_id}, time_until_refresh)
end

# Add handle_info callback to handle scheduled refresh
def handle_info({:refresh_oauth_token, account_id}, state) do
  case GscAnalytics.Auth.refresh_oauth_access_token(nil, account_id) do
    {:ok, refreshed} ->
      new_state = put_account(state, account_id, %{
        token: refreshed.access_token,
        expires_at: refreshed.expires_at
      })

      # Schedule next refresh
      schedule_token_refresh(refreshed.expires_at, account_id)

      {:noreply, new_state}

    {:error, reason} ->
      Logger.warning("Proactive OAuth token refresh failed for account #{account_id}: #{inspect(reason)}")
      # Token will be refreshed on next request
      {:noreply, state}
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
- Proactive refresh before expiry (5 min lead time)
- Retry logic for failed refreshes (handled on next request)
- No blocking operations in GenServer (refresh happens in background)

## Security Considerations for GenServer Token Storage

**From Research:** GenServers that store sensitive data like access tokens in their state could potentially have that data leaked through logging tools when errors are raised.

**Mitigation strategies:**
1. **Never log the full state** - Use selective logging that excludes token fields
2. **Implement custom inspect** - Override `Inspect` protocol for state struct
3. **Use ETS for token storage** (alternative) - Tokens in ETS instead of GenServer state
4. **Scrub crash reports** - Configure Logger to scrub sensitive fields

**Current approach:** Keep tokens in GenServer state (simplest), but be aware:
- Don't use `inspect(state)` in logs
- Crash reports via Logger will show state (configure Logger scrubbing if needed)
- For production, consider implementing custom `Inspect` protocol

**Example custom inspect:**
```elixir
defimpl Inspect, for: Authenticator.State do
  def inspect(state, _opts) do
    "#Authenticator.State<accounts: #{map_size(state.accounts)} [REDACTED]>"
  end
end
```

## Success Metrics
- Account 1 continues working unchanged
- Account 2 can authenticate via OAuth
- Token refresh happens automatically
- No performance degradation
- Clear error messages for troubleshooting

## Outcome
- Authenticator now chooses between service-account and OAuth tokens with proactive refresh timers (`lib/gsc_analytics/data_sources/gsc/support/authenticator.ex:235`).
- Added configurable startup toggle to keep tests stable while allowing runtime boot in other environments (`lib/gsc_analytics/application.ex:10`, `config/test.exs:39`).
- Behaviour validated via updated OAuth unit suite and manual boot checks; full integration tests remain pending until sandbox allowances are expanded.
