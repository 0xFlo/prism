defmodule GscAnalyticsWeb.Presenters.ChartDataPresenterTest do
  use GscAnalytics.DataCase

  alias GscAnalytics.Analytics.TimeSeriesData
  alias GscAnalyticsWeb.Presenters.ChartDataPresenter

  describe "prepare_chart_data/2" do
    test "returns complete data package with data" do
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
      assert result.time_series_json == "[]"
      assert result.events_json == "[]"
    end

    test "includes events when provided" do
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

      events = [%{type: "url_changes", date: ~D[2025-01-15], count: 5}]

      result = ChartDataPresenter.prepare_chart_data(time_series, events)

      decoded_events = JSON.decode!(result.events_json)
      assert length(decoded_events) == 1
    end

    test "counts multiple data points correctly" do
      time_series = [
        %TimeSeriesData{
          date: ~D[2025-01-15],
          clicks: 100,
          impressions: 1000,
          ctr: 0.1,
          position: 5.0,
          period_end: nil
        },
        %TimeSeriesData{
          date: ~D[2025-01-16],
          clicks: 150,
          impressions: 1200,
          ctr: 0.125,
          position: 4.5,
          period_end: nil
        }
      ]

      result = ChartDataPresenter.prepare_chart_data(time_series, [])

      assert result.data_points == 2
      assert result.has_data == true
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

      first = List.first(decoded)
      assert first["date"] == "2025-01-15"
      assert first["clicks"] == 100
      assert first["impressions"] == 1000
      assert first["ctr"] == 0.1
      assert first["position"] == 5.0
    end

    test "includes period_end when present (weekly data)" do
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

      first = List.first(decoded)
      assert first["period_end"] == "2025-01-14"
      assert first["date"] == "2025-01-08"
    end

    test "handles monthly data with period_end" do
      time_series = [
        %TimeSeriesData{
          date: ~D[2025-01-01],
          period_end: ~D[2025-01-31],
          clicks: 5000,
          impressions: 50000,
          ctr: 0.1,
          position: 4.5
        }
      ]

      result = ChartDataPresenter.encode_time_series(time_series)
      decoded = JSON.decode!(result)

      first = List.first(decoded)
      assert first["period_end"] == "2025-01-31"
    end

    test "encodes empty list as empty JSON array" do
      result = ChartDataPresenter.encode_time_series([])

      assert result == "[]"
    end

    test "encodes multiple data points in order" do
      time_series = [
        %TimeSeriesData{
          date: ~D[2025-01-15],
          clicks: 100,
          impressions: 1000,
          ctr: 0.1,
          position: 5.0,
          period_end: nil
        },
        %TimeSeriesData{
          date: ~D[2025-01-16],
          clicks: 150,
          impressions: 1200,
          ctr: 0.125,
          position: 4.5,
          period_end: nil
        },
        %TimeSeriesData{
          date: ~D[2025-01-17],
          clicks: 200,
          impressions: 1500,
          ctr: 0.133,
          position: 4.0,
          period_end: nil
        }
      ]

      result = ChartDataPresenter.encode_time_series(time_series)
      decoded = JSON.decode!(result)

      assert length(decoded) == 3
      assert Enum.at(decoded, 0)["date"] == "2025-01-15"
      assert Enum.at(decoded, 1)["date"] == "2025-01-16"
      assert Enum.at(decoded, 2)["date"] == "2025-01-17"
    end

    test "preserves numeric precision" do
      time_series = [
        %TimeSeriesData{
          date: ~D[2025-01-15],
          clicks: 123,
          impressions: 4567,
          ctr: 0.026935361,
          position: 12.3456789,
          period_end: nil
        }
      ]

      result = ChartDataPresenter.encode_time_series(time_series)
      decoded = JSON.decode!(result)

      first = List.first(decoded)
      assert first["clicks"] == 123
      assert first["impressions"] == 4567
      # Elixir's JSON library may round floats
      assert is_float(first["ctr"])
      assert is_float(first["position"])
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
      assert length(decoded) == 1
    end

    test "encodes empty list as empty JSON array" do
      result = ChartDataPresenter.encode_events([])

      assert result == "[]"
    end

    test "encodes multiple events" do
      events = [
        %{type: "url_changes", date: ~D[2025-01-15], count: 5},
        %{type: "content_update", date: ~D[2025-01-20], description: "Major rewrite"},
        %{type: "algorithm_update", date: ~D[2025-01-25], name: "Core Update"}
      ]

      result = ChartDataPresenter.encode_events(events)
      decoded = JSON.decode!(result)

      assert length(decoded) == 3
    end

    test "preserves event structure" do
      events = [
        %{
          type: "url_changes",
          date: ~D[2025-01-15],
          count: 5,
          metadata: %{
            added: 3,
            removed: 2
          }
        }
      ]

      result = ChartDataPresenter.encode_events(events)
      decoded = JSON.decode!(result)

      first = List.first(decoded)
      assert first["type"] == "url_changes"
      assert first["count"] == 5
      assert first["metadata"]["added"] == 3
      assert first["metadata"]["removed"] == 2
    end
  end
end
