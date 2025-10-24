defmodule GscAnalytics.Analytics.MigrationDetectorTest do
  use GscAnalytics.DataCase

  alias GscAnalytics.Analytics.MigrationDetector
  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.TimeSeries

  @account_id 1
  @old_url "https://example.com/legacy"
  @new_url "https://example.com/new-home"
  @migration_date ~D[2025-02-01]

  describe "detect/3" do
    test "returns migration details anchored on first impressions" do
      insert_series(@old_url, Date.add(@migration_date, -6), Date.add(@migration_date, -1),
        clicks: 12,
        impressions: 100
      )

      insert_series(@new_url, @migration_date, Date.add(@migration_date, 6),
        clicks: 10,
        impressions: 80
      )

      result = MigrationDetector.detect(@old_url, @new_url, @account_id)

      expected_old_last_seen_on = Date.add(@migration_date, -1)

      assert %{
               migration_date: @migration_date,
               new_first_impression_on: @migration_date,
               old_last_seen_on: ^expected_old_last_seen_on,
               confidence: :high
             } = result
    end

    test "returns nil when new url has no impressions" do
      insert_series(@old_url, Date.add(@migration_date, -10), Date.add(@migration_date, -1),
        clicks: 8,
        impressions: 60
      )

      assert MigrationDetector.detect(@old_url, @new_url, @account_id) == nil
    end
  end

  defp insert_series(url, start_date, end_date, attrs) do
    Enum.reduce_while(Stream.iterate(start_date, &Date.add(&1, 1)), start_date, fn date, _acc ->
      if Date.compare(date, end_date) == :gt do
        {:halt, :ok}
      else
        insert_series_for_date(url, date, attrs)
        {:cont, date}
      end
    end)
  end

  defp insert_series_for_date(url, date, attrs) do
    attrs = Map.new(attrs)

    params =
      %{
        account_id: @account_id,
        url: url,
        date: date,
        period_type: :daily,
        clicks: Map.get(attrs, :clicks, 0),
        impressions: Map.get(attrs, :impressions, 0),
        ctr: 0.1,
        position: 5.0,
        data_available: true
      }

    %TimeSeries{}
    |> TimeSeries.changeset(params)
    |> Repo.insert!()
  end
end
