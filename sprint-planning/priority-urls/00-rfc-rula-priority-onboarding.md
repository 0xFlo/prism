# RFC: Rula Priority URL Onboarding & Page-Type Integration

- **Author:** Codex (on behalf of flor)
- **Date:** 2025-02-14
- **Status:** Draft
- **Reviewers Needed:** Platform (GSC ingestion), Web (LiveView), Data (workflows)

## 1. Summary

Rula is onboarding with a 60 k URL ceiling, but Google Search Console (GSC) forces us to fetch the entire property anyway. We need a deterministic way to ingest the client's curated priority lists (P1–P4 JSON files), store the annotations, and keep all downstream dashboards scoped to those URLs without discarding the rest of the crawl data. This RFC describes a reusable ingestion contract, metadata strategy, and dashboard/query changes so we can:

1. Accept priority payloads in `output/priority_urls_p*.json` while enforcing the 60 k cap.
2. Persist client-provided priority tiers and manual page types inside `gsc_url_metadata`.
3. Hydrate dashboard queries with metadata so filters (`filter_page_type`, priority badges) operate on persisted values rather than brittle SQL `ILIKE`s.
4. Extend `PageTypeClassifier` to understand therapist-directory patterns (profiles, locations, list pages) and reconcile heuristics with manual overrides.
5. Trigger targeted re-sync/crawler work when priority lists change, without overwhelming Oban queues.

## 2. Background & Problem Statement

- **Data ingestion today**: `GscAnalytics.DataSources.GSC.Core.Persistence` pulls every URL that GSC exposes. There is no notion of "priority URLs" other than runtime filtering.
- **Classification duplication**: `GscAnalytics.ContentInsights.PageTypeClassifier` (Elixir side) and `GscAnalytics.ContentInsights.Filters.apply_page_type/2` (SQL) re-implement the same heuristics. No values are stored in the DB, so every dashboard request recomputes page types.
- **Metadata gap**: `gsc_url_metadata` already has `url_type`, `content_category`, `update_priority`, but `ContentInsights.UrlPerformance` does not join that table, so UI columns never surface the data.
- **Client requirement**: Rula supplies four JSON files totaling ~63.5 k URLs. They expect us to retain only the highest-priority 60 k, keep tier info, and differentiate directory sections (therapist list vs. profile vs. location). We also need import transparency (reporting what was dropped/accepted).

## 3. Goals

1. Define a stable import pipeline for `output/priority_urls_p{1..4}.json` that validates schema, dedupes URLs, and enforces the 60 k cap.
2. Persist `priority_tier`, `page_type`, and optional metadata (notes, labels) in `gsc_url_metadata`.
3. Update `ContentInsights.UrlPerformance` to join metadata so LiveView filters and badges reflect stored values.
4. Prefer metadata-derived page types when filtering; fall back to classifier heuristics when missing.
5. Expand `PageTypeClassifier` with therapist-directory rules and keep SQL + Elixir logic in sync.
6. Provide operational hooks (Mix task and Workflow step) to re-run imports + downstream syncs when clients drop new files.

## 4. Non-Goals

- Changing how GSC ingest works (we still pull full datasets).
- Building a UI for uploading JSON (manual file drops or automation outside scope).
- Replacing existing HTTP/crawler scheduling logic beyond what's required to focus on the priority set.

## 5. Detailed Requirements

### 5.1 Functional
- Accept four JSON files located at `output/priority_urls_p{1..4}.json` plus `JSON_FORMAT.md`.
- Schema must include `url` and `priority_tier` (P1–P4). Optional fields: `page_type`, `notes`, `tags`.
- Import must dedupe URLs (case- and trailing-slash-insensitive) and trim to ≤60 000, dropping from lowest tier first.
- Persist:
  - `update_priority` = tier (P1–P4) in `gsc_url_metadata`.
  - `url_type` or new `page_type` column for manual overrides.
  - `metadata_source` audit fields (file batch ID, imported_at).
- Provide a report summarizing counts per tier, truncated URLs, validation failures.
- Dashboard queries must include `update_priority`, `url_type/page_type`, `content_category` in the result set.
- Filters must use metadata when present, else fallback heuristics.
- Provide command(s) to rerun import + trigger `GscAnalytics.Workers.HttpStatusCheckWorker.enqueue_new_urls/1` for affected URLs.

### 5.2 Performance & Scale
- Import must handle 65 k+ URLs in <60 s locally; use streaming JSON with Elixir built-in `:json` module (per AGENTS.md).
- Database upserts should batch (e.g., `Repo.insert_all` with `on_conflict`) to avoid one-by-one writes.
- Dashboard query plan must remain index-friendly: use stored columns instead of `ILIKE`.

## 6. Proposed Solution

### 6.1 File Contract & Validation
- Document schema in `output/JSON_FORMAT.md` and enforce with a dedicated struct + `NimbleOptions`.
- Implement `Mix.Tasks.Prism.ImportPriorityUrls`:
  1. Read each `priority_urls_p*.json`.
  2. Validate JSON → list of `%PriorityEntry{url, tier, page_type?, notes?}`.
  3. Normalize URLs (lowercase host, ensure scheme).
  4. Aggregate by URL keeping highest-priority tier.
  5. Apply 60 k cap (drop overflow from lowest tier, log details).
  6. Upsert into metadata.

