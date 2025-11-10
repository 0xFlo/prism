defmodule GscAnalyticsWeb.Router.PropertyScopedRoutes do
  @moduledoc false

  defmacro property_live(path, module, action \\ :index) do
    property_path = inject_property_segment(path)

    quote do
      live unquote(property_path), unquote(module), unquote(action)
    end
  end

  defmacro property_get(path, module, action) do
    property_path = inject_property_segment(path)

    quote do
      get unquote(property_path), unquote(module), unquote(action)
    end
  end

  defp inject_property_segment(path) when is_binary(path) do
    unless String.starts_with?(path, "/dashboard") do
      raise ArgumentError,
            "property_* helpers only support /dashboard routes, got #{inspect(path)}"
    end

    if String.contains?(path, ":property_id") do
      raise ArgumentError,
            "property_* helpers expect a path without :property_id, got #{inspect(path)}"
    end

    case path do
      "/dashboard" -> "/dashboard/:property_id"
      "/dashboard" <> rest -> "/dashboard/:property_id" <> rest
    end
  end
end
