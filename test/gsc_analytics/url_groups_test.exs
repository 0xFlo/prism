defmodule GscAnalytics.UrlGroupsTest do
  use GscAnalytics.DataCase

  alias GscAnalytics.Repo
  alias GscAnalytics.UrlGroups
  alias GscAnalytics.Schemas.{Performance, TimeSeries}
  alias GscAnalytics.Test.QueryCounter

  @account_id 1

  setup do
    {:ok, _} = QueryCounter.start()

    on_exit(fn ->
      QueryCounter.stop()
    end)

    :ok
  end

  describe "resolve/2" do
    test "resolves three-hop chain with reduced queries" do
      [first, second, third] = build_chain(~D[2024-12-01], 3)

      QueryCounter.reset()
      result = UrlGroups.resolve(first.url)
      analysis = QueryCounter.analyze()

      assert result.canonical_url == third.url
      assert Enum.sort(result.urls) == Enum.sort(Enum.map([first, second, third], & &1.url))
      assert Enum.count(result.redirect_events, &(&1.type == :http_redirect)) == 2
      assert Enum.count(result.redirect_events, &(&1.type == :gsc_migration)) == 2
      assert analysis.total_count <= 16
    end

    test "resolves five-hop chain without exceeding query guard" do
      chain = build_chain(~D[2024-11-01], 5)
      first = hd(chain)
      last = List.last(chain)

      QueryCounter.reset()
      result = UrlGroups.resolve(first.url)
      analysis = QueryCounter.analyze()

      assert result.canonical_url == last.url
      assert Enum.sort(result.urls) == Enum.sort(Enum.map(chain, & &1.url))
      assert Enum.count(result.redirect_events, &(&1.type == :http_redirect)) == 4
      assert Enum.count(result.redirect_events, &(&1.type == :gsc_migration)) == 4
      assert analysis.total_count <= 24
    end

    test "handles circular redirects gracefully" do
      url_a = "https://example.com/start"
      url_b = "https://example.com/loop"

      insert_performance(url_a, url_b, http_checked_at: ~U[2024-12-01 10:00:00Z])
      insert_performance(url_b, url_a, http_checked_at: ~U[2024-12-01 11:00:00Z])
      insert_time_series(url_a, ~D[2024-11-01])
      insert_time_series(url_b, ~D[2024-11-01])

      QueryCounter.reset()
      result = UrlGroups.resolve(url_a)

      assert Enum.sort(result.urls) == Enum.sort([url_a, url_b])
      assert result.canonical_url in [url_a, url_b]
      assert Enum.count(result.redirect_events, &(&1.type == :http_redirect)) == 2
      assert Enum.count(result.redirect_events, &(&1.type == :gsc_migration)) == 2
    end

    test "ignores empty redirect values" do
      url = "https://example.com/content"

      insert_performance(url, "")
      insert_time_series(url, ~D[2024-10-01])

      QueryCounter.reset()
      result = UrlGroups.resolve(url)

      assert result.canonical_url == url
      assert result.redirect_events == []
      assert result.urls == [url]
    end

    test "filters fragment urls from redirect history" do
      old_url = "https://example.com/article"
      new_url = "https://example.com/posts/article"
      fragment_url = old_url <> "#section"

      insert_performance(old_url, new_url, http_checked_at: ~U[2025-02-05 00:00:00Z])
      insert_performance(fragment_url, new_url, http_checked_at: ~U[2025-02-05 01:00:00Z])

      insert_time_series(old_url, ~D[2025-02-01])
      insert_time_series(new_url, ~D[2025-02-02])

      result = UrlGroups.resolve(old_url)

      refute Enum.any?(result.urls, &String.contains?(&1, "#"))
      assert Enum.count(result.redirect_events, &(&1.type == :gsc_migration)) == 1

      refute Enum.any?(result.redirect_events, fn event ->
               String.contains?(event.source_url, "#") or
                 String.contains?(event.target_url || "", "#")
             end)
    end
  end

  defp build_chain(start_date, length) when length >= 2 do
    urls =
      1..length
      |> Enum.map(fn idx ->
        "https://example.com/url-#{idx}"
      end)

    Enum.with_index(urls)
    |> Enum.map(fn {url, index} ->
      redirect = Enum.at(urls, index + 1)
      checked_at = DateTime.new!(Date.add(start_date, index), ~T[00:00:00], "Etc/UTC")

      insert_performance(url, redirect, http_checked_at: checked_at)
      insert_time_series(url, Date.add(start_date, index))

      %{url: url, redirect: redirect}
    end)
  end

  defp insert_performance(url, redirect_url, attrs \\ %{}) do
    attrs = Map.new(attrs)

    defaults = %{
      account_id: @account_id,
      url: url,
      redirect_url: redirect_url,
      http_status: (redirect_url && redirect_url != "" && 301) || 200,
      http_checked_at: Map.get(attrs, :http_checked_at, ~U[2024-12-01 00:00:00Z])
    }

    params = Map.merge(defaults, attrs)

    %Performance{}
    |> Performance.changeset(params)
    |> Repo.insert!()
  end

  defp insert_time_series(url, date) do
    %TimeSeries{
      account_id: @account_id,
      url: url,
      date: date,
      period_type: :daily,
      clicks: 5,
      impressions: 10,
      ctr: 0.1,
      position: 5.0,
      data_available: true
    }
    |> Repo.insert!()
  end
end
