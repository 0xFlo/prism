# Ticket-002: Update Auth Context for OAuth + Current Scope

## Status: TODO
**Priority:** P1
**Estimate:** 1 hour
**Dependencies:** ticket-001 (Req client)
**Blocks:** ticket-003, ticket-004, ticket-005

## Problem Statement
The Auth context needs OAuth token management functions that:
1. Accept current_scope as first parameter (per auth guidelines)
2. Store/retrieve encrypted OAuth tokens
3. Handle token refresh using Req (not :httpc)
4. Return decrypted tokens for immediate use

Currently missing:
- OAuth token CRUD operations
- Refresh token logic
- Current scope parameter passing
- Decrypted token return values

## Acceptance Criteria
- [ ] All OAuth functions accept current_scope as first parameter
- [ ] `store_oauth_token/2` returns decrypted token
- [ ] `refresh_oauth_access_token/2` uses Req.post/2
- [ ] Token encryption/decryption working via Vault
- [ ] Functions handle nil current_scope for internal use
- [ ] Existing user auth functions unchanged

## Implementation Plan

### 1. Add OAuth Token Functions to lib/gsc_analytics/auth.ex

```elixir
# All functions take current_scope as first arg (can be nil)

def get_oauth_token(_current_scope, account_id)
def store_oauth_token(_current_scope, attrs) # Returns decrypted!
def refresh_oauth_access_token(current_scope, account_id)
def disconnect_oauth_account(_current_scope, account_id)
def has_oauth_token?(_current_scope, account_id)
```

### 2. Key Implementation Details

#### store_oauth_token MUST return decrypted token:
```elixir
def store_oauth_token(_current_scope, attrs) do
  result =
    case Repo.get_by(OAuthToken, account_id: attrs.account_id) do
      nil ->
        %OAuthToken{}
        |> OAuthToken.changeset(attrs)
        |> Repo.insert()
      existing ->
        existing
        |> OAuthToken.changeset(attrs)
        |> Repo.update()
    end

  # Critical: Return with decrypted tokens!
  case result do
    {:ok, token} -> {:ok, OAuthToken.with_decrypted_tokens(token)}
    error -> error
  end
end
```

#### Token refresh using Req:
```elixir
defp request_token_refresh(refresh_token) do
  oauth_config = Application.get_env(:gsc_analytics, :google_oauth)

  body = %{
    client_id: oauth_config[:client_id],
    client_secret: oauth_config[:client_secret],
    refresh_token: refresh_token,
    grant_type: "refresh_token"
  }

  case Req.post("https://oauth2.googleapis.com/token", form: body) do
    {:ok, %Req.Response{status: 200, body: response}} ->
      {:ok, response}
    {:ok, %Req.Response{status: status, body: body}} ->
      {:error, {:http_error, status, body}}
    {:error, reason} ->
      {:error, reason}
  end
end
```

### 3. Files to Modify
- `lib/gsc_analytics/auth.ex` - Add OAuth functions
- `lib/gsc_analytics/auth/oauth_token.ex` - Ensure with_decrypted_tokens/1 works

## Testing Checklist
- [ ] Can store OAuth token with encryption
- [ ] Retrieved token has decrypted access_token field
- [ ] Refresh token request uses Req (not :httpc)
- [ ] All functions accept current_scope (including nil)
- [ ] Token expiry calculation correct

## Edge Cases
- [ ] Handle nil current_scope for internal calls
- [ ] Handle missing OAuth config gracefully
- [ ] Handle network errors during refresh
- [ ] Handle invalid/revoked refresh tokens
- [ ] Prevent duplicate token storage for same account

## Migration Notes
- Existing user auth functions remain unchanged
- OAuth is additive, not replacing existing auth
- Internal callers (Authenticator) pass nil for current_scope

## Success Metrics
- All OAuth context functions implemented
- Tests pass with proper scope handling
- Token encryption/decryption verified
- Req client used for HTTP calls