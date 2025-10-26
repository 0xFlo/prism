# Ticket-006: Router Protection & OAuth Routes

## Status: TODO
**Priority:** P1
**Estimate:** 30 minutes
**Dependencies:** ticket-003 (GoogleAuth module)
**Blocks:** Full system testing

## Problem Statement
Current issues with router:
1. Dashboard routes are NOT protected (anonymous access allowed!)
2. No OAuth routes defined
3. Dashboard LiveViews in wrong live_session

Need to:
- Move dashboard into authenticated live_session
- Add OAuth controller routes
- Ensure all routes require authentication
- Maintain existing user routes

## Acceptance Criteria
- [ ] Dashboard requires login (no anonymous access)
- [ ] OAuth routes added and protected
- [ ] Account settings route added
- [ ] All dashboard LiveViews in authenticated session
- [ ] Export controller requires authentication
- [ ] Existing user routes unchanged
- [ ] No duplicate live_sessions created

## Implementation Plan

### 1. Current Router Structure (BROKEN)

```elixir
# PROBLEM: Dashboard routes are unprotected!
scope "/", GscAnalyticsWeb do
  pipe_through :browser  # <-- NO authentication!

  live "/", DashboardLive, :index
  live "/dashboard", DashboardLive, :index
  # ... other dashboard routes
end
```

### 2. Fixed Router Structure

File: `lib/gsc_analytics_web/router.ex`

```elixir
# REMOVE the unprotected scope entirely

# ADD everything to authenticated scope
scope "/", GscAnalyticsWeb do
  pipe_through [:browser, :require_authenticated_user]

  # OAuth routes (new)
  scope "/auth/google" do
    get "/", GoogleAuthController, :request
    get "/callback", GoogleAuthController, :callback
  end

  # All LiveViews in ONE authenticated session
  live_session :require_authenticated_user,
    on_mount: [{GscAnalyticsWeb.UserAuth, :require_authenticated}] do

    # User settings (existing)
    live "/users/settings", UserLive.Settings, :edit
    live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email

    # Dashboard routes (MOVED HERE)
    live "/", DashboardLive, :index
    live "/dashboard", DashboardLive, :index
    live "/dashboard/keywords", DashboardKeywordsLive, :index
    live "/dashboard/sync", DashboardSyncLive, :index
    live "/dashboard/crawler", DashboardCrawlerLive, :index
    live "/dashboard/url", DashboardUrlLive, :show

    # Account settings (new)
    live "/accounts", AccountSettingsLive, :index
  end

  # Controller routes (also authenticated)
  post "/users/update-password", UserSessionController, :update_password
  get "/dashboard/export", Dashboard.ExportController, :export_csv
end

# Public routes (login/register) remain in separate scope
scope "/", GscAnalyticsWeb do
  pipe_through [:browser]

  live_session :current_user,
    on_mount: [{GscAnalyticsWeb.UserAuth, :mount_current_scope}] do
    live "/users/register", UserLive.Registration, :new
    live "/users/log-in", UserLive.Login, :new
    live "/users/log-in/:token", UserLive.Confirmation, :new
  end

  post "/users/log-in", UserSessionController, :create
  delete "/users/log-out", UserSessionController, :delete
end
```

### 3. Key Changes Summary

**DELETE:**
- Remove unprotected dashboard scope at lines 20-31

**MOVE:**
- Dashboard LiveViews into :require_authenticated_user session
- Export controller into authenticated scope

**ADD:**
- OAuth routes in authenticated scope
- Account settings LiveView route

### 4. Testing After Changes

```bash
# Compile and verify no errors
mix compile

# Test authentication requirement
curl -I http://localhost:4000/dashboard
# Should return 302 redirect to /users/log-in

# Test with browser
# 1. Try accessing /dashboard without login → redirected
# 2. Login → can access dashboard
# 3. Logout → redirected from dashboard
```

## Common Pitfalls to Avoid
- DON'T create multiple live_sessions for same protection level
- DON'T leave any dashboard routes unprotected
- DON'T duplicate route definitions
- DON'T forget controller routes need protection too

## Rollback Plan
If routes break:
1. Git diff to see exact changes
2. Revert router.ex changes
3. Restart Phoenix server
4. Debug specific route issues

## Success Metrics
- All dashboard routes return 302 when not logged in
- OAuth flow completes successfully
- No routes accessible without authentication (except login/register)
- Existing user flows still work

## Security Impact
**HIGH** - Currently dashboard is publicly accessible!
This ticket fixes critical security issue where anyone can view GSC data without authentication.