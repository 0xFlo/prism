# Ticket-003: SERP Snapshot Schema & Migration

## Status: TODO
**Priority:** P1
**Estimate:** 5 pts
**Dependencies:** None
**Blocks:** ticket-004, ticket-005, ticket-006, ticket-007

## Problem Statement
Our `serp_snapshots` table only stores three competitors without domain/content-type info, making downstream analytics impossible. We need to extend the schema, backfill historical rows, and document the new data contract without breaking existing queries.

## Goals
- Store full top-10 competitor maps with normalized domains and content type metadata
- Add fields to summarize content types present plus ScrapFly citation flags/position
- Create a reversible migration and a backfill task so old rows stay queryable
- Document serialization rules (use the built-in `JSON` module) and provide helper functions for future migrations

## Acceptance Criteria
- [ ] Migration adds `content_types_present`, `scrapfly_mentioned_in_ao`, `scrapfly_citation_position`, indexes, and extends the `competitors` array shape
- [ ] Backfill task upgrades historical rows without locking the table for long (>500 ms per batch)
- [ ] HTML parser stores 10 competitor maps with keys: `title`, `url`, `domain`, `position`, `content_type`
- [ ] Domain helper trims protocol/www and optionally subdomains per documented rules
- [ ] Schema + migration documented in TECHNICAL_SPEC and regression tests cover serialization/backfill helpers

## Implementation Plan
1. **Schema Update**
   - Modify `GscAnalytics.Schemas.SerpSnapshot` with new fields + validations; ensure changes propagate through contexts.
2. **Migration**
   - Add new columns/indices (per RFC) and update `competitors` default to an empty list of maps.
   - Provide `down/0` to drop new columns/indexes.
3. **Backfill Task**
   - Create mix task (or Oban job) to iterate snapshots in batches, augmenting competitor arrays and populating new fields from existing data.
   - Provide progress logging + ability to resume.
4. **Parser Enhancements**
   - Update HTML parser to capture top-10 results, detect content types, and call new domain helper.
5. **Documentation & Tests**
   - Update TECHNICAL_SPEC + README; add ExUnit coverage for parser classification, domain helper, migration/backfill.

## Deliverables
- Migration file + mix task for backfill with instructions
- Updated schema + parser modules using built-in `JSON`
- Tests covering serialization, content-type detection, and backfill logic
