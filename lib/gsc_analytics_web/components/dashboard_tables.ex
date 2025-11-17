defmodule GscAnalyticsWeb.Components.DashboardTables do
  @moduledoc """
  Table-focused Phoenix function components used across dashboard experiences.
  Extracted from the legacy `DashboardComponents` mega-module to keep each concern
  small, composable, and testable.
  """

  use GscAnalyticsWeb, :html

  import GscAnalyticsWeb.Dashboard.HTMLHelpers

  alias GscAnalyticsWeb.PropertyRoutes
  alias GscAnalyticsWeb.Live.PaginationHelpers

  @doc """
  Renders a URL in breadcrumb-style hierarchical format.

  Displays URLs as: `path1 / ... / page-name` (domain omitted to save space)

  ## Attributes
  - `url` - The full URL to display (required)
  - `property_id` - Property identifier used to build the default URL detail link
  - `link_to` - The target path for the link (default: URL detail page)
  - `max_segments` - Maximum path segments to show (default: 3)

  ## Example
      <.url_breadcrumb
        url="https://scrapfly.io/blog/web-scraping/tutorial"
        property_id="scoped-property-id"
        link_to="/dashboard/<property-id>/url?url=https://scrapfly.io/blog/web-scraping/tutorial"
      />
  """
  attr :url, :string, required: true
  attr :property_id, :string, required: true
  attr :link_to, :string, default: nil
  attr :max_segments, :integer, default: 3

  def url_breadcrumb(assigns) do
    breadcrumb = parse_url_for_breadcrumb(assigns.url, max_segments: assigns.max_segments)

    assigns =
      assigns
      |> assign(:breadcrumb, breadcrumb)
      |> assign(:domain, breadcrumb.domain)
      |> assign(:has_path, breadcrumb.segments != [])
      |> assign_new(:default_link, fn ->
        PropertyRoutes.url_path(assigns.property_id, %{url: assigns.url})
      end)

    ~H"""
    <div class="flex items-center gap-1 text-xs sm:text-sm overflow-hidden min-w-0">
      <%= if @has_path do %>
        <!-- Path segments with separators -->
        <%= for {segment, index} <- Enum.with_index(@breadcrumb.segments) do %>
          <%= if index > 0 do %>
            <span class="text-slate-400 dark:text-slate-500 shrink-0">/</span>
          <% end %>

          <%= case segment.type do %>
            <% :ellipsis -> %>
              <span class="text-slate-400 dark:text-slate-500 shrink-0">...</span>
            <% :domain -> %>
              <!-- Domain prefix for single-segment URLs -->
              <span class="text-slate-500 dark:text-slate-400 shrink-0">
                {@domain}
              </span>
            <% :last -> %>
              <!-- Last segment (page name) - emphasized, clickable, truncates if too long -->
              <a
                href={@link_to || @default_link}
                class="link link-primary font-semibold hover:underline truncate max-w-xs"
                title={segment.text}
              >
                {segment.text}
              </a>
            <% :path -> %>
              <!-- Middle path segment - show fully or hide via ellipsis -->
              <span class="text-slate-600 dark:text-slate-300 shrink-0" title={segment.text}>
                {segment.text}
              </span>
          <% end %>
        <% end %>
      <% else %>
        <!-- No path - show domain only (fallback for domain-only URLs like homepage) -->
        <a
          href={@link_to || @default_link}
          class="link link-primary font-semibold hover:underline min-w-0 overflow-hidden text-ellipsis whitespace-nowrap"
          title={@breadcrumb.domain}
        >
          {@breadcrumb.domain}
        </a>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders a sortable table of URL performance data.

  ## Attributes
  - `urls` - List of URL performance maps with metrics
  - `view_mode` - Display mode ("basic" or "all") controls column visibility
  - `sort_by` - Current sort column
  - `sort_direction` - Sort direction ("asc" or "desc")
  - `account_id` - Currently selected workspace/account id (used to preserve context)
  - `property_id` - Currently selected property id (required, scopes the generated links)

  ## Example
      <.url_table
        urls={@urls}
        view_mode={@view_mode}
        sort_by={@sort_by}
        sort_direction={@sort_direction}
        property_id={@current_property_id}
      />
  """
  attr :urls, :list, required: true
  attr :view_mode, :string, default: "basic"
  attr :sort_by, :string, default: "clicks"
  attr :sort_direction, :string, default: "desc"
  attr :period_label, :string, default: "Last 30 days"
  attr :account_id, :integer, default: nil
  attr :property_id, :string, required: true

  def url_table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class={"table table-zebra #{if @view_mode == "all", do: "table-xs", else: ""}"}>
        <thead>
          <tr>
            <%= for col <- visible_columns(@view_mode) do %>
              <%= if Map.get(col, :sortable, false) do %>
                <% header_label = column_header_label(col.key, @period_label) || col.label %>
                <th
                  class={sort_header_class(Atom.to_string(col.key), @sort_by) <> " " <> col.align}
                  phx-click="sort_column"
                  phx-value-column={Atom.to_string(col.key)}
                >
                  <div class="flex items-center gap-1 #{col.align}">
                    <span>{header_label}</span>
                    <.icon
                      name={sort_icon(Atom.to_string(col.key), @sort_by, @sort_direction)}
                      class="h-4 w-4"
                    />
                  </div>
                </th>
              <% else %>
                <% header_label = column_header_label(col.key, @period_label) || col.label %>
                <th class={col.align}>{header_label}</th>
              <% end %>
            <% end %>
          </tr>
        </thead>
        <tbody>
          <%= if Enum.empty?(@urls) do %>
            <tr>
              <td
                class="py-10 text-center text-sm text-slate-500"
                colspan={Enum.count(visible_columns(@view_mode))}
              >
                No URLs found for the current filters
              </td>
            </tr>
          <% else %>
            <tr :for={url <- @urls} :key={url.url} class="hover">
              <!-- URL column with responsive width -->
              <td class="max-w-sm sm:max-w-md lg:max-w-xl xl:max-w-2xl">
                <div class="tooltip tooltip-bottom w-full" data-tip={url.url}>
                  <% params =
                    []
                    |> maybe_put_param(:url, url.url)
                    |> maybe_put_param(:account_id, @account_id) %>
                  <% link_path = PropertyRoutes.url_path(@property_id, params) %>
                  <.url_breadcrumb
                    url={url.url}
                    property_id={@property_id}
                    link_to={link_path}
                    max_segments={if @view_mode == "all", do: 2, else: 3}
                  />
                </div>
                <%= if url.redirect_url do %>
                  <div class="mt-1 flex items-center gap-1">
                    <span class="text-xs text-slate-400 dark:text-slate-500 shrink-0">→</span>
                    <div class="tooltip tooltip-bottom flex-1" data-tip={url.redirect_url}>
                      <.url_breadcrumb
                        url={url.redirect_url}
                        property_id={@property_id}
                        link_to={link_path}
                        max_segments={if @view_mode == "all", do: 2, else: 2}
                      />
                    </div>
                  </div>
                <% end %>
              </td>
              <!-- Type -->
              <%= if column_visible?(:type, @view_mode) do %>
                <td>
                  <%= if url.type do %>
                    <span class="badge badge-ghost badge-sm">{url.type}</span>
                  <% else %>
                    <span class="text-gray-400">—</span>
                  <% end %>
                </td>
              <% end %>
              <!-- Category -->
              <%= if column_visible?(:category, @view_mode) do %>
                <td>
                  <%= if url.content_category do %>
                    <span class={content_category_badge(url.content_category)}>
                      {url.content_category}
                    </span>
                  <% else %>
                    <span class="text-gray-400">—</span>
                  <% end %>
                </td>
              <% end %>
              <!-- Update Needed -->
              <%= if column_visible?(:needs_update, @view_mode) do %>
                <td class="text-center">
                  <%= if url.needs_update do %>
                    <span class="badge badge-error badge-sm">Yes</span>
                  <% else %>
                    <span class="badge badge-success badge-sm">No</span>
                  <% end %>
                </td>
              <% end %>
              <!-- Update Reason -->
              <%= if column_visible?(:update_reason, @view_mode) do %>
                <td class="text-xs">
                  {url.update_reason || "—"}
                </td>
              <% end %>
              <!-- Priority -->
              <%= if column_visible?(:update_priority, @view_mode) do %>
                <td>
                  <%= if url.update_priority do %>
                    <span class={priority_badge(url.update_priority)}>
                      {url.update_priority}
                    </span>
                  <% else %>
                    <span class="text-gray-400">—</span>
                  <% end %>
                </td>
              <% end %>
              <!-- Clicks with trend indicator -->
              <td class="text-right">
                <div class="flex items-center justify-end gap-1.5">
                  <span class="font-semibold text-green-700 dark:text-green-600">
                    {format_number(url.selected_clicks || 0)}
                  </span>
                  <%= if url.wow_growth_last4w && url.wow_growth_last4w != 0 do %>
                    <span class={"text-xs font-medium #{trend_color(url.wow_growth_last4w)}"}>
                      {trend_arrow(url.wow_growth_last4w)}{abs(Float.round(url.wow_growth_last4w, 1))}%
                    </span>
                  <% end %>
                </div>
              </td>
              <!-- Impressions (only in 'all' mode) -->
              <%= if column_visible?(:impressions, @view_mode) do %>
                <td class="text-right text-blue-600">
                  {format_number(url.selected_impressions || 0)}
                </td>
              <% end %>
              <!-- Active Since (only in 'all' mode) -->
              <%= if column_visible?(:first_seen_date, @view_mode) do %>
                <td class="text-center text-sm text-gray-600">
                  <%= if url.first_seen_date do %>
                    {Calendar.strftime(url.first_seen_date, "%b %Y")}
                  <% else %>
                    <span class="text-gray-400">—</span>
                  <% end %>
                </td>
              <% end %>
              <!-- CTR -->
              <td class="text-right">
                <%= if url.selected_ctr do %>
                  <% ctr_value = url.selected_ctr * 100 %>
                  <span class={"badge #{if @view_mode == "all", do: "badge-sm", else: ""} #{get_badge_color(ctr_value, :ctr)}"}>
                    {format_percentage(ctr_value)}
                  </span>
                <% else %>
                  <span class="text-gray-400">—</span>
                <% end %>
              </td>
              <!-- Avg Position -->
              <td class="text-right">
                <%= if url.selected_position do %>
                  <span class={"badge #{if @view_mode == "all", do: "badge-sm", else: ""} #{get_badge_color(url.selected_position, :position)}"}>
                    {format_position(url.selected_position)}
                  </span>
                <% else %>
                  <span class="text-gray-400">—</span>
                <% end %>
              </td>
              <!-- WoW Growth -->
              <%= if column_visible?(:wow_growth, @view_mode) do %>
                <td class="text-right">
                  <span class={"badge badge-sm #{get_badge_color(url.wow_growth_last4w || 0, :growth)}"}>
                    <%= if url.wow_growth_last4w && url.wow_growth_last4w != 0 do %>
                      {if url.wow_growth_last4w > 0, do: "+", else: ""}{Float.round(
                        url.wow_growth_last4w,
                        1
                      )}%
                    <% else %>
                      —
                    <% end %>
                  </span>
                </td>
              <% end %>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders a sortable table of top search queries.

  ## Attributes
  - `queries` - List of query performance maps
  - `sort_by` - Current sort column (default: "clicks")
  - `sort_direction` - Sort direction ("asc" or "desc")

  ## Example
      <.query_table
        queries={@insights.top_queries}
        sort_by={@queries_sort_by}
        sort_direction={@queries_sort_direction}
      />
  """
  attr :queries, :list, default: []
  attr :sort_by, :string, default: "clicks"
  attr :sort_direction, :string, default: "desc"

  def query_table(assigns) do
    ~H"""
    <div class="overflow-hidden rounded-2xl border border-slate-200">
      <table class="min-w-full divide-y divide-slate-200 text-sm">
        <thead class="bg-slate-50 text-left text-xs font-semibold uppercase tracking-wider text-slate-500">
          <tr>
            <th
              class={sort_header_class("query", @sort_by) <> " px-4 py-3"}
              phx-click="sort_queries"
              phx-value-column="query"
            >
              <div class="flex items-center gap-1">
                <span>Query</span>
                <.icon
                  name={sort_icon("query", @sort_by, @sort_direction)}
                  class="h-4 w-4"
                />
              </div>
            </th>
            <th
              class={sort_header_class("clicks", @sort_by) <> " px-4 py-3 text-right"}
              phx-click="sort_queries"
              phx-value-column="clicks"
            >
              <div class="flex items-center justify-end gap-1">
                <span>Clicks</span>
                <.icon
                  name={sort_icon("clicks", @sort_by, @sort_direction)}
                  class="h-4 w-4"
                />
              </div>
            </th>
            <th
              class={sort_header_class("impressions", @sort_by) <> " px-4 py-3 text-right"}
              phx-click="sort_queries"
              phx-value-column="impressions"
            >
              <div class="flex items-center justify-end gap-1">
                <span>Impressions</span>
                <.icon
                  name={sort_icon("impressions", @sort_by, @sort_direction)}
                  class="h-4 w-4"
                />
              </div>
            </th>
            <th
              class={sort_header_class("ctr", @sort_by) <> " px-4 py-3 text-right"}
              phx-click="sort_queries"
              phx-value-column="ctr"
            >
              <div class="flex items-center justify-end gap-1">
                <span>CTR</span>
                <.icon
                  name={sort_icon("ctr", @sort_by, @sort_direction)}
                  class="h-4 w-4"
                />
              </div>
            </th>
            <th
              class={sort_header_class("position", @sort_by) <> " px-4 py-3 text-right"}
              phx-click="sort_queries"
              phx-value-column="position"
            >
              <div class="flex items-center justify-end gap-1">
                <span>Position</span>
                <.icon
                  name={sort_icon("position", @sort_by, @sort_direction)}
                  class="h-4 w-4"
                />
              </div>
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-slate-100">
          <tr :for={query <- @queries} :key={query.query}>
            <td class="px-4 py-3 font-medium text-slate-800">{query.query}</td>
            <td class="px-4 py-3 text-right text-slate-600">{format_number(query.clicks)}</td>
            <td class="px-4 py-3 text-right text-slate-600">
              {format_number(query.impressions)}
            </td>
            <td class="px-4 py-3 text-right text-emerald-600">
              {format_percentage(query.ctr * 100)}
            </td>
            <td class="px-4 py-3 text-right text-slate-600">
              {format_position(query.position)}
            </td>
          </tr>
          <tr :if={Enum.empty?(@queries)}>
            <td colspan="5" class="px-4 py-12 text-center text-slate-400">
              No query data available yet for this URL.
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp maybe_put_param(params, _key, nil), do: params
  defp maybe_put_param(params, _key, ""), do: params
  defp maybe_put_param(params, key, value), do: [{key, value} | params]

  @doc """
  Renders pagination controls with page navigation and item count.

  ## Attributes
  - `current_page` - Current page number (required)
  - `total_pages` - Total number of pages (required)
  - `total_items` - Total count of items across all pages (required)
  - `per_page` - Number of items per page (required)

  ## Example
      <.pagination
        current_page={@page}
        total_pages={@total_pages}
        total_items={@total_count}
        per_page={@limit}
      />
  """
  attr :current_page, :integer, required: true
  attr :total_pages, :integer, required: true
  attr :total_items, :integer, required: true
  attr :per_page, :integer, required: true
  attr :per_page_options, :list, default: [50, 100, 200, 500]

  def pagination(assigns) do
    {start_item, end_item} =
      PaginationHelpers.calculate_item_range(
        assigns.current_page,
        assigns.per_page,
        assigns.total_items
      )

    visible_pages =
      PaginationHelpers.calculate_visible_pages(assigns.current_page, assigns.total_pages)

    assigns =
      assigns
      |> assign(:start_item, start_item)
      |> assign(:end_item, end_item)
      |> assign(:visible_pages, visible_pages)

    ~H"""
    <div class="flex flex-col sm:flex-row items-center justify-between gap-4 py-4 px-6 border-t border-slate-200">
      <div class="flex flex-col sm:flex-row sm:items-center sm:gap-6 text-sm text-slate-600">
        <div>
          Showing <span class="font-semibold text-slate-900">{@start_item}</span>
          to <span class="font-semibold text-slate-900">{@end_item}</span>
          of <span class="font-semibold text-slate-900">{format_number(@total_items)}</span>
          URLs
        </div>
        <form phx-change="change_limit" class="flex items-center gap-2">
          <label for="per-page-select" class="text-xs uppercase tracking-wide text-slate-400">
            Rows per page
          </label>
          <select
            id="per-page-select"
            name="limit"
            class="select select-bordered select-sm"
          >
            <option :for={option <- @per_page_options} value={option} selected={@per_page == option}>
              {option}
            </option>
          </select>
        </form>
      </div>
      <div class="join">
        <button
          type="button"
          phx-click="prev_page"
          disabled={@current_page == 1}
          class="join-item btn btn-sm"
          aria-label="Previous page"
        >
          «
        </button>
        <%= for page_number <- @visible_pages do %>
          <%= if page_number == :ellipsis do %>
            <button type="button" class="join-item btn btn-sm btn-disabled" disabled>
              ...
            </button>
          <% else %>
            <button
              type="button"
              phx-click="goto_page"
              phx-value-page={page_number}
              class={[
                "join-item btn btn-sm",
                @current_page == page_number && "btn-active"
              ]}
              aria-label={"Page #{page_number}"}
              aria-current={if @current_page == page_number, do: "page", else: false}
            >
              {page_number}
            </button>
          <% end %>
        <% end %>
        <button
          type="button"
          phx-click="next_page"
          disabled={@current_page == @total_pages}
          class="join-item btn btn-sm"
          aria-label="Next page"
        >
          »
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a sortable table of backlinks.

  ## Attributes
  - `backlinks` - List of backlink maps
  - `sort_by` - Current sort column (default: "first_seen_at")
  - `sort_direction` - Sort direction ("asc" or "desc")
  """
  attr :backlinks, :list, default: []
  attr :sort_by, :string, default: "first_seen_at"
  attr :sort_direction, :string, default: "desc"

  def backlinks_table(assigns) do
    ~H"""
    <div class="overflow-hidden rounded-2xl border border-slate-200">
      <table class="min-w-full divide-y divide-slate-200 text-sm">
        <thead class="bg-slate-50 text-left text-xs font-semibold uppercase tracking-wider text-slate-500">
          <tr>
            <th
              class={sort_header_class("source_domain", @sort_by) <> " px-4 py-3"}
              phx-click="sort_backlinks"
              phx-value-column="source_domain"
            >
              <div class="flex items-center gap-1">
                <span>Source Domain</span>
                <.icon name={sort_icon("source_domain", @sort_by, @sort_direction)} class="h-4 w-4" />
              </div>
            </th>
            <th
              class={sort_header_class("anchor_text", @sort_by) <> " px-4 py-3"}
              phx-click="sort_backlinks"
              phx-value-column="anchor_text"
            >
              <div class="flex items-center gap-1">
                <span>Anchor Text</span>
                <.icon name={sort_icon("anchor_text", @sort_by, @sort_direction)} class="h-4 w-4" />
              </div>
            </th>
            <th
              class={sort_header_class("domain_rating", @sort_by) <> " px-4 py-3 text-center"}
              phx-click="sort_backlinks"
              phx-value-column="domain_rating"
            >
              <div class="flex items-center justify-center gap-1">
                <span>DR</span>
                <.icon name={sort_icon("domain_rating", @sort_by, @sort_direction)} class="h-4 w-4" />
              </div>
            </th>
            <th
              class={sort_header_class("domain_traffic", @sort_by) <> " px-4 py-3 text-right"}
              phx-click="sort_backlinks"
              phx-value-column="domain_traffic"
            >
              <div class="flex items-center justify-end gap-1">
                <span>Traffic</span>
                <.icon name={sort_icon("domain_traffic", @sort_by, @sort_direction)} class="h-4 w-4" />
              </div>
            </th>
            <th
              class={sort_header_class("first_seen_at", @sort_by) <> " px-4 py-3 text-center"}
              phx-click="sort_backlinks"
              phx-value-column="first_seen_at"
            >
              <div class="flex items-center justify-center gap-1">
                <span>First Seen</span>
                <.icon name={sort_icon("first_seen_at", @sort_by, @sort_direction)} class="h-4 w-4" />
              </div>
            </th>
            <th
              class={sort_header_class("data_source", @sort_by) <> " px-4 py-3 text-center"}
              phx-click="sort_backlinks"
              phx-value-column="data_source"
            >
              <div class="flex items-center justify-center gap-1">
                <span>Source</span>
                <.icon name={sort_icon("data_source", @sort_by, @sort_direction)} class="h-4 w-4" />
              </div>
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-slate-100">
          <tr :for={backlink <- @backlinks} :key={"#{backlink.source_url}-#{backlink.first_seen_at}"}>
            <td class="px-4 py-3">
              <a
                href={backlink.source_url}
                target="_blank"
                rel="noopener noreferrer"
                class="link link-primary font-medium hover:underline"
              >
                {backlink.source_domain || URI.parse(backlink.source_url).host || backlink.source_url}
              </a>
            </td>
            <td class="max-w-md px-4 py-3 text-slate-600">
              <div class="truncate" title={backlink.anchor_text}>
                {backlink.anchor_text || "—"}
              </div>
            </td>
            <td class="px-4 py-3 text-center">
              <%= if backlink.domain_rating do %>
                <span class="badge badge-sm badge-primary font-semibold">
                  {backlink.domain_rating}
                </span>
              <% else %>
                <span class="text-slate-400">—</span>
              <% end %>
            </td>
            <td class="px-4 py-3 text-right text-slate-600">
              <%= if backlink.domain_traffic do %>
                {format_number(backlink.domain_traffic)}
              <% else %>
                <span class="text-slate-400">—</span>
              <% end %>
            </td>
            <td class="px-4 py-3 text-center text-slate-600">
              {format_date(backlink.first_seen_at)}
            </td>
            <td class="px-4 py-3 text-center">
              <span class={badge_class_for_source(backlink.data_source)}>
                {backlink.data_source}
              </span>
            </td>
          </tr>
          <tr :if={Enum.empty?(@backlinks)}>
            <td colspan="6" class="px-4 py-12 text-center text-slate-400">
              No backlinks found for this URL.
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp column_header_label(:clicks, period_label), do: "Clicks · #{period_label}"
  defp column_header_label(:impressions, period_label), do: "Impressions · #{period_label}"
  defp column_header_label(:ctr, period_label), do: "CTR · #{period_label}"
  defp column_header_label(:position, period_label), do: "Position · #{period_label}"
  defp column_header_label(_key, _period_label), do: nil
end
