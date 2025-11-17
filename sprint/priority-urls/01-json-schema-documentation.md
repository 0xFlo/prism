---
ticket_id: "01"
title: "Document JSON Schema and Validation Rules"
status: pending
priority: P1
milestone: 1
estimate_days: 1
dependencies: []
blocks: ["02", "03"]
success_metrics:
  - "JSON_FORMAT.md exists with complete schema documentation"
  - "All required and optional fields documented with examples"
  - "Validation rules clearly specified for each field"
  - "Example valid and invalid payloads included"
---

# Ticket 01: Document JSON Schema and Validation Rules

## Context

Before building the import pipeline, we need a clear contract for the JSON file format that Rula will provide. This documentation serves as the specification for both the client (who generates the files) and our validation logic (in Ticket 02).

The client will provide 4 JSON files: `priority_urls_p1.json`, `priority_urls_p2.json`, `priority_urls_p3.json`, `priority_urls_p4.json`, containing a total of ~63,500 URLs that must be trimmed to 60,000.

## Acceptance Criteria

1. ✅ Create `output/JSON_FORMAT.md` documentation file
2. ✅ Document JSON structure as array of objects with required/optional fields
3. ✅ Specify validation rules for each field (type, format, constraints)
4. ✅ Include valid example payload (at least 3 complete entries)
5. ✅ Include invalid example payloads with explanation of why they're invalid
6. ✅ Document URL normalization rules (case-sensitivity, trailing slashes)
7. ✅ Document deduplication strategy (what happens when same URL appears multiple times)
8. ✅ Document 60k cap enforcement strategy (which URLs get dropped)
9. ✅ Answer open question: Enforce P1-P4 or support arbitrary tier names?

## Technical Specifications

### File Location
```
output/JSON_FORMAT.md
```

