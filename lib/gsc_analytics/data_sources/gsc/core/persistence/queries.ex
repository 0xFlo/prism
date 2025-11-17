defmodule GscAnalytics.DataSources.GSC.Core.Persistence.Queries do
  @moduledoc false

  alias GscAnalytics.DataSources.GSC.Core.Config
  alias GscAnalytics.DataSources.GSC.Core.Persistence.Helpers
  alias GscAnalytics.DataSources.GSC.Support.QueryAccumulator
  alias GscAnalytics.DateTime, as: AppDateTime
  alias GscAnalytics.Repo

  @doc """
  Process and store query data for URLs using the streaming accumulator.
  Returns the total number of query rows observed.
  """
  def process_query_response(account_id, site_url, date, %QueryAccumulator{} = accumulator) do
    now = AppDateTime.utc_now()
    chunk_size = Config.query_write_chunk_size()
    timeout = Config.query_write_timeout()

    accumulator
    |> QueryAccumulator.entries()
    |> Enum.chunk_every(chunk_size)
    |> Enum.each(fn chunk ->
      rows =
        Enum.map(chunk, fn {url, queries} ->
          %{
            account_id: account_id,
            property_url: Helpers.safe_truncate(site_url, 255),
            url: Helpers.safe_truncate(url, 2048),
            date: date,
            top_queries: queries,
            inserted_at: now
          }
        end)

      Repo.insert_all(
        GscAnalytics.Schemas.TimeSeries,
        rows,
        on_conflict: {:replace, [:top_queries]},
        conflict_target: [:account_id, :property_url, :url, :date],
        timeout: timeout,
        log: false
      )
    end)

    QueryAccumulator.row_count(accumulator)
  end

  def process_query_response(account_id, site_url, date, query_rows) when is_list(query_rows) do
    accumulator =
      QueryAccumulator.new()
      |> QueryAccumulator.ingest_chunk(query_rows)

    process_query_response(account_id, site_url, date, accumulator)
  end
end
