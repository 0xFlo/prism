# Sprint: Priority URLs - Rula Onboarding

## Epic Summary

**Objective:** Build deterministic import pipeline to onboard Rula's 60,000 priority URLs with tiered metadata (P1-P4) and therapist directory page-type classification.

**Business Problem:** Rula requires tracking 60k curated URLs from a larger set (~63.5k total). Current system has no concept of "priority URLs" and relies on expensive SQL pattern matching for page-type classification. Need to persist client-curated metadata and surface it throughout dashboards.

**Technical Solution:** Create JSON ingestion pipeline that validates, dedupes, and persists priority tiers and page types into `gsc_url_metadata` table, then refactor dashboard queries to use stored metadata instead of runtime heuristics.

## Reference Documentation

- `00-rfc-rula-priority-onboarding.md` - Complete technical RFC with architecture decisions
- `00-project-plan.md` - High-level milestone breakdown

## Sprint Structure

This sprint is organized into **6 milestones** with **18 total tickets**:

### Milestone 1: File Contract & Importer (Week 1)
Build JSON ingestion pipeline with validation and 60k cap enforcement.

- `01-json-schema-documentation.md` - Document JSON format and validation rules
- `02-mix-task-ingestion-pipeline.md` - Build Mix task for import with streaming JSON
- `03-import-reporting-audit.md` - Create import summary reports and audit trail

### Milestone 2: Metadata Persistence (Week 2)
Database schema changes and reusable persistence layer.

- `04-database-migration-metadata.md` - Add new columns and indexes to gsc_url_metadata
- `05-upsert-helper-module.md` - Extract reusable metadata upsert logic
- `06-backfill-metadata-classifier.md` - Backfill existing URLs with classifier output

### Milestone 3: Dashboard & API Integration (Week 2)
Surface metadata in UI queries and filters.

- `07-url-performance-metadata-joins.md` - Add LEFT JOIN to metadata table in queries
- `08-filters-stored-metadata.md` - Refactor filters to prefer stored metadata
- `09-liveview-ui-badges.md` - Update LiveView UI with priority badges and page types

### Milestone 4: Classifier Enhancements (Week 3)
Extend page-type classification for therapist directories.

- `10-classifier-directory-patterns.md` - Add new classifier atoms and URL patterns
- `11-sync-elixir-sql-classification.md` - Sync classification logic across Elixir and SQL
- `12-classifier-regression-tests.md` - Comprehensive test coverage for new patterns

### Milestone 5: Workflow & Ops Automation (Week 3)
Operational hooks and targeted reprocessing.

- `13-priority-import-workflow.md` - Create workflow step for scheduled imports
- `14-post-import-job-enqueueing.md` - Trigger targeted HTTP status checks after import
- `15-logging-telemetry.md` - Add metrics, logging, and observability

### Milestone 6: Rollout & Validation (Week 4)
Testing, deployment, and performance validation.

- `16-dry-run-testing.md` - Test import with sample data and validate 60k cap
- `17-production-rollout-feature-flag.md` - Deploy to production with feature flag
- `18-performance-validation-docs.md` - Measure performance improvements and document

## Dependency Graph

```
Milestone 1 (File Contract & Importer)
├── 01 → 02 → 03
│
Milestone 2 (Metadata Persistence)
├── 04 → 05 → 06
│
├─────────────┐
│             │
Milestone 3   Milestone 4
(Dashboard)   (Classifier)
│             │
07 → 08 → 09  10 → 11 → 12
│             │
└─────┬───────┘
      │
Milestone 5 (Workflow & Ops)
├── 13 → 14 → 15
│
Milestone 6 (Rollout & Validation)
└── 16 → 17 → 18
```

**Critical Path:**
1. Milestones 1 & 2 can start in parallel (documentation vs. database design)
2. Milestone 3 **depends on** Milestone 2 (needs database columns)
3. Milestone 4 can develop in parallel with Milestone 3
4. Milestone 5 **depends on** Milestones 1-4 (needs all components integrated)
5. Milestone 6 **depends on** everything (final integration and validation)

## Success Metrics

### Technical Performance
- ✓ Import completes in <2 minutes for 65k URLs
- ✓ Zero validation errors in production import
- ✓ Dashboard query time <250ms (10-20% improvement)
- ✓ 100% of priority URLs show correct badges

