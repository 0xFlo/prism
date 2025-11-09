defmodule GscAnalyticsWeb.Presenters.DashboardUrlHelpers do
  @moduledoc """
  Pure presentation helpers shared by the Dashboard URL LiveView and templates.
  """

  use GscAnalyticsWeb, :verified_routes

  alias GscAnalyticsWeb.Live.DashboardParams

  @doc """
  Human-friendly label for the chart resolution dropdown.
  """
  @spec chart_view_label(String.t()) :: String.t()
  def chart_view_label("weekly"), do: "Weekly trend"
  def chart_view_label("monthly"), do: "Monthly trend"
  def chart_view_label(_), do: "Daily trend"

  @doc """
  Sort query rows according to the requested column + direction.
  """
  @spec sort_queries(map(), String.t(), String.t()) :: map()
  def sort_queries(insights, sort_by, direction) do
    case Map.get(insights, :top_queries) do
      queries when is_list(queries) ->
        sorted =
          Enum.sort_by(
            queries,
            fn query ->
              case sort_by do
                "query" -> query.query
                "clicks" -> query.clicks
                "impressions" -> query.impressions
                "ctr" -> query.ctr
                "position" -> query.position
                _ -> query.clicks
              end
            end,
            if(direction == "asc", do: :asc, else: :desc)
          )

        %{insights | top_queries: sorted}

      _ ->
        insights
    end
  end

  @doc """
  Sort backlink rows according to the requested column + direction.
  """
  @spec sort_backlinks(map(), String.t(), String.t()) :: map()
  def sort_backlinks(insights, sort_by, direction) do
    case Map.get(insights, :backlinks) do
      backlinks when is_list(backlinks) ->
        sorted =
          Enum.sort_by(
            backlinks,
            fn backlink ->
              case sort_by do
                "source_domain" -> backlink.source_domain || backlink.source_url
                "anchor_text" -> backlink.anchor_text || ""
                "domain_rating" -> backlink.domain_rating || 0
                "domain_traffic" -> backlink.domain_traffic || 0
                "first_seen_at" -> backlink.first_seen_at || ~U[1970-01-01 00:00:00Z]
                "data_source" -> backlink.data_source
                _ -> backlink.first_seen_at || ~U[1970-01-01 00:00:00Z]
              end
            end,
            if(direction == "asc", do: :asc, else: :desc)
          )

        %{insights | backlinks: sorted}

      _ ->
        insights
    end
  end

  @doc """
  Build the dashboard and export links so they stay in sync with the URL view.
  """
  @spec dashboard_links(map()) :: %{return_path: String.t(), export_path: String.t()}
  def dashboard_links(assigns) do
    base = %{
      current_account_id: Map.get(assigns, :current_account_id),
      current_property_id: Map.get(assigns, :current_property_id),
      chart_view: Map.get(assigns, :chart_view),
      period_days: Map.get(assigns, :period_days),
      visible_series: Map.get(assigns, :visible_series, [:clicks, :impressions])
    }

    dashboard_query = DashboardParams.build_dashboard_query(base)

    dashboard_path =
      if dashboard_query == [] do
        ~p"/dashboard"
      else
        ~p"/dashboard?#{dashboard_query}"
      end

    export_query =
      DashboardParams.build_dashboard_query(
        base,
        %{limit: 100, sort_by: "clicks", view_mode: "basic"}
      )

    export_path =
      if export_query == [] do
        ~p"/dashboard/export"
      else
        ~p"/dashboard/export?#{export_query}"
      end

    %{return_path: dashboard_path, export_path: export_path}
  end
end
