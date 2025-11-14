# Priority URL Import JSON Format Specification

**Version:** 1.0
**Last Updated:** 2025-11-14
**Status:** Approved for Production Use

## Overview

This document defines the JSON file format for importing priority URLs into the GSC Analytics platform. The import system accepts four JSON files (one per priority tier: P1-P4) containing curated URL lists with metadata annotations.

### Key Constraints

- **Maximum URLs:** 60,000 total across all files
- **File Count:** 4 files (one per priority tier)
- **File Naming:** `priority_urls_p1.json`, `priority_urls_p2.json`, `priority_urls_p3.json`, `priority_urls_p4.json`
- **Overflow Handling:** URLs exceeding 60k are dropped from lowest tier first (P4 → P3 → P2)

## JSON Structure

Each JSON file must contain an array of URL entry objects:

```json
[
  {
    "url": "https://www.example.com/path",
    "priority_tier": "P1",
    "page_type": "profile",
    "notes": "Optional human-readable context",
    "tags": ["tag1", "tag2"]
  }
]
```

### Required Fields

| Field | Type | Description | Validation Rules |
|-------|------|-------------|------------------|
| `url` | String | Fully-qualified URL | Must include `http://` or `https://` protocol; must have valid hostname |
| `priority_tier` | String | Priority classification | Must be exactly one of: `"P1"`, `"P2"`, `"P3"`, `"P4"` (case-sensitive) |

### Optional Fields

| Field | Type | Description | Validation Rules |
|-------|------|-------------|------------------|
| `page_type` | String | Manual page type classification | Non-empty string if provided; suggested values: `"profile"`, `"directory"`, `"location"`, `"article"`, `"landing_page"` (not enforced) |
| `notes` | String | Human-readable context about this URL | Any text; used for documentation/auditing |
| `tags` | Array of Strings | Labels for grouping/filtering | Each tag must be non-empty string |

## Validation Rules

### 1. URL Validation

URLs must be fully-qualified and follow these rules:

- **Protocol Required:** Must start with `http://` or `https://`
- **Hostname Required:** Must have valid domain name
- **Path Optional:** Can be empty (e.g., `https://example.com`)
- **Query Parameters:** Allowed and preserved (e.g., `?utm_source=email`)
- **Fragments:** Allowed and preserved (e.g., `#section`)

**Valid Examples:**
```json
"https://www.rula.com/therapists/john-smith"
"https://www.rula.com/therapy/locations/california?state=ca"
"https://www.rula.com/"
```

**Invalid Examples:**
```json
"www.rula.com/therapists"           // Missing protocol
"//rula.com/path"                   // Missing protocol
"rula.com"                          // Missing protocol
"https://"                          // Missing hostname
```

### 2. Priority Tier Validation

Priority tier must be an exact string match (case-sensitive):

- **Valid Values:** `"P1"`, `"P2"`, `"P3"`, `"P4"`
- **Invalid Values:** `"p1"`, `"Priority1"`, `"High"`, `"Tier A"`, `1`, `"P5"`

**Decision:** We enforce P1-P4 naming for consistency and simplicity. Arbitrary tier names are not supported.

### 3. Page Type Validation (Optional)

If provided, `page_type` must be a non-empty string:

- **Flexible:** No strict enum enforcement (allows client-defined types)
- **Suggested Values:** `"profile"`, `"directory"`, `"location"`, `"article"`, `"landing_page"`, `"homepage"`
- **Custom Values:** Allowed (e.g., `"therapist_bio"`, `"service_page"`)

**Valid Examples:**
```json
"page_type": "profile"
"page_type": "therapist_directory"
"page_type": null           // Omit field or set to null
```

**Invalid Examples:**
```json
"page_type": ""             // Empty string not allowed
"page_type": 123            // Must be string
```

### 4. URL Normalization

The import system normalizes URLs to ensure consistent deduplication:

#### Normalization Rules

1. **Hostname:** Convert to lowercase
   - `Example.COM` → `example.com`
   - `WWW.SITE.COM` → `www.site.com`

2. **Scheme:** Convert to lowercase
   - `HTTPS://site.com` → `https://site.com`

3. **Path:** Preserve case (paths may be case-sensitive)
   - `https://example.com/Path` → `https://example.com/Path` (unchanged)

4. **Trailing Slash:** Trim from paths (except root)
   - `https://example.com/path/` → `https://example.com/path`
   - `https://example.com/` → `https://example.com/` (root preserved)

5. **Query Parameters:** Preserve order and case
   - `https://example.com?B=2&A=1` → `https://example.com?B=2&A=1` (unchanged)

#### Normalization Examples

| Original URL | Normalized URL |
|--------------|----------------|
| `https://Example.COM/Path` | `https://example.com/Path` |
| `HTTPS://Site.com/path/` | `https://site.com/path` |
| `https://example.com/` | `https://example.com/` |
| `http://EXAMPLE.COM/API/` | `http://example.com/API` |

