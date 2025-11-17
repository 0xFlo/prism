---
ticket_id: "12"
title: "Add Comprehensive Classifier Regression Tests"
status: pending
priority: P3
milestone: 4
estimate_days: 2
dependencies: ["10", "11"]
blocks: []
success_metrics:
  - "Test coverage >95% for PageTypeClassifier"
  - "All new patterns have test cases"
  - "Edge cases documented and tested"
  - "Regression test suite runs in CI"
---

# Ticket 12: Add Comprehensive Classifier Regression Tests

## Context

With new therapist directory patterns (Ticket 10), add comprehensive regression tests to ensure classifier accuracy and prevent future regressions. Test both positive matches (correct classifications) and negative cases (should not match).

## Acceptance Criteria

1. ✅ Create test fixture with 100+ sample URLs
2. ✅ Test all new patterns: directory, profile, location
3. ✅ Test edge cases: trailing slashes, query params, uppercase
4. ✅ Test account-specific rules (Rula vs other clients)
5. ✅ Test backward compatibility (existing patterns still work)
6. ✅ Property-based tests for URL normalization
7. ✅ Performance tests (classify 1000 URLs in <1s)
8. ✅ Document expected classifications

## Testing Requirements

```elixir
defmodule GscAnalytics.ContentInsights.PageTypeClassifierTest do
  use GscAnalytics.DataCase

  @therapist_profiles [
    "https://www.rula.com/therapist/john-smith-lmft",
    "https://www.rula.com/therapist/jane-doe-phd",
    "https://www.rula.com/provider/sarah-johnson-lcsw"
  ]

  @directory_pages [
    "https://www.rula.com/therapists",
    "https://www.rula.com/therapists/",
    "https://www.rula.com/providers"
  ]

  @location_pages [
    "https://www.rula.com/therapy/locations/california",
    "https://www.rula.com/therapy/locations/california/san-francisco"
  ]

  describe "therapist directory classification" do
    test "classifies profiles correctly" do
      for url <- @therapist_profiles do
        assert PageTypeClassifier.classify(url, account_id: rula_id()) == :profile
      end
    end

    test "classifies directory pages correctly" do
      for url <- @directory_pages do
        assert PageTypeClassifier.classify(url, account_id: rula_id()) == :directory
      end
    end

    test "classifies location pages correctly" do
      for url <- @location_pages do
        assert PageTypeClassifier.classify(url, account_id: rula_id()) == :location
      end
    end
  end

  describe "edge cases" do
    test "handles query parameters" do
      url = "https://www.rula.com/therapist/john-smith?ref=google"
      assert PageTypeClassifier.classify(url, account_id: rula_id()) == :profile
    end

    test "handles uppercase in path" do
      url = "https://www.rula.com/Therapist/John-Smith"
      # Should normalize to lowercase and still match
      assert PageTypeClassifier.classify(url, account_id: rula_id()) == :profile
    end
  end

  describe "account specificity" do
    test "Rula patterns only apply to Rula account" do
      url = "https://example.com/therapists"
      assert PageTypeClassifier.classify(url, account_id: other_id()) != :directory
    end
  end

  describe "performance" do
    test "classifies 1000 URLs in under 1 second" do
      urls = generate_test_urls(1000)

      {time_microseconds, _results} = :timer.tc(fn ->
        Enum.map(urls, &PageTypeClassifier.classify/1)
      end)

      time_seconds = time_microseconds / 1_000_000
      assert time_seconds < 1.0
    end
  end
end
```

## Success Metrics

- ✓ >95% test coverage for classifier module
- ✓ All edge cases have test coverage
- ✓ Performance benchmarks pass
- ✓ CI runs tests on every PR

## Related Files

- `10-classifier-directory-patterns.md` - Patterns being tested
- `06-backfill-metadata-classifier.md` - Uses classifier in production
