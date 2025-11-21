defmodule GscAnalytics.QueryParamsTest do
  use ExUnit.Case, async: true

  alias GscAnalytics.QueryParams

  doctest QueryParams

  # ============================================================================
  # LIMIT NORMALIZATION TESTS
  # ============================================================================

  describe "normalize_limit/2" do
    test "returns default for nil" do
      assert QueryParams.normalize_limit(nil) == 100
    end

    test "accepts custom default via options" do
      assert QueryParams.normalize_limit(nil, default: 50) == 50
    end

    test "parses valid string integers" do
      assert QueryParams.normalize_limit("50") == 50
      assert QueryParams.normalize_limit("100") == 100
      assert QueryParams.normalize_limit("1") == 1
    end

    test "returns default for invalid string" do
      assert QueryParams.normalize_limit("invalid") == 100
      assert QueryParams.normalize_limit("") == 100
      assert QueryParams.normalize_limit("12abc") == 100
      assert QueryParams.normalize_limit("abc123") == 100
    end

    test "clamps integer values to max limit" do
      assert QueryParams.normalize_limit(5000) == 1000
      assert QueryParams.normalize_limit(9999) == 1000
      assert QueryParams.normalize_limit("5000") == 1000
    end

    test "accepts custom max via options" do
      assert QueryParams.normalize_limit(500, max: 250) == 250
      assert QueryParams.normalize_limit("500", max: 250) == 250
    end

    test "clamps integer values to min limit" do
      assert QueryParams.normalize_limit(0) == 100
      assert QueryParams.normalize_limit(-5) == 100
      assert QueryParams.normalize_limit("-10") == 100
    end

    test "accepts custom min via options" do
      # Note: When value is <= 0, it falls through to default
      # But we can test with positive values
      assert QueryParams.normalize_limit(5, min: 10) == 10
    end

    test "accepts valid integer within bounds" do
      assert QueryParams.normalize_limit(50) == 50
      assert QueryParams.normalize_limit(250) == 250
      assert QueryParams.normalize_limit(1000) == 1000
      assert QueryParams.normalize_limit(1) == 1
    end

    test "handles edge cases" do
      assert QueryParams.normalize_limit(%{}) == 100
      assert QueryParams.normalize_limit([]) == 100
      assert QueryParams.normalize_limit(:atom) == 100
      assert QueryParams.normalize_limit({1, 2}) == 100
    end

    test "string with whitespace returns default" do
      assert QueryParams.normalize_limit("  50  ") == 100
      assert QueryParams.normalize_limit(" ") == 100
    end

    test "float values are not integers, return default" do
      assert QueryParams.normalize_limit(50.5) == 100
      assert QueryParams.normalize_limit(99.9) == 100
    end
  end

  # ============================================================================
  # PAGE NORMALIZATION TESTS
  # ============================================================================

  describe "normalize_page/1" do
    test "returns 1 for nil" do
      assert QueryParams.normalize_page(nil) == 1
    end

    test "parses valid string integers" do
      assert QueryParams.normalize_page("1") == 1
      assert QueryParams.normalize_page("5") == 5
      assert QueryParams.normalize_page("100") == 100
      assert QueryParams.normalize_page("9999") == 9999
    end

    test "returns 1 for invalid string" do
      assert QueryParams.normalize_page("invalid") == 1
      assert QueryParams.normalize_page("") == 1
      assert QueryParams.normalize_page("12abc") == 1
      assert QueryParams.normalize_page("abc123") == 1
    end

    test "rejects zero and negative integers" do
      assert QueryParams.normalize_page(0) == 1
      assert QueryParams.normalize_page(-1) == 1
      assert QueryParams.normalize_page(-100) == 1
      assert QueryParams.normalize_page("0") == 1
      assert QueryParams.normalize_page("-5") == 1
    end

    test "accepts valid positive integers" do
      assert QueryParams.normalize_page(1) == 1
      assert QueryParams.normalize_page(10) == 10
      assert QueryParams.normalize_page(999) == 999
    end

    test "handles edge cases" do
      assert QueryParams.normalize_page(%{}) == 1
      assert QueryParams.normalize_page([]) == 1
      assert QueryParams.normalize_page(:atom) == 1
      assert QueryParams.normalize_page({1, 2}) == 1
    end

    test "string with whitespace returns 1" do
      assert QueryParams.normalize_page("  5  ") == 1
      assert QueryParams.normalize_page(" ") == 1
    end

    test "float values return 1" do
      assert QueryParams.normalize_page(5.5) == 1
      assert QueryParams.normalize_page(9.9) == 1
    end
  end

  # ============================================================================
  # SORT DIRECTION NORMALIZATION TESTS
  # ============================================================================

  describe "normalize_sort_direction/1" do
    test "returns :desc for nil" do
      assert QueryParams.normalize_sort_direction(nil) == :desc
    end

    test "normalizes string 'asc' to :asc" do
      assert QueryParams.normalize_sort_direction("asc") == :asc
    end

    test "passes through atom :asc" do
      assert QueryParams.normalize_sort_direction(:asc) == :asc
    end

    test "normalizes string 'desc' to :desc" do
      assert QueryParams.normalize_sort_direction("desc") == :desc
    end

    test "passes through atom :desc" do
      assert QueryParams.normalize_sort_direction(:desc) == :desc
    end

    test "returns :desc for invalid strings" do
      assert QueryParams.normalize_sort_direction("invalid") == :desc
      assert QueryParams.normalize_sort_direction("") == :desc
      assert QueryParams.normalize_sort_direction("ASC") == :desc
      assert QueryParams.normalize_sort_direction("DESC") == :desc
      assert QueryParams.normalize_sort_direction("ascending") == :desc
    end

    test "returns :desc for invalid atoms" do
      assert QueryParams.normalize_sort_direction(:invalid) == :desc
      assert QueryParams.normalize_sort_direction(:ascending) == :desc
      assert QueryParams.normalize_sort_direction(:descending) == :desc
    end

    test "handles edge cases" do
      assert QueryParams.normalize_sort_direction(%{}) == :desc
      assert QueryParams.normalize_sort_direction([]) == :desc
      assert QueryParams.normalize_sort_direction(123) == :desc
      assert QueryParams.normalize_sort_direction({:asc}) == :desc
    end
  end

  # ============================================================================
  # CONFIGURATION ACCESS TESTS
  # ============================================================================

  describe "configuration accessors" do
    test "default_limit/0 returns expected value" do
      assert QueryParams.default_limit() == 100
    end

    test "default_page/0 returns expected value" do
      assert QueryParams.default_page() == 1
    end

    test "default_sort_direction/0 returns expected value" do
      assert QueryParams.default_sort_direction() == :desc
    end

    test "max_limit/0 returns expected value" do
      assert QueryParams.max_limit() == 1000
    end
  end

  # ============================================================================
  # INTEGRATION TESTS - COMMON USAGE PATTERNS
  # ============================================================================

  describe "integration - typical LiveView param parsing" do
    test "parses params from LiveView handle_params/3" do
      # Simulate LiveView params (all strings or nil)
      params = %{
        "page" => "2",
        "limit" => "50",
        "sort_direction" => "asc"
      }

      assert QueryParams.normalize_page(params["page"]) == 2
      assert QueryParams.normalize_limit(params["limit"]) == 50
      assert QueryParams.normalize_sort_direction(params["sort_direction"]) == :asc
    end

    test "handles missing params gracefully" do
      # Simulate LiveView with no query params
      params = %{}

      assert QueryParams.normalize_page(params["page"]) == 1
      assert QueryParams.normalize_limit(params["limit"]) == 100
      assert QueryParams.normalize_sort_direction(params["sort_direction"]) == :desc
    end

    test "handles malicious or malformed params" do
      # Simulate user tampering with URL
      params = %{
        "page" => "<script>alert('xss')</script>",
        "limit" => "<script>alert('xss')</script>",
        "sort_direction" => "; DROP TABLE users; --"
      }

      # All should fall back to safe defaults
      assert QueryParams.normalize_page(params["page"]) == 1
      assert QueryParams.normalize_limit(params["limit"]) == 100
      assert QueryParams.normalize_sort_direction(params["sort_direction"]) == :desc
    end

    test "handles very large integers gracefully" do
      # Very large integer strings parse successfully - they're valid integers
      # Page accepts them (no upper bound)
      assert QueryParams.normalize_page("999999999999999999999999") ==
               999_999_999_999_999_999_999_999

      # Limit clamps to max
      assert QueryParams.normalize_limit("999999999999999999999999") == 1000
    end

    test "handles params from Ecto query composition" do
      # When building queries with normalized params
      opts = %{
        limit: QueryParams.normalize_limit("50"),
        page: QueryParams.normalize_page("2"),
        direction: QueryParams.normalize_sort_direction("asc")
      }

      assert opts.limit == 50
      assert opts.page == 2
      assert opts.direction == :asc
    end
  end

  # ============================================================================
  # PROPERTY-BASED TESTS (EDGE CASE COVERAGE)
  # ============================================================================

  describe "property-based guarantees" do
    test "normalize_limit always returns positive integer within bounds" do
      # Test with random inputs
      random_inputs = [
        nil,
        "0",
        "-100",
        "9999999",
        "",
        "abc",
        %{},
        [],
        :atom,
        1.5,
        -50,
        0,
        5000
      ]

      for input <- random_inputs do
        result = QueryParams.normalize_limit(input)
        assert is_integer(result), "Expected integer, got: #{inspect(result)}"
        assert result > 0, "Expected positive, got: #{result}"
        assert result <= 1000, "Expected <= 1000, got: #{result}"
        assert result >= 1, "Expected >= 1, got: #{result}"
      end
    end

    test "normalize_page always returns positive integer" do
      # Test with random inputs
      random_inputs = [
        nil,
        "0",
        "-100",
        "999999",
        "",
        "abc",
        %{},
        [],
        :atom,
        1.5,
        -50,
        0
      ]

      for input <- random_inputs do
        result = QueryParams.normalize_page(input)
        assert is_integer(result), "Expected integer, got: #{inspect(result)}"
        assert result > 0, "Expected positive, got: #{result}"
      end
    end

    test "normalize_sort_direction always returns :asc or :desc" do
      # Test with random inputs
      random_inputs = [
        nil,
        "asc",
        "desc",
        :asc,
        :desc,
        "ASC",
        "DESC",
        "",
        "invalid",
        %{},
        [],
        123,
        :atom
      ]

      for input <- random_inputs do
        result = QueryParams.normalize_sort_direction(input)
        assert result in [:asc, :desc], "Expected :asc or :desc, got: #{inspect(result)}"
      end
    end
  end
end
