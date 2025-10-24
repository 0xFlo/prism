defmodule GscAnalytics.Analytics.PeriodConfigTest do
  use ExUnit.Case, async: true

  alias GscAnalytics.Analytics.PeriodConfig

  describe "config/1" do
    test "returns correct config for day period" do
      config = PeriodConfig.config(:day)

      assert config.group_by_fragment == "?"
      assert config.order_by_fragment == "?"
      assert config.type == :day
      assert config.compute_period_end == false
    end

    test "returns correct config for week period" do
      config = PeriodConfig.config(:week)

      assert config.group_by_fragment == "DATE_TRUNC('week', ?)::date"
      assert config.order_by_fragment == "DATE_TRUNC('week', ?)::date"
      assert config.type == :week
      assert config.compute_period_end == true
    end

    test "returns correct config for month period" do
      config = PeriodConfig.config(:month)

      assert config.group_by_fragment == "DATE_TRUNC('month', ?)::date"
      assert config.order_by_fragment == "DATE_TRUNC('month', ?)::date"
      assert config.type == :month
      assert config.compute_period_end == true
    end
  end

  describe "compute_period_end/2" do
    test "returns nil for daily data" do
      row = %{date: ~D[2025-01-15]}
      result = PeriodConfig.compute_period_end(row, :day)

      assert result.period_end == nil
      assert result.date == ~D[2025-01-15]
    end

    test "calculates week end correctly for Monday" do
      # ISO 8601: Week starts on Monday
      row = %{date: ~D[2025-01-06]}  # Monday
      result = PeriodConfig.compute_period_end(row, :week)

      # Week runs Monday to Sunday (date + 6 days)
      assert result.period_end == ~D[2025-01-12]  # Sunday
      assert result.date == ~D[2025-01-06]
    end

    test "calculates week end correctly for mid-week" do
      # If date is Wednesday, still should add 6 days
      row = %{date: ~D[2025-01-08]}  # Wednesday
      result = PeriodConfig.compute_period_end(row, :week)

      assert result.period_end == ~D[2025-01-14]  # Wednesday + 6 days
      assert result.date == ~D[2025-01-08]
    end

    test "calculates month end for 31-day month (January)" do
      row = %{date: ~D[2025-01-01]}
      result = PeriodConfig.compute_period_end(row, :month)

      assert result.period_end == ~D[2025-01-31]
      assert result.date == ~D[2025-01-01]
    end

    test "calculates month end for 30-day month (April)" do
      row = %{date: ~D[2025-04-01]}
      result = PeriodConfig.compute_period_end(row, :month)

      assert result.period_end == ~D[2025-04-30]
      assert result.date == ~D[2025-04-01]
    end

    test "calculates month end for February in non-leap year" do
      row = %{date: ~D[2025-02-01]}
      result = PeriodConfig.compute_period_end(row, :month)

      assert result.period_end == ~D[2025-02-28]
      assert result.date == ~D[2025-02-01]
    end

    test "calculates month end for February in leap year" do
      row = %{date: ~D[2024-02-01]}
      result = PeriodConfig.compute_period_end(row, :month)

      assert result.period_end == ~D[2024-02-29]
      assert result.date == ~D[2024-02-01]
    end

    test "handles mid-month date correctly" do
      row = %{date: ~D[2025-01-15]}
      result = PeriodConfig.compute_period_end(row, :month)

      # Month end is still last day of month, not +N days
      assert result.period_end == ~D[2025-01-31]
      assert result.date == ~D[2025-01-15]
    end

    test "preserves other fields in row" do
      row = %{
        date: ~D[2025-01-06],
        clicks: 100,
        impressions: 1000,
        custom_field: "test"
      }

      result = PeriodConfig.compute_period_end(row, :week)

      # Original fields preserved
      assert result.clicks == 100
      assert result.impressions == 1000
      assert result.custom_field == "test"
      # New field added
      assert result.period_end == ~D[2025-01-12]
    end
  end

  describe "compute_period_ends/2" do
    test "processes empty list" do
      result = PeriodConfig.compute_period_ends([], :week)

      assert result == []
    end

    test "processes single row" do
      rows = [%{date: ~D[2025-01-06]}]
      result = PeriodConfig.compute_period_ends(rows, :week)

      assert length(result) == 1
      assert List.first(result).period_end == ~D[2025-01-12]
    end

    test "processes multiple rows for weekly period" do
      rows = [
        %{date: ~D[2025-01-06]},  # Week 1
        %{date: ~D[2025-01-13]},  # Week 2
        %{date: ~D[2025-01-20]}   # Week 3
      ]

      result = PeriodConfig.compute_period_ends(rows, :week)

      assert length(result) == 3
      assert Enum.at(result, 0).period_end == ~D[2025-01-12]
      assert Enum.at(result, 1).period_end == ~D[2025-01-19]
      assert Enum.at(result, 2).period_end == ~D[2025-01-26]
    end

    test "processes multiple rows for monthly period" do
      rows = [
        %{date: ~D[2025-01-01]},  # January
        %{date: ~D[2025-02-01]},  # February (non-leap)
        %{date: ~D[2024-02-01]}   # February (leap year)
      ]

      result = PeriodConfig.compute_period_ends(rows, :month)

      assert length(result) == 3
      assert Enum.at(result, 0).period_end == ~D[2025-01-31]
      assert Enum.at(result, 1).period_end == ~D[2025-02-28]
      assert Enum.at(result, 2).period_end == ~D[2024-02-29]
    end

    test "processes multiple rows for daily period (all nil)" do
      rows = [
        %{date: ~D[2025-01-01]},
        %{date: ~D[2025-01-02]},
        %{date: ~D[2025-01-03]}
      ]

      result = PeriodConfig.compute_period_ends(rows, :day)

      assert length(result) == 3
      assert Enum.all?(result, fn row -> row.period_end == nil end)
    end

    test "preserves row order" do
      rows = [
        %{date: ~D[2025-01-20], seq: 3},
        %{date: ~D[2025-01-06], seq: 1},
        %{date: ~D[2025-01-13], seq: 2}
      ]

      result = PeriodConfig.compute_period_ends(rows, :week)

      # Order preserved
      assert Enum.at(result, 0).seq == 3
      assert Enum.at(result, 1).seq == 1
      assert Enum.at(result, 2).seq == 2
    end
  end

  describe "edge cases" do
    test "handles year boundaries for weekly period" do
      # Week spanning 2024-2025 boundary
      row = %{date: ~D[2024-12-30]}  # Monday
      result = PeriodConfig.compute_period_end(row, :week)

      # Should correctly add 6 days across year boundary
      assert result.period_end == ~D[2025-01-05]
    end

    test "handles year boundaries for monthly period" do
      row = %{date: ~D[2024-12-01]}
      result = PeriodConfig.compute_period_end(row, :month)

      assert result.period_end == ~D[2024-12-31]
    end

    test "handles last day of month" do
      row = %{date: ~D[2025-01-31]}
      result = PeriodConfig.compute_period_end(row, :month)

      # Period end is still the same day
      assert result.period_end == ~D[2025-01-31]
    end

    test "handles first day of year" do
      row = %{date: ~D[2025-01-01]}
      result = PeriodConfig.compute_period_end(row, :month)

      assert result.period_end == ~D[2025-01-31]
    end

    test "handles last day of year" do
      row = %{date: ~D[2025-12-31]}
      result = PeriodConfig.compute_period_end(row, :month)

      assert result.period_end == ~D[2025-12-31]
    end
  end
end