### 5. Deduplication Strategy

When the same URL appears multiple times (after normalization), the import system applies these rules:

#### Cross-File Deduplication

**Keep highest priority tier** (P1 > P2 > P3 > P4):

```json
// File: priority_urls_p2.json
{"url": "https://example.com/page", "priority_tier": "P2"}

// File: priority_urls_p1.json
{"url": "https://example.com/page", "priority_tier": "P1"}

// Result: P1 entry is kept, P2 entry is discarded
```

#### Within-File Deduplication

**Keep first occurrence:**

```json
// File: priority_urls_p1.json
[
  {"url": "https://example.com/page", "priority_tier": "P1", "notes": "First"},
  {"url": "https://example.com/page", "priority_tier": "P1", "notes": "Duplicate"}
]

// Result: First entry kept, second entry discarded
```

#### Case-Insensitive Deduplication

Normalized URLs are compared case-insensitively for hostname:

```json
{"url": "https://Example.com/Path", "priority_tier": "P1"}
{"url": "https://example.com/Path", "priority_tier": "P2"}

// After normalization: both become "https://example.com/Path"
// Result: P1 entry is kept (higher priority)
```

### 6. 60k Cap Enforcement

The system enforces a hard limit of **60,000 unique URLs** across all files.

#### Overflow Handling Strategy

1. **Count Total:** Sum all unique URLs after deduplication
2. **If Total ≤ 60,000:** Accept all URLs
3. **If Total > 60,000:** Drop URLs from lowest tier first

#### Drop Order

1. Drop all P4 URLs until total ≤ 60,000
2. If still over limit, drop P3 URLs
3. If still over limit, drop P2 URLs
4. **Never drop P1 URLs** (assumed highest business value)

#### Within-Tier Drop Order

When dropping within a tier, use **file position order**:
- Files processed in order: `p1.json` → `p2.json` → `p3.json` → `p4.json`
- Within each file, URLs encountered later are dropped first

#### Overflow Reporting

When URLs are dropped, the system generates an overflow report showing:
- Which URLs were dropped
- What tier they belonged to
- Why they were dropped (`"60k_cap_exceeded"`)
- Optional metadata (page_type, notes) for context

**Example Overflow Scenario:**

```
Total URLs Collected: 63,542
After Deduplication: 61,200
60k Cap: 60,000

Overflow: 1,200 URLs

Drop Strategy:
- P4 tier: 6,187 URLs → Keep 4,987, Drop 1,200
- P3 tier: 20,123 URLs → Keep all
- P2 tier: 18,456 URLs → Keep all
- P1 tier: 15,234 URLs → Keep all

Final Count: 60,000 URLs
```