### Required Fields
Each JSON entry must include:
- `url` (string): Fully-qualified URL including protocol (https://)
- `priority_tier` (string): One of P1, P2, P3, P4

### Optional Fields
- `page_type` (string): Manual page type classification (e.g., "profile", "directory", "location")
- `notes` (string): Human-readable context about this URL
- `tags` (array of strings): Optional labels for grouping/filtering

### JSON Schema Structure
```json
[
  {
    "url": "https://example.com/path",
    "priority_tier": "P1",
    "page_type": "profile",
    "notes": "High-value therapist profile page",
    "tags": ["therapist", "high-intent"]
  }
]
```

### Validation Rules

1. **URL Validation**
   - Must start with `http://` or `https://`
   - Must have valid hostname
   - Path is optional but should be normalized
   - Query parameters and fragments allowed

2. **Priority Tier Validation**
   - Must be exactly one of: "P1", "P2", "P3", "P4"
   - Case-sensitive (reject "p1" or "Priority1")
   - No arbitrary tier names (per RFC open question - decision needed)

3. **Page Type Validation (Optional)**
   - If provided, must be non-empty string
   - Suggest known types: "profile", "directory", "location", "article", "landing_page"
   - Don't enforce enum (allow client flexibility)

4. **URL Normalization**
   - Convert hostname to lowercase (`Example.COM` → `example.com`)
   - Preserve path case (may be case-sensitive)
   - Trim trailing slash inconsistency: treat `example.com/path` same as `example.com/path/`
   - Preserve query parameters and order

5. **Deduplication Strategy**
   - If same URL appears in multiple files: keep highest priority tier (P1 > P2 > P3 > P4)
   - If same URL appears multiple times in same file: keep first occurrence
   - If normalized URLs collide: treat as duplicate (e.g., `Example.com/Path` vs `example.com/path`)

6. **60k Cap Enforcement**
   - Count total unique URLs across all 4 files
   - If total > 60,000: drop URLs from lowest tier first (P4, then P3, then P2)
   - Within same tier: drop URLs in order they appear (file order: p1, p2, p3, p4)
   - Generate overflow report showing which URLs were dropped

### Example Valid Payload

```json
[
  {
    "url": "https://www.rula.com/therapists/john-smith-lmft",
    "priority_tier": "P1",
    "page_type": "profile",
    "notes": "High-converting therapist in top metro area",
    "tags": ["therapist", "top-performer", "california"]
  },
  {
    "url": "https://www.rula.com/therapy/locations/california/san-francisco",
    "priority_tier": "P1",
    "page_type": "location",
    "tags": ["location", "california"]
  },
  {
    "url": "https://www.rula.com/therapists",
    "priority_tier": "P2",
    "page_type": "directory"
  }
]
```

### Example Invalid Payloads

```json
// INVALID: Missing priority_tier
[
  {
    "url": "https://www.rula.com/therapists/jane-doe"
  }
]

// INVALID: Invalid priority tier value
[
  {
    "url": "https://www.rula.com/therapists/jane-doe",
    "priority_tier": "High"
  }
]

// INVALID: Missing protocol in URL
[
  {
    "url": "www.rula.com/therapists/jane-doe",
    "priority_tier": "P1"
  }
]

// INVALID: Malformed JSON (trailing comma)
[
  {
    "url": "https://www.rula.com/therapists/jane-doe",
    "priority_tier": "P1",
  }
]
```

## Testing Requirements

### Documentation Validation
1. **Completeness Check**
   - All required fields documented
   - All optional fields documented
   - All validation rules specified
   - Examples provided for valid and invalid cases

2. **Schema Consistency**
   - Example payloads validate against documented schema
   - Invalid examples clearly violate documented rules

3. **Edge Cases Documented**
   - URL normalization edge cases (trailing slashes, case)
   - Deduplication conflicts (same URL in multiple tiers)
   - 60k cap overflow scenarios

### Review Checklist
- [ ] Can client generate files matching this spec?
- [ ] Are validation rules unambiguous?
- [ ] Do examples cover common use cases?
- [ ] Are edge cases clearly explained?

## Implementation Notes

### Decisions Required
1. **Tier naming:** Enforce P1-P4 or support arbitrary names?
   - **Recommendation:** Enforce P1-P4 for consistency and simplicity
   - **Alternative:** Support arbitrary names with mapping configuration

2. **Documentation location:** `output/` or `docs/clients/rula/`?
   - **Recommendation:** `output/` since files are placed there
   - **Alternative:** `docs/clients/rula/` for version control (client-specific)

3. **Page type validation:** Strict enum or flexible string?
   - **Recommendation:** Flexible string with suggested values
   - **Rationale:** Allow client to define new types without code changes

### File Format Best Practices
- Use UTF-8 encoding
- Pretty-print JSON with 2-space indentation (for human readability)
- One file per priority tier (not one large file)
- Max file size: ~10 MB per file (should handle 15-20k URLs easily)

### URL Normalization Reference
```elixir
# Pseudocode for normalization
def normalize_url(url) do
  uri = URI.parse(url)

  %URI{uri |
    scheme: String.downcase(uri.scheme || "https"),
    host: String.downcase(uri.host || ""),
    path: String.trim_trailing(uri.path || "/", "/")
  }
  |> URI.to_string()
end
```

## Success Metrics

1. **Documentation Quality**
   - ✓ JSON_FORMAT.md contains all required sections
   - ✓ 0 ambiguous validation rules (peer review confirms clarity)
   - ✓ All examples parse as valid JSON
   - ✓ Client confirms spec is implementable

2. **Coverage**
   - ✓ 100% of required fields documented
   - ✓ 100% of optional fields documented
   - ✓ At least 3 valid examples
   - ✓ At least 4 invalid examples

3. **Usability**
   - ✓ Ticket 02 can implement validation without additional clarification
   - ✓ Client can generate files without asking questions

## Related Files

- `00-rfc-rula-priority-onboarding.md` - RFC Section 5.1 (Functional Requirements)
- `00-project-plan.md` - Milestone 1, Task 1.1

## Next Steps

After this ticket is complete:
1. **Ticket 02:** Implement Mix task using this schema for validation
2. **Ticket 03:** Use this schema to generate import reports
3. **Client communication:** Share JSON_FORMAT.md with Rula for file generation
