defmodule GscAnalytics.ContentInsights.KeywordAggregatorTest do
  use GscAnalytics.DataCase

  alias GscAnalytics.ContentInsights.KeywordAggregator
  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.TimeSeries

  @account_id 1

  setup do
    today = Date.utc_today()

    insert_time_series(
      @account_id,
      "https://example.com/a",
      Date.add(today, -5),
      [
        %{
          "query" => "elixir",
          "clicks" => 10,
          "impressions" => 100,
          "ctr" => 0.1,
          "position" => 3.0
        },
        %{
          "query" => "beam",
          "clicks" => 5,
          "impressions" => 40,
          "ctr" => 0.125,
          "position" => 5.0
        }
      ]
    )

    insert_time_series(
      @account_id,
      "https://example.com/b",
      Date.add(today, -4),
      [
        %{
          "query" => "elixir",
          "clicks" => 7,
          "impressions" => 50,
          "ctr" => 0.14,
          "position" => 2.5
        }
      ]
    )

    insert_time_series(
      2,
      "https://example.com/c",
      Date.add(today, -3),
      [
        %{
          "query" => "python",
          "clicks" => 20,
          "impressions" => 200,
          "ctr" => 0.1,
          "position" => 4.0
        }
      ]
    )

    :ok
  end

  test "list/1 aggregates keyword metrics" do
    result = KeywordAggregator.list(%{account_id: @account_id, limit: 10, page: 1})

    assert result.total_count == 2
    assert result.total_pages == 1

    [first | _] = result.keywords
    assert first.query == "elixir"
    assert first.clicks == 17
    assert first.impressions == 150
    assert_in_delta first.position, (3.0 * 100 + 2.5 * 50) / 150, 0.01
  end

  test "list/1 supports search filtering" do
    result =
      KeywordAggregator.list(%{
        account_id: @account_id,
        search: "beam",
        limit: 5,
        page: 1
      })

    assert result.total_count == 1
    assert Enum.all?(result.keywords, &(&1.query == "beam"))
  end

  test "list/1 supports sorting" do
    result =
      KeywordAggregator.list(%{
        account_id: @account_id,
        sort_by: "query",
        sort_direction: :asc,
        limit: 10,
        page: 1
      })

    assert Enum.map(result.keywords, & &1.query) == ["beam", "elixir"]
  end

  defp insert_time_series(account_id, url, date, top_queries) do
    %TimeSeries{
      account_id: account_id,
      url: url,
      date: date,
      period_type: :daily,
      clicks: Enum.reduce(top_queries, 0, &(Map.get(&1, "clicks", 0) + &2)),
      impressions: Enum.reduce(top_queries, 0, &(Map.get(&1, "impressions", 0) + &2)),
      ctr: 0.0,
      position: 0.0,
      top_queries: top_queries,
      data_available: true
    }
    |> Repo.insert!()
  end
end
