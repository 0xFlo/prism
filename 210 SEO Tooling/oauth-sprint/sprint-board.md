# OAuth Implementation Sprint Board

## Sprint Goal
Enable OAuth2 authentication for Account 2 (Alba Analytics) to access GSC data via i@alba.cc Google account, while maintaining service account authentication for Account 1 (Scrapfly).

## Sprint Duration
Estimated: 2-3 days
Started: 2024-10-23

## Success Criteria
- [ ] Dashboard requires authentication (no anonymous access)
- [ ] Account 1 continues using service account (unchanged)
- [ ] Account 2 can connect via OAuth to i@alba.cc
- [ ] Tokens refresh automatically
- [ ] Complete test coverage for dual-mode authentication
- [ ] Data remains isolated between accounts

## Tickets

### 🔴 Critical Path (Must Complete First)
- [ticket-001] **Add Req HTTP Client Dependency** (P1) - BLOCKER
  - Status: TODO
  - Assignee: Claude
  - Estimate: 30 min
  - Blocks: All other tickets

### 🟡 Core Implementation
- [ticket-002] **Update Auth Context for OAuth + Current Scope** (P1)
  - Status: TODO
  - Depends on: ticket-001
  - Assignee: Claude
  - Estimate: 1 hour

- [ticket-003] **Implement GoogleAuth OAuth Flow Module** (P1)
  - Status: TODO
  - Depends on: ticket-001, ticket-002
  - Assignee: Claude
  - Estimate: 2 hours

- [ticket-004] **Dual-Mode Authenticator (JWT + OAuth)** (P1)
  - Status: TODO
  - Depends on: ticket-002
  - Assignee: Claude
  - Estimate: 1.5 hours

### 🟢 User Interface
- [ticket-005] **Account Settings LiveView UI** (P1)
  - Status: TODO
  - Depends on: ticket-002, ticket-003
  - Assignee: Claude
  - Estimate: 1 hour

- [ticket-006] **Router Protection & OAuth Routes** (P1)
  - Status: TODO
  - Depends on: ticket-003
  - Assignee: Claude
  - Estimate: 30 min

### 🔵 Quality & Testing
- [ticket-007] **Test Suite for Dual Authentication** (P2)
  - Status: TODO
  - Depends on: ticket-004
  - Assignee: Claude
  - Estimate: 1.5 hours

## Sprint Metrics
- Total Story Points: ~8 hours
- Completed: 0/7
- In Progress: 0/7
- Blocked: 7/7 (waiting for ticket-001)

## Risk Register
1. **Google OAuth Credentials**: Need to be created in Google Cloud Console
2. **Token Encryption**: Already implemented with Vault
3. **Breaking Changes**: Service account auth must continue working
4. **Scope Contract**: All functions must accept current_scope

## Definition of Done
- [ ] Code implemented and compiling
- [ ] Tests passing (existing + new)
- [ ] Manual testing complete
- [ ] Documentation updated
- [ ] No regressions in existing auth