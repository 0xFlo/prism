# Account Properties Sprint

## Overview
- Unlock multi-property management for Google Search Console workspaces
- Align dashboard and settings UX so that workspace > account > property flows feel intuitive
- Stabilize sync pipeline to ingest, store, and surface metrics for multiple properties per workspace

## Sprint Goals
- Persist an explicit “workspace” concept that can own many Search Console properties
- Let operators connect any Google login per workspace and curate the property list from the UI
- Enable dashboard, reports, and sync jobs to scope by property and switch seamlessly
- Ship proactive guidance (empty states, warnings) so users always know their next step

## Success Criteria
- Users can connect OAuth once and toggle between any verified property without reconnecting
- Dashboard selection control reflects saved property names and stays in sync with settings
- Sync jobs refuse to run without a chosen property and provide actionable remediation hints
- Regression suite covers property selection flows (LiveView + integration) and passes cleanly

## Out of Scope
- Building per-user authorization rules (shared workspace invites handled later)
- Bulk backfills across all properties simultaneously (limit to one active property per sync job)
- Non-Google data sources (keep this sprint focused on Search Console)

## Key Dependencies
- Existing OAuth flow and token storage in `GscAnalytics.Auth`
- Sync pipeline modules under `GscAnalytics.DataSources.GSC`
- LiveView helpers in `GscAnalyticsWeb.Live.AccountHelpers`

## Timeline & Checkpoints
1. **Day 1–2**: Data modelling & migration strategy signed off
2. **Day 3–4**: Settings UI + property picker refactor wired into Accounts context
3. **Day 5–6**: Dashboard, sync pipeline, and background jobs updated for multi-property support
4. **Day 7**: Regression tests, docs, and hand-off demo

