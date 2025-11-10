defmodule GscAnalyticsWeb.Dashboard.ExportController do
  use GscAnalyticsWeb, :controller

  alias GscAnalytics.ContentInsights
  alias GscAnalytics.Dashboard, as: DashboardUtils
  alias GscAnalyticsWeb.Dashboard.Columns
  alias GscAnalyticsWeb.PropertyContext

  def export_csv(conn, params) do
    scope = conn.assigns[:current_scope]
    property_id = params["property_id"]

    limit = DashboardUtils.normalize_limit(params["limit"])
    sort_by = normalize_sort_by(params["sort_by"])
    view_mode = Columns.validate_view_mode(params["view_mode"] || "basic")
    period_days = parse_period(params["period"] || "30")

    with {:ok, property} <- PropertyContext.fetch_property(scope, property_id) do
      result =
        ContentInsights.list_urls(%{
          limit: limit,
          sort_by: sort_by,
          period_days: period_days,
          account_id: property.workspace_id,
          property_url: property.property_url
        })

      csv_content = generate_csv_content(result.urls, view_mode)

      filename =
        "gsc-analytics-#{view_mode}-#{sort_by}-#{Date.to_string(Date.utc_today())}.csv"

      conn
      |> put_resp_content_type("text/csv")
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
      |> send_resp(200, csv_content)
    else
      {:error, reason} ->
        conn
        |> put_flash(:error, property_error_message(reason))
        |> redirect(to: PropertyContext.default_dashboard_path(scope))
    end
  end

  # Private helpers

  defp property_error_message(:unauthenticated),
    do: "Please sign in to choose a workspace."

  defp property_error_message(:not_found),
    do: "We couldn't find that property. Please choose another workspace."

  defp property_error_message(:unauthorized),
    do: "That property does not belong to your workspace."

  defp property_error_message(:no_accounts),
    do: "Create a workspace to export analytics."

  defp property_error_message(:no_property),
    do: "Select a Search Console property to export analytics."

  defp generate_csv_content(data, view_mode) do
    headers = Columns.csv_headers(view_mode)
    header_line = Enum.join(headers, ",") <> "\n"

    data_lines =
      data
      |> Enum.map(fn row ->
        row
        |> Columns.csv_row(view_mode)
        |> Enum.join(",")
      end)
      |> Enum.join("\n")

    header_line <> data_lines
  end

  defp parse_period(nil), do: 30
  defp parse_period("7"), do: 7
  defp parse_period("30"), do: 30
  defp parse_period("90"), do: 90
  defp parse_period("180"), do: 180
  defp parse_period("365"), do: 365
  defp parse_period("all"), do: 10000
  defp parse_period(value) when is_integer(value) and value > 0, do: value

  defp parse_period(value) when is_binary(value) do
    case Integer.parse(value) do
      {days, ""} when days > 0 -> days
      _ -> 30
    end
  end

  defp parse_period(_), do: 30

  defp normalize_sort_by(nil), do: "clicks"
  defp normalize_sort_by(""), do: "clicks"

  defp normalize_sort_by(sort_by) when sort_by in ["clicks", "impressions", "ctr", "position"],
    do: sort_by

  defp normalize_sort_by("lifetime_clicks"), do: "clicks"
  defp normalize_sort_by("period_clicks"), do: "clicks"
  defp normalize_sort_by("period_impressions"), do: "impressions"
  defp normalize_sort_by("lifetime_avg_ctr"), do: "ctr"
  defp normalize_sort_by("lifetime_avg_position"), do: "position"
  defp normalize_sort_by(other) when is_binary(other), do: other
  defp normalize_sort_by(_), do: "clicks"
end
