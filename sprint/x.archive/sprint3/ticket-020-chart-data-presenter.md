# Ticket 020 — Centralize Presentation Logic with ChartDataPresenter

**Status**: 📋 Pending
**Estimate**: 3h
**Actual**: TBD
**Priority**: 🟡 Medium
**Dependencies**: #018 (TimeSeriesData), #019a (Database aggregation)

## Problem

Our presentation layer has significant code duplication and scattered concerns:

1. **Duplicate JSON encoding**: Identical `encode_time_series_json/1` functions in both `DashboardLive` and `DashboardUrlLive`
2. **Duplicate event encoding**: `encode_events_json/1` also duplicated
3. **LiveView responsibilities blur**: LiveViews shouldn't handle data serialization - that's presentation logic
4. **Hard to maintain**: Changes to JSON format require updates in multiple files
5. **No single source of truth**: Each LiveView could theoretically encode differently

### Current Duplication

Found in `/lib/gsc_analytics_web/live/dashboard_live.ex:356-374`:
```elixir
defp encode_time_series_json(series) do
  series
  |> Enum.map(fn ts ->
    base = %{
      date: Date.to_string(ts.date),
      clicks: ts.clicks,
      impressions: ts.impressions,
      ctr: ts.ctr,
      position: ts.position
    }

    if Map.has_key?(ts, :period_end) and not is_nil(ts.period_end) do
      Map.put(base, :period_end, Date.to_string(ts.period_end))
    else
      base
    end
  end)
  |> JSON.encode!()
end
```

**Identical code** in `/lib/gsc_analytics_web/live/dashboard_url_live.ex:179-197`!

## Proposed Approach

Create a **Presenter** module that centralizes all chart data preparation logic.

### 1. Create ChartDataPresenter Module

Location: `/lib/gsc_analytics_web/presenters/chart_data_presenter.ex`

```elixir
defmodule GscAnalyticsWeb.Presenters.ChartDataPresenter do
  @moduledoc """
  Centralized presentation logic for preparing chart data for frontend consumption.

  Single source of truth for:
  - JSON encoding of time series data
  - Event data preparation
  - Chart configuration and metadata

  Eliminates duplicate encoding logic across LiveViews.
  """

  alias GscAnalytics.Analytics.TimeSeriesData

  @doc """
  Prepare complete chart data package for frontend rendering.

  ## Examples

      iex> ChartDataPresenter.prepare_chart_data(time_series, events)
      %{
        time_series_json: "{...}",
        events_json: "[...]",
        has_data: true,
        data_points: 30
      }
  """
  def prepare_chart_data(time_series, events \\ []) do
    %{
      time_series_json: encode_time_series(time_series),
      events_json: encode_events(events),
      has_data: length(time_series) > 0,
      data_points: length(time_series)
    }
  end

  @doc """
  Encode time series data to JSON string.
  Uses TimeSeriesData.to_json_map/1 for consistent transformation.
  """
  def encode_time_series(series) when is_list(series) do
    series
    |> Enum.map(&TimeSeriesData.to_json_map/1)
    |> JSON.encode!()
  end

  @doc """
  Encode event data to JSON string.
  """
  def encode_events(events) when is_list(events) do
    JSON.encode!(events)
  end
end
```

### 2. Update DashboardLive

**Remove duplicate functions** (lines 356-374):
```elixir
# DELETE THIS
defp encode_time_series_json(series) do
  # ... duplicate code ...
end
```

**Add import and use presenter**:
```elixir
defmodule GscAnalyticsWeb.DashboardLive do
  use GscAnalyticsWeb, :live_view

  alias GscAnalyticsWeb.Presenters.ChartDataPresenter  # ADD THIS

  # ...

  def handle_params(params, uri, socket) do
    # ... fetch data ...

    # REPLACE: |> assign(:site_trends_json, encode_time_series_json(site_trends))
    # WITH:
    {:noreply,
     socket
     |> assign(:site_trends_json, ChartDataPresenter.encode_time_series(site_trends))
     # ... other assigns ...
    }
  end
end
```

### 3. Update DashboardUrlLive

**Remove duplicate functions** (lines 179-201):
```elixir
# DELETE THESE
defp encode_time_series_json(series) do
  # ... duplicate code ...
end

defp encode_events_json(events) do
  # ... duplicate code ...
end
```

**Add import and use presenter**:
```elixir
defmodule GscAnalyticsWeb.DashboardUrlLive do
  use GscAnalyticsWeb, :live_view

  alias GscAnalyticsWeb.Presenters.ChartDataPresenter  # ADD THIS

  # ...

  def handle_params(%{"url" => url} = params, uri, socket) do
    # ... fetch insights ...

    # REPLACE manual encoding
    # WITH:
    enriched_insights =
      sorted_insights
      |> Map.put(:time_series_json,
                 ChartDataPresenter.encode_time_series(sorted_insights.time_series || []))
      |> Map.put(:chart_events_json,
                 ChartDataPresenter.encode_events(sorted_insights.chart_events || []))

    # ... rest of function ...
  end
end
```

### 4. Optional: Batch Preparation

For even cleaner LiveView code:
```elixir
# In handle_params
chart_data = ChartDataPresenter.prepare_chart_data(
  sorted_insights.time_series || [],
  sorted_insights.chart_events || []
)

{:noreply,
 socket
 |> assign(:chart_data, chart_data)
 |> assign(:time_series_json, chart_data.time_series_json)
 |> assign(:events_json, chart_data.events_json)}
```

## Migration Strategy

### Phase 1: Create Presenter
1. Create the new module with all encoding functions
2. Add comprehensive tests
3. No changes to LiveViews yet (coexistence)

