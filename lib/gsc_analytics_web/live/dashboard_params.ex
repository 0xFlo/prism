defmodule GscAnalyticsWeb.Live.DashboardParams do
  @moduledoc """
  Shared parsing and formatting helpers for dashboard query parameters.

  Centralising this logic keeps the main and single-url dashboards in sync and
  prevents unsafe conversions (e.g. `String.to_atom/1` on user input).
  """

  @default_period 30
  @all_period 10_000

  @series_map %{
    "clicks" => :clicks,
    "impressions" => :impressions,
    "ctr" => :ctr,
    "position" => :position
  }

  @series_inverse Map.new(@series_map, fn {string, atom} -> {atom, string} end)
  @default_series [:clicks, :impressions]

  @doc """
  Parse user supplied period values (days) from query parameters.
  """
  @spec parse_period(term()) :: pos_integer()
  def parse_period(nil), do: @default_period
  def parse_period(""), do: @default_period
  def parse_period("all"), do: @all_period

  def parse_period(value) when value in ["7", "30", "90", "180", "365"],
    do: String.to_integer(value)

  def parse_period(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> @default_period
    end
  end

  def parse_period(value) when is_integer(value) and value > 0, do: value
  def parse_period(_), do: @default_period

  @doc """
  Decode the comma separated series list into a list of allowed metrics.

  Unknown or blank values are dropped; defaults are returned when nothing valid
  is provided.
  """
  @spec parse_visible_series(term()) :: [:clicks | :impressions | :ctr | :position, ...]
  def parse_visible_series(value) when value in [nil, ""], do: @default_series

  def parse_visible_series(value) when is_binary(value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&Map.get(@series_map, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> case do
      [] -> @default_series
      series -> series
    end
  end

  def parse_visible_series(_), do: @default_series

  @doc """
  Encode a list of metrics into a comma separated string suitable for URLs.
  """
  @spec encode_series(list(atom())) :: String.t()
  def encode_series(series) when is_list(series) do
    series
    |> Enum.map(&Map.get(@series_inverse, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.join(",")
  end

  @doc """
  Human readable label for a period length (in days or the special all-time value).
  """
  @spec period_label(pos_integer()) :: String.t()
  def period_label(7), do: "Last 7 days"
  def period_label(30), do: "Last 30 days"
  def period_label(90), do: "Last 90 days"
  def period_label(180), do: "Last 6 months"
  def period_label(365), do: "Last 12 months"
  def period_label(@all_period), do: "All time"
  def period_label(value) when is_integer(value) and value > 0, do: "#{value} days"
  def period_label(_), do: "Selected period"

  @doc """
  Build a sanitized params map for the main dashboard view.

  Accepts a struct or assigns map (anything implementing the Access behaviour).
  """
  @spec build_dashboard_query(map(), map()) :: keyword()
  def build_dashboard_query(assigns, overrides \\ %{}) do
    overrides = Map.new(overrides)

    [
      {:view_mode, Map.get(overrides, :view_mode, Map.get(assigns, :view_mode))},
      {:sort_by, Map.get(overrides, :sort_by, Map.get(assigns, :sort_by))},
      {:sort_direction, Map.get(overrides, :sort_direction, Map.get(assigns, :sort_direction))},
      {:limit, Map.get(overrides, :limit, Map.get(assigns, :limit))},
      {:page, Map.get(overrides, :page, Map.get(assigns, :page))},
      {:chart_view, Map.get(overrides, :chart_view, Map.get(assigns, :chart_view))},
      {:search, Map.get(overrides, :search, Map.get(assigns, :search))},
      {:period, Map.get(overrides, :period, Map.get(assigns, :period_days))},
      {:property_id, Map.get(overrides, :property_id, Map.get(assigns, :current_property_id))},
      {:account_id, Map.get(overrides, :account_id, Map.get(assigns, :current_account_id))},
      {:series,
       Map.get(
         overrides,
         :series,
         encode_series(Map.get(assigns, :visible_series, @default_series))
       )}
    ]
    |> reject_blank_values()
  end

  @doc """
  Build a params map for the single URL dashboard view.
  """
  @spec build_url_query(map(), map()) :: keyword()
  def build_url_query(assigns, overrides \\ %{}) do
    overrides = Map.new(overrides)

    [
      {:url, Map.get(overrides, :url, Map.get(assigns, :encoded_url) || "")},
      {:view, Map.get(overrides, :view, Map.get(assigns, :chart_view))},
      {:period, Map.get(overrides, :period, Map.get(assigns, :period_days))},
      {:queries_sort, Map.get(overrides, :queries_sort, Map.get(assigns, :queries_sort_by))},
      {:queries_dir, Map.get(overrides, :queries_dir, Map.get(assigns, :queries_sort_direction))},
      {:backlinks_sort,
       Map.get(overrides, :backlinks_sort, Map.get(assigns, :backlinks_sort_by))},
      {:backlinks_dir,
       Map.get(overrides, :backlinks_dir, Map.get(assigns, :backlinks_sort_direction))},
      {:series,
       Map.get(
         overrides,
         :series,
         encode_series(Map.get(assigns, :visible_series, @default_series))
       )},
      {:account_id, Map.get(overrides, :account_id, Map.get(assigns, :current_account_id))},
      {:property_id, Map.get(overrides, :property_id, Map.get(assigns, :current_property_id))}
    ]
    |> reject_blank_values()
  end

  defp reject_blank_values(params) do
    params
    |> Enum.reduce([], fn
      {:url, value}, acc -> [{:url, value} | acc]
      {_key, value}, acc when value in [nil, ""] -> acc
      entry, acc -> [entry | acc]
    end)
    |> Enum.reverse()
  end
end
