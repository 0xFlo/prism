defmodule GscAnalytics.SerpChecks do
  @moduledoc """
  Orchestrates bulk SERP checks (keyword selection, run persistence, PubSub progress).
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Phoenix.PubSub
  alias Oban

  alias GscAnalytics.Repo
  alias GscAnalytics.SerpChecks.TopQuerySelector
  alias GscAnalytics.Schemas.{SerpCheckRun, SerpCheckRunKeyword}
  alias GscAnalytics.Workers.SerpCheckWorker

  @pubsub GscAnalytics.PubSub
  @topic_prefix "serp_check_run"

  @default_keyword_limit 7
  @scrapfly_credit_cost 36

  @doc """
  Subscribe the caller to real-time updates for the given run id.
  """
  def subscribe(run_id) when is_binary(run_id) do
    PubSub.subscribe(@pubsub, topic(run_id))
  end

  @doc """
  Returns the topic for broadcasting run updates.
  """
  def topic(run_id), do: "#{@topic_prefix}:#{run_id}"

  @doc """
  Kick off a bulk SERP check for the provided scope/url.

  Returns `{:ok, run, keywords}` on success so the caller can render immediately,
  or `{:error, reason}` when the prerequisites fail (no keywords, validation, etc.).
  """
  def start_bulk_check(current_scope, account_id, property_url, url, opts \\ %{}) do
    keyword_limit = Map.get(opts, :keyword_limit, @default_keyword_limit)
    geo = Map.get(opts, :geo, "us")
    period_days = Map.get(opts, :period_days, 30)

    with {:ok, keywords} <-
           TopQuerySelector.top_queries_for_url(
             current_scope,
             account_id,
             property_url,
             url,
             limit: keyword_limit,
             period_days: period_days,
             geo: geo
           ),
         {:ok, %{run: run, keyword_rows: keyword_rows}} <-
           create_run(account_id, property_url, url, keywords) do
      :telemetry.execute(
        [:gsc_analytics, :serp_checks, :bulk_start],
        %{keyword_count: length(keyword_rows), estimated_cost: run.estimated_cost},
        %{account_id: account_id, property_url: property_url}
      )

      enqueue_jobs(run, keyword_rows, geo)

      full_run = preload_keywords(run)

      PubSub.broadcast(
        @pubsub,
        topic(run.id),
        {:serp_check_progress, %{event: :run_started, run: full_run}}
      )

      {:ok, full_run}
    end
  end

  @doc """
  Fetch the latest run for a URL (if any) including keyword rows sorted by inserted order.
  """
  def latest_run(account_id, property_url, url) do
    SerpCheckRun
    |> where(
      [r],
      r.account_id == ^account_id and r.property_url == ^property_url and r.url == ^url
    )
    |> order_by([r], desc: r.inserted_at)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> nil
      run -> preload_keywords(run)
    end
  end

  @doc """
  Update per-keyword status as a worker starts processing it.
  """
  def mark_keyword_running(run_keyword_id) do
    case update_keyword(run_keyword_id, %{status: :running, completed_at: nil, error: nil}) do
      {:ok, keyword} ->
        broadcast_run(keyword.serp_check_run_id)
        {:ok, keyword}

      error ->
        error
    end
  end

  @doc """
  Called when a SERP check succeeds. Updates keyword + run counters and broadcasts.
  """
  def mark_keyword_success(run_keyword_id, attrs) do
    case update_keyword(run_keyword_id, %{status: :success, completed_at: DateTime.utc_now()}) do
      {:ok, keyword} -> finalize_run(keyword.serp_check_run_id, :success, attrs)
      error -> error
    end
  end

  @doc """
  Called when a SERP check fails permanently.
  """
  def mark_keyword_failed(run_keyword_id, error_msg) do
    case update_keyword(run_keyword_id, %{
           status: :failed,
           completed_at: DateTime.utc_now(),
           error: error_msg
         }) do
      {:ok, keyword} -> finalize_run(keyword.serp_check_run_id, :failed, %{error: error_msg})
      error -> error
    end
  end

  @doc """
  Broadcast the latest status for a run.
  """
  def broadcast_run(run_id) do
    if run = Repo.get(SerpCheckRun, run_id) |> preload_keywords() do
      PubSub.broadcast(
        @pubsub,
        topic(run.id),
        {:serp_check_progress, %{event: :run_updated, run: run}}
      )
    end
  end

  defp finalize_run(run_id, status, attrs) do
    Repo.transaction(fn ->
      {counts, new_status} = rollup_status(run_id, status)

      set_values =
        %{
          succeeded_count: counts.succeeded,
          failed_count: counts.failed,
          status: new_status
        }
        |> maybe_put(:last_error, attrs[:error])
        |> maybe_put(:finished_at, finish_time(new_status))
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)

      from(r in SerpCheckRun, where: r.id == ^run_id)
      |> Repo.update_all(set: set_values)

      run = Repo.get!(SerpCheckRun, run_id) |> preload_keywords()

      PubSub.broadcast(
        @pubsub,
        topic(run.id),
        {:serp_check_progress, %{event: :run_updated, run: run}}
      )

      {:ok, run}
    end)
  end

  defp rollup_status(run_id, latest_status) do
    run = Repo.get!(SerpCheckRun, run_id)

    succeeded =
      Repo.aggregate(
        from(k in SerpCheckRunKeyword,
          where: k.serp_check_run_id == ^run_id and k.status == :success
        ),
        :count,
        :id
      )

    failed =
      Repo.aggregate(
        from(k in SerpCheckRunKeyword,
          where: k.serp_check_run_id == ^run_id and k.status == :failed
        ),
        :count,
        :id
      )

    total = run.keyword_count

    new_status =
      cond do
        succeeded + failed == total and failed == 0 -> :complete
        succeeded + failed == total and failed > 0 -> :partial
        latest_status == :failed -> :running
        true -> :running
      end

    {%{succeeded: succeeded, failed: failed}, new_status}
  end

  defp finish_time(:complete), do: DateTime.utc_now()
  defp finish_time(:partial), do: DateTime.utc_now()
  defp finish_time(:failed), do: DateTime.utc_now()
  defp finish_time(_), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp update_keyword(run_keyword_id, attrs) do
    Repo.get!(SerpCheckRunKeyword, run_keyword_id)
    |> SerpCheckRunKeyword.changeset(attrs)
    |> Repo.update()
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  defp preload_keywords(nil), do: nil

  defp preload_keywords(run) do
    Repo.preload(run, keywords: from(k in SerpCheckRunKeyword, order_by: [asc: k.inserted_at]))
  end

  defp create_run(account_id, property_url, url, keywords) do
    keyword_count = length(keywords)

    if keyword_count == 0 do
      {:error, :no_keywords}
    else
      estimated_cost = keyword_count * @scrapfly_credit_cost

      Multi.new()
      |> Multi.insert(
        :run,
        SerpCheckRun.changeset(%SerpCheckRun{}, %{
          account_id: account_id,
          property_url: property_url,
          url: url,
          keyword_count: keyword_count,
          estimated_cost: estimated_cost,
          status: :running,
          started_at: DateTime.utc_now()
        })
      )
      |> Multi.run(:keyword_rows, fn _repo, %{run: run} ->
        entries =
          Enum.map(keywords, fn keyword ->
            %{
              serp_check_run_id: run.id,
              keyword: keyword[:keyword],
              geo: keyword[:geo] || "us",
              inserted_at: DateTime.utc_now(),
              updated_at: DateTime.utc_now()
            }
          end)

        case Repo.insert_all(SerpCheckRunKeyword, entries, returning: true) do
          {_, rows} -> {:ok, rows}
        end
      end)
      |> Repo.transaction()
      |> case do
        {:ok, result} -> {:ok, %{run: result.run, keyword_rows: result.keyword_rows}}
        {:error, _op, reason, _} -> {:error, reason}
      end
    end
  end

  defp enqueue_jobs(run, keyword_rows, geo) do
    job_changesets =
      Enum.map(keyword_rows, fn keyword ->
        keyword_value = Map.get(keyword, :keyword) || Map.get(keyword, "keyword")
        geo_value = Map.get(keyword, :geo) || Map.get(keyword, "geo") || geo
        keyword_row_id = Map.get(keyword, :id) || Map.get(keyword, "id")

        SerpCheckWorker.new(%{
          "account_id" => run.account_id,
          "property_url" => run.property_url,
          "url" => run.url,
          "keyword" => keyword_value,
          "geo" => geo_value,
          "run_id" => run.id,
          "run_keyword_id" => keyword_row_id
        })
      end)

    Oban.insert_all(job_changesets)
  end
end
