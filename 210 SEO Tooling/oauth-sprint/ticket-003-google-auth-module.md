# Ticket-003: Implement GoogleAuth OAuth Flow Module

## Status: TODO
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
- [ ] OAuth authorization URL generation working
- [ ] State token includes account_id and user_id
- [ ] CSRF protection via Phoenix.Token verification
- [ ] Authorization code exchange using Req
- [ ] Email extraction handles missing id_token
- [ ] Tokens stored with current_scope passing
- [ ] Proper error handling and redirects
- [ ] No emoji in code (ASCII only)

## Implementation Plan

### 1. Create lib/gsc_analytics_web/google_auth.ex

```elixir
defmodule GscAnalyticsWeb.GoogleAuth do
  # Critical: Use controller macro for verified routes!
  use GscAnalyticsWeb, :controller

  @google_auth_url "https://accounts.google.com/o/oauth2/v2/auth"
  @google_token_url "https://oauth2.googleapis.com/token"
  @scope "https://www.googleapis.com/auth/webmasters.readonly email openid"

  def request(conn, account_id)
  def callback(conn, params)

  # Private helpers:
  defp verify_state(state_token, current_scope)
  defp exchange_code_for_tokens(code)
  defp store_tokens(current_scope, account_id, tokens)
  defp extract_email_safely(tokens)
  defp calculate_expires_at(expires_in)
end
```

### 2. Critical Implementation Details

#### State Token Security:
```elixir
# Encode BOTH account_id and user_id
state = Phoenix.Token.sign(
  GscAnalyticsWeb.Endpoint,
  "oauth_state",
  %{
    account_id: account_id,
    user_id: current_scope.user.id
  }
)

# Verify user_id matches on callback
case Phoenix.Token.verify(endpoint, "oauth_state", state_token, max_age: 600) do
  {:ok, %{user_id: user_id} = state_data} when user_id == current_scope.user.id ->
    {:ok, state_data}
  _ ->
    {:error, :invalid_state}
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
- [ ] Authorization URL includes all required parameters
- [ ] State token expires after 10 minutes
- [ ] CSRF attack blocked (mismatched user_id)
- [ ] Code exchange returns tokens
- [ ] Missing id_token doesn't crash
- [ ] Tokens stored with encryption
- [ ] Error cases show appropriate flash messages

## Security Checklist
- [ ] State token signed with Phoenix.Token
- [ ] User ID verified in state token
- [ ] Tokens encrypted at rest (via Auth context)
- [ ] No secrets logged
- [ ] OAuth config from environment variables
- [ ] HTTPS enforced in production

## Configuration Required
```elixir
# In config/runtime.exs:
config :gsc_analytics, :google_oauth,
  client_id: System.get_env("GOOGLE_OAUTH_CLIENT_ID"),
  client_secret: System.get_env("GOOGLE_OAUTH_CLIENT_SECRET")
```

## Edge Cases
- [ ] Missing OAuth configuration
- [ ] Google returns error instead of code
- [ ] Network timeout during token exchange
- [ ] Malformed id_token
- [ ] Expired state token
- [ ] User already has token for account