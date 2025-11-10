defmodule GscAnalytics.UrlGroups do
  @moduledoc """
  Resolve canonical URL groupings and redirect history for Search Console data.

  A URL group captures the current canonical URL, any historical URLs that now
  redirect to it, and the earliest/latest dates with time-series data. The HTTP
  crawler is responsible for discovering those redirect relationships; this
  module simply combines them with GSC evidence (via the migration detector) so
  the dashboard can display when Google actually switched traffic to the new
  URL.
  """

  import Ecto.Query

  alias GscAnalytics.Accounts
  alias GscAnalytics.Analytics.MigrationDetector
  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.{Performance, TimeSeries, UrlLifetimeStats}

  @type redirect_event ::
          %{
            required(:type) => :http_redirect | :gsc_migration,
            required(:source_url) => String.t(),
            required(:target_url) => String.t() | nil,
            required(:checked_at) => DateTime.t() | nil,
            optional(:status) => integer() | nil,
            optional(:confidence) => :high | :medium | :low,
            optional(:new_first_impression_on) => Date.t(),
            optional(:old_last_seen_on) => Date.t()
          }

  @type t :: %{
          requested_url: String.t(),
          canonical_url: String.t(),
          urls: [String.t()],
          redirect_events: [redirect_event],
          earliest_date: Date.t() | nil,
          latest_date: Date.t() | nil
        }

  @doc """
  Resolve the canonical grouping for the given URL.

  Returns a map with the canonical URL, all related URLs (including the
  requested URL), redirect events, and data bounds.
  """
  @spec resolve(String.t(), map()) :: t()
  def resolve(url, opts \\ %{}) when is_binary(url) do
    account_id = Accounts.resolve_account_id(opts)
    property_url = Map.get(opts, :property_url)
    decoded_url = URI.decode(url)

    redirect_rows =
      decoded_url
      |> fetch_redirect_chain(account_id, property_url)
      |> sanitize_redirect_rows()

    redirect_map = build_redirect_map(redirect_rows)

    canonical = walk_chain(decoded_url, redirect_map)

    urls =
      ([decoded_url, canonical] ++ Map.keys(redirect_rows))
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&has_fragment?/1)
      |> Enum.uniq()

    redirect_events =
      redirect_rows
      |> Map.values()
      |> Enum.filter(fn row ->
        valid_redirect?(row.redirect_url) and row.redirect_url != row.url
      end)
      |> Enum.map(fn row ->
        %{
          type: :http_redirect,
          source_url: row.url,
          target_url: row.redirect_url,
          status: row.http_status,
          checked_at: row.http_checked_at
        }
      end)
      |> Enum.sort_by(&(&1.checked_at || default_epoch()), DateTime)

    gsc_migration_events =
      redirect_events
      |> Enum.map(fn %{source_url: old, target_url: new} ->
        case MigrationDetector.detect(old, new, account_id) do
          nil ->
            nil

          migration ->
            event = %{
              type: :gsc_migration,
              source_url: migration.old_url,
              target_url: migration.new_url,
              checked_at: DateTime.new!(migration.migration_date, ~T[00:00:00], "Etc/UTC"),
              confidence: migration.confidence,
              new_first_impression_on: migration.new_first_impression_on,
              old_last_seen_on: migration.old_last_seen_on
            }

            if has_fragment?(event.source_url) or has_fragment?(event.target_url) do
              nil
            else
              event
            end
        end
      end)
      |> Enum.reject(&is_nil/1)

    all_events =
      (redirect_events ++ gsc_migration_events)
      |> Enum.sort_by(&(&1.checked_at || default_epoch()), DateTime)

    {earliest, latest} = time_bounds(urls, account_id, property_url)

    %{
      requested_url: decoded_url,
      canonical_url: canonical,
      urls: urls,
      redirect_events: all_events,
      earliest_date: earliest,
      latest_date: latest
    }
  end

  defp sanitize_redirect_rows(rows) when is_map(rows) do
    rows
    |> Enum.reject(fn {url, row} ->
      has_fragment?(url) or has_fragment?(row.redirect_url)
    end)
    |> Map.new()
  end

  defp sanitize_redirect_rows(rows), do: rows

  defp fetch_redirect_chain(url, account_id, property_url) do
    {:ok, rows} =
      do_fetch_redirect_chain(url, account_id, property_url, %{}, MapSet.new(), MapSet.new())

    rows
  end

  defp do_fetch_redirect_chain(nil, _account_id, _property_url, rows, _processed, _queued),
    do: {:ok, rows}

  defp do_fetch_redirect_chain(url, account_id, property_url, rows, processed, queued)
       when is_binary(url) do
    cond do
      MapSet.member?(processed, url) ->
        {:ok, rows}

      MapSet.size(processed) >= 50 ->
        # Safety guard against runaway recursion
        {:ok, rows}

      true ->
        batch =
          queued
          |> MapSet.put(url)
          |> Enum.reject(&MapSet.member?(processed, &1))
          |> Enum.filter(&valid_redirect?/1)

        if batch == [] do
          {:ok, rows}
        else
          performance_query =
            Performance
            |> where([p], p.account_id == ^account_id)
            |> where([p], p.url in ^batch or p.redirect_url in ^batch)
            |> maybe_filter_property(property_url)
            |> select([p], %{
              url: p.url,
              redirect_url: p.redirect_url,
              http_status: p.http_status,
              http_checked_at: p.http_checked_at
            })

          lifetime_query =
            UrlLifetimeStats
            |> where([ls], ls.account_id == ^account_id)
            |> where([ls], ls.url in ^batch or ls.redirect_url in ^batch)
            |> maybe_filter_property(property_url)
            |> select([ls], %{
              url: ls.url,
              redirect_url: ls.redirect_url,
              http_status: ls.http_status,
              http_checked_at: ls.http_checked_at
            })

          results =
            Repo.all(lifetime_query) ++ Repo.all(performance_query)

          updated_rows =
            Enum.reduce(results, rows, fn row, acc ->
              Map.put_new(acc, row.url, row)
            end)

          newly_seen = Enum.reduce(batch, processed, &MapSet.put(&2, &1))

          next_urls =
            results
            |> Enum.reduce(MapSet.new(), fn row, acc ->
              acc
              |> maybe_put(row.url)
              |> maybe_put(row.redirect_url)
            end)

          case next_urls |> MapSet.difference(newly_seen) |> Enum.to_list() do
            [] ->
              {:ok, updated_rows}

            [next | rest] ->
              queued = Enum.reduce(rest, MapSet.new(), &MapSet.put(&2, &1))

              do_fetch_redirect_chain(
                next,
                account_id,
                property_url,
                updated_rows,
                newly_seen,
                queued
              )
          end
        end
    end
  end

  defp build_redirect_map(rows) do
    Enum.reduce(rows, %{}, fn {url, row}, acc ->
      case normalize_redirect(row.redirect_url) do
        nil -> acc
        redirect -> Map.put(acc, url, redirect)
      end
    end)
  end

  defp walk_chain(url, redirects) when is_binary(url) do
    do_walk_chain(url, redirects, MapSet.new(), 0)
  end

  defp do_walk_chain(nil, _redirects, _visited, _depth), do: nil

  defp do_walk_chain(url, _redirects, _visited, depth) when depth >= 10 do
    url
  end

  defp do_walk_chain(url, redirects, visited, depth) do
    cond do
      MapSet.member?(visited, url) ->
        url

      true ->
        case Map.get(redirects, url) do
          redirect when redirect in [nil, ""] ->
            url

          redirect when redirect == url ->
            url

          redirect ->
            do_walk_chain(redirect, redirects, MapSet.put(visited, url), depth + 1)
        end
    end
  end

  defp valid_redirect?(value) do
    case value do
      nil -> false
      "" -> false
      value -> not has_fragment?(value)
    end
  end

  defp maybe_put(set, value) do
    case normalize_redirect(value) do
      nil -> set
      data -> MapSet.put(set, data)
    end
  end

  defp normalize_redirect(value) do
    cond do
      is_nil(value) -> nil
      value == "" -> nil
      has_fragment?(value) -> nil
      true -> value
    end
  end

  defp time_bounds([], _account_id, _property_url), do: {nil, nil}

  defp time_bounds(urls, account_id, property_url) do
    TimeSeries
    |> where([ts], ts.account_id == ^account_id)
    |> where([ts], ts.url in ^urls)
    |> maybe_filter_property(property_url)
    |> select([ts], %{
      earliest: min(ts.date),
      latest: max(ts.date)
    })
    |> Repo.one()
    |> case do
      %{earliest: earliest, latest: latest} -> {earliest, latest}
      nil -> {nil, nil}
    end
  end

  defp default_epoch do
    DateTime.from_unix!(0)
  end

  defp has_fragment?(value) when is_binary(value) do
    case URI.parse(value) do
      %URI{fragment: fragment} when is_binary(fragment) and fragment != "" -> true
      _ -> false
    end
  end

  defp has_fragment?(_), do: false

  defp maybe_filter_property(query, nil), do: query

  defp maybe_filter_property(query, property_url),
    do: where(query, [row], field(row, :property_url) == ^property_url)
end
