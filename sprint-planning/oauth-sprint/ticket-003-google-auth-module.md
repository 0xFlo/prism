# Ticket-003: Implement GoogleAuth OAuth Flow Module

## Status: DONE
**Priority:** P1
**Estimate:** 2 hours
**Dependencies:** ticket-001 (Req), ticket-002 (Auth context)
**Blocks:** ticket-005, ticket-006

## Problem Statement
Need OAuth2 authorization flow to connect Google accounts to dashboard accounts. Must:
- Generate secure authorization URLs
- Handle OAuth callbacks with CSRF protection
- Exchange authorization codes for tokens
- Extract user email from response
- Store tokens securely

Critical requirements:
- Use verified routes (`use GscAnalyticsWeb, :controller`)
- Encode account_id AND user_id in state token
- Handle missing id_token gracefully
- Pass current_scope through all Auth calls

## Acceptance Criteria
- [x] OAuth authorization URL generation working
- [x] State token includes account_id and user_id
- [x] CSRF protection via Phoenix.Token verification
- [x] Public `generate_state/2` and `verify_state/2` helpers align with test plan
- [x] Authorization code exchange using Req
- [x] Email extraction handles missing id_token
- [x] Tokens stored with current_scope passing and enforcing scope authorization
- [x] Proper error handling and redirects
- [x] No emoji in code (ASCII only)

## Implementation Plan

### 1. Create lib/gsc_analytics_web/google_auth.ex

```elixir
defmodule GscAnalyticsWeb.GoogleAuth do
  # Critical: Use controller macro for verified routes!
  use GscAnalyticsWeb, :controller

  alias GscAnalytics.Auth.Scope

  @google_auth_url "https://accounts.google.com/o/oauth2/v2/auth"
  @google_token_url "https://oauth2.googleapis.com/token"
  @scope "https://www.googleapis.com/auth/webmasters.readonly email openid"

  def generate_state(current_scope, account_id)
  def verify_state(state_token, current_scope)
  def request(conn, account_id)
  def callback(conn, params)

  # Private helpers:
  defp authorize_account!(current_scope, account_id)
  defp exchange_code_for_tokens(code)
  defp store_tokens(current_scope, account_id, tokens)
  defp extract_email_safely(tokens)
  defp calculate_expires_at(expires_in)
end
```

### 2. Critical Implementation Details

#### State Token Security:

**Best Practice from Research (OAuth2 + Phoenix.Token CSRF Protection):**
- **OAuth 2.0 spec requires CSRF protection** via state parameter (RFC 6749)
- **Phoenix.Token provides cryptographically signed tokens** with automatic expiry
- **Encode BOTH account_id AND user_id** to prevent token swapping attacks
- **10-minute expiry** (max_age: 600) balances security and UX
- **Alternative CSRF methods:** PKCE (OAuth 2.1) or OIDC nonce, but state parameter is minimum requirement

**Why include user_id in state token:**
If only account_id is in state, a malicious user could intercept the callback URL and use it in their own session, connecting their account to someone else's Google account. By including and verifying user_id, we ensure the OAuth flow completes in the same user session that started it.

**CSRF Attack Prevention:**
1. User A starts OAuth flow → state token includes user_id=1
2. Attacker intercepts callback URL with state token
3. Attacker tries to use callback in their session (user_id=2)
4. Verification fails: token user_id (1) ≠ session user_id (2)
5. Attack blocked!

```elixir
# Encode BOTH account_id and user_id
def generate_state(current_scope, account_id) do
  authorize_account!(current_scope, account_id)

  Phoenix.Token.sign(
    GscAnalyticsWeb.Endpoint,
    "oauth_state",
    %{
      account_id: account_id,
      user_id: current_scope.user.id
    }
  )
end

def request(conn, account_id) do
  current_scope = conn.assigns.current_scope
  authorize_account!(current_scope, account_id)

  state = generate_state(current_scope, account_id)
  callback_url = url(~p"/auth/google/callback")

  query = %{
    client_id: oauth_config()[:client_id],
    redirect_uri: callback_url,
    response_type: "code",
    scope: @scope,
    access_type: "offline",
    prompt: "consent",
    state: state
  }

  redirect(conn, external: "#{@google_auth_url}?#{URI.encode_query(query)}")
end

# Verify user_id matches on callback
def verify_state(state_token, current_scope) do
  case Phoenix.Token.verify(GscAnalyticsWeb.Endpoint, "oauth_state", state_token, max_age: 600) do
    {:ok, %{user_id: user_id} = state_data} when user_id == current_scope.user.id ->
      {:ok, state_data}

    {:ok, _} ->
      {:error, :invalid_state}

    other ->
      other
  end
end
```

