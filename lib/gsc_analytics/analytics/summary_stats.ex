defmodule GscAnalytics.Analytics.SummaryStats do
  @moduledoc """
  Aggregates site-wide summary statistics for the dashboard cards.

  Computes month-to-date, last-month, and all-time metrics while exposing the
  derived month-over-month percentage change.
  """

  import Ecto.Query

  alias GscAnalytics.Accounts
  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.TimeSeries

  @doc """
  Fetch summary statistics for the requested account.

  Returns a map with `:current_month`, `:last_month`, `:all_time`, and
  `:month_over_month_change` keys.
  """
  def fetch(opts \\ %{}) do
    account_id = Accounts.resolve_account_id(opts)
    property_url = Map.get(opts, :property_url) || raise ArgumentError, "property_url is required"
    today = Date.utc_today()

    current_month_start = Date.beginning_of_month(today)
    last_month_end = Date.add(current_month_start, -1)
    last_month_start = Date.beginning_of_month(last_month_end)

    current_month = aggregate_period(account_id, property_url, current_month_start, today)
    last_month = aggregate_period(account_id, property_url, last_month_start, last_month_end)
    all_time = aggregate_lifetime_from_table(account_id, property_url)

    mom_change = calculate_percentage_change(last_month.total_clicks, current_month.total_clicks)

    %{
      current_month: current_month,
      last_month: last_month,
      all_time: all_time,
      month_over_month_change: mom_change
    }
  end

  defp aggregate_period(account_id, property_url, start_date, end_date) do
    result =
      TimeSeries
      |> where(
        [ts],
        ts.account_id == ^account_id and ts.property_url == ^property_url and
          ts.date >= ^start_date and ts.date <= ^end_date and
          ts.data_available == true
      )
      |> select([ts], %{
        total_urls: fragment("COUNT(DISTINCT ?)", ts.url),
        total_clicks: sum(ts.clicks),
        total_impressions: sum(ts.impressions),
        avg_position:
          fragment(
            "SUM(? * ?) / NULLIF(SUM(?), 0)",
            ts.position,
            ts.impressions,
            ts.impressions
          ),
        avg_ctr:
          fragment(
            "SUM(?)::float / NULLIF(SUM(?), 0) * 100",
            ts.clicks,
            ts.impressions
          )
      })
      |> Repo.one()
      |> format_stats()

    Map.put(result, :period_label, format_period_label(start_date, end_date))
  end

  defp aggregate_lifetime_from_table(account_id, property_url) do
    from(ls in "url_lifetime_stats",
      where: ls.account_id == ^account_id and ls.property_url == ^property_url,
      select: %{
        total_urls: count(ls.url),
        total_clicks: sum(ls.lifetime_clicks),
        total_impressions: sum(ls.lifetime_impressions),
        avg_position: avg(ls.avg_position),
        avg_ctr: avg(ls.avg_ctr) * 100,
        earliest_date: min(ls.first_seen_date),
        latest_date: max(ls.last_seen_date)
      }
    )
    |> Repo.one()
    |> maybe_add_day_span()
    |> format_stats()
  end

  defp format_stats(nil) do
    %{
      total_urls: 0,
      total_clicks: 0,
      total_impressions: 0,
      avg_position: 0.0,
      avg_ctr: 0.0
    }
  end

  defp format_stats(stats) do
    %{
      total_urls: convert_to_integer(stats.total_urls) || 0,
      total_clicks: convert_to_integer(stats.total_clicks) || 0,
      total_impressions: convert_to_integer(stats.total_impressions) || 0,
      avg_position: Float.round(convert_to_float(stats.avg_position) || 0.0, 2),
      avg_ctr: Float.round(convert_to_float(stats.avg_ctr) || 0.0, 2)
    }
    |> maybe_add_date_fields(stats)
  end

  defp convert_to_integer(nil), do: 0
  defp convert_to_integer(value) when is_integer(value), do: value
  defp convert_to_integer(%Decimal{} = value), do: Decimal.to_integer(value)
  defp convert_to_integer(value) when is_float(value), do: trunc(value)
  defp convert_to_integer(_), do: 0

  defp convert_to_float(nil), do: 0.0
  defp convert_to_float(value) when is_float(value), do: value
  defp convert_to_float(%Decimal{} = value), do: Decimal.to_float(value)
  defp convert_to_float(value) when is_integer(value), do: value * 1.0
  defp convert_to_float(_), do: 0.0

  defp maybe_add_date_fields(result, stats) do
    result
    |> maybe_put(:earliest_date, Map.get(stats, :earliest_date))
    |> maybe_put(:latest_date, Map.get(stats, :latest_date))
    |> maybe_put(:days_with_data, convert_to_integer(Map.get(stats, :days_with_data)))
  end

  defp maybe_add_day_span(nil), do: nil

  defp maybe_add_day_span(%{earliest_date: nil} = stats), do: stats

  defp maybe_add_day_span(%{latest_date: nil} = stats), do: stats

  defp maybe_add_day_span(%{earliest_date: earliest, latest_date: latest} = stats) do
    days =
      latest
      |> Date.diff(earliest)
      |> Kernel.+(1)
      |> max(0)

    Map.put(stats, :days_with_data, days)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp calculate_percentage_change(nil, _), do: 0.0
  defp calculate_percentage_change(_, nil), do: 0.0
  defp calculate_percentage_change(0, _), do: 0.0
  defp calculate_percentage_change(old_value, _) when old_value == 0.0, do: 0.0

  defp calculate_percentage_change(old_value, new_value) do
    Float.round((new_value - old_value) / old_value * 100, 1)
  end

  defp format_period_label(start_date, end_date) do
    if start_date == Date.beginning_of_month(start_date) and
         end_date == Date.end_of_month(end_date) and
         start_date.month == end_date.month do
      Calendar.strftime(start_date, "%B %Y")
    else
      "#{start_date} to #{end_date}"
    end
  end
end
