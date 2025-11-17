# Ticket 018 — Create TimeSeriesData Domain Type

**Status**: ✅ Complete
**Estimate**: 3h
**Actual**: 2.5h
**Priority**: 🔥 Critical (Foundation for entire sprint)
**Dependencies**: None

## Problem

Our current time series handling suffers from structural brittleness:

1. **Raw maps without contracts**: Time series data is passed as plain maps with implicit structure assumptions
2. **No type safety**: Functions assume fields like `:date`, `:clicks`, etc. exist but nothing enforces this
3. **Scattered date sorting**: 8 different places manually sorting with `Enum.sort_by(& &1.date, Date)`
4. **Inconsistent transformations**: Each function handles date conversion and optional fields differently
5. **Bug prone**: The recent date sorting bug showed how easy it is to forget the `Date` module

### The Root Cause

Time series data lacks a **domain type** that guarantees:
- Structure (required fields present and correct types)
- Ordering (chronologically sorted by default)
- Consistency (standardized transformations)

## Proposed Approach

Create a `TimeSeriesData` module that serves as the single source of truth for time series structure and behavior.

### 1. Define the Struct

```elixir
defmodule GscAnalytics.Analytics.TimeSeriesData do
  @moduledoc """
  Domain type for time series data with guaranteed sorting and structure.
  Prevents the entire class of bugs related to incorrect date handling.
  """

  @enforce_keys [:date, :clicks, :impressions, :ctr, :position]
  defstruct [
    :date,           # Date.t() - required
    :period_end,     # Date.t() | nil - for weekly/monthly aggregations
    :clicks,         # integer() - required
    :impressions,    # integer() - required
    :ctr,           # float() - required
    :position       # float() - required
  ]

  @type t :: %__MODULE__{
    date: Date.t(),
    period_end: Date.t() | nil,
    clicks: integer(),
    impressions: integer(),
    ctr: float(),
    position: float()
  }
end
```

### 2. Core Behaviors

```elixir
  @doc """
  Convert raw data to structured time series, ensuring proper sorting.
  Single point of entry for creating time series data.
  """
  def from_raw_data(data) when is_list(data) do
    data
    |> Enum.map(&to_struct/1)
    |> sort_chronologically()
  end

  @doc """
  Normalize external payloads into the domain struct.
  Centralizes validation of required keys and date coercion.
  """
  defp to_struct(%{} = attrs) do
    %__MODULE__{
      date: attrs |> Map.fetch!(:date) |> normalize_to_date!(),
      period_end: attrs |> Map.get(:period_end) |> normalize_optional_date(),
      clicks: attrs |> Map.fetch!(:clicks),
      impressions: attrs |> Map.fetch!(:impressions),
      ctr: attrs |> Map.fetch!(:ctr),
      position: attrs |> Map.fetch!(:position)
    }
  end

  defp normalize_to_date!(%Date{} = date), do: date
  defp normalize_to_date!(date) when is_binary(date), do: Date.from_iso8601!(date)

  defp normalize_optional_date(nil), do: nil
  defp normalize_optional_date(%Date{} = date), do: date
  defp normalize_optional_date(date) when is_binary(date), do: Date.from_iso8601!(date)

  @doc """
  Always sort chronologically using Date module.
  Replaces all 8 scattered sorting calls across the codebase.
  """
  def sort_chronologically(series) when is_list(series) do
    Enum.sort_by(series, & &1.date, Date)
  end

  @doc """
  Convert to JSON-ready map for frontend consumption.
  Single source of truth for time series serialization.
  """
  def to_json_map(%__MODULE__{} = ts) do
    base = %{
      date: Date.to_string(ts.date),
      clicks: ts.clicks,
      impressions: ts.impressions,
      ctr: ts.ctr,
      position: ts.position
    }

    if ts.period_end do
      Map.put(base, :period_end, Date.to_string(ts.period_end))
    else
      base
    end
  end
```

### 3. Migration Strategy

