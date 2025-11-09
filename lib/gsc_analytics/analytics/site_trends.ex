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
    first_date = resolve_first_data_date(account_id, property_url, opts)

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
    first_date = resolve_first_data_date(account_id, property_url, opts)

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
    first_date = resolve_first_data_date(account_id, property_url, opts)

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

  @doc """
  Return the earliest available Search Console date for the given
  account/property pair. The value comes from `url_lifetime_stats`, which keeps
  the answer in a compact table so we avoid scanning the entire
  `gsc_time_series` partition on every dashboard refresh.
  """
  def first_data_date(account_id, property_url) do
    get_first_data_date(account_id, property_url)
  end

  defp resolve_first_data_date(account_id, property_url, opts) when is_map(opts) do
    case Map.get(opts, :first_data_date) do
      %Date{} = date -> date
      _ -> get_first_data_date(account_id, property_url)
    end
  end

  defp resolve_first_data_date(account_id, property_url, _opts) do
    get_first_data_date(account_id, property_url)
  end

  defp get_first_data_date(account_id, property_url) do
    from(ls in "url_lifetime_stats",
      where: ls.account_id == ^account_id and ls.property_url == ^property_url,
      select: min(ls.first_seen_date)
    )
    |> Repo.one()
    |> case do
      nil -> fallback_first_data_date(account_id, property_url)
      date -> date
    end
  end

  defp fallback_first_data_date(account_id, property_url) do
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

  @doc """
  Fetch aggregated totals for the selected period.

  Returns a map with:
  - `total_clicks`: Sum of all clicks in the period
  - `total_impressions`: Sum of all impressions in the period
  - `avg_ctr`: Average CTR (weighted by impressions)
  - `avg_position`: Average position (weighted by impressions)
  """
  def fetch_period_totals(opts \\ %{}) do
    account_id = Accounts.resolve_account_id(opts)
    property_url = Map.get(opts, :property_url) || raise ArgumentError, "property_url is required"
    period_days = requested_period_days(opts)
    first_date = resolve_first_data_date(account_id, property_url, opts)

    case resolve_period_range(period_days, first_date) do
      {:all_time, _} ->
        aggregate_lifetime_period_totals(account_id, property_url)

      {:range, start_date} ->
        aggregate_period_totals(account_id, property_url, start_date)
    end
  end

  defp resolve_period_range(nil, first_date), do: {:all_time, first_date}

  defp resolve_period_range(days, first_date) when is_integer(days) and days >= 10_000,
    do: {:all_time, first_date}

  defp resolve_period_range(days, _first_date) when is_integer(days) and days > 0 do
    {:range, Date.add(Date.utc_today(), -days)}
  end

  defp aggregate_period_totals(account_id, property_url, start_date) do
    TimeSeries
    |> where(
      [ts],
      ts.date >= ^start_date and
        ts.account_id == ^account_id and
        ts.property_url == ^property_url
    )
    |> select([ts], %{
      total_clicks: sum(ts.clicks),
      total_impressions: sum(ts.impressions),
      avg_ctr: fragment("CAST(SUM(?) AS FLOAT) / NULLIF(SUM(?), 0)", ts.clicks, ts.impressions),
      avg_position: avg(ts.position)
    })
    |> Repo.one()
    |> format_period_totals()
  end

  defp aggregate_lifetime_period_totals(account_id, property_url) do
    from(ls in "url_lifetime_stats",
      where: ls.account_id == ^account_id and ls.property_url == ^property_url,
      select: %{
        total_clicks: sum(coalesce(ls.lifetime_clicks, 0)),
        total_impressions: sum(coalesce(ls.lifetime_impressions, 0)),
        avg_ctr:
          fragment(
            "CAST(SUM(COALESCE(?, 0)) AS FLOAT) / NULLIF(SUM(COALESCE(?, 0)), 0)",
            ls.lifetime_clicks,
            ls.lifetime_impressions
          ),
        avg_position:
          fragment(
            "SUM(COALESCE(?, 0) * COALESCE(?, 0)) / NULLIF(SUM(COALESCE(?, 0)), 0)",
            ls.avg_position,
            ls.lifetime_impressions,
            ls.lifetime_impressions
          )
      }
    )
    |> Repo.one()
    |> format_period_totals()
  end

  defp format_period_totals(nil) do
    %{total_clicks: 0, total_impressions: 0, avg_ctr: 0.0, avg_position: 0.0}
  end

  defp format_period_totals(result) do
    %{
      total_clicks: result.total_clicks || 0,
      total_impressions: result.total_impressions || 0,
      avg_ctr: result.avg_ctr || 0.0,
      avg_position: result.avg_position || 0.0
    }
  end
end