### 6.2 Metadata Persistence
- Extend `gsc_url_metadata`:
  - Add columns: `page_type` (string), `metadata_source` (string), `metadata_batch_id` (string), `priority_imported_at` (utc).
  - Add composite unique index `(account_id, url)`.
- Reuse logic from `GscAnalytics.Workflows.Steps.UpdateMetadataStep` by extracting common upsert helper (e.g., `GscAnalytics.Metadata.upsert_priority_metadata/3`).
- When page type is provided, store it; when missing, allow classifier to populate `url_type`.

### 6.3 Dashboard Query Changes
- In `GscAnalytics.ContentInsights.UrlPerformance.build_hybrid_query/4`, add `LEFT JOIN gsc_url_metadata ON account_id/url`.
- Select `update_priority`, `page_type`, `content_category`, `metadata_source`.
- Update `enrich_urls/4` to merge metadata attributes (respect existing `needs_update` logic).
- Adjust `Filters.apply_page_type/2`:
  - If metadata join alias provides `page_type`, filter on that ( e.g., `where metadata.page_type IN (...)`).
  - Only fall back to current `build_page_type_condition` when metadata is null.

### 6.4 Classifier Improvements
- Add new atoms: `:directory`, `:profile`, `:location`.
- Recognize therapist patterns: `/therapists/`, `/providers/`, `/therapy/locations/`, `/therapist/<name>`.
- Mirror logic in SQL helper or, preferably, compute classifier output once and store in metadata; Filters can then filter on stored values.
- Provide automated tests for new patterns.

### 6.5 Workflow & Automation
- Add Workflow step `priority_import` that shells into Mix task (or reuses the same module) so Ops can schedule imports.
- After import, emit list of updated URLs so we can:
  - Kick `GscAnalytics.Workers.HttpStatusCheckWorker.enqueue_new_urls/1` for new URLs.
  - Optionally call `GscAnalytics.DataSources.GSC.Core.Persistence.enqueue_http_status_checks/3` for changed tiers.

### 6.6 Reporting & Observability
- Mix task outputs summary (counts per tier, duplicates removed, overflow dropped).
- Store `metadata_batch_id` (e.g., timestamp or hash of files) for audit.
- Add Oban job logging to indicate when targeted rechecks begin/end.

## 7. Alternatives Considered
1. **Store priority list externally (S3, Supabase)** – rejected to keep everything self-contained per client instructions.
2. **Filter at query time only** – rejected because it keeps expensive regex filters and loses manual overrides.
3. **Use separate table for priorities** – adds extra joins w/out leveraging existing metadata table; `gsc_url_metadata` already models these attributes.

## 8. Impact
- **Product**: Clients see accurate priority badges, can filter to e.g., "Therapist Profiles (P1–P2)" instantly.
- **Engineering**: Centralized metadata reduces duplication between SQL and Elixir heuristics.
- **Ops**: Mix task + workflow allow repeatable imports; reports clarify what was ingested/dropped.
- **Performance**: Removing `ILIKE` chains and using indexed columns should lower query latency (expected 10–20% improvement for page-type filters).

## 9. Risks & Mitigations
| Risk | Mitigation |
| --- | --- |
| Malformed JSON or >60 k URLs break import | Strict validation + dry-run flag and overflow reporting |
| Metadata joins slow queries | Add composite index on `(account_id, property_url, url)` and keep select list minimal |
| Classifier changes mislabel other clients | Scope therapist-specific rules behind optional config (per account) or guard by hostname |
| Duplicate classifier + stored values diverge | Always prefer stored metadata; add nightly job to backfill missing page types using classifier |

## 10. Open Questions
1. Do we need to support arbitrary tier names (e.g., "Tier A") or enforce P1–P4?
2. Should directory-specific page types appear in the generic dashboard filter, or do we create a client-specific view?
3. Where should `JSON_FORMAT.md` live for version control—root `output/` or `docs/clients/rula/`?
4. Can we expose import status in-app (e.g., banner) or is console logging enough?

## 11. Rollout Plan
1. **Week 1**
   - Finalize JSON schema doc.
   - Implement Mix task + validation + reporting (feature flag per account).
2. **Week 2**
   - Add metadata columns + migration.
   - Update `UrlPerformance` joins and `Filters.apply_page_type/2`.
   - Update LiveView assigns/UI to read stored values.
3. **Week 3**
   - Extend classifier + tests.
   - Wire workflow step + targeted rechecks.
4. **Week 4**
   - Dry-run import with sample files, capture metrics.
   - Production rollout (enable for Rula account ID, monitor dashboards).

## 12. Success Metrics
- Import task completes in <2 minutes for 65 k URLs with zero validation errors.
- Dashboard page-type filter latency improves vs. baseline (target: <250 ms DB query time).
- 100% of Rula priority URLs show correct `update_priority` badge and desired page type in UI.
- Alerting/reporting identifies any attempt to exceed 60 k URLs within 5 minutes of import.

## 13. References
- `lib/gsc_analytics/content_insights/page_type_classifier.ex`
- `lib/gsc_analytics/content_insights/filters.ex`
- `lib/gsc_analytics/content_insights/url_performance.ex`
- `lib/gsc_analytics/schemas/url_metadata.ex`
- `lib/gsc_analytics/workflows/steps/update_metadata_step.ex`
