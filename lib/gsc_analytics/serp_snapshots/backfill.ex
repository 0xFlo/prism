defmodule GscAnalytics.SerpSnapshots.Backfill do
  @moduledoc """
  Backfills legacy SERP snapshots with enriched competitor, content-type, and
  ScrapFly citation metadata. Designed for incremental, resumable runs.
  """

  import Ecto.Query

  alias GscAnalytics.DataSources.SERP.Core.HTMLParser
  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.SerpSnapshot

  require Logger

  @default_batch_size 100

  @type summary :: %{
          batch_size: pos_integer(),
          dry_run: boolean(),
          errors: list(),
          last_processed_at: DateTime.t() | nil,
          last_processed_id: String.t() | nil,
          limit: integer() | nil,
          skipped: non_neg_integer(),
          total: non_neg_integer(),
          updated: non_neg_integer()
        }

  @doc """
  Runs the backfill.

  ## Options
  * `:batch_size` – rows per query (default #{ @default_batch_size })
  * `:limit` – max rows to process (handy for rehearsals)
  * `:dry_run` – when true, only reports potential changes
  * `:resume_after` – ISO8601 timestamp to skip older rows
  """
  @spec run(keyword()) :: {:ok, summary()} | {:error, term()}
  def run(opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    limit = Keyword.get(opts, :limit)
    dry_run? = Keyword.get(opts, :dry_run, false)
    resume_after = Keyword.get(opts, :resume_after)

    with {:ok, resume_dt} <- parse_resume_option(resume_after) do
      base_query =
        SerpSnapshot
        |> where([s], not is_nil(s.raw_response))
        |> where(
          [s],
          fragment("coalesce(array_length(?, 1), 0) = 0", s.competitors) or
            fragment("coalesce(array_length(?, 1), 0) = 0", s.content_types_present) or
            (s.ai_overview_present and is_nil(s.scrapfly_citation_position) and
               s.scrapfly_mentioned_in_ao == false)
        )

      base_query =
        if resume_dt do
          from s in base_query, where: s.inserted_at > ^resume_dt
        else
          base_query
        end

      initial_stats = %{
        batch_size: batch_size,
        dry_run: dry_run?,
        errors: [],
        last_processed_at: nil,
        last_processed_id: nil,
        limit: limit,
        skipped: 0,
        total: 0,
        updated: 0
      }

      Logger.info("Starting SERP snapshot backfill",
        batch_size: batch_size,
        dry_run: dry_run?,
        limit: limit,
        resume_after: resume_after
      )

      process_batches(base_query, batch_size, limit, dry_run?, initial_stats, nil)
    end
  end

  defp parse_resume_option(nil), do: {:ok, nil}

  defp parse_resume_option(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> {:ok, dt}
      {:error, reason} -> {:error, {:invalid_resume_after, reason}}
    end
  end

  defp process_batches(_query, _batch_size, limit, _dry_run?, stats, _cursor)
       when is_integer(limit) and stats.total >= limit do
    Logger.info("SERP snapshot backfill complete (limit reached)", stats)
    {:ok, stats}
  end

  defp process_batches(base_query, batch_size, limit, dry_run?, stats, cursor) do
    query =
      base_query
      |> order_by([s], asc: s.inserted_at, asc: s.id)
      |> limit(^batch_size)
      |> apply_cursor(cursor)

    batch = Repo.all(query)

    if batch == [] do
      Logger.info("SERP snapshot backfill complete", stats)
      {:ok, stats}
    else
      {updated_stats, last_snapshot} =
        Enum.reduce_while(batch, {stats, cursor}, fn snapshot, {acc, _} ->
          cond do
            limit && acc.total >= limit ->
              {:halt, {acc, snapshot_cursor(snapshot)}}

            true ->
              case maybe_update_snapshot(snapshot, dry_run?) do
                {:ok, status} ->
                  acc = update_stats(acc, snapshot, status)
                  {:cont, {acc, snapshot_cursor(snapshot)}}

                {:error, reason} ->
                  acc = record_error(acc, snapshot, reason)
                  {:cont, {acc, snapshot_cursor(snapshot)}}
              end
          end
        end)

      process_batches(base_query, batch_size, limit, dry_run?, updated_stats, last_snapshot)
    end
  end

  defp apply_cursor(query, nil), do: query

  defp apply_cursor(query, %{inserted_at: inserted_at, id: id}) do
    from s in query,
      where: s.inserted_at > ^inserted_at or (s.inserted_at == ^inserted_at and s.id > ^id)
  end

  defp snapshot_cursor(nil), do: nil

  defp snapshot_cursor(snapshot) do
    %{inserted_at: snapshot.inserted_at, id: snapshot.id}
  end

  defp maybe_update_snapshot(snapshot, dry_run?) do
    parsed = HTMLParser.parse_serp_response(snapshot.raw_response, snapshot.url || "")

    competitors =
      parsed
      |> Map.get(:competitors, [])
      |> SerpSnapshot.migrate_competitors()

    content_types =
      case Map.get(parsed, :content_types_present) do
        list when is_list(list) and list != [] -> list
        _ -> SerpSnapshot.content_types_from_competitors(competitors)
      end

    {scrapfly_flag, scrapfly_position} =
      SerpSnapshot.scrapfly_citation_stats(snapshot.ai_overview_citations)

    attrs = %{
      competitors: competitors,
      content_types_present: content_types,
      scrapfly_mentioned_in_ao: scrapfly_flag,
      scrapfly_citation_position: scrapfly_position
    }

    changeset = SerpSnapshot.changeset(snapshot, attrs)

    cond do
      changeset.changes == %{} ->
        {:ok, :skipped}

      dry_run? ->
        {:ok, :updated}

      true ->
        case Repo.update(changeset) do
          {:ok, _} -> {:ok, :updated}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp update_stats(stats, snapshot, status) do
    stats
    |> Map.update!(:total, &(&1 + 1))
    |> Map.put(:last_processed_id, snapshot.id)
    |> Map.put(:last_processed_at, snapshot.inserted_at)
    |> then(fn acc ->
      case status do
        :updated -> Map.update!(acc, :updated, fn count -> count + 1 end)
        :skipped -> Map.update!(acc, :skipped, fn count -> count + 1 end)
      end
    end)
  end

  defp record_error(stats, snapshot, reason) do
    entry = %{id: snapshot.id, reason: inspect(reason)}

    stats
    |> Map.update!(:total, &(&1 + 1))
    |> Map.put(:last_processed_id, snapshot.id)
    |> Map.put(:last_processed_at, snapshot.inserted_at)
    |> Map.update!(:errors, fn errors -> (errors ++ [entry]) |> Enum.take(-10) end)
  end
end
