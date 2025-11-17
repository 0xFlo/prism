# Ticket-002: Update Auth Context for OAuth + Current Scope

## Status: DONE
**Priority:** P1
**Estimate:** 1 hour
**Dependencies:** ticket-001 (Req client)
**Blocks:** ticket-003, ticket-004, ticket-005

## Problem Statement
The Auth context needs OAuth token management functions that:
1. Accept `current_scope` as the first parameter (per scope guidelines)
2. Enforce account access by checking that the scope contains the requested account
3. Store/retrieve encrypted OAuth tokens
4. Handle token refresh using Req (not :httpc)
5. Return decrypted tokens for immediate use

Currently missing:
- Scope-aware authorization helpers for account access
- OAuth token CRUD operations
- Refresh token logic
- Current scope parameter passing and enforcement
- Decrypted token return values

## Acceptance Criteria
- [x] All OAuth functions accept current_scope as first parameter and raise/return {:error, :unauthorized_account} when the scope lacks access
- [x] Scope helpers (e.g., `Scope.authorize_account!/2`) added so contexts consistently enforce membership
- [x] `store_oauth_token/2` returns decrypted token
- [x] `refresh_oauth_access_token/2` uses Req.post/2
- [x] Token encryption/decryption working via Vault
- [x] Functions handle nil current_scope for internal use
- [x] Existing user auth functions unchanged

## Implementation Plan

### 1. Extend Scope and Account Access Helpers

**Best Practice from Research (Bodyguard Pattern):**
Centralize authorization checks in the Scope module to prevent developers from forgetting requirements when adding new features. This follows the "policy scope" pattern common in Phoenix apps.

```elixir
# lib/gsc_analytics/auth/scope.ex
defmodule GscAnalytics.Auth.Scope do
  defstruct [:user, :account_ids]

  @doc """
  Check if account is authorized for this scope.
  Returns true/false (use for conditional logic).
  """
  def account_authorized?(nil, _account_id), do: true  # Internal calls bypass
  def account_authorized?(%__MODULE__{account_ids: ids}, account_id) do
    account_id in ids
  end

  @doc """
  Authorize account access or raise.
  Use this at the start of context functions (raises on unauthorized).
  """
  def authorize_account!(nil, _account_id), do: :ok  # Internal calls bypass
  def authorize_account!(%__MODULE__{} = scope, account_id) do
    if account_authorized?(scope, account_id) do
      :ok
    else
      raise "Unauthorized access to account #{account_id}"
    end
  end

  @doc """
  Build scope for a user with their accessible account IDs.
  """
  def for_user(nil), do: nil
  def for_user(user) do
    # TODO: Load from database when multi-tenancy implemented
    # For now, derive from config
    account_ids = GscAnalytics.Accounts.account_ids_for_user(user)
    %__MODULE__{user: user, account_ids: account_ids}
  end
end
```

**Why This Pattern:**
- Single source of truth for authorization logic
- Prevents forgetting to check permissions in new code
- Nil scope support for internal system calls (document why safe)
- Follows Phoenix context conventions

**Implementation Steps:**
- Update `GscAnalytics.Auth.Scope` to track accessible account IDs (struct field: `account_ids`)
- Add `GscAnalytics.Accounts.account_ids_for_user/1` helper
- Populate scope in `fetch_current_scope_for_user/2` within UserAuth module

### 2. Add OAuth Token Functions to lib/gsc_analytics/auth.ex

```elixir
# All functions take current_scope as first arg (can be nil for system calls)

def get_oauth_token(current_scope, account_id)
def store_oauth_token(current_scope, attrs) # Returns decrypted!
def refresh_oauth_access_token(current_scope, account_id)
def disconnect_oauth_account(current_scope, account_id)
def has_oauth_token?(current_scope, account_id)
```

### 3. Key Implementation Details

#### store_oauth_token MUST return decrypted token:

**CRITICAL:** The `store_oauth_token/2` function must return a token struct with **decrypted** fields. This is necessary because the GoogleAuth callback needs the access_token immediately to verify the connection works, without making a second database query.

```elixir
def store_oauth_token(current_scope, attrs) do
  Scope.authorize_account!(current_scope, attrs.account_id)

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
  # The caller (GoogleAuth.callback) needs immediate access to the token
  # without making another database query.
  case result do
    {:ok, token} -> {:ok, OAuthToken.with_decrypted_tokens(token)}
    error -> error
  end
end
```

**Why decrypted return?**
- Tokens are encrypted at rest in the database (Vault)
- After storing, the encrypted fields are not usable
- `OAuthToken.with_decrypted_tokens/1` returns a struct with decrypted fields
- This allows immediate use without an extra `get_oauth_token/2` call

#### Token refresh using Req:

**Best Practice:** Use Req.post/2 with `form:` option for OAuth token requests. Req automatically:
- Sets `Content-Type: application/x-www-form-urlencoded` header
- Encodes the form body properly
- Uses Finch connection pooling (configured in ticket-001)
- Provides better error messages than `:httpc`

```elixir
defp request_token_refresh(refresh_token) do
  oauth_config = Application.get_env(:gsc_analytics, :google_oauth)

  body = %{
    client_id: oauth_config[:client_id],
    client_secret: oauth_config[:client_secret],
    refresh_token: refresh_token,
    grant_type: "refresh_token"
  }

  # Req.post with form: option automatically sets correct headers
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

**Alternative with explicit Finch pool:**
```elixir
# If you need to specify the Finch instance explicitly:
Req.post("https://oauth2.googleapis.com/token",
  form: body,
  finch: GscAnalytics.Finch
)
```

All functions should return `{:error, :unauthorized_account}` instead of raising when preferred by the caller (e.g., `has_oauth_token?/2`), but must call `Scope.account_authorized?/2` before touching the database.

### 4. Files to Modify
- `lib/gsc_analytics/auth.ex` - Add OAuth functions
- `lib/gsc_analytics/auth/oauth_token.ex` - Ensure with_decrypted_tokens/1 works
- `lib/gsc_analytics/auth/scope.ex` - Track accessible accounts + helpers
- `lib/gsc_analytics_web/user_auth.ex` - Populate scope with account access list
- `lib/gsc_analytics/accounts.ex` (and supporting modules) - Helper to retrieve allowed account ids

## Testing Checklist
- [x] Can store OAuth token with encryption
- [x] Retrieved token has decrypted access_token field
- [x] Refresh token request uses Req (not :httpc)
- [x] All functions accept current_scope (including nil)
- [x] Token expiry calculation correct

## Edge Cases
- [x] Handle nil current_scope for internal calls (explicit guard)
- [x] Handle missing OAuth config gracefully
- [x] Handle network errors during refresh
- [x] Handle invalid/revoked refresh tokens
- [x] Prevent duplicate token storage for same account
- [x] Unauthorized scopes receive {:error, :unauthorized_account}

## Migration Notes
- Existing user auth functions remain unchanged
- OAuth is additive, not replacing existing auth
- Internal callers (Authenticator) pass nil for current_scope and must document why bypass is safe

## Success Metrics
- All OAuth context functions implemented
- Tests pass with proper scope handling
- Token encryption/decryption verified
- Req client used for HTTP calls

## Outcome
- Expanded scope struct to include permitted account IDs and added authorization helpers consumed across contexts (`lib/gsc_analytics/auth/scope.ex:12`).
- Reworked OAuth helpers to enforce scope, return decrypted tokens, and rely on Req for refreshes (`lib/gsc_analytics/auth.ex:304`).
- Validated via updated unit coverage (`mix test test/gsc_analytics/auth_test.exs --trace`) and ensured edge cases return descriptive errors.
