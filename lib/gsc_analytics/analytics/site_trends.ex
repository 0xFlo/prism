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

  def fetch("weekly", opts) do
    account_id = Accounts.resolve_account_id(opts)

    first_date = get_first_data_date(account_id)
    days_available = Date.diff(Date.utc_today(), first_date)
    weeks = div(days_available, 7) + 1

    series =
      TimeSeriesAggregator.fetch_site_aggregate_by_week(weeks, %{account_id: account_id})

    {series, "Week Starting"}
  end

  def fetch("monthly", opts) do
    account_id = Accounts.resolve_account_id(opts)
    first_date = get_first_data_date(account_id)

    today = Date.utc_today()
    months = (today.year - first_date.year) * 12 + (today.month - first_date.month) + 1

    series =
      TimeSeriesAggregator.fetch_site_aggregate_by_month(months, %{account_id: account_id})

    {series, "Month"}
  end

  def fetch(_view_mode, opts) do
    account_id = Accounts.resolve_account_id(opts)

    first_date = get_first_data_date(account_id)
    days_available = Date.diff(Date.utc_today(), first_date)
    days = min(days_available, 365)

    series =
      TimeSeriesAggregator.fetch_site_aggregate(days, %{account_id: account_id})

    {series, "Date"}
  end

  defp get_first_data_date(account_id) do
    TimeSeries
    |> where([ts], ts.account_id == ^account_id and ts.data_available == true)
    |> select([ts], min(ts.date))
    |> Repo.one()
    |> case do
      nil -> Date.utc_today()
      date -> date
    end
  end
end
