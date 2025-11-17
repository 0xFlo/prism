---
ticket_id: "07"
title: "Update UrlPerformance Query with Metadata Joins"
status: pending
priority: P1
milestone: 3
estimate_days: 3
dependencies: ["04"]
blocks: ["08", "09"]
success_metrics:
  - "LEFT JOIN to gsc_url_metadata added to build_hybrid_query/4"
  - "Metadata columns (update_priority, page_type, content_category) selected"
  - "Query performance <250ms with indexes"
  - "enrich_urls/4 merges metadata attributes correctly"
---

# Ticket 07: Update UrlPerformance Query with Metadata Joins

## Context

Modify `ContentInsights.UrlPerformance.build_hybrid_query/4` to LEFT JOIN the `gsc_url_metadata` table and select priority tier, page type, and other metadata fields. This makes stored metadata available to dashboard queries and LiveView components.

## Acceptance Criteria

1. ✅ Add LEFT JOIN to `gsc_url_metadata` table
2. ✅ Join on `account_id` and `url` columns
3. ✅ Select metadata fields: `update_priority`, `page_type`, `content_category`, `metadata_source`
4. ✅ Update `enrich_urls/4` to merge metadata into result structs
5. ✅ Preserve existing `needs_update` logic
6. ✅ Ensure query plan uses indexes (validate with EXPLAIN)
7. ✅ Add integration tests for metadata-enriched queries
8. ✅ Handle NULL metadata gracefully (URLs without priority data)

## Technical Specifications

### Updated Query Builder

```elixir
defmodule GscAnalytics.ContentInsights.UrlPerformance do
  def build_hybrid_query(account_id, date_range, filters \\ [], opts \\ []) do
    from(u in "gsc_url_performance",
      as: :url_perf,
      join: m in "gsc_url_metadata",
      as: :metadata,
      on: m.account_id == u.account_id and m.url == u.url,
      # Make it a LEFT JOIN so URLs without metadata still appear
      where: u.account_id == ^account_id,
      where: u.date >= ^date_range.start_date and u.date <= ^date_range.end_date,
      select: %{
        url: u.url,
        clicks: u.clicks,
        impressions: u.impressions,
        # Metadata fields
        update_priority: m.update_priority,
        page_type: m.page_type,
        content_category: m.content_category,
        metadata_source: m.metadata_source
      }
    )
    |> apply_filters(filters)
  end

  def enrich_urls(urls, metadata_map, needs_update_urls, opts \\ []) do
    Enum.map(urls, fn url_data ->
      # Merge metadata from JOIN
      url_data
      |> Map.put(:needs_update, MapSet.member?(needs_update_urls, url_data.url))
      |> merge_metadata()
    end)
  end

  defp merge_metadata(url_data) do
    # Metadata already in url_data from SELECT
    # Just ensure defaults for NULL values
    url_data
    |> Map.put_new(:update_priority, nil)
    |> Map.put_new(:page_type, nil)
    |> Map.put_new(:content_category, nil)
  end
end
```

## Testing Requirements

```elixir
test "joins metadata and selects priority fields" do
  account_id = 123

  # Create URL with metadata
  insert(:url_metadata,
    account_id: account_id,
    url: "https://example.com/path",
    update_priority: "P1",
    page_type: "profile"
  )

  # Insert performance data
  insert(:url_performance,
    account_id: account_id,
    url: "https://example.com/path",
    clicks: 100
  )

  query = UrlPerformance.build_hybrid_query(account_id, date_range)
  results = Repo.all(query)

  assert length(results) == 1
  assert hd(results).update_priority == "P1"
  assert hd(results).page_type == "profile"
end

test "handles URLs without metadata gracefully" do
  # URL performance without metadata record
  insert(:url_performance, account_id: 123, url: "https://example.com/new")

  query = UrlPerformance.build_hybrid_query(123, date_range)
  results = Repo.all(query)

  # Should still return URL with NULL metadata
  assert length(results) == 1
  assert hd(results).update_priority == nil
end
```

## Success Metrics

- ✓ Metadata fields available in dashboard queries
- ✓ Query performance <250ms (with indexes)
- ✓ LEFT JOIN allows URLs without metadata
- ✓ All tests pass

## Related Files

- `04-database-migration-metadata.md` - Provides metadata table and indexes
- `08-filters-stored-metadata.md` - Will use metadata in filters
- `09-liveview-ui-badges.md` - Will display metadata in UI
