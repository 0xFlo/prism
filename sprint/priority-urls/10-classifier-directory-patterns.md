---
ticket_id: "10"
title: "Extend PageTypeClassifier with Therapist Directory Patterns"
status: pending
priority: P2
milestone: 4
estimate_days: 3
dependencies: []
blocks: ["11", "12"]
success_metrics:
  - "New classifier atoms added: :directory, :profile, :location"
  - "Therapist URL patterns recognized correctly"
  - "Classifier accuracy >90% on test URLs"
  - "No regression on existing classifications"
---

# Ticket 10: Extend PageTypeClassifier with Therapist Directory Patterns

## Context

Extend `PageTypeClassifier` to recognize therapist directory URL patterns: therapist profiles (`/therapist/john-smith`), directory list pages (`/therapists`), and location pages (`/therapy/locations/california`). This enables accurate page type classification for Rula's directory structure.

## Acceptance Criteria

1. ✅ Add new classifier atoms: `:directory`, `:profile`, `:location`
2. ✅ Recognize URL patterns: `/therapists/`, `/providers/`, `/therapy/locations/`
3. ✅ Distinguish profiles from list pages (slug pattern matching)
4. ✅ Add account-specific configuration (Rula only, don't affect other clients)
5. ✅ Update classifier tests with new patterns
6. ✅ Validate accuracy on sample Rula URLs
7. ✅ Ensure backward compatibility for existing page types

## Technical Specifications

```elixir
defmodule GscAnalytics.ContentInsights.PageTypeClassifier do
  def classify(url, opts \\ []) do
    account_id = Keyword.get(opts, :account_id)
    uri = URI.parse(url)

    cond do
      therapist_directory?(uri, account_id) -> :directory
      therapist_profile?(uri, account_id) -> :profile
      location_page?(uri, account_id) -> :location
      # ... existing patterns
      true -> :other
    end
  end

  defp therapist_directory?(uri, account_id) do
    rula_account?(account_id) and
      uri.path =~ ~r{^/(therapists|providers)/?$}
  end

  defp therapist_profile?(uri, account_id) do
    rula_account?(account_id) and
      uri.path =~ ~r{^/(therapist|provider)/[\w-]+$}
  end

  defp location_page?(uri, account_id) do
    rula_account?(account_id) and
      uri.path =~ ~r{^/therapy/locations/[\w-/]+$}
  end

  defp rula_account?(account_id) do
    # Check if account is Rula (avoid affecting other clients)
    account_id == Application.get_env(:gsc_analytics, :rula_account_id)
  end
end
```

## Testing Requirements

```elixir
test "classifies therapist profiles correctly" do
  url = "https://www.rula.com/therapist/john-smith-lmft"
  assert PageTypeClassifier.classify(url, account_id: rula_id) == :profile
end

test "classifies directory list pages" do
  url = "https://www.rula.com/therapists"
  assert PageTypeClassifier.classify(url, account_id: rula_id) == :directory
end

test "classifies location pages" do
  url = "https://www.rula.com/therapy/locations/california/san-francisco"
  assert PageTypeClassifier.classify(url, account_id: rula_id) == :location
end

test "does not affect other clients" do
  url = "https://example.com/therapists"
  assert PageTypeClassifier.classify(url, account_id: other_id) != :directory
end
```

## Success Metrics

- ✓ >90% accuracy on 1000 sample Rula URLs
- ✓ 0 regressions on existing client classifications
- ✓ Rula-specific rules don't affect other accounts

## Related Files

- `06-backfill-metadata-classifier.md` - Will use enhanced classifier
- `11-sync-elixir-sql-classification.md` - Needs same logic
- `12-classifier-regression-tests.md` - Comprehensive test coverage