### Business Outcomes
- ✓ Rula account stays within 60k URL limit
- ✓ All priority tiers (P1-P4) correctly represented
- ✓ Therapist directory pages accurately classified
- ✓ Import/refresh operations complete within 5-minute alerting window

## Key Technical Components

| Component | Purpose | Files Modified |
|-----------|---------|---------------|
| **Mix Task** | JSON ingestion & validation | `lib/mix/tasks/prism/import_priority_urls.ex` |
| **Metadata Schema** | Store priority tiers & page types | `lib/gsc_analytics/schemas/url_metadata.ex` |
| **Database Migration** | Add new columns & indexes | `priv/repo/migrations/*_add_priority_metadata.exs` |
| **UrlPerformance** | Query metadata with LEFT JOIN | `lib/gsc_analytics/content_insights/url_performance.ex` |
| **Filters** | Use stored metadata over heuristics | `lib/gsc_analytics/content_insights/filters.ex` |
| **PageTypeClassifier** | Therapist directory patterns | `lib/gsc_analytics/content_insights/page_type_classifier.ex` |
| **Workflow Step** | Scheduled import automation | `lib/gsc_analytics/workflows/steps/priority_import_step.ex` |
| **LiveView** | Priority badges & page type UI | `lib/prism_web/live/content_insights/*` |

## Technology Stack

- **Language:** Elixir 1.14+
- **Framework:** Phoenix 1.7+ with LiveView
- **Database:** PostgreSQL 14+ (with composite indexes)
- **Background Jobs:** Oban 2.x
- **Validation:** NimbleOptions for schema enforcement
- **JSON Processing:** Elixir built-in `:json` module (streaming)

## Risk Management

| Risk | Impact | Mitigation | Status |
|------|--------|------------|--------|
| Malformed JSON breaks import | High | Strict validation + dry-run flag | Addressed in Ticket 01 |
| >60k URLs exceed limit | High | Overflow reporting with tier-based truncation | Addressed in Ticket 02 |
| Metadata joins slow queries | Medium | Composite index on (account_id, url) | Addressed in Ticket 04 |
| Classifier mislabels other clients | Medium | Scope therapist rules behind account config | Addressed in Ticket 10 |
| Stored values diverge from classifier | Low | Always prefer metadata; nightly backfill job | Addressed in Ticket 06 |

## Getting Started

### Prerequisites
```bash
# Ensure you have Elixir and PostgreSQL installed
mix deps.get
mix ecto.setup
```

### Execution Order

1. **Start with Milestone 1:** JSON schema documentation and Mix task implementation
2. **Parallel track:** Begin database migration design (Milestone 2) while Milestone 1 is in progress
3. **Integration phase:** Once Milestones 1 & 2 complete, start Milestones 3 & 4 in parallel
4. **Automation phase:** Milestone 5 requires all previous work to be integrated
5. **Validation phase:** Milestone 6 is the final gate before production rollout

### Running Individual Tickets

Each ticket file contains:
- YAML frontmatter with status, priority, and dependencies
- Comprehensive description with context
- Acceptance criteria (numbered checklist)
- Technical specifications (modules, functions, patterns)
- Testing requirements (unit, integration, regression)
- Success metrics (how to verify completion)

### Example Ticket Execution

```bash
# Read the ticket
cat 02-mix-task-ingestion-pipeline.md

# Implement the changes described
# Run tests
mix test test/prism/import_priority_urls_test.exs

# Verify acceptance criteria
mix prism.import_priority_urls --dry-run --files "test/fixtures/priority_urls_p*.json"

# Mark ticket as complete when all criteria pass
```

## Open Questions (RFC Section 10)

1. **Tier naming:** Enforce P1-P4 or support arbitrary names (e.g., "Tier A")?
   - *Decision needed before Ticket 01*
2. **UI customization:** Directory page types in generic filter OR client-specific view?
   - *Decision needed before Ticket 09*
3. **Documentation location:** Where should `JSON_FORMAT.md` live for version control?
   - *Decision needed before Ticket 01*
4. **Import status:** Expose in-app (banner/alert) or console logging sufficient?
   - *Decision needed before Ticket 03*

## Changelog

- **2025-11-13:** Sprint planning folder created with 18 tickets across 6 milestones
- **2025-02-14:** Original RFC drafted by Codex

---

**Ready to execute?** Start with Ticket 01: `01-json-schema-documentation.md`
