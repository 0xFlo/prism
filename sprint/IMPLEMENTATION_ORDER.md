# Implementation Order - SERP Landscape Sprint

This guide provides the recommended order for implementing the SERP Landscape Intelligence System. Follow this sequence to ensure dependencies are met and testing can happen incrementally.

---

## Phase 1: Foundation (Days 1-3)

### Step 1: Database Schema Changes
**Priority**: 🔥 P1 Critical
**Estimate**: 30 minutes
**Files**: New migration file

```bash
mix ecto.gen.migration add_serp_landscape_fields
```

**Migration content**: See `TECHNICAL_SPEC.md` → Database Schema Changes

**Validation**:
```bash
mix ecto.migrate
mix ecto.rollback
mix ecto.migrate  # Verify idempotent
```

---

### Step 2: Enhanced HTML Parser (Content Type Detection)
**Priority**: 🔥 P1 Critical
**Estimate**: 2 hours
**Files**: `lib/gsc_analytics/data_sources/serp/core/html_parser.ex`

**Changes**:
1. Add `classify_content_type/2` function
2. Add `extract_domain/1` function
3. Modify `extract_competitors/1` to return 10 instead of 3
4. Enhance competitor map structure with `domain` and `content_type`

**Testing**:
```elixir
# In IEx (iex -S mix)
alias GscAnalytics.DataSources.SERP.Core.HTMLParser

HTMLParser.classify_content_type("https://www.reddit.com/r/webscraping", "Title")
# => "reddit"

HTMLParser.extract_domain("https://scrapfly.io/blog/web-scraping")
# => "scrapfly.io"
```

**Unit Tests**: Add to `test/gsc_analytics/data_sources/serp/core/html_parser_test.exs`

---

### Step 3: Enhanced SerpCheckWorker
**Priority**: 🔥 P1 Critical
**Estimate**: 1 hour
**Files**: `lib/gsc_analytics/workers/serp_check_worker.ex`

**Changes**:
1. Add `check_scrapfly_citation/1` private function
2. Store enhanced fields in snapshot:
   - `content_types_present`
   - `scrapfly_mentioned_in_ao`
   - `scrapfly_citation_position`

**Testing**:
```elixir
# Queue a test job
%{
  account_id: 1,
  property_url: "sc-domain:scrapfly.io",
  url: "https://scrapfly.io/blog/web-scraping-with-python",
  keyword: "web scraping python",
  geo: "us"
}
|> GscAnalytics.Workers.SerpCheckWorker.new()
|> Oban.insert()

# Check result in database
GscAnalytics.Repo.get_by(GscAnalytics.Schemas.SerpSnapshot, keyword: "web scraping python")
```

---

## Phase 2: Business Logic (Days 4-5)

### Step 4: SerpLandscape Context Module
**Priority**: 🔥 P1 Critical
**Estimate**: 4 hours
**Files**: `lib/gsc_analytics/content_insights/serp_landscape.ex` (NEW)

**Implementation order within file**:
1. Private helpers first:
   - `fetch_latest_snapshots/2`
   - `build_citation_breakdown/1`
   - `build_ao_samples/1`
   - `find_domain_position/3`

2. Public functions:
   - `ai_overview_stats/2` (most important)
   - `competitor_positions/2`
   - `content_type_distribution/2`

**Testing approach**:
```elixir
# Create test fixtures
defp insert_test_snapshots do
  Enum.each(1..7, fn i ->
    %GscAnalytics.Schemas.SerpSnapshot{}
    |> GscAnalytics.Schemas.SerpSnapshot.changeset(%{
      account_id: 1,
      property_url: "sc-domain:example.com",
      url: "https://example.com/page",
      keyword: "keyword_#{i}",
      position: i,
      competitors: [...],
      ai_overview_present: rem(i, 2) == 0,  # 50% have AO
      checked_at: DateTime.utc_now()
    })
    |> GscAnalytics.Repo.insert!()
  end)
end

# Test aggregation
stats = SerpLandscape.ai_overview_stats("https://example.com/page",
  account_id: 1,
  property_url: "sc-domain:example.com"
)

assert stats.total_keywords_checked == 7
```