#### Safe Email Extraction:
```elixir
defp extract_email_safely(%{"id_token" => id_token}) when is_binary(id_token) do
  try do
    [_header, payload, _signature] = String.split(id_token, ".")
    payload
    |> Base.url_decode64!(padding: false)
    |> JSON.decode!()
    |> Map.get("email", "unknown@oauth.local")
  rescue
    _ -> "unknown@oauth.local"
  end
end

defp extract_email_safely(_), do: "unknown@oauth.local"
```

#### Dynamic Callback URL:
```elixir
# Use verified routes helper
callback_url = url(~p"/auth/google/callback")
# NOT hardcoded "http://localhost:4000/..."
```

#### Code Exchange with Req:

**Best Practice:** Use Req for authorization code exchange, leveraging the Finch pool from ticket-001.

```elixir
defp exchange_code_for_tokens(code) do
  oauth_config = Application.get_env(:gsc_analytics, :google_oauth)
  callback_url = GscAnalyticsWeb.Endpoint.url() <> "/auth/google/callback"

  body = %{
    code: code,
    client_id: oauth_config[:client_id],
    client_secret: oauth_config[:client_secret],
    redirect_uri: callback_url,
    grant_type: "authorization_code"
  }

  case Req.post("https://oauth2.googleapis.com/token", form: body) do
    {:ok, %Req.Response{status: 200, body: tokens}} ->
      {:ok, tokens}
    {:ok, %Req.Response{status: status, body: error}} ->
      {:error, {:http_error, status, error}}
    {:error, reason} ->
      {:error, reason}
  end
end
```

**Additional Implementation Notes:**
- Implement `authorize_account!/2` as a thin wrapper around `Scope.authorize_account!/2` so every controller action and helper respects the scope membership rules introduced in ticket-002. Unauthorized access should halt with `{:error, :unauthorized_account}` and redirect with an error flash.
- Provide a small helper `oauth_config/0` (or inline config lookup) for client credentials to keep the request/callback functions clean.
- After verifying the state token in the callback, call `authorize_account!(current_scope, state_data.account_id)` again to prevent token swapping between accounts.

### 3. Create Controller Wrapper

File: `lib/gsc_analytics_web/controllers/google_auth_controller.ex`

```elixir
defmodule GscAnalyticsWeb.GoogleAuthController do
  use GscAnalyticsWeb, :controller
  alias GscAnalyticsWeb.GoogleAuth

  def request(conn, %{"account_id" => account_id}) do
    GoogleAuth.request(conn, String.to_integer(account_id))
  end

  def callback(conn, params) do
    GoogleAuth.callback(conn, params)
  end
end
```

### 4. Required OAuth Scopes
- `https://www.googleapis.com/auth/webmasters.readonly` - GSC access
- `email` - Identify which account
- `openid` - Ensures id_token is returned

### 5. Error Handling
- Invalid state → "Invalid OAuth state" flash
- User denial → "OAuth authorization denied" flash
- Exchange failure → "OAuth failed: {reason}" flash
- All errors redirect to /accounts

## Testing Checklist
- [x] Authorization URL includes all required parameters
- [x] State token expires after 10 minutes
- [x] CSRF attack blocked (mismatched user_id)
- [x] Unauthorized account access returns {:error, :unauthorized_account} and redirects with flash
- [x] Code exchange returns tokens
- [x] Missing id_token doesn't crash
- [x] Tokens stored with encryption
- [x] Error cases show appropriate flash messages

## Security Checklist
- [x] State token signed with Phoenix.Token
- [x] User ID verified in state token
- [x] Tokens encrypted at rest (via Auth context)
- [x] No secrets logged
- [x] OAuth config from environment variables
- [x] HTTPS enforced in production

## Configuration Required
```elixir
# In config/runtime.exs:
config :gsc_analytics, :google_oauth,
  client_id: System.get_env("GOOGLE_OAUTH_CLIENT_ID"),
  client_secret: System.get_env("GOOGLE_OAUTH_CLIENT_SECRET")
```

## Edge Cases
- [x] Missing OAuth configuration
- [x] Google returns error instead of code
- [x] Network timeout during token exchange
- [x] Malformed id_token
- [x] Expired state token
- [x] User already has token for account

## Outcome
- Implemented `GscAnalyticsWeb.GoogleAuth` and controller wrapper with state-token verification and Req-powered code exchange (`lib/gsc_analytics_web/google_auth.ex:16`).
- Added conditional runtime configuration and documented required env vars; flow now redirects through `/accounts`.
- Exercised via manual smoke test and supporting unit coverage in `AuthTest` to ensure token storage path works.
