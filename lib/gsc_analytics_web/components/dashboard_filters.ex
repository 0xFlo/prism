defmodule GscAnalyticsWeb.Components.DashboardFilters do
  @moduledoc """
  Filter controls shared across dashboard screens.
  """

  use GscAnalyticsWeb, :html

  @doc """
  Renders the full filters toolbar with individual dropdowns.
  """
  attr :filter_http_status, :string, default: nil
  attr :filter_position, :string, default: nil
  attr :filter_clicks, :string, default: nil
  attr :filter_ctr, :string, default: nil
  attr :filter_backlinks, :string, default: nil
  attr :filter_redirect, :string, default: nil
  attr :filter_first_seen, :any, default: nil
  attr :filter_page_type, :string, default: nil

  def filter_bar(assigns) do
    active_count =
      [
        assigns.filter_http_status,
        assigns.filter_position,
        assigns.filter_clicks,
        assigns.filter_ctr,
        assigns.filter_backlinks,
        assigns.filter_redirect,
        assigns.filter_first_seen,
        assigns.filter_page_type
      ]
      |> Enum.reject(&is_nil/1)
      |> length()

    assigns = assign(assigns, :active_filters_count, active_count)

    ~H"""
    <div class="border-b border-slate-200 bg-slate-50/50 dark:border-slate-700 dark:bg-slate-800/50">
      <div class="px-6 py-4">
        <div class="flex flex-wrap items-center justify-between gap-4">
          <div class="flex items-center gap-2">
            <.icon name="hero-funnel" class="h-5 w-5 text-slate-600 dark:text-slate-400" />
            <h3 class="text-sm font-semibold text-slate-900 dark:text-slate-100">Filters</h3>
            <%= if @active_filters_count > 0 do %>
              <span class="badge badge-primary badge-sm">{@active_filters_count}</span>
            <% end %>
          </div>

          <%= if @active_filters_count > 0 do %>
            <button
              phx-click="clear_filters"
              class="btn btn-ghost btn-sm gap-2 text-slate-600 hover:text-slate-900 dark:text-slate-400 dark:hover:text-slate-100"
            >
              <.icon name="hero-x-mark" class="h-4 w-4" /> Clear all filters
            </button>
          <% end %>
        </div>

        <div class="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <div>
            <label class="label label-text text-xs">HTTP Status</label>
            <select
              phx-change="filter_http_status"
              name="http_status"
              class="select select-sm select-bordered w-full"
            >
              <option value="" selected={is_nil(@filter_http_status)}>All statuses</option>
              <option value="ok" selected={@filter_http_status == "ok"}>200 OK</option>
              <option value="redirect" selected={@filter_http_status == "redirect"}>
                3xx Redirect
              </option>
              <option value="broken" selected={@filter_http_status == "broken"}>
                4xx/5xx Broken
              </option>
              <option value="unchecked" selected={@filter_http_status == "unchecked"}>
                Unchecked
              </option>
            </select>
          </div>

          <div>
            <label class="label label-text text-xs">Position Range</label>
            <select
              phx-change="filter_position"
              name="position"
              class="select select-sm select-bordered w-full"
            >
              <option value="" selected={is_nil(@filter_position)}>All positions</option>
              <option value="top3" selected={@filter_position == "top3"}>Top 3 (Podium)</option>
              <option value="top10" selected={@filter_position == "top10"}>Top 10 (Page 1)</option>
              <option value="page2" selected={@filter_position == "page2"}>Page 2 (11-20)</option>
              <option value="poor" selected={@filter_position == "poor"}>Poor (&gt;20)</option>
              <option value="unranked" selected={@filter_position == "unranked"}>Unranked</option>
            </select>
          </div>

          <div>
            <label class="label label-text text-xs">Clicks</label>
            <select
              phx-change="filter_clicks"
              name="clicks"
              class="select select-sm select-bordered w-full"
            >
              <option value="" selected={is_nil(@filter_clicks)}>All click counts</option>
              <option value="10+" selected={@filter_clicks == "10+"}>10+ clicks</option>
              <option value="100+" selected={@filter_clicks == "100+"}>100+ clicks</option>
              <option value="1000+" selected={@filter_clicks == "1000+"}>
                1000+ clicks (High performers)
              </option>
              <option value="none" selected={@filter_clicks == "none"}>
                No clicks (Impressions only)
              </option>
            </select>
          </div>

          <div>
            <label class="label label-text text-xs">CTR Performance</label>
            <select phx-change="filter_ctr" name="ctr" class="select select-sm select-bordered w-full">
              <option value="" selected={is_nil(@filter_ctr)}>All CTR ranges</option>
              <option value="high" selected={@filter_ctr == "high"}>High (&gt;5%)</option>
              <option value="good" selected={@filter_ctr == "good"}>Good (3-5%)</option>
              <option value="average" selected={@filter_ctr == "average"}>Average (1-3%)</option>
              <option value="low" selected={@filter_ctr == "low"}>
                Low (&lt;1%, needs optimization)
              </option>
            </select>
          </div>

          <div>
            <label class="label label-text text-xs">Backlinks</label>
            <select
              phx-change="filter_backlinks"
              name="backlinks"
              class="select select-sm select-bordered w-full"
            >
              <option value="" selected={is_nil(@filter_backlinks)}>All backlink counts</option>
              <option value="any" selected={@filter_backlinks == "any"}>Has backlinks</option>
              <option value="none" selected={@filter_backlinks == "none"}>No backlinks</option>
              <option value="10+" selected={@filter_backlinks == "10+"}>10+ backlinks</option>
              <option value="100+" selected={@filter_backlinks == "100+"}>
                100+ backlinks (Authority)
              </option>
            </select>
          </div>

          <div>
            <label class="label label-text text-xs">Redirects</label>
            <select
              phx-change="filter_redirect"
              name="redirect"
              class="select select-sm select-bordered w-full"
            >
              <option value="" selected={is_nil(@filter_redirect)}>All redirect states</option>
              <option value="yes" selected={@filter_redirect == "yes"}>Has redirect</option>
              <option value="no" selected={@filter_redirect == "no"}>No redirect</option>
            </select>
          </div>

          <div>
            <label class="label label-text text-xs">First Seen</label>
            <select
              phx-change="filter_first_seen"
              name="first_seen"
              class="select select-sm select-bordered w-full"
            >
              <option value="" selected={is_nil(@filter_first_seen)}>All dates</option>
              <option value="7d" selected={@filter_first_seen == "7d"}>Last 7 days</option>
              <option value="30d" selected={@filter_first_seen == "30d"}>Last 30 days</option>
              <option value="90d" selected={@filter_first_seen == "90d"}>Last 90 days</option>
            </select>
          </div>

          <div>
            <label class="label label-text text-xs">Page Type</label>
            <.page_type_multiselect filter_page_type={@filter_page_type} />
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Multi-select dropdown for page types.
  """
  attr :filter_page_type, :string, default: nil

  def page_type_multiselect(assigns) do
    selected_types =
      case assigns.filter_page_type do
        nil -> []
        "" -> []
        value -> value |> String.split(",") |> Enum.map(&String.trim/1)
      end

    all_types = [
      {"homepage", "Homepage"},
      {"blog", "Blog"},
      {"documentation", "Documentation"},
      {"product", "Product"},
      {"category", "Category"},
      {"landing", "Landing Page"},
      {"legal", "Legal"},
      {"other", "Other"}
    ]

    assigns =
      assigns
      |> assign(:selected_types, selected_types)
      |> assign(:all_types, all_types)

    ~H"""
    <div class="dropdown dropdown-end w-full">
      <label tabindex="0" class="btn btn-sm btn-bordered w-full justify-between normal-case">
        <%= if Enum.empty?(@selected_types) do %>
          All page types
        <% else %>
          {length(@selected_types)} selected
        <% end %>
        <.icon name="hero-chevron-down" class="h-4 w-4 ml-2" />
      </label>
      <div
        tabindex="0"
        class="dropdown-content menu menu-compact rounded-box mt-2 w-64 bg-base-100 p-2 shadow-lg border border-base-300 z-50"
      >
        <div class="px-2 py-2 text-xs font-semibold text-slate-500 uppercase tracking-wider">
          Select Page Types
        </div>
        <li :for={{type_value, type_label} <- @all_types}>
          <label class="label cursor-pointer justify-start gap-2 py-2 px-3 hover:bg-base-200">
            <input
              type="checkbox"
              class="checkbox checkbox-sm"
              checked={type_value in @selected_types}
              phx-click="filter_page_type"
              phx-value-page_type={toggle_page_type(@selected_types, type_value)}
            />
            <span class="label-text">{type_label}</span>
          </label>
        </li>
        <%= if not Enum.empty?(@selected_types) do %>
          <div class="divider my-1"></div>
          <li>
            <button
              type="button"
              phx-click="filter_page_type"
              phx-value-page_type=""
              class="text-sm text-error hover:bg-error/10"
            >
              Clear selection
            </button>
          </li>
        <% end %>
      </div>
    </div>
    """
  end

  defp toggle_page_type(selected_types, type_value) do
    if type_value in selected_types do
      selected_types
      |> List.delete(type_value)
      |> Enum.join(",")
    else
      [type_value | selected_types]
      |> Enum.join(",")
    end
  end
end
