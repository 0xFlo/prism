defmodule GscAnalyticsWeb.DashboardRedirectController do
  use GscAnalyticsWeb, :controller

  alias GscAnalyticsWeb.PropertyContext
  alias GscAnalyticsWeb.PropertyRoutes

  def dashboard(conn, params) do
    redirect_to_property(conn, &PropertyRoutes.dashboard_path/2, params)
  end

  def export(conn, params) do
    redirect_to_property(conn, &PropertyRoutes.export_path/2, params)
  end

  defp redirect_to_property(conn, path_fun, params) do
    scope = conn.assigns[:current_scope]

    case PropertyContext.default_property_id(scope) do
      nil ->
        conn
        |> put_flash(:info, "Select a Search Console property to continue.")
        |> redirect(to: ~p"/users/settings")

      property_id ->
        redirect(conn, to: path_fun.(property_id, Map.delete(params, "property_id")))
    end
  end
end
