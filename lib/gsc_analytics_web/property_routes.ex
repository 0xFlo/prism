defmodule GscAnalyticsWeb.PropertyRoutes do
  @moduledoc """
  Helper functions for generating dashboard URLs that stay scoped to the
  currently selected workspace property. Legacy query parameters have been
  removed, so callers must always pass the property segment explicitly.
  """

  use GscAnalyticsWeb, :verified_routes

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def dashboard_path(property_id, params \\ []) do
    build_path!(property_id, "", params)
  end

  def keywords_path(property_id, params \\ []) do
    build_path!(property_id, "/keywords", params)
  end

  def sync_path(property_id, params \\ []) do
    build_path!(property_id, "/sync", params)
  end

  def crawler_path(property_id, params \\ []) do
    build_path!(property_id, "/crawler", params)
  end

  def workflows_path(property_id, params \\ []) do
    build_path!(property_id, "/workflows", params)
  end

  def workflow_edit_path(property_id, workflow_id, params \\ []) do
    suffix = "/workflows/#{workflow_id}/edit"
    build_path!(property_id, suffix, params)
  end

  def url_path(property_id, params \\ []) do
    build_path!(property_id, "/url", params)
  end

  def export_path(property_id, params \\ []) do
    build_path!(property_id, "/export", params)
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp build_path!(property_id, suffix, params) do
    if property_id in [nil, ""] do
      raise ArgumentError,
            "property_id is required for dashboard route #{suffix}"
    end

    "/dashboard/#{property_id}"
    |> append_suffix(suffix)
    |> append_query(params)
  end

  defp append_suffix(path, ""), do: path
  defp append_suffix(path, suffix), do: path <> suffix

  defp append_query(path, params) do
    params
    |> normalize_params()
    |> case do
      %{} = map when map_size(map) == 0 ->
        path

      %{} = map ->
        path <> "?" <> URI.encode_query(map)
    end
  end

  defp normalize_params(params) when is_map(params), do: params
  defp normalize_params(params) when is_list(params), do: Enum.into(params, %{})
  defp normalize_params(_), do: %{}
end
