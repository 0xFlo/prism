defmodule GscAnalytics.Analytics.TimeSeriesDataTest do
  use GscAnalytics.DataCase, async: true

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

    test "preserves all metric fields correctly" do
      raw = [
        %{date: ~D[2025-01-15], clicks: 100, impressions: 1000, ctr: 0.1, position: 5.5}
      ]

      [result] = TimeSeriesData.from_raw_data(raw)

      assert result.date == ~D[2025-01-15]
      assert result.clicks == 100
      assert result.impressions == 1000
      assert result.ctr == 0.1
      assert result.position == 5.5
      assert result.period_end == nil
    end

    test "handles period_end field when present" do
      raw = [
        %{
          date: ~D[2025-01-08],
          period_end: ~D[2025-01-14],
          clicks: 500,
          impressions: 5000,
          ctr: 0.1,
          position: 6.0
        }
      ]

      [result] = TimeSeriesData.from_raw_data(raw)

      assert result.date == ~D[2025-01-08]
      assert result.period_end == ~D[2025-01-14]
    end

    test "handles empty list" do
      result = TimeSeriesData.from_raw_data([])

      assert result == []
    end

    test "emits telemetry event" do
      test_pid = self()

      :telemetry.attach(
        "test-time-series-data",
        [:gsc_analytics, :time_series_data, :from_raw_data],
        fn event_name, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event_name, measurements, metadata})
        end,
        nil
      )

      raw = [
        %{date: ~D[2025-01-15], clicks: 100, impressions: 1000, ctr: 0.1, position: 5.5},
        %{date: ~D[2025-01-14], clicks: 90, impressions: 900, ctr: 0.1, position: 6.0}
      ]

      TimeSeriesData.from_raw_data(raw)

      assert_receive {:telemetry_event, [:gsc_analytics, :time_series_data, :from_raw_data],
                      measurements, _metadata}

      assert measurements.count == 2
      assert is_number(measurements.duration_ms)
      assert measurements.duration_ms >= 0

      :telemetry.detach("test-time-series-data")
    end
  end

  describe "sort_chronologically/1" do
    test "sorts TimeSeriesData structs by date" do
      unsorted = [
        %TimeSeriesData{
          date: ~D[2025-01-15],
          clicks: 100,
          impressions: 1000,
          ctr: 0.1,
          position: 5.5,
          period_end: nil
        },
        %TimeSeriesData{
          date: ~D[2025-01-14],
          clicks: 90,
          impressions: 900,
          ctr: 0.1,
          position: 6.0,
          period_end: nil
        },
        %TimeSeriesData{
          date: ~D[2025-01-16],
          clicks: 110,
          impressions: 1100,
          ctr: 0.1,
          position: 5.0,
          period_end: nil
        }
      ]

      sorted = TimeSeriesData.sort_chronologically(unsorted)
      dates = Enum.map(sorted, & &1.date)

      assert dates == [~D[2025-01-14], ~D[2025-01-15], ~D[2025-01-16]]
    end

    test "handles already sorted data" do
      already_sorted = [
        %TimeSeriesData{
          date: ~D[2025-01-14],
          clicks: 90,
          impressions: 900,
          ctr: 0.1,
          position: 6.0,
          period_end: nil
        },
        %TimeSeriesData{
          date: ~D[2025-01-15],
          clicks: 100,
          impressions: 1000,
          ctr: 0.1,
          position: 5.5,
          period_end: nil
        }
      ]

      sorted = TimeSeriesData.sort_chronologically(already_sorted)
      dates = Enum.map(sorted, & &1.date)

      assert dates == [~D[2025-01-14], ~D[2025-01-15]]
    end

    test "handles empty list" do
      result = TimeSeriesData.sort_chronologically([])

      assert result == []
    end

    test "handles year boundary correctly" do
      data = [
        %TimeSeriesData{
          date: ~D[2025-01-05],
          clicks: 100,
          impressions: 1000,
          ctr: 0.1,
          position: 5.5,
          period_end: nil
        },
        %TimeSeriesData{
          date: ~D[2024-12-28],
          clicks: 90,
          impressions: 900,
          ctr: 0.1,
          position: 6.0,
          period_end: nil
        },
        %TimeSeriesData{
          date: ~D[2024-12-15],
          clicks: 80,
          impressions: 800,
          ctr: 0.1,
          position: 6.5,
          period_end: nil
        }
      ]

      sorted = TimeSeriesData.sort_chronologically(data)
      dates = Enum.map(sorted, & &1.date)

      assert dates == [~D[2024-12-15], ~D[2024-12-28], ~D[2025-01-05]]
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

    test "converts dates to ISO8601 strings" do
      ts = %TimeSeriesData{
        date: ~D[2025-01-15],
        period_end: ~D[2025-01-21],
        clicks: 100,
        impressions: 1000,
        ctr: 0.1,
        position: 5.5
      }

      result = TimeSeriesData.to_json_map(ts)

      assert is_binary(result.date)
      assert is_binary(result.period_end)
      assert result.date =~ ~r/^\d{4}-\d{2}-\d{2}$/
      assert result.period_end =~ ~r/^\d{4}-\d{2}-\d{2}$/
    end

    test "preserves metric values exactly" do
      ts = %TimeSeriesData{
        date: ~D[2025-01-15],
        clicks: 12345,
        impressions: 678_910,
        ctr: 0.01818,
        position: 4.567,
        period_end: nil
      }

      result = TimeSeriesData.to_json_map(ts)

      assert result.clicks == 12345
      assert result.impressions == 678_910
      assert result.ctr == 0.01818
      assert result.position == 4.567
    end
  end

  describe "normalization" do
    test "raises descriptive error when required keys missing - clicks" do
      assert_raise KeyError, ~r/clicks/, fn ->
        TimeSeriesData.from_raw_data([
          %{date: ~D[2025-01-15], impressions: 1000, ctr: 0.1, position: 5.5}
        ])
      end
    end

    test "raises descriptive error when required keys missing - impressions" do
      assert_raise KeyError, ~r/impressions/, fn ->
        TimeSeriesData.from_raw_data([
          %{date: ~D[2025-01-15], clicks: 100, ctr: 0.1, position: 5.5}
        ])
      end
    end

    test "raises descriptive error when required keys missing - ctr" do
      assert_raise KeyError, ~r/ctr/, fn ->
        TimeSeriesData.from_raw_data([
          %{date: ~D[2025-01-15], clicks: 100, impressions: 1000, position: 5.5}
        ])
      end
    end

    test "raises descriptive error when required keys missing - position" do
      assert_raise KeyError, ~r/position/, fn ->
        TimeSeriesData.from_raw_data([
          %{date: ~D[2025-01-15], clicks: 100, impressions: 1000, ctr: 0.1}
        ])
      end
    end

    test "raises descriptive error when required keys missing - date" do
      assert_raise KeyError, ~r/date/, fn ->
        TimeSeriesData.from_raw_data([
          %{clicks: 100, impressions: 1000, ctr: 0.1, position: 5.5}
        ])
      end
    end

    test "coerces ISO8601 strings into Date structs for date" do
      raw = [
        %{
          date: "2025-01-15",
          clicks: 10,
          impressions: 100,
          ctr: 0.1,
          position: 5.0
        }
      ]

      [result] = TimeSeriesData.from_raw_data(raw)

      assert result.date == ~D[2025-01-15]
    end

    test "coerces ISO8601 strings into Date structs for period_end" do
      raw = [
        %{
          date: "2025-01-15",
          period_end: "2025-01-21",
          clicks: 10,
          impressions: 100,
          ctr: 0.1,
          position: 5.0
        }
      ]

      [result] = TimeSeriesData.from_raw_data(raw)

      assert result.date == ~D[2025-01-15]
      assert result.period_end == ~D[2025-01-21]
    end

    test "handles Date structs directly" do
      raw = [
        %{
          date: ~D[2025-01-15],
          period_end: ~D[2025-01-21],
          clicks: 10,
          impressions: 100,
          ctr: 0.1,
          position: 5.0
        }
      ]

      [result] = TimeSeriesData.from_raw_data(raw)

      assert result.date == ~D[2025-01-15]
      assert result.period_end == ~D[2025-01-21]
    end

    test "handles nil period_end" do
      raw = [
        %{
          date: ~D[2025-01-15],
          period_end: nil,
          clicks: 10,
          impressions: 100,
          ctr: 0.1,
          position: 5.0
        }
      ]

      [result] = TimeSeriesData.from_raw_data(raw)

      assert result.period_end == nil
    end

    test "handles missing period_end (defaults to nil)" do
      raw = [
        %{
          date: ~D[2025-01-15],
          clicks: 10,
          impressions: 100,
          ctr: 0.1,
          position: 5.0
        }
      ]

      [result] = TimeSeriesData.from_raw_data(raw)

      assert result.period_end == nil
    end
  end

  describe "struct enforcement" do
    # Note: @enforce_keys validation happens at compile time, so we can't test
    # the error cases directly. These tests verify that valid structs work correctly.

    test "can create struct with all required fields" do
      ts = %TimeSeriesData{
        date: ~D[2025-01-15],
        clicks: 100,
        impressions: 1000,
        ctr: 0.1,
        position: 5.5
      }

      assert ts.date == ~D[2025-01-15]
      assert ts.period_end == nil
    end

    test "can create struct with optional period_end" do
      ts = %TimeSeriesData{
        date: ~D[2025-01-15],
        period_end: ~D[2025-01-21],
        clicks: 100,
        impressions: 1000,
        ctr: 0.1,
        position: 5.5
      }

      assert ts.period_end == ~D[2025-01-21]
    end
  end
end