**Unit Tests**: Create `test/gsc_analytics/content_insights/serp_landscape_test.exs`

---

## Phase 3: UI Components (Days 6-8)

### Step 5: SERP Component Library
**Priority**: 🔥 P1 Critical
**Estimate**: 3 hours
**Files**: `lib/gsc_analytics_web/components/serp_components.ex` (NEW)

**Implementation order**:
1. `ai_overview_panel/1` - Start here (highest priority)
2. `competitor_heatmap/1`
3. `content_type_chart/1`

**Development workflow**:
```bash
# Start Phoenix server with live reload
mix phx.server

# Navigate to: http://localhost:4000/dev/preview
# Add component previews for visual development
```

**Manual testing checklist**:
- [ ] AI Overview panel renders with test data
- [ ] Citation table shows ScrapFly highlighted
- [ ] Heatmap color coding works (positions 1-10)
- [ ] Content type chart percentages sum to 100%

---

### Step 6: Bulk Check Button (DashboardUrlLive)
**Priority**: 🔥 P1 Critical
**Estimate**: 2 hours
**Files**:
- `lib/gsc_analytics_web/live/dashboard_url_live.ex`
- `lib/gsc_analytics_web/live/dashboard_url_live.html.heex`

**Changes**:

**In `.ex` file**:
1. Add mount assigns:
   ```elixir
   |> assign(:show_progress_modal, false)
   |> assign(:checking_keywords, [])
   |> assign(:checked_count, 0)
   ```

2. Add `handle_event("check_top_keywords", ...)` - See TECHNICAL_SPEC.md

3. Add `handle_info({:serp_check_complete, keyword}, ...)` for PubSub

**In `.html.heex` file**:
1. Replace single check button with bulk check button
2. Add progress modal (lines ~300-330)

**Testing**:
```bash
# Start server
mix phx.server

# Navigate to URL detail page
# Click "Check Top Keywords" button
# Verify:
# - Modal appears
# - Progress updates in real-time
# - Modal closes when complete
# - Flash message shows
```

---

## Phase 4: Dashboard Page (Days 9-10)

### Step 7: SERP Landscape LiveView Page
**Priority**: 🟡 P2 Medium
**Estimate**: 3 hours
**Files**:
- `lib/gsc_analytics_web/live/dashboard_serp_landscape_live.ex` (NEW)
- `lib/gsc_analytics_web/live/dashboard_serp_landscape_live.html.heex` (NEW)
- `lib/gsc_analytics_web/router.ex` (MODIFY)

**Implementation steps**:

1. **Router** (1 minute):
   ```elixir
   # In lib/gsc_analytics_web/router.ex
   scope "/", GscAnalyticsWeb do
     pipe_through [:browser, :require_authenticated_user]

     # ... existing routes ...
     live "/dashboard/url/serp-landscape", DashboardSerpLandscapeLive, :index
   end
   ```

2. **LiveView module** (30 minutes):
   - Copy structure from `dashboard_url_live.ex`
   - Modify `handle_params/3` to call `SerpLandscape` functions
   - Assign data to socket

3. **Template** (1 hour):
   - Grid layout with 3 panels
   - Use components from Step 5
   - Add navigation breadcrumb

4. **Link from URL detail page** (15 minutes):
   ```heex
   <.link
     navigate={~p"/dashboard/url/serp-landscape?#{[url: @url, account_id: @current_account.id, property_url: @property_url]}"}
     class="btn btn-outline btn-sm"
   >
     View Full SERP Landscape →
   </.link>
   ```

**Testing**:
- Create 7 test snapshots with varied data
- Navigate to `/dashboard/url/serp-landscape?url=...`
- Verify all 3 panels render
- Check data accuracy

