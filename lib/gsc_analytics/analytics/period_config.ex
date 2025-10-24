defmodule GscAnalytics.Analytics.PeriodConfig do
  @moduledoc """
  Configuration for different aggregation periods (daily, weekly, monthly).

  Defines SQL fragments and metadata for each time granularity to enable
  unified query building across all period types.

  This module eliminates duplication in aggregation queries by centralizing
  period-specific logic into configuration maps.

  ## Usage

      iex> PeriodConfig.config(:week)
      %{
        group_by_fragment: "DATE_TRUNC('week', ?)::date",
        order_by_fragment: "DATE_TRUNC('week', ?)::date",
        type: :week,
        compute_period_end: true
      }

  ## Design Decision: Application-Layer Period End Calculation

  Unlike the initial design which attempted to compute `period_end` in SQL,
  this implementation calculates `period_end` in the application layer after
  fetching from the database.

  **Rationale**:
  - PostgreSQL GROUP BY requires all SELECT expressions to be in the GROUP BY
  - Computing period_end with different logic (e.g., date + 6 days) causes violations
  - Application-layer calculation is negligible cost (52 rows vs 3,650 rows aggregated)
  - Same pattern successfully used in ticket #019a

  See `compute_period_end/2` for the application-layer calculation logic.
  """

  @type period_type :: :day | :week | :month
  @type config :: %{
          group_by_fragment: String.t(),
          order_by_fragment: String.t(),
          type: period_type(),
          compute_period_end: boolean()
        }

  @doc """
  Get configuration for a specific period type.

  Returns a configuration map with SQL fragments and metadata for the period.

  ## Parameters
    - `period_type`: The period type (:day, :week, or :month)

  ## Returns
    Configuration map with:
    - `group_by_fragment`: SQL fragment for GROUP BY clause
    - `order_by_fragment`: SQL fragment for ORDER BY clause
    - `type`: The period type (echoed back for metadata)
    - `compute_period_end`: Whether to compute period_end in app layer

  ## Examples

      iex> PeriodConfig.config(:day)
      %{
        group_by_fragment: "?",
        order_by_fragment: "?",
        type: :day,
        compute_period_end: false
      }

      iex> PeriodConfig.config(:week)
      %{
        group_by_fragment: "DATE_TRUNC('week', ?)::date",
        order_by_fragment: "DATE_TRUNC('week', ?)::date",
        type: :week,
        compute_period_end: true
      }
  """
  @spec config(period_type()) :: config()
  def config(:day) do
    %{
      # Group by exact date (no truncation needed)
      group_by_fragment: "?",
      order_by_fragment: "?",
      type: :day,
      # Daily doesn't need period_end (same as date)
      compute_period_end: false
    }
  end

  def config(:week) do
    %{
      # DATE_TRUNC('week', date) returns Monday (ISO 8601)
      group_by_fragment: "DATE_TRUNC('week', ?)::date",
      order_by_fragment: "DATE_TRUNC('week', ?)::date",
      type: :week,
      # Week runs Monday to Sunday (date + 6 days)
      compute_period_end: true
    }
  end

  def config(:month) do
    %{
      # DATE_TRUNC('month', date) returns 1st of month
      group_by_fragment: "DATE_TRUNC('month', ?)::date",
      order_by_fragment: "DATE_TRUNC('month', ?)::date",
      type: :month,
      # Month runs 1st to last day of month
      compute_period_end: true
    }
  end

  @doc """
  Compute period_end for a data row based on period type.

  This function is called in the application layer after fetching aggregated
  rows from the database.

  ## Parameters
    - `row`: Map with at least a `:date` field
    - `period_type`: The period type (:day, :week, or :month)

  ## Returns
    Row with `:period_end` field added (or nil for daily)

  ## Examples

      iex> row = %{date: ~D[2025-01-06]}
      iex> PeriodConfig.compute_period_end(row, :week)
      %{date: ~D[2025-01-06], period_end: ~D[2025-01-12]}

      iex> row = %{date: ~D[2025-01-01]}
      iex> PeriodConfig.compute_period_end(row, :month)
      %{date: ~D[2025-01-01], period_end: ~D[2025-01-31]}

      iex> row = %{date: ~D[2025-01-15]}
      iex> PeriodConfig.compute_period_end(row, :day)
      %{date: ~D[2025-01-15], period_end: nil}
  """
  @spec compute_period_end(map(), period_type()) :: map()
  def compute_period_end(row, :day) do
    # Daily data doesn't have a period_end (or it equals date)
    Map.put(row, :period_end, nil)
  end

  def compute_period_end(row, :week) do
    # ISO 8601: Week runs Monday (date) to Sunday (date + 6)
    period_end = Date.add(row.date, 6)
    Map.put(row, :period_end, period_end)
  end

  def compute_period_end(row, :month) do
    # Month runs from 1st (date) to last day of month
    days_in_month = Date.days_in_month(row.date)
    period_end = %{row.date | day: days_in_month}
    Map.put(row, :period_end, period_end)
  end

  @doc """
  Compute period_end for a list of rows.

  Convenience function for mapping `compute_period_end/2` over a list.

  ## Examples

      iex> rows = [%{date: ~D[2025-01-06]}, %{date: ~D[2025-01-13]}]
      iex> PeriodConfig.compute_period_ends(rows, :week)
      [
        %{date: ~D[2025-01-06], period_end: ~D[2025-01-12]},
        %{date: ~D[2025-01-13], period_end: ~D[2025-01-19]}
      ]
  """
  @spec compute_period_ends(list(map()), period_type()) :: list(map())
  def compute_period_ends(rows, period_type) when is_list(rows) do
    Enum.map(rows, &compute_period_end(&1, period_type))
  end
end
