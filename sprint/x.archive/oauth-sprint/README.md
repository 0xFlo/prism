# OAuth Implementation Sprint

## Executive Summary

This sprint implements OAuth2 authentication for Account 2 (Alba Analytics) to access Google Search Console data via the i@alba.cc Google account, while maintaining backward compatibility with service account authentication for Account 1 (Scrapfly).

## Background

**Current State:**

- Account 1 (Scrapfly) uses service account JSON credentials (working)
- Account 2 (Alba) has service account but clients haven't granted access
- Dashboard is currently unprotected (SECURITY ISSUE)
- No way to connect existing Google accounts with GSC access

**Desired State:**

- Two-layer security: Dashboard login + API authorization
- Account 1 continues with service account (no changes)
- Account 2 uses OAuth to connect i@alba.cc
- Dashboard requires authentication
- Automatic token refresh for both auth methods

## Sprint Tickets

### Critical Path (Blocker)

- **[ticket-001]** Add Req HTTP Client Dependency (30 min)
  - Must complete first - blocks all other work

### Core Implementation

- **[ticket-002]** Update Auth Context for OAuth + Current Scope (1 hr)

  - OAuth token CRUD operations
  - Token refresh with Req
  - Current scope parameter passing

- **[ticket-003]** Implement GoogleAuth OAuth Flow Module (2 hrs)

  - Authorization URL generation
  - Callback handling with CSRF protection
  - Token exchange and storage

- **[ticket-004]** Dual-Mode Authenticator (1.5 hrs)
  - Auto-detect auth method per account
  - OAuth token fetching and refresh
  - Maintain JWT backward compatibility

### User Interface

- **[ticket-005]** Account Settings LiveView UI (1 hr)

  - Display account auth status
  - Connect/disconnect Google accounts
  - Proper scope handling

- **[ticket-006]** Router Protection & OAuth Routes (30 min)
  - Protect dashboard routes (SECURITY)
  - Add OAuth controller routes
  - Consolidate live_sessions

### Quality

- **[ticket-007]** Test Suite for Dual Authentication (1.5 hrs)
  - Unit tests for OAuth functions
  - Integration tests for both auth modes
  - Security tests for CSRF protection

## Technical Architecture

```
┌─────────────────────────────────────────┐
│         Dashboard Authentication         │
│        (phx.gen.auth - Layer 1)         │
│    Email/password login required        │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│        API Authorization (Layer 2)       │
├─────────────────────────────────────────┤
│ Account 1: Service Account JWT (as-is)  │
│ Account 2: OAuth Refresh Token (new)    │
└─────────────────────────────────────────┘
```

## Key Implementation Decisions

1. **Req over :httpc**: Following codebase guidelines for HTTP client
2. **Current scope contract**: All functions accept scope as first parameter
3. **State token security**: Encode both account_id and user_id
4. **No dev.secret.exs**: Use environment variables per security guidelines
5. **Single live_session**: Reuse existing authenticated session
6. **ASCII only**: No emoji in code per repo rules

## Setup Instructions

### 1. Google Cloud Console Setup

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Select project: `alba-analytics-475918`
3. Enable **Google Search Console API**
4. Create OAuth 2.0 Client ID (Web application)
5. Add redirect URI: `http://localhost:4000/auth/google/callback`
6. Download credentials

### 2. Environment Variables

```bash
export GOOGLE_OAUTH_CLIENT_ID="your_client_id.apps.googleusercontent.com"
export GOOGLE_OAUTH_CLIENT_SECRET="your_secret"
export CLOAK_KEY="ZzkKpsL01gl7QvRP1ThEmypkny/XrLaM/3FrfIjtNuA="
```

### 3. Run Migrations

```bash
mix deps.get
mix ecto.migrate
```

## Testing Plan

### Manual Testing Flow

1. Register user account at `/users/register`
2. Confirm email via `/dev/mailbox`
3. Login at `/users/log-in`
4. Verify dashboard requires login
5. Visit `/accounts`
6. Connect Account 2 to i@alba.cc
7. Test GSC API access
8. Verify token refresh
9. Test disconnect

### Automated Tests

- Auth context OAuth functions
- Authenticator dual-mode branches
- State token security
- Token refresh mocking
- Integration tests for both auth types

## Risk Mitigation

| Risk                          | Mitigation                            |
| ----------------------------- | ------------------------------------- |
| Breaking service account auth | Extensive testing, feature flag ready |
| OAuth token leakage           | Encryption at rest, HTTPS only        |
| CSRF attacks                  | State token with user verification    |
| Expired tokens                | Automatic refresh logic               |
| Missing credentials           | Graceful error handling               |

## Success Criteria

- [ ] Dashboard requires authentication
- [ ] Account 1 service account unchanged
- [ ] Account 2 OAuth working with i@alba.cc
- [ ] Automatic token refresh
- [ ] All tests passing
- [ ] No security vulnerabilities

## Rollback Plan

If critical issues arise:

1. **Revert router changes** - Restore unprotected dashboard (temporary)
2. **Disable OAuth** - Remove auth method detection in Authenticator
3. **Remove OAuth UI** - Hide account settings page
4. **Clean migrations** - Rollback oauth_tokens table if needed

Each ticket can be rolled back independently except ticket-001 (Req dependency).

## Dependencies

External:

- Google OAuth2 API availability
- Google Cloud Console access
- i@alba.cc account permissions

Internal:

- Existing auth system (phx.gen.auth)
- Vault encryption
- PostgreSQL database

## Timeline

- **Day 1**: Tickets 001-003 (Infrastructure)
- **Day 2**: Tickets 004-006 (Implementation)
- **Day 3**: Ticket 007 + Testing (Quality)

Total estimate: 8 hours of focused work

## References

- [Google OAuth2 Documentation](https://developers.google.com/identity/protocols/oauth2)
- [Phoenix Authentication Guide](https://hexdocs.pm/phoenix/authentication.html)
- [Req HTTP Client](https://hexdocs.pm/req/Req.html)
- Project OAuth Setup: `100-190 Projects & Planning/210 SEO Tooling/OAUTH-SETUP.md`