## Complete Valid Example

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
    "notes": "Major metro location page",
    "tags": ["location", "california", "high-volume"]
  },
  {
    "url": "https://www.rula.com/therapists",
    "priority_tier": "P1",
    "page_type": "directory"
  },
  {
    "url": "https://www.rula.com/online-therapy",
    "priority_tier": "P1",
    "page_type": "landing_page",
    "tags": ["marketing", "high-intent"]
  }
]
```

## Invalid Examples with Explanations

### Example 1: Missing Required Field

```json
[
  {
    "url": "https://www.rula.com/therapists/jane-doe"
    // ERROR: Missing required field "priority_tier"
  }
]
```

**Error:** `"Missing required field: priority_tier"`

### Example 2: Invalid Priority Tier

```json
[
  {
    "url": "https://www.rula.com/therapists/jane-doe",
    "priority_tier": "High"
    // ERROR: Invalid value "High", must be P1, P2, P3, or P4
  }
]
```

**Error:** `"Invalid priority_tier: 'High'. Must be one of: P1, P2, P3, P4"`

### Example 3: Missing URL Protocol

```json
[
  {
    "url": "www.rula.com/therapists/jane-doe",
    // ERROR: URL must include http:// or https://
    "priority_tier": "P1"
  }
]
```

**Error:** `"Invalid URL: Missing protocol (http:// or https://)"`

### Example 4: Malformed JSON

```json
[
  {
    "url": "https://www.rula.com/therapists/jane-doe",
    "priority_tier": "P1",
    // ERROR: Trailing comma causes JSON parse error
  }
]
```

**Error:** `"JSON parse error: Unexpected token '}' at position 123"`

### Example 5: Empty Page Type

```json
[
  {
    "url": "https://www.rula.com/therapists/jane-doe",
    "priority_tier": "P1",
    "page_type": ""
    // ERROR: page_type must be non-empty string if provided
  }
]
```

**Error:** `"Invalid page_type: Cannot be empty string. Omit field or use null."`

### Example 6: Invalid URL Hostname

```json
[
  {
    "url": "https:///path/to/page",
    // ERROR: Missing hostname
    "priority_tier": "P1"
  }
]
```

**Error:** `"Invalid URL: Missing or invalid hostname"`

## File Format Best Practices

### Encoding and Formatting

- **Encoding:** UTF-8 (required)
- **Indentation:** 2 spaces (recommended for readability)
- **Line Endings:** Unix-style LF (`\n`) or Windows-style CRLF (`\r\n`) both accepted
- **Pretty Printing:** Recommended for version control diffs

### File Size Guidelines

- **Max File Size:** ~10 MB per file (supports 15-20k URLs comfortably)
- **Total Size:** ~40 MB for all 4 files combined
- **Large Files:** If files exceed 10 MB, consider splitting into smaller batches

### File Organization

Use one file per priority tier:

```
output/
├── priority_urls_p1.json  (~15k URLs, highest priority)
├── priority_urls_p2.json  (~18k URLs)
├── priority_urls_p3.json  (~20k URLs)
└── priority_urls_p4.json  (~10k URLs, lowest priority)
```

### Version Control

- **Track JSON files:** Yes, if URLs are stable
- **Exclude from Git:** If URLs change frequently or contain sensitive data
- **File Naming:** Use consistent naming for automation

## Import Process Overview

When you run the import:

1. **File Discovery:** System finds all `priority_urls_p*.json` files
2. **Parsing:** Each file is parsed and validated
3. **Validation:** Every entry is checked against validation rules
4. **Normalization:** All URLs are normalized for consistency
5. **Deduplication:** Duplicate URLs are resolved (keeping highest priority)
6. **Cap Enforcement:** If total > 60k, lowest tier URLs are dropped
7. **Persistence:** Valid URLs are upserted into database
8. **Reporting:** Import summary and overflow report are generated

### Import Command

```bash
# Import with defaults (looks for files in output/ directory)
mix prism.import_priority_urls --account-id 123

# Import with custom file path
mix prism.import_priority_urls --account-id 123 --files "custom/path/p*.json"

# Dry run (validate without persisting)
mix prism.import_priority_urls --account-id 123 --dry-run

# Export overflow report
mix prism.import_priority_urls --account-id 123 --export-overflow overflow.json
```

## Troubleshooting Common Issues

### Issue: "File not found"

**Cause:** JSON files not in expected location
**Solution:** Use `--files` option to specify custom path

```bash
mix prism.import_priority_urls --account-id 123 --files "/path/to/files/p*.json"
```

### Issue: "JSON parse error"

**Cause:** Malformed JSON (trailing commas, unquoted strings, etc.)
**Solution:** Validate JSON using online validator (jsonlint.com) or `jq`

```bash
jq . priority_urls_p1.json > /dev/null && echo "Valid JSON" || echo "Invalid JSON"
```

### Issue: "Missing required field"

**Cause:** Entry missing `url` or `priority_tier`
**Solution:** Ensure all entries have both required fields

### Issue: "Invalid priority tier"

**Cause:** Using non-standard tier names (e.g., "High", "p1", "Tier1")
**Solution:** Use exactly `"P1"`, `"P2"`, `"P3"`, or `"P4"` (case-sensitive)

### Issue: "Too many URLs dropped"

**Cause:** Total URLs exceed 60k cap
**Solution:** Review overflow report to see which URLs were dropped, then either:
- Reduce URLs in lower-priority files
- Promote important URLs to higher tiers
- Remove low-value URLs before import

## Schema Validation with NimbleOptions

The import system uses NimbleOptions for runtime validation. Here's the internal schema:

```elixir
@entry_schema [
  url: [
    type: :string,
    required: true,
    doc: "Fully-qualified URL with protocol"
  ],
  priority_tier: [
    type: :string,
    required: true,
    doc: "Priority tier: P1, P2, P3, or P4"
  ],
  page_type: [
    type: :string,
    required: false,
    doc: "Optional page type classification"
  ],
  notes: [
    type: :string,
    required: false,
    doc: "Optional human-readable notes"
  ],
  tags: [
    type: {:list, :string},
    required: false,
    doc: "Optional list of tags"
  ]
]
```

## Change Log

| Date | Version | Changes |
|------|---------|---------|
| 2025-11-14 | 1.0 | Initial specification approved for production |

## Related Documentation

- `sprint-planning/priority-urls/00-rfc-rula-priority-onboarding.md` - Technical RFC
- `sprint-planning/priority-urls/02-mix-task-ingestion-pipeline.md` - Implementation details
- `sprint-planning/priority-urls/README.md` - Sprint overview

## Support

For questions about this specification or import issues:
- Review the troubleshooting section above
- Check import logs for detailed error messages
- Contact platform team for assistance
