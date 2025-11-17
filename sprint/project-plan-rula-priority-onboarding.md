# Project Plan — Rula Priority URL Onboarding

## Objective
Operationalize Rula’s 60 k priority URL program by importing client JSON files, persisting metadata, and surfacing tiers/page types throughout the dashboard and crawler workflows.

## Milestones & Tasks

### Milestone 1 — File Contract & Importer (Target: Week 1)
- **Task 1.1** Document JSON schema in `output/JSON_FORMAT.md` with validation rules.
- **Task 1.2** Build `mix prism.import_priority_urls` to ingest `priority_urls_p*.json`, dedupe, validate, and enforce 60 k cap.
- **Task 1.3** Emit import summary (counts, drops, validation errors) and persist batch metadata for audit.

### Milestone 2 — Metadata Persistence (Target: Week 2)
- **Task 2.1** Add `page_type`, `metadata_source`, `metadata_batch_id`, `priority_imported_at` columns + indexes to `gsc_url_metadata`.
- **Task 2.2** Extract reusable metadata upsert helper shared by Mix task and workflows.
- **Task 2.3** Backfill existing metadata with classifier output where missing.

### Milestone 3 — Dashboard & API Integration (Target: Week 2)
- **Task 3.1** Update `ContentInsights.UrlPerformance` to left join metadata and select priority/page-type fields.
- **Task 3.2** Modify `Filters.apply_page_type/2` to prefer stored metadata, fallback to heuristics.
- **Task 3.3** Ensure LiveView assigns render priority badges + new directory page types (add tests).

### Milestone 4 — Classifier Enhancements (Target: Week 3)
- **Task 4.1** Extend `PageTypeClassifier` with therapist directory patterns (`:directory`, `:profile`, `:location`).
- **Task 4.2** Mirror logic in SQL or rely on stored metadata to avoid divergence.
- **Task 4.3** Add regression tests covering new patterns.

### Milestone 5 — Workflow & Ops Automation (Target: Week 3)
- **Task 5.1** Create workflow step (`priority_import`) that invokes the import helper with configurable paths.
- **Task 5.2** After import, enqueue HTTP/GSC refresh jobs for changed URLs only.
- **Task 5.3** Add logging/metrics for workflow runs and link to batch IDs.

### Milestone 6 — Rollout & Validation (Target: Week 4)
- **Task 6.1** Dry-run importer with sample Rula files, confirm 60 k cap behaviour.
- **Task 6.2** Enable feature flag for Rula account, monitor dashboard query performance and badge accuracy.
- **Task 6.3** Capture lessons learned + update onboarding docs for future clients.

## Ownership & Dependencies
- **Primary Engineer:** TBD (needs Elixir + LiveView familiarity).
- **Dependencies:** DB migration review, Ops for workflow scheduling, QA for dashboard regression testing.

## Success Metrics
- Import completes in <2 min for 65 k entries.
- Dashboard page-type filters return results within SLA (<250 ms DB time).
- 100% of Rula URLs display correct priority badge/page type after rollout.
