# Large Module Refactor Queue

Documenting outsized modules and the immediate improvements we can tackle.

## GscAnalyticsWeb.Components.DashboardComponents (lib/gsc_analytics_web/components/dashboard_components.ex, ~1,564 LOC)
**Prompt:** Now that you read the code, what can we improve?
- Split the file into cohesive component modules (tables, filters, selectors, metric cards) so each module is ~200-300 LOC instead of everything living under `DashboardComponents`.
- Extract duplicated helper logic (`maybe_put_param/3`, column header formatting, toggle helpers) into a helper module and give each component its own attrs/assign validation.
- Add focused component tests (for `url_breadcrumb/1`, pagination UI, `page_type_multiselect/1`) to lock down HTML output and avoid regressions when we start moving things around.
- ✅ Extracted the table/pagination/backlink components into `GscAnalyticsWeb.Components.DashboardTables` with new tests guarding `url_breadcrumb/1`, pagination rendering, and the backlink empty state (Nov 17, 2025).
- ✅ Split selectors/controls and filter UI into `GscAnalyticsWeb.Components.DashboardControls` and `GscAnalyticsWeb.Components.DashboardFilters`, shrinking the mega-module to nothing and covering property selector + filter bar behaviors with component tests (Nov 17, 2025).

## GscAnalyticsWeb.UserLive.Settings (lib/gsc_analytics_web/live/user_live/settings.ex, ~1,034 LOC)
**Prompt:** Now that you read the code, what can we improve?
- Break the monolithic LiveView into LiveComponents (`AccountConnectionCard`, `PropertyPicker`, `PasswordForm`) so each concern is tested independently and the parent mount/handle_event blocks shrink substantially.
- Move the workspace/property mutation helpers (`save_property`, `disconnect_oauth`, `remove_workspace`, `change_account`) into a dedicated service/context so we can unit-test validation logic without a LiveView socket.
- Add LiveView tests covering the high-risk flows (email/password validation, property switching, workspace deletion) to ensure we keep redirects, flashes, and assignments stable.
- ✅ Introduced `GscAnalytics.UserSettings.WorkspaceManager` to own account loading, parsing, and human-friendly labels so the LiveView delegates side-effects to a testable module (Nov 17, 2025).

## GscAnalyticsWeb.DashboardSyncLive (lib/gsc_analytics_web/live/dashboard_sync_live.ex, ~1,003 LOC)
**Prompt:** Now that you read the code, what can we improve?
- Extract sync progress subscription + state machine (`assign_progress/2`, `maybe_request_sync_info/4`) into a `DashboardSync` service so the LiveView only orchestrates UI interaction.
- Pull property/account bootstrap logic (`AccountHelpers.*` calls, property labels/favicons) into smaller helpers and reuse them across `handle_params/3` and `mount/3` instead of duplicating.
- Add LiveView tests for the `start_sync` and `change_account` events plus error branches (property misconfiguration, ongoing sync) to prevent regressions when we refactor the long conditionals.
- ✅ Added `GscAnalyticsWeb.Live.DashboardSync` + `DashboardSyncHelpers` so the LiveView now delegates data loading, progress formatting, and socket assignments to reusable modules (Nov 17, 2025).

## GscAnalyticsWeb.DashboardCrawlerLive (lib/gsc_analytics_web/live/dashboard_crawler_live.ex, ~916 LOC)
**Prompt:** Now that you read the code, what can we improve?
- The LiveView intermixes bootstrapping, pagination, and job scoping inside `mount/3` and `handle_params/3` (lines 33-151) leading to repeated property/account queries and brittle assigns; pull that block (plus the default assigns) into a `DashboardCrawler` service and split the UI into child components (progress, queue stats, problem table) so each concern is manageable.
- Crawler mutations and pagination handlers (lines 198-275) embed identical `push_crawler_patch/2` plumbing and `Task.start` usage; moving the event handlers into dedicated modules/components (e.g. `CrawlerFilterComponent`, `CrawlerPagerComponent`, `CrawlerJobActions`) would let us isolate tests for filter/pagination edge cases instead of keeping every branch in the parent LiveView.
- Data access helpers such as `fetch_problem_urls_paginated/5` and `fetch_global_stats/2` (lines 516-653) run complex Ecto queries directly in the LiveView, making it hard to unit-test query logic; extract these into `Crawler` context functions that accept scopes/current_property and return DTOs the LiveView only formats.
- Observability helpers (`Crawler.subscribe/0`, telemetry attachment, `get_queue_stats/0`, and `handle_info` updates across lines 33-365 & 732-778) should live in a monitor module that we can supervise and integration-test; right now we have no guardrails around telemetry detaches or queue-stat failure handling.
- `test/gsc_analytics_web/live/dashboard_crawler_live_test.exs` only covers the property selector, job scoping, and redirect helpers; add LiveView tests covering `start_check` authorization, pagination/filter events, and queue-stat refreshes so we can refactor confidently.