**Phase 1**: Create module, add tests
**Phase 2**: Update `TimeSeriesAggregator` to return `TimeSeriesData` structs (Ticket #019a)
**Phase 3**: Update presentation layer to use `to_json_map/1` (Ticket #020)

### 4. Implementation Steps

1. Scaffold module + struct with `@enforce_keys`, helper functions (`normalize_to_date!/1`, `normalize_optional_date/1`, `to_struct/1`).
2. Add doctests + unit tests covering ordering guarantees, optional `period_end`, and error messaging for missing keys.
3. Emit Telemetry span for `from_raw_data/1` (`[:gsc_analytics, :time_series_data, :from_raw_data]`) to track downstream latency.
4. Refactor fixtures/tests to construct structs via `from_raw_data/1` (avoid bare struct creation) to catch regressions early.
5. Align with #019a owner on migration path (parallel functions returning both map + struct if needed).
6. Draft contract/migration note for inclusion in #022 documentation update.

### 5. Coordination Checklist
- [ ] Confirm with frontend that `to_json_map/1` keys/format remain backward compatible.
- [ ] Notify Data Ops of stricter validation (missing metrics will now raise).
- [ ] Update architecture decision log with domain type rationale + guardrails.
- [ ] Schedule code review with secondary engineer due to cross-cutting impact.

## Acceptance Criteria

- [ ] `TimeSeriesData` module created at `/lib/gsc_analytics/analytics/time_series_data.ex`
- [ ] Struct defined with `@enforce_keys` for required fields
- [ ] Typespec `@type t` documents expected structure
- [ ] `from_raw_data/1` function converts maps to structs and sorts
- [ ] Normalization helper(s) enforce required keys and convert dates safely
- [ ] `sort_chronologically/1` function handles sorting with Date module
- [ ] `to_json_map/1` function handles serialization consistently
- [ ] Comprehensive test coverage (see test plan below)
- [ ] Module documented with @moduledoc and @doc for all public functions
- [ ] No impact on existing code (module exists but not yet integrated)
- [ ] Telemetry event emitted for `from_raw_data/1`

## Test Plan

Create `/test/gsc_analytics/analytics/time_series_data_test.exs`:

```elixir
defmodule GscAnalytics.Analytics.TimeSeriesDataTest do
  use GscAnalytics.DataCase
  alias GscAnalytics.Analytics.TimeSeriesData

  describe "from_raw_data/1" do
    test "converts raw maps to TimeSeriesData structs" do
      raw = [
        %{date: ~D[2025-01-15], clicks: 100, impressions: 1000, ctr: 0.1, position: 5.5},
        %{date: ~D[2025-01-14], clicks: 90, impressions: 900, ctr: 0.1, position: 6.0}
      ]

      result = TimeSeriesData.from_raw_data(raw)

      assert [%TimeSeriesData{}, %TimeSeriesData{}] = result
      assert length(result) == 2
    end

    test "automatically sorts data chronologically" do
      raw = [
        %{date: ~D[2025-01-15], clicks: 100, impressions: 1000, ctr: 0.1, position: 5.5},
        %{date: ~D[2025-01-14], clicks: 90, impressions: 900, ctr: 0.1, position: 6.0},
        %{date: ~D[2025-01-16], clicks: 110, impressions: 1100, ctr: 0.1, position: 5.0}
      ]

      result = TimeSeriesData.from_raw_data(raw)
      dates = Enum.map(result, & &1.date)

      assert dates == [~D[2025-01-14], ~D[2025-01-15], ~D[2025-01-16]]
    end

    test "handles year boundary correctly" do
      raw = [
        %{date: ~D[2025-01-05], clicks: 100, impressions: 1000, ctr: 0.1, position: 5.5},
        %{date: ~D[2024-12-28], clicks: 90, impressions: 900, ctr: 0.1, position: 6.0}
      ]

      result = TimeSeriesData.from_raw_data(raw)
      dates = Enum.map(result, & &1.date)

      # This is the bug we're preventing!
      assert dates == [~D[2024-12-28], ~D[2025-01-05]]
    end
  end

  describe "to_json_map/1" do
    test "converts struct to JSON-serializable map" do
      ts = %TimeSeriesData{
        date: ~D[2025-01-15],
        clicks: 100,
        impressions: 1000,
        ctr: 0.1,
        position: 5.5,
        period_end: nil
      }

      result = TimeSeriesData.to_json_map(ts)

      assert result.date == "2025-01-15"
      assert result.clicks == 100
      assert result.impressions == 1000
      assert result.ctr == 0.1
      assert result.position == 5.5
      refute Map.has_key?(result, :period_end)
    end

    test "includes period_end when present" do
      ts = %TimeSeriesData{
        date: ~D[2025-01-08],
        period_end: ~D[2025-01-14],
        clicks: 500,
        impressions: 5000,
        ctr: 0.1,
        position: 6.0
      }

      result = TimeSeriesData.to_json_map(ts)

      assert result.period_end == "2025-01-14"
    end
  end

  describe "normalization" do
    test "raises descriptive error when required keys missing" do
      assert_raise KeyError, ~r/clicks/, fn ->
        TimeSeriesData.from_raw_data([%{date: ~D[2025-01-15]}])
      end
    end

    test "coerces ISO8601 strings into Date structs" do
      raw = [
        %{
          date: "2025-01-15",
          period_end: "2025-01-15",
          clicks: 10,
          impressions: 100,
          ctr: 0.1,
          position: 5.0
        }
      ]

      [result] = TimeSeriesData.from_raw_data(raw)
      assert result.date == ~D[2025-01-15]
      assert result.period_end == ~D[2025-01-15]
    end
  end
end
```

## Estimate

**3 hours total**
- 1h: Module creation and core functions
- 1h: Comprehensive test suite
- 1h: Documentation and edge case handling

## Rollback Plan

If issues arise:
1. Module exists but is not integrated yet (no risk)
2. Can delete module without impact on existing code
3. No database changes or LiveView modifications

## Success Metrics

- ✅ All tests pass (27/27 tests)
- ✅ Module fully documented
- ✅ No impact on existing functionality (57/57 analytics tests pass)
- ✅ Ready for integration in Ticket #019a

## Implementation Notes

**Completed**: 2025-10-19

### What Was Built

1. **Domain Module** (`lib/gsc_analytics/analytics/time_series_data.ex`):
   - Struct with `@enforce_keys` for required fields (date, clicks, impressions, ctr, position)
   - Optional `period_end` field for weekly/monthly aggregations
   - Comprehensive `@type` specification for Dialyzer
   - `from_raw_data/1` - Single constructor with automatic sorting and validation
   - `sort_chronologically/1` - Centralized sorting logic using Date module
   - `to_json_map/1` - JSON serialization for frontend
   - Telemetry event emission for performance monitoring

2. **Test Suite** (`test/gsc_analytics/analytics/time_series_data_test.exs`):
   - 27 comprehensive tests covering all functionality
   - Tests for struct construction, normalization, and sorting
   - Edge case testing (year boundaries, empty lists, missing fields)
   - Telemetry event verification
   - JSON serialization tests

### Design Decisions

**Best Practices Applied**:
- ✅ `@enforce_keys` for compile-time field enforcement
- ✅ `@type` specification for documentation and static analysis
- ✅ Helper functions for validation (normalize_to_date!, normalize_optional_date)
- ✅ Single constructor pattern (from_raw_data/1) to enforce invariants
- ✅ Immutable struct (natural in Elixir)
- ✅ Telemetry integration for observability

**Year Boundary Bug Fix**:
The module specifically addresses the December 2024/January 2025 sorting bug by using `Enum.sort_by(& &1.date, Date)` consistently. Test coverage includes year boundary scenarios to prevent regressions.

**No Breaking Changes**:
Module exists standalone and does not affect existing code. Integration will happen in subsequent tickets (#019a, #020).

### Verification

```bash
# All new tests pass
mix test test/gsc_analytics/analytics/time_series_data_test.exs
# 27 tests, 0 failures

# All existing analytics tests still pass
mix test test/gsc_analytics/analytics/
# 57 tests, 0 failures (27 new + 30 existing)
```

### Next Steps

Ready for integration in:
- **#019a**: TimeSeriesAggregator to return TimeSeriesData structs
- **#020**: Presentation layer to use to_json_map/1
