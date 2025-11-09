defmodule GscAnalyticsWeb.Dashboard.Columns do
  @moduledoc """
  Single source of truth for dashboard column definitions.
  Used by both HTML templates and CSV export.
  """

  alias GscAnalyticsWeb.Dashboard.HTMLHelpers

  @valid_view_modes ["basic", "all"]

  @doc """
  Define all available columns with their properties.
  Each column has:
  - key: internal identifier
  - label: display name
  - visible_in: list of view modes where this column appears
  - getter: function to extract value from row data
  - formatter: function to format value for display (HTML or CSV)
  - align: CSS alignment class
  - sortable: whether this column can be sorted (default: false)
  """
  def columns do
    [
      %{
        key: :url,
        label: "URL",
        visible_in: [:basic, :all],
        getter: & &1.url,
        formatter: &format_url/2,
        align: "text-left",
        sortable: false
      },
      %{
        key: :type,
        label: "Type",
        visible_in: [:all],
        getter: & &1.type,
        formatter: &format_nullable/2,
        align: "text-left",
        sortable: false
      },
      %{
        key: :category,
        label: "Category",
        visible_in: [:all],
        getter: & &1.content_category,
        formatter: &format_nullable/2,
        align: "text-left",
        sortable: false
      },
      %{
        key: :needs_update,
        label: "Update Needed",
        visible_in: [:all],
        getter: & &1.needs_update,
        formatter: &format_boolean/2,
        align: "text-center",
        sortable: false
      },
      %{
        key: :update_reason,
        label: "Update Reason",
        visible_in: [:all],
        getter: & &1.update_reason,
        formatter: &format_nullable/2,
        align: "text-left",
        sortable: false
      },
      %{
        key: :update_priority,
        label: "Priority",
        visible_in: [:all],
        getter: & &1.update_priority,
        formatter: &format_nullable/2,
        align: "text-left",
        sortable: false
      },
      %{
        key: :clicks,
        label: "Clicks",
        visible_in: [:basic, :all],
        getter: & &1.selected_clicks,
        formatter: &format_number/2,
        align: "text-right",
        sortable: true
      },
      %{
        key: :impressions,
        label: "Impressions",
        visible_in: [:all],
        getter: & &1.selected_impressions,
        formatter: &format_number/2,
        align: "text-right",
        sortable: true
      },
      %{
        key: :ctr,
        label: "CTR",
        visible_in: [:basic, :all],
        getter: & &1.selected_ctr,
        formatter: &format_ctr/2,
        align: "text-right",
        sortable: true
      },
      %{
        key: :position,
        label: "Position",
        visible_in: [:basic, :all],
        getter: & &1.selected_position,
        formatter: &format_position/2,
        align: "text-right",
        sortable: true
      },
      %{
        key: :http_status,
        label: "HTTP Status",
        visible_in: [:all],
        getter: & &1.http_status,
        formatter: &format_http_status/2,
        align: "text-center",
        sortable: true
      },
      %{
        key: :backlinks,
        label: "Backlinks",
        visible_in: [:all],
        getter: & &1.backlink_count,
        formatter: &format_number/2,
        align: "text-right",
        sortable: true
      },
      %{
        key: :first_seen_date,
        label: "Active Since",
        visible_in: [:all],
        getter: & &1.first_seen_date,
        formatter: &format_date/2,
        align: "text-center",
        sortable: true
      },
      %{
        key: :wow_growth,
        label: "WoW Growth %",
        visible_in: [:all],
        getter: & &1.wow_growth_last4w,
        formatter: &format_wow_growth/2,
        align: "text-right",
        sortable: false
      },
      %{
        key: :status,
        label: "Status",
        visible_in: [],
        getter: & &1.data_available,
        formatter: &format_status/2,
        align: "text-center",
        sortable: false
      }
    ]
  end

  @doc """
  Validate and normalize view mode, falling back to "basic" if invalid
  """
  def validate_view_mode(view_mode) when view_mode in @valid_view_modes, do: view_mode
  def validate_view_mode(_), do: "basic"

  @doc """
  Get columns visible for a specific view mode
  """
  def visible_columns(view_mode) do
    valid_mode = validate_view_mode(view_mode)
    mode_atom = String.to_existing_atom(valid_mode)
    Enum.filter(columns(), fn col -> mode_atom in col.visible_in end)
  end

  @doc """
  Generate CSV headers for a view mode
  """
  def csv_headers(view_mode) do
    view_mode
    |> visible_columns()
    |> Enum.map(& &1.label)
  end

  @doc """
  Generate CSV row for a data row in a view mode
  """
  def csv_row(row, view_mode) do
    view_mode
    |> visible_columns()
    |> Enum.map(fn col ->
      value = col.getter.(row)
      col.formatter.(value, :csv)
    end)
  end

  # Formatters - each takes (value, format) where format is :html or :csv

  defp format_url(url, :csv), do: escape_csv_field(url)
  # Template handles link rendering
  defp format_url(url, :html), do: url

  defp format_nullable(nil, _), do: "—"
  defp format_nullable(value, :csv), do: escape_csv_field(value)
  defp format_nullable(value, :html), do: value

  defp format_boolean(true, :csv), do: "Yes"
  defp format_boolean(false, :csv), do: "No"
  defp format_boolean(true, :html), do: true
  defp format_boolean(false, :html), do: false

  defp format_number(num, _format) when is_integer(num), do: to_string(num)
  defp format_number(num, _format) when is_float(num), do: num |> trunc() |> to_string()
  defp format_number(nil, _), do: "0"

  defp format_ctr(ctr, :csv) when is_float(ctr) do
    HTMLHelpers.format_percentage(ctr * 100)
  end

  defp format_ctr(ctr, :html), do: ctr

  defp format_position(pos, :csv) when is_float(pos), do: Float.to_string(pos)
  defp format_position(pos, :csv) when is_integer(pos), do: to_string(pos)
  defp format_position(nil, :csv), do: "—"
  defp format_position(pos, :html), do: pos

  defp format_wow_growth(nil, _), do: "—"
  defp format_wow_growth(0, _), do: "—"
  defp format_wow_growth(growth, _) when is_float(growth) and growth == 0.0, do: "—"

  defp format_wow_growth(growth, :csv) when is_float(growth) do
    sign = if growth > 0, do: "+", else: ""
    "#{sign}#{Float.round(growth, 1)}%"
  end

  defp format_wow_growth(growth, :html), do: growth

  defp format_status(true, :csv), do: "Active"
  defp format_status(false, :csv), do: "No Data"
  defp format_status(status, :html), do: status

  defp format_date(nil, _), do: "—"
  defp format_date(%Date{} = date, :csv), do: Date.to_string(date)
  defp format_date(%Date{} = date, :html), do: date

  defp format_http_status(nil, _), do: "—"
  defp format_http_status(status, _) when is_integer(status), do: to_string(status)

  defp escape_csv_field(field) when is_binary(field) do
    if String.contains?(field, [",", "\n", "\""]) do
      "\"" <> String.replace(field, "\"", "\"\"") <> "\""
    else
      field
    end
  end

  defp escape_csv_field(field), do: to_string(field)
end
