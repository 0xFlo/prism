---
ticket_id: "06"
title: "Backfill Existing Metadata with Classifier Output"
status: pending
priority: P3
milestone: 2
estimate_days: 3
dependencies: ["04", "05"]
blocks: []
success_metrics:
  - "All existing URLs have page_type populated"
  - "Classifier output matches expected patterns"
  - "Backfill completes without overwriting manual values"
  - "Process is repeatable for future backfills"
---

# Ticket 06: Backfill Existing Metadata with Classifier Output

## Context

After adding new metadata columns (Ticket 04), existing URL records have NULL values for `page_type`. Run the `PageTypeClassifier` against all existing URLs and populate the metadata using the upsert helper from Ticket 05. This ensures consistent data before rolling out dashboard features.

## Acceptance Criteria

1. ✅ Create Mix task `mix prism.backfill_page_types`
2. ✅ Query all URLs without `page_type` for given account
3. ✅ Run `PageTypeClassifier` against each URL
4. ✅ Use `Metadata.backfill_page_types/3` to persist results
5. ✅ Process in batches to avoid memory issues
6. ✅ Skip URLs that already have manual `page_type` values
7. ✅ Add `--dry-run` flag for validation
8. ✅ Generate summary report of classifications
9. ✅ Support incremental backfill (resume from last processed)

## Technical Specifications

```elixir
defmodule Mix.Tasks.Prism.BackfillPageTypes do
  use Mix.Task
  alias GscAnalytics.{Metadata, ContentInsights.PageTypeClassifier}

  @shortdoc "Backfill page_type metadata using PageTypeClassifier"

  def run(args) do
    # Parse options
    # Query URLs without page_type
    # Classify in batches
    # Upsert using Metadata.backfill_page_types/3
    # Report statistics
  end

  defp classify_batch(urls) do
    Enum.map(urls, fn url ->
      {url, PageTypeClassifier.classify(url)}
    end)
  end
end
```

## Testing Requirements

```elixir
test "backfills page types for unclassified URLs" do
  # Create URLs without page_type
  insert_list(100, :url_metadata, account_id: 123, page_type: nil)

  Mix.Tasks.Prism.BackfillPageTypes.run(["--account-id", "123"])

  # Verify all have page_type now
  unclassified = Repo.all(
    from m in UrlMetadata,
    where: m.account_id == 123 and is_nil(m.page_type)
  )

  assert length(unclassified) == 0
end
```

## Success Metrics

- ✓ 100% of URLs have `page_type` after backfill
- ✓ Manual values not overwritten
- ✓ Backfill completes in <10 minutes for 100k URLs

## Related Files

- `05-upsert-helper-module.md` - Uses backfill helper
- `10-classifier-directory-patterns.md` - Will enhance classifier first
