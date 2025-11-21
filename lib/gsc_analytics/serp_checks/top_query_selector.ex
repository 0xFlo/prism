defmodule GscAnalytics.SerpChecks.TopQuerySelector do
  @moduledoc """
  Fetches top-performing Search Console queries for a given URL so bulk SERP
  checks can target the most valuable keywords.
  """

  import Ecto.Query

  alias GscAnalytics.Auth.Scope
  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.TimeSeries

  @default_limit 7

  @doc """
  Returns the top queries for a URL, scoped to the caller's permissions.

  Options:
    * `:limit` (default 7)
    * `:period_days` (default 30)
    * `:geo` (default "us")
  """
  def top_queries_for_url(scope, account_id, property_url, url, opts \\ %{}) do
    with :ok <- Scope.authorize_account(scope, account_id),
         {:ok, normalized_url} <- normalize_url(url) do
      limit = opts[:limit] || @default_limit
      period_days = opts[:period_days] || 30
      geo = opts[:geo] || "us"
      period_start = Date.add(Date.utc_today(), -period_days)

      keywords =
        TimeSeries
        |> where([ts], ts.account_id == ^account_id)
        |> maybe_filter_property(property_url)
        |> where([ts], fragment("LOWER(?) = ?", ts.url, ^String.downcase(normalized_url)))
        |> where([ts], ts.date >= ^period_start)
        |> where([ts], fragment("array_length(?, 1) > 0", ts.top_queries))
        |> join(:cross, [ts], q in fragment("unnest(?)", ts.top_queries))
        |> group_by([_ts, q], fragment("LOWER(TRIM(COALESCE(?->>'query', '')))", q))
        |> order_by([_ts, q], desc: fragment("SUM((?->>'clicks')::bigint)", q))
        |> limit(^limit)
        |> select([_ts, q], %{
          keyword: fragment("MIN(TRIM(COALESCE(?->>'query', '')))", q),
          clicks: fragment("SUM((?->>'clicks')::bigint)", q),
          impressions: fragment("SUM((?->>'impressions')::bigint)", q),
          ctr:
            fragment(
              "COALESCE(SUM((?->>'clicks')::bigint)::float / NULLIF(SUM((?->>'impressions')::bigint), 0), 0)",
              q,
              q
            ),
          position:
            fragment(
              "COALESCE(SUM((?->>'position')::float * (?->>'impressions')::bigint) / NULLIF(SUM((?->>'impressions')::bigint), 0), 0)",
              q,
              q,
              q
            )
        })
        |> Repo.all()
        |> Enum.map(&format_row(&1, geo))
        |> Enum.reject(&is_nil(&1.keyword))

      if keywords == [] do
        {:error, :no_keywords}
      else
        {:ok, keywords}
      end
    end
  end

  defp maybe_filter_property(query, nil), do: query

  defp maybe_filter_property(query, property_url) when is_binary(property_url) do
    where(query, [ts], ts.property_url == ^property_url)
  end

  defp normalize_url(url) when is_binary(url) and url != "" do
    {:ok, url}
  end

  defp normalize_url(_), do: {:error, :invalid_url}

  defp format_row(row, geo) do
    %{
      keyword: normalize_query(row.keyword),
      clicks: to_int(row.clicks),
      impressions: to_int(row.impressions),
      ctr: to_float(row.ctr),
      position: to_float(row.position),
      geo: geo
    }
  end

  defp normalize_query(nil), do: nil

  defp normalize_query(query) do
    query
    |> to_string()
    |> String.trim()
  end

  defp to_int(nil), do: 0
  defp to_int(value) when is_integer(value), do: value

  defp to_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> 0
    end
  end

  defp to_int(_), do: 0

  defp to_float(nil), do: 0.0
  defp to_float(value) when is_float(value), do: value
  defp to_float(value) when is_integer(value), do: value / 1.0

  defp to_float(value) when is_binary(value) do
    case Float.parse(value) do
      {flt, _} -> flt
      :error -> 0.0
    end
  end

  defp to_float(_), do: 0.0
end
