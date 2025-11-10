defmodule GscAnalytics.Workflows.Steps.QueryStep do
  @moduledoc """
  Executes database queries to find URLs matching specific criteria.

  ## Configuration

  ```elixir
  %{
    "type" => "query",
    "config" => %{
      "query_type" => "aging_content" | "broken_links" | "low_ctr",
      "params" => %{
        # For aging_content:
        "days_threshold" => 90,

        # For broken_links:
        "status_codes" => [404, 500, 503],

        # For low_ctr:
        "min_impressions" => 100,
        "max_ctr" => 2.0
      }
    }
  }
  ```

  ## Output

  Returns a map with:
  - `urls`: List of URL strings
  - `count`: Total number of URLs found
  - `query_type`: The query type executed
  """

  alias GscAnalytics.{Repo, Schemas.UrlLifetimeStats, Schemas.UrlMetadata}
  import Ecto.Query

  @doc """
  Executes the configured query and returns matching URLs.
  """
  def execute(step_config, _context, account_id) do
    query_type = get_in(step_config, ["config", "query_type"])
    params = get_in(step_config, ["config", "params"]) || %{}

    case query_type do
      "aging_content" ->
        execute_aging_content_query(account_id, params)

      "broken_links" ->
        execute_broken_links_query(account_id, params)

      "low_ctr" ->
        execute_low_ctr_query(account_id, params)

      _ ->
        {:error, "Unknown query_type: #{query_type}"}
    end
  end

  defp execute_aging_content_query(account_id, params) do
    days_threshold = params["days_threshold"] || 90
    cutoff_date = Date.utc_today() |> Date.add(-days_threshold)

    urls =
      from(m in UrlMetadata,
        join: u in UrlLifetimeStats,
        on: m.url == u.url and m.account_id == u.account_id,
        where: m.account_id == ^account_id,
        where: not is_nil(m.publish_date),
        where: m.publish_date <= ^cutoff_date,
        where: u.lifetime_clicks > 0,
        select: m.url,
        order_by: [asc: m.publish_date]
      )
      |> Repo.all()

    {:ok,
     %{
       "urls" => urls,
       "count" => length(urls),
       "query_type" => "aging_content",
       "days_threshold" => days_threshold
     }}
  end

  defp execute_broken_links_query(account_id, params) do
    status_codes = params["status_codes"] || [404, 500, 503]

    urls =
      from(u in UrlLifetimeStats,
        where: u.account_id == ^account_id,
        where: u.http_status in ^status_codes,
        where: u.lifetime_clicks > 0,
        select: u.url,
        order_by: [desc: u.lifetime_clicks]
      )
      |> Repo.all()

    {:ok,
     %{
       "urls" => urls,
       "count" => length(urls),
       "query_type" => "broken_links",
       "status_codes" => status_codes
     }}
  end

  defp execute_low_ctr_query(account_id, params) do
    min_impressions = params["min_impressions"] || 100
    max_ctr = params["max_ctr"] || 2.0

    urls =
      from(u in UrlLifetimeStats,
        where: u.account_id == ^account_id,
        where: u.lifetime_impressions >= ^min_impressions,
        where: u.avg_ctr < ^max_ctr,
        where: u.lifetime_clicks > 0,
        select: u.url,
        order_by: [desc: u.lifetime_impressions]
      )
      |> Repo.all()

    {:ok,
     %{
       "urls" => urls,
       "count" => length(urls),
       "query_type" => "low_ctr",
       "min_impressions" => min_impressions,
       "max_ctr" => max_ctr
     }}
  end
end