---

## Phase 5: Testing & Polish (Days 11-12)

### Step 8: Comprehensive Testing
**Priority**: 🟡 P2 Medium
**Estimate**: 4 hours

**Unit tests** (2 hours):
- `serp_landscape_test.exs` - All 3 main functions
- `html_parser_test.exs` - Content type classification
- Coverage target: >80%

**Integration tests** (1 hour):
- `dashboard_url_live_test.exs` - Bulk check event
- `dashboard_serp_landscape_live_test.exs` - Page rendering

**Manual QA** (1 hour):
- Test with real ScrapFly API calls
- Verify cost tracking accurate
- Check error handling (rate limits, timeouts)
- Mobile responsive check

---

### Step 9: Documentation & Polish
**Priority**: 🟡 P2 Medium
**Estimate**: 2 hours

**Code documentation**:
- Add `@moduledoc` to `SerpLandscape`
- Add `@doc` to all public functions
- Add examples to docstrings

**User-facing**:
- Add tooltips to heatmap cells
- Add loading states during bulk checks
- Improve error messages
- Add "empty state" when no snapshots exist

**Performance**:
- Add database query explain plans
- Verify indexes used
- Test with 100+ snapshots

---

## Validation Checklist (Before Merge)

### Functional Requirements
- [ ] Bulk check creates N Oban jobs (1 per keyword)
- [ ] Progress modal updates in real-time via PubSub
- [ ] Content types detected: reddit, youtube, paa, website, forum
- [ ] Top 10 competitors captured (not just 3)
- [ ] AI Overview presence calculated correctly
- [ ] ScrapFly citations identified and highlighted
- [ ] Competitor heatmap shows position grid
- [ ] Content type chart shows distribution
- [ ] SERP Landscape page accessible via link

### Non-Functional Requirements
- [ ] Database migration runs without errors
- [ ] All tests pass: `mix test`
- [ ] Pre-commit passes: `mix precommit`
- [ ] No N+1 queries (check with Ecto logs)
- [ ] Page loads <2 seconds with 50 snapshots
- [ ] Mobile responsive (test on 375px width)
- [ ] ScrapFly cost accurately tracked

### Edge Cases
- [ ] Handles URL with no GSC queries (shows empty state)
- [ ] Handles URL never checked (shows CTA to check)
- [ ] Handles ScrapFly not in top 10 (shows "-" in heatmap)
- [ ] Handles no AI Overview present (shows 0%)
- [ ] Handles API timeout (shows error, allows retry)
- [ ] Handles rate limit (snoozes job, retries later)

---

## Common Issues & Solutions

### Issue: Migration fails with "relation already exists"

**Solution**:
```bash
mix ecto.rollback
# Edit migration to fix
mix ecto.migrate
```

### Issue: Content type always returns "website"

**Cause**: URL parsing not handling www prefix

**Solution**: Update `extract_domain/1` to strip www:
```elixir
def extract_domain(url) do
  uri = URI.parse(url)
  (uri.host || "")
  |> String.replace(~r/^www\./, "")
end
```

### Issue: Heatmap shows wrong positions

**Cause**: Not using latest snapshot per keyword

**Solution**: Ensure query uses `distinct` with `order_by`:
```elixir
SerpSnapshot
|> order_by([s], desc: s.checked_at)
|> distinct([s], s.keyword)
|> Repo.all()
```

### Issue: Progress modal doesn't close

**Cause**: PubSub not broadcasting completion event

**Solution**: Add broadcast to `SerpCheckWorker.perform/1`:
```elixir
Phoenix.PubSub.broadcast(
  GscAnalytics.PubSub,
  "serp_check:#{account_id}",
  {:serp_check_complete, keyword}
)
```

### Issue: ScrapFly citations not detected

**Cause**: Domain matching too strict

**Solution**: Use `String.contains?` instead of exact match:
```elixir
String.contains?(citation["domain"] || "", "scrapfly")
```

