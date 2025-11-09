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

  # Filter whitelists
  @valid_http_statuses ["ok", "broken", "redirect", "unchecked"]
  @valid_position_ranges ["top3", "top10", "page1", "page2", "poor", "unranked"]
  @valid_clicks_thresholds ["10+", "100+", "1000+", "none"]
  @valid_ctr_ranges ["high", "good", "average", "low"]
  @valid_backlink_filters ["any", "none", "10+", "100+"]
  @valid_redirect_filters ["yes", "no"]
  @valid_date_shortcuts ["7d", "30d", "90d"]

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

  # ============================================================================
  # FILTER PARSING FUNCTIONS
  # ============================================================================

  @doc """
  Parse HTTP status filter from query parameters.

  Valid values: "ok", "broken", "redirect", "unchecked"
  Returns nil for invalid/blank values (no filter applied).
  """
  @spec parse_http_status(term()) :: String.t() | nil
  def parse_http_status(nil), do: nil
  def parse_http_status(""), do: nil
  def parse_http_status(status) when status in @valid_http_statuses, do: status
  def parse_http_status(_), do: nil

  @doc """
  Parse position range filter from query parameters.

  Valid values: "top3", "top10", "page1", "page2", "poor", "unranked"
  Returns nil for invalid/blank values (no filter applied).
  """
  @spec parse_position_range(term()) :: String.t() | nil
  def parse_position_range(nil), do: nil
  def parse_position_range(""), do: nil
  def parse_position_range(range) when range in @valid_position_ranges, do: range
  def parse_position_range(_), do: nil

  @doc """
  Parse clicks threshold filter from query parameters.

  Valid values: "10+", "100+", "1000+", "none"
  Returns nil for invalid/blank values (no filter applied).
  """
  @spec parse_clicks_threshold(term()) :: String.t() | nil
  def parse_clicks_threshold(nil), do: nil
  def parse_clicks_threshold(""), do: nil
  def parse_clicks_threshold(threshold) when threshold in @valid_clicks_thresholds, do: threshold
  def parse_clicks_threshold(_), do: nil

  @doc """
  Parse CTR range filter from query parameters.

  Valid values: "high", "good", "average", "low"
  Returns nil for invalid/blank values (no filter applied).
  """
  @spec parse_ctr_range(term()) :: String.t() | nil
  def parse_ctr_range(nil), do: nil
  def parse_ctr_range(""), do: nil
  def parse_ctr_range(range) when range in @valid_ctr_ranges, do: range
  def parse_ctr_range(_), do: nil

  @doc """
  Parse backlink count filter from query parameters.

  Valid values: "any", "none", "10+", "100+"
  Returns nil for invalid/blank values (no filter applied).
  """
  @spec parse_backlink_count(term()) :: String.t() | nil
  def parse_backlink_count(nil), do: nil
  def parse_backlink_count(""), do: nil
  def parse_backlink_count(filter) when filter in @valid_backlink_filters, do: filter
  def parse_backlink_count(_), do: nil

  @doc """
  Parse redirect filter from query parameters.

  Valid values: "yes", "no"
  Returns nil for invalid/blank values (no filter applied).
  """
  @spec parse_has_redirect(term()) :: String.t() | nil
  def parse_has_redirect(nil), do: nil
  def parse_has_redirect(""), do: nil
  def parse_has_redirect(filter) when filter in @valid_redirect_filters, do: filter
  def parse_has_redirect(_), do: nil

  @doc """
  Parse first seen date filter from query parameters.

  Accepts:
  - Date shortcuts: "7d", "30d", "90d" (converted to Date struct)
  - ISO 8601 date strings: "2024-01-15" (parsed to Date struct)
  - nil/"" (no filter)

  Returns Date struct or nil.
  """
  @spec parse_first_seen_after(term()) :: Date.t() | String.t() | nil
  def parse_first_seen_after(nil), do: nil
  def parse_first_seen_after(""), do: nil

  def parse_first_seen_after(shortcut) when shortcut in @valid_date_shortcuts, do: shortcut

  def parse_first_seen_after(date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> date
      {:error, _} -> nil
    end
  end

  def parse_first_seen_after(_), do: nil

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
       )},
      # Filter parameters
      {:http_status, Map.get(overrides, :http_status, Map.get(assigns, :filter_http_status))},
      {:position, Map.get(overrides, :position, Map.get(assigns, :filter_position))},
      {:clicks, Map.get(overrides, :clicks, Map.get(assigns, :filter_clicks))},
      {:ctr, Map.get(overrides, :ctr, Map.get(assigns, :filter_ctr))},
      {:backlinks, Map.get(overrides, :backlinks, Map.get(assigns, :filter_backlinks))},
      {:redirect, Map.get(overrides, :redirect, Map.get(assigns, :filter_redirect))},
      {:first_seen, Map.get(overrides, :first_seen, Map.get(assigns, :filter_first_seen))}
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
