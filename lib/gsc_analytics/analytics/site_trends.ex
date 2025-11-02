defmodule GscAnalytics.Analytics.SiteTrends do
  @moduledoc """
  Site-wide trend aggregations for the dashboard charts.

  Provides daily, weekly, and monthly views by delegating the heavy lifting to
  `TimeSeriesAggregator` while handling the date range calculations and fallback
  behaviour when historical data is limited.
  """

  import Ecto.Query

  alias GscAnalytics.Accounts
  alias GscAnalytics.Analytics.TimeSeriesAggregator
  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.TimeSeries

  @doc """
  Fetch aggregated site trends for the requested view mode.

  Returns a tuple `{series, label}` where `series` is the aggregated data and
  `label` is the axis label used by the charts.
  """
  def fetch(view_mode, opts \\ %{})

  def fetch(view_mode, opts) when is_atom(view_mode) do
    fetch(Atom.to_string(view_mode), opts)
  end

  @max_daily_window 365
  @days_per_month 30

  def fetch("weekly", opts) do
    account_id = Accounts.resolve_account_id(opts)
    property_url = Map.get(opts, :property_url) || raise ArgumentError, "property_url is required"
    first_date = get_first_data_date(account_id, property_url)

    today = Date.utc_today()
    days_available = max(Date.diff(today, first_date), 0)
    weeks_available = max(div(days_available, 7) + 1, 1)

    weeks =
      opts
      |> requested_period_days()
      |> case do
        nil ->
          weeks_available

        period_days ->
          period_days
          |> days_to_weeks()
          |> clamp(1, weeks_available)
      end

    series =
      TimeSeriesAggregator.fetch_site_aggregate_by_week(weeks, %{
        account_id: account_id,
        property_url: property_url
      })

    {series, "Week Starting"}
  end

  def fetch("monthly", opts) do
    account_id = Accounts.resolve_account_id(opts)
    property_url = Map.get(opts, :property_url) || raise ArgumentError, "property_url is required"
    first_date = get_first_data_date(account_id, property_url)

    today = Date.utc_today()
    months_available = max(months_between(first_date, today) + 1, 1)

    months =
      opts
      |> requested_period_days()
      |> case do
        nil ->
          months_available

        period_days ->
          period_days
          |> days_to_months()
          |> clamp(1, months_available)
      end

    series =
      TimeSeriesAggregator.fetch_site_aggregate_by_month(months, %{
        account_id: account_id,
        property_url: property_url
      })

    {series, "Month"}
  end

  def fetch(_view_mode, opts) do
    account_id = Accounts.resolve_account_id(opts)
    property_url = Map.get(opts, :property_url) || raise ArgumentError, "property_url is required"
    first_date = get_first_data_date(account_id, property_url)

    days_available =
      Date.utc_today()
      |> Date.diff(first_date)
      |> max(0)

    days =
      opts
      |> requested_period_days()
      |> case do
        nil ->
          min(days_available, @max_daily_window)

        period_days ->
          period_days
          |> min(@max_daily_window)
          |> min(days_available)
      end

    series =
      TimeSeriesAggregator.fetch_site_aggregate(days, %{
        account_id: account_id,
        property_url: property_url
      })

    {series, "Date"}
  end

  defp get_first_data_date(account_id, property_url) do
    TimeSeries
    |> where(
      [ts],
      ts.account_id == ^account_id and ts.property_url == ^property_url and
        ts.data_available == true
    )
    |> select([ts], min(ts.date))
    |> Repo.one()
    |> case do
      nil -> Date.utc_today()
      date -> date
    end
  end

  defp requested_period_days(opts) do
    case Map.get(opts, :period_days) do
      value when is_integer(value) and value > 0 and value < 10_000 -> value
      _ -> nil
    end
  end

  defp days_to_weeks(days) when is_integer(days) and days > 0 do
    ceil_div(days, 7)
  end

  defp days_to_months(days) when is_integer(days) and days > 0 do
    ceil_div(days, @days_per_month)
  end

  defp ceil_div(numerator, denominator) do
    div(numerator + denominator - 1, denominator)
  end

  defp clamp(value, min_value, _max_value) when value < min_value, do: min_value
  defp clamp(value, _min_value, max_value) when value > max_value, do: max_value
  defp clamp(value, _min_value, _max_value), do: value

  defp months_between(start_date, end_date) do
    total_months = (end_date.year - start_date.year) * 12 + (end_date.month - start_date.month)
    max(total_months, 0)
  end
end