---

## Performance Benchmarks

### Target Metrics

**Database queries**:
- Fetch latest snapshots: <50ms for 10 keywords
- AI Overview stats aggregation: <100ms
- Competitor positions: <150ms
- Content type distribution: <100ms

**UI rendering**:
- Initial page load: <2 seconds
- Heatmap with 20 domains × 10 keywords: <500ms
- Chart rendering: <300ms

**Bulk check**:
- Queue 7 jobs: <1 second
- Complete all checks: <2 minutes (depends on ScrapFly API)
- PubSub broadcast latency: <100ms

### How to measure

```elixir
# In IEx
:timer.tc(fn ->
  GscAnalytics.ContentInsights.SerpLandscape.ai_overview_stats(
    "https://scrapfly.io/blog/web-scraping-with-python",
    account_id: 1,
    property_url: "sc-domain:scrapfly.io"
  )
end)
# => {microseconds, result}
```

---

## Deployment Steps

### 1. Pre-deployment

```bash
# Run full test suite
mix test

# Run pre-commit checks
mix precommit

# Check for compilation warnings
mix compile --warnings-as-errors

# Generate migration SQL for review
mix ecto.migrate --log-sql > migration.sql
```

### 2. Staging deployment

```bash
# Deploy to staging
git push staging feature/serp-landscape

# Run migration
fly ssh console -a app-staging
> mix ecto.migrate

# Test with real data
# - Check 7 keywords for a test URL
# - Verify SERP Landscape page renders
# - Confirm costs tracked correctly
```

### 3. Production deployment

```bash
# Merge to main
git checkout main
git merge feature/serp-landscape
git push origin main

# Deploy
fly deploy

# Run migration
fly ssh console -a app-production
> mix ecto.migrate

# Verify
# - Check logs for errors
# - Test bulk check on 1 URL
# - Monitor ScrapFly credit usage
```

### 4. Post-deployment monitoring

**First 24 hours**:
- Watch error logs: `fly logs -a app-production | grep ERROR`
- Monitor Oban queue: Check `/dev/dashboard` (Oban Web UI)
- Track API costs: Query `serp_snapshots.api_cost` sum
- User feedback: Slack channel, email

**First week**:
- Gather usage metrics: # of bulk checks per day
- Identify issues: Common errors, slow queries
- Iterate: Fix bugs, improve UX

---

## Success Metrics

### Week 1 Goals
- [ ] 10 bulk keyword checks completed successfully
- [ ] 0 critical bugs reported
- [ ] <2% error rate on SERP checks
- [ ] SERP Landscape page viewed 20+ times

### Month 1 Goals
- [ ] 50+ URLs analyzed with bulk checks
- [ ] AI Overview citation data collected for 200+ keywords
- [ ] User satisfaction: 4+ stars (if surveyed)
- [ ] ScrapFly costs within budget (<$50/month)

### Long-term Goals
- [ ] SERP Landscape becomes primary URL analysis tool
- [ ] Users proactively check SERP instead of reactive
- [ ] Data informs content strategy decisions
- [ ] Competitive intelligence actionable

---

## Next Steps After MVP

Once the core functionality is stable, consider these enhancements:

1. **Automated Scheduling** (Week 5-6)
   - Weekly checks for flagged URLs
   - Smart scheduling based on rank volatility

2. **Historical Rank Tracking** (Week 7-8)
   - Time-series charts
   - Position change alerts
   - Trend detection

3. **Alerts & Notifications** (Week 9-10)
   - Email when AI Overview cites ScrapFly
   - Slack integration for rank changes
   - Weekly digest reports

4. **Advanced Analytics** (Week 11-12)
   - SERP feature correlation analysis
   - Competitor strategy insights
   - Content gap identification

---

**Document Version**: 1.0
**Last Updated**: 2025-11-17
**Estimated Total Time**: 10-12 days
**Team Size**: 1 developer