### Phase 2: Update DashboardLive
1. Import `ChartDataPresenter`
2. Replace `encode_time_series_json` calls
3. Remove duplicate function
4. Verify chart still renders

### Phase 3: Update DashboardUrlLive
1. Import `ChartDataPresenter`
2. Replace both encoding function calls
3. Remove both duplicate functions
4. Verify URL detail chart still renders

### Phase 4: Cleanup
1. Search codebase for any other encoding calls
2. Update documentation
3. Add presenter to architecture docs

## Rollout Plan & Guardrails
- Reuse LiveView Telemetry instrumentation to time serialization paths (`:chart_data_presenter` span) and alert if >50ms.
- Capture before/after payload snapshots to confirm JSON schema is unchanged; store under `/priv/data_samples/sprint3`.
- Define manual QA checklist covering empty states, anomaly markers, and locale/date formatting (share with QA).
- Remove duplicate encoding helpers from LiveViews in the same PR (no fallback left behind).

## Coordination Checklist
- [ ] Align with frontend/data visualization owners on schema invariants and naming.
- [ ] Communicate new presenter entry point to engineering (standup + Slack doc).
- [ ] Ensure ChartDataPresenter usage documented in #022 deliverable.
- [ ] Pair with #021 owner to confirm presenter output shape compatible with cache serialization.

## Acceptance Criteria

- [ ] `ChartDataPresenter` module created at `/lib/gsc_analytics_web/presenters/chart_data_presenter.ex`
- [ ] `prepare_chart_data/2` function provides complete data package
- [ ] `encode_time_series/1` uses `TimeSeriesData.to_json_map/1`
- [ ] `encode_events/1` handles event serialization
- [ ] `DashboardLive` uses presenter (duplicate function removed)
- [ ] `DashboardUrlLive` uses presenter (both duplicate functions removed)
- [ ] All tests pass (mix test)
- [ ] Manual QA: Main dashboard chart renders correctly
- [ ] Manual QA: URL detail chart renders correctly (daily/weekly/monthly)
- [ ] No duplicate `encode_*` functions remain in LiveViews
- [ ] Module fully documented with examples
- [ ] Telemetry added (or documented) for serialization timing with 50ms alert threshold
- [ ] Payload snapshot comparison stored for regression history
- [ ] Legacy encoding functions deleted; LiveViews rely solely on presenter

## Test Plan

Create `/test/gsc_analytics_web/presenters/chart_data_presenter_test.exs`:

```elixir
defmodule GscAnalyticsWeb.Presenters.ChartDataPresenterTest do
  use GscAnalytics.DataCase

  alias GscAnalytics.Analytics.TimeSeriesData
  alias GscAnalyticsWeb.Presenters.ChartDataPresenter

  describe "prepare_chart_data/2" do
    test "returns complete data package" do
      time_series = [
        %TimeSeriesData{
          date: ~D[2025-01-15],
          clicks: 100,
          impressions: 1000,
          ctr: 0.1,
          position: 5.0,
          period_end: nil
        }
      ]

      result = ChartDataPresenter.prepare_chart_data(time_series, [])

      assert is_binary(result.time_series_json)
      assert is_binary(result.events_json)
      assert result.has_data == true
      assert result.data_points == 1
    end

    test "indicates when no data present" do
      result = ChartDataPresenter.prepare_chart_data([], [])

      assert result.has_data == false
      assert result.data_points == 0
    end
  end

  describe "encode_time_series/1" do
    test "encodes TimeSeriesData to JSON string" do
      time_series = [
        %TimeSeriesData{
          date: ~D[2025-01-15],
          clicks: 100,
          impressions: 1000,
          ctr: 0.1,
          position: 5.0,
          period_end: nil
        }
      ]

      result = ChartDataPresenter.encode_time_series(time_series)

      assert is_binary(result)
      decoded = JSON.decode!(result)
      assert is_list(decoded)
      assert length(decoded) == 1
      assert List.first(decoded)["date"] == "2025-01-15"
    end

    test "includes period_end when present" do
      time_series = [
        %TimeSeriesData{
          date: ~D[2025-01-08],
          period_end: ~D[2025-01-14],
          clicks: 500,
          impressions: 5000,
          ctr: 0.1,
          position: 6.0
        }
      ]

      result = ChartDataPresenter.encode_time_series(time_series)
      decoded = JSON.decode!(result)

      assert List.first(decoded)["period_end"] == "2025-01-14"
    end
  end

  describe "encode_events/1" do
    test "encodes event list to JSON string" do
      events = [
        %{type: "url_changes", date: ~D[2025-01-15], count: 5}
      ]

      result = ChartDataPresenter.encode_events(events)

      assert is_binary(result)
      decoded = JSON.decode!(result)
      assert is_list(decoded)
    end
  end
end
```

### Regression Tests
- Verify Telemetry event fires (use `assert_receive` on test handler) when encoding large payload.

## Estimate

**3 hours total**
- 1h: Create presenter module and tests
- 1h: Update DashboardLive and verify
- 0.5h: Update DashboardUrlLive and verify
- 0.5h: Documentation and final QA

## Rollback Plan

If issues arise:
1. Revert LiveView changes
2. Keep presenter module (it's harmless if unused)
3. Restore duplicate functions temporarily
4. Diagnose issue before proceeding

## Success Metrics

- Code reduction: ~40 lines of duplicate code eliminated
- Single source of truth for chart data encoding
- All charts render correctly (manual QA)
- Tests pass with no regressions
- Cleaner LiveView code (presentation logic extracted)
