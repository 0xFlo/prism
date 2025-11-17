# SERP Landscape Intelligence System - Sprint Plan

**Sprint Goal**: Transform single SERP check into comprehensive AI Overview monitoring and competitor tracking system

**Focus Areas**:
- 🎯 AI Overview citation tracking (Priority #1)
- 📊 Competitor landscape heatmap
- 📈 Content type analysis
- 🔄 Bulk keyword checking

---

## User Story

**As a ScrapFly SEO analyst**, I want to understand the SERP landscape for my content so that I can:
- Know when AI Overviews appear and if ScrapFly gets cited
- Identify who ranks in top 10 (competitors)
- Understand what content types dominate (Reddit, YouTube, websites)
- Track ScrapFly's current position across multiple keywords

---

## Sprint Backlog

### 🔥 P1: Critical (Must Have)

#### Story 1: Bulk Keyword Checking
**Priority**: P1 Critical
**Estimate**: 3 points
**Dependencies**: None

**Tasks**:
- [ ] Implement `ContentInsights.top_queries/3` to fetch top GSC queries per `current_scope`, dedupe keywords, and respect a configurable keyword cap and geo filter
- [ ] Add `check_top_keywords` event handler to `DashboardUrlLive` that loads the keywords, logs the projected ScrapFly credit cost, and disables the CTA while checks run
- [ ] Enqueue one idempotent Oban job per keyword with retry/backoff settings, per-scope throttling, and telemetry for queued/processed counts
- [ ] Add a modal-driven progress experience with PubSub updates, ETA, and explicit failure/timeout states (e.g., "3/7 complete – 1 failed, retrying")
- [ ] Persist the last-run metadata (timestamp, keyword count, estimated cost) to reuse across sessions and to power the "View Landscape" CTA

**Files to modify**:
- `lib/gsc_analytics_web/live/dashboard_url_live.ex`
- `lib/gsc_analytics_web/live/dashboard_url_live.html.heex`

**Acceptance Criteria**:
- ✅ One button click checks 5-10 keywords (configurable per account scope) using top-performing GSC queries
- ✅ Shows estimated ScrapFly cost before starting and logs the projection for later auditing
- ✅ Progress modal updates in real-time, surfaces retries/failures/timeouts, and never leaves the user stuck when a job fails
- ✅ All checks either complete within 2 minutes or surface a "still running" fallback state with guidance
- ✅ Last-run metadata cached and shown on reload so users know when to expect the next check

---

#### Story 2: Enhanced SERP Data Collection
**Priority**: P1 Critical
**Estimate**: 5 points
**Dependencies**: None

**Tasks**:
- [ ] Add `content_type` classification helpers to the HTML parser and normalize values ("reddit", "youtube", "paa", "forum", "website", etc.)
- [ ] Detect Reddit, YouTube, Forums, PAA, AI Overview, and Website patterns plus fallback heuristics for anything unknown
- [ ] Capture full top 10 competitors per keyword (not just top 3) and persist them as maps with `domain`, `title`, `url`, `content_type`, and `position`
- [ ] Extract normalized domains (`https://scrapfly.io/blog/web-scraping` → `scrapfly.io`) with a dedicated helper that trims subdomains when appropriate
- [ ] Extend the `serp_snapshots` schema with new fields and write a reversible migration that backfills historical rows via a lightweight task
- [ ] Ensure any serialization/deserialization for competitor maps uses the built-in `JSON` module (per Elixir 1.18) instead of `Jason`
- [ ] Document the data shape and versioning in `SerpSnapshot` so future migrations stay compatible

**Files to modify**:
- `lib/gsc_analytics/data_sources/serp/core/html_parser.ex`
- `lib/gsc_analytics/schemas/serp_snapshot.ex`
- Create migration: `priv/repo/migrations/XXXXXX_add_serp_landscape_fields.exs`

**Migration**:
```elixir
defmodule GscAnalytics.Repo.Migrations.AddSerpLandscapeFields do
  use Ecto.Migration

  def change do
    alter table(:serp_snapshots) do
      add :content_types_present, {:array, :string}, default: []
      add :scrapfly_mentioned_in_ao, :boolean, default: false
      add :scrapfly_citation_position, :integer
    end

    create index(:serp_snapshots, [:account_id, :property_url, :url, :checked_at])
    create index(:serp_snapshots, [:ai_overview_present])
  end
end
```

**Acceptance Criteria**:
- ✅ All 10 organic results captured with normalized maps containing title, url, domain, position, and `content_type`
- ✅ Content type detected (or safely marked "unknown") for each top-10 result with >90% accuracy in fixtures
- ✅ Domain extraction helper trims protocols, `www`, and marketing params exactly as documented
- ✅ `serp_snapshots` migration adds `content_types_present`, `scrapfly_mentioned_in_ao`, `scrapfly_citation_position`, and richer competitor maps without breaking existing queries
- ✅ A backfill script upgrades legacy rows and is covered by regression tests

---

#### Story 3: AI Overview Intelligence Panel
**Priority**: P1 Critical
**Estimate**: 8 points
**Dependencies**: Story 2 (enhanced data)

**Tasks**:
- [ ] Create `ContentInsights.SerpLandscape` context module that accepts `current_scope` and memoizes expensive aggregations
- [ ] Implement `ai_overview_stats(current_scope, url)` plus helpers that return normalized structs for LiveView consumption
- [ ] Create `<.ai_overview_panel />` component with empty/error states, streaming support, and ScrapFly-brand highlight styling
- [ ] Build citation analysis table (domain, citation count, keywords cited in) along with keyword filters and CSV export hook
- [ ] Add "AI Overview Presence" percentage card powered by cached aggregates, with tooltip explaining timeframe/sample size
- [ ] Show expandable AI Overview text samples per keyword with sanitized HTML and length caps to avoid rendering issues

**New files**:
- `lib/gsc_analytics/content_insights/serp_landscape.ex`
- `lib/gsc_analytics_web/components/serp_components.ex`

**Component Structure**:
```elixir
defmodule GscAnalyticsWeb.Components.SerpComponents do
  use Phoenix.Component

  attr :snapshots, :list, required: true
  attr :target_url, :string, required: true

  def ai_overview_panel(assigns) do
    # Aggregate AI Overview stats across all keyword snapshots
    # Show citation table, presence %, ScrapFly highlights
  end

  attr :snapshots, :list, required: true

  def competitor_heatmap(assigns) do
    # Rows: domains, Columns: keywords, Cells: position
  end

  attr :snapshots, :list, required: true

  def content_type_chart(assigns) do
    # Pie/donut chart of content types
  end
end
```

**Acceptance Criteria**:
- ✅ Shows "AI Overview present in X of Y keywords" with derived percentage and clarifying tooltip
- ✅ Citation table lists all domains, counts, per-keyword badges, and highlights ScrapFly rows using brand colors
- ✅ `SerpLandscape` context always receives `current_scope`, enforces authorization, and caches aggregates for at least one minute
- ✅ Expand/collapse control reveals sanitized AI Overview text per keyword without blocking UI rendering
- ✅ Handles empty states (no AI Overview, no citations) with guidance to rerun checks

---

### 🟡 P2: Medium (Should Have)

#### Story 4: SERP Landscape Dashboard Page
**Priority**: P2 Medium
**Estimate**: 5 points
**Dependencies**: Stories 1-3

**Tasks**:
- [ ] Create new route: `/dashboard/url/serp-landscape`
- [ ] Place the route inside the existing `scope "/", GscAnalyticsWeb` + `pipe_through [:browser, :require_authenticated_user]` + `live_session :require_authenticated_user` block per `AGENTS.md`, and explain the placement in code comments/RFC
- [ ] Create `DashboardSerpLandscapeLive` LiveView that mounts with `current_scope`, loads snapshots via the new context, and streams data for perf
- [ ] Layout with 3 panels: AI Overview, Competitors, Content Types, plus header actions for "Run Bulk Check" and docs link
- [ ] Add navigation link from URL detail page (existing LiveView) including guard rails if no snapshots exist
- [ ] Show "Last checked" timestamp, keyword count badge, and warning banner when data is older than X days

**New files**:
- `lib/gsc_analytics_web/live/dashboard_serp_landscape_live.ex`
- `lib/gsc_analytics_web/live/dashboard_serp_landscape_live.html.heex`

**Router changes**:
```elixir
# lib/gsc_analytics_web/router.ex
scope "/", GscAnalyticsWeb do
  pipe_through [:browser, :require_authenticated_user]

  live_session :require_authenticated_user,
    on_mount: [{GscAnalyticsWeb.UserAuth, :require_authenticated}] do
    live "/dashboard/url/serp-landscape", DashboardSerpLandscapeLive, :index
  end
end
```
> This lives inside the authenticated browser pipeline/live_session so only logged-in users with a hydrated `current_scope` can access SERP data.

**Acceptance Criteria**:
- ✅ Dedicated page for SERP landscape analysis that enforces the authenticated pipeline/live_session rules
- ✅ Shows all 3 intelligence panels using the shared components
- ✅ Can navigate from URL detail page and returns gracefully when no snapshots are available
- ✅ URL, property, and `current_scope` passed via params/session and validated
- ✅ Warning banner appears when data is stale; CTA routes users back to bulk check flow

---

#### Story 5: Competitor Landscape Heatmap
**Priority**: P2 Medium
**Estimate**: 5 points
**Dependencies**: Story 2

**Tasks**:
- [ ] Implement `competitor_positions(url)` in `SerpLandscape` context
- [ ] Aggregate all competitors across all keyword snapshots
- [ ] Build heatmap component with position color coding
- [ ] Position 1 = dark green, Position 10 = light yellow
- [ ] Empty cells = not in top 10
- [ ] ScrapFly row highlighted with brand color
- [ ] Show average position per domain

**Acceptance Criteria**:
- ✅ Heatmap shows domains × keywords grid
- ✅ Cell color intensity = ranking strength
- ✅ ScrapFly row always visible and highlighted
- ✅ Tooltips show exact position on hover
- ✅ Average position calculated per domain

---

#### Story 6: Content Type Distribution Analysis
**Priority**: P2 Medium
**Estimate**: 3 points
**Dependencies**: Story 2

**Tasks**:
- [ ] Implement `content_type_distribution(url)` in context
- [ ] Create pie/donut chart component
- [ ] Calculate % breakdown: Reddit, YouTube, PAA, AI Overview, Websites
- [ ] Add table view: Type, Avg Position, Count, Example Domains
- [ ] Use existing chart infrastructure (PerformanceChart pattern)

**Acceptance Criteria**:
- ✅ Pie chart shows content type distribution
- ✅ Percentages accurate across all snapshots
- ✅ Table shows average position per content type
- ✅ Identifies if Reddit/YouTube dominate vs traditional sites

---

### Deprioritized (Nice to Have)

#### Story 7: Rank History Tracking
**Priority**: Deprioritized
**Estimate**: 5 points
**Dependencies**: Story 1

**Tasks**:
- [ ] Build time-series chart for ScrapFly position over time
- [ ] Multi-line chart (1 line per keyword)
- [ ] Toggle visibility per keyword
- [ ] Show position change alerts (↑↓→)
- [ ] Color-code: Green (improved), Red (declined), Gray (stable)

**Reason for deprioritization**: Requires multiple check cycles over time. Focus on current snapshot analysis first.

---

#### Story 8: Quick Insights Summary Cards
**Priority**: Deprioritized
**Estimate**: 2 points
**Dependencies**: Stories 3, 5, 6

**Tasks**:
- [ ] Add summary cards to main URL detail page
- [ ] "AI Overview Present: 5/7 keywords"
- [ ] "ScrapFly Citations: 3 mentions"
- [ ] "Avg Position: #4.2 across 7 keywords"
- [ ] Link to full landscape view

**Reason for deprioritization**: Dashboard page (Story 4) is higher priority. Cards are nice UX enhancement but not critical for MVP.

---

## Sprint Structure

### Week 1: Foundation
- **Day 1-2**: Story 1 (Bulk Keyword Checking)
- **Day 3-5**: Story 2 (Enhanced Data Collection)

### Week 2: Intelligence Panels
- **Day 1-3**: Story 3 (AI Overview Panel)
- **Day 4-5**: Story 4 (Landscape Dashboard Page)

### Week 3: Competitor & Content Analysis
- **Day 1-3**: Story 5 (Competitor Heatmap)
- **Day 4-5**: Story 6 (Content Type Analysis)

---

## Technical Architecture

### Data Flow
```
User clicks "Check Top Keywords" button
  ↓
DashboardUrlLive.handle_event("check_top_keywords")
  ↓
Query ContentInsights.top_queries(url, limit: 7)
  ↓
For each keyword:
  → SerpCheckWorker.new(account_id, property_url, url, keyword, geo)
  → Enqueue Oban job
  ↓
SerpCheckWorker.perform()
  → ScrapFly API call (36 credits)
  → HTMLParser.extract_position()
  → AIOverviewExtractor.extract()
  → Store in serp_snapshots table
  ↓
PubSub broadcast: "serp_check_complete"
  ↓
DashboardUrlLive receives update
  → Update progress modal
  → When all complete: Show "View Landscape →" link
```

### Database Schema

**serp_snapshots table** (existing + new fields):
```elixir
field :keyword, :string
field :position, :integer
field :competitors, {:array, :map}  # Enhanced with content_type, domain
field :ai_overview_present, :boolean
field :ai_overview_text, :string
field :ai_overview_citations, {:array, :map}
field :content_types_present, {:array, :string}  # NEW
field :scrapfly_mentioned_in_ao, :boolean        # NEW
field :scrapfly_citation_position, :integer      # NEW
field :checked_at, :utc_datetime
```

### Key Modules

```
lib/gsc_analytics/
  content_insights/
    serp_landscape.ex           # Aggregation logic

  data_sources/serp/core/
    html_parser.ex              # Content type detection

  schemas/
    serp_snapshot.ex            # Enhanced schema

lib/gsc_analytics_web/
  live/
    dashboard_url_live.ex       # Bulk check handler
    dashboard_serp_landscape_live.ex  # New landscape view

  components/
    serp_components.ex          # AI Overview, heatmap, charts
```

---

## Testing Strategy

### Unit Tests
- `SerpLandscape.ai_overview_stats/1` - Citation aggregation
- `HTMLParser.classify_content_type/2` - Type detection
- `SerpLandscape.competitor_positions/1` - Heatmap data structure
- `SerpSnapshot.migrate_competitors/1` - Ensures old rows upgrade to the richer map structure without losing data
- `DashboardUrlLive` helpers for credit estimation, error states, and telemetry payloads

### Integration Tests
- Bulk keyword checking workflow (mock Oban)
- PubSub progress updates
- Full SERP landscape page load
- Data migration/backfill task to ensure historical snapshots receive new fields
- Router/auth flow for `/dashboard/url/serp-landscape` to confirm only authenticated scopes can access

### Performance / Load Tests
- Run load test for `SerpLandscape` aggregations with >=50 keywords to ensure queries stay <200 ms
- Simulate concurrent bulk-check runs to validate Oban throttling and rate limiting
- Browser-level test to ensure the landscape page remains responsive when rendering 50+ snapshot cards

### Manual Testing Checklist
- [ ] Check 7 keywords for ScrapFly blog post
- [ ] Verify AI Overview citations include ScrapFly
- [ ] Confirm competitor heatmap shows expected domains
- [ ] Validate content type detection (Reddit, YouTube visible)
- [ ] Test with URL that has no AI Overview
- [ ] Test with URL not in top 10 for any keyword

---

## Cost Analysis

**ScrapFly Credits**: 36 credits per keyword check

**Sprint Testing Costs**:
- 10 test URLs × 7 keywords × 36 credits = **2,520 credits**
- Assume 3 test iterations = **~7,500 credits total**
- At $0.001 per credit = **~$7.50 for full sprint**

**Production Costs (On-demand)**:
- User checks 1 URL with 7 keywords = 252 credits (~$0.25)
- 100 URLs checked per month = 25,200 credits (~$25/month)

**Note**: On-demand only (no scheduled jobs) keeps costs predictable and low.

---

## Success Metrics

### Quantitative
- ✅ Bulk check completes <2 minutes for 10 keywords
- ✅ AI Overview presence detected 100% when present
- ✅ ScrapFly citations identified 100% accuracy
- ✅ Content type classification >90% accuracy
- ✅ Competitor heatmap loads <1 second

### Qualitative
- ✅ User understands SERP landscape at a glance
- ✅ Can answer: "Do AI Overviews cite us?"
- ✅ Can answer: "Who are our main competitors?"
- ✅ Can answer: "What content types dominate?"
- ✅ Can answer: "Where does ScrapFly rank?"

---

## Risk Assessment

### Technical Risks
- **ScrapFly rate limits**: Mitigated by existing backoff logic
- **HTML parsing breaks**: Mitigated by multiple fallback patterns
- **Database performance**: Mitigated by proper indexing

### Product Risks
- **Inaccurate content type detection**: Manual review + refinement needed
- **AI Overview structure changes**: Monitoring required, update patterns
- **Competitor noise**: Filter to top 20 domains max
- **Migration fallout**: Need rehearsed backfill and clear rollback plan in case snapshot schema changes fail in production
- **Authorization regressions**: New LiveView must stay inside authenticated scope; add regression tests

---

## References

### Existing Code
- `lib/gsc_analytics/data_sources/serp/core/html_parser.ex` - SERP parsing logic
- `lib/gsc_analytics/data_sources/serp/core/ai_overview_extractor.ex` - AI Overview detection
- `lib/gsc_analytics/workers/serp_check_worker.ex` - Oban job handler
- `lib/gsc_analytics_web/live/dashboard_url_live.ex` - Current single check button

### Documentation
- ScrapFly SERP API: https://scrapfly.io/docs/scrape-api/serp
- Google SERP structure (2025): https://developers.google.com/search
- Phoenix LiveView 1.1: https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html

---

## Sprint Retrospective (Post-Sprint)

### What Went Well
- TBD

### What Could Be Improved
- TBD

### Action Items for Next Sprint
- TBD

---

**Sprint Start Date**: TBD
**Sprint End Date**: TBD
**Sprint Owner**: TBD
**Stakeholders**: ScrapFly SEO Team
