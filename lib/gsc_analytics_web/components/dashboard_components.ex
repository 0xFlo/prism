defmodule GscAnalyticsWeb.Components.DashboardComponents do
  @moduledoc """
  Reusable Phoenix LiveView 1.1+ function components for the GSC Analytics dashboard.

  ## Best Practices Implemented:
  - Type-safe `attr` declarations for all props
  - Slots for customizable content
  - LiveView 1.1 :for comprehensions with :key attributes for optimal change tracking
  - Proper separation of concerns (presentation logic in components)
  """

  use GscAnalyticsWeb, :html

  import GscAnalyticsWeb.Dashboard.HTMLHelpers

  @doc """
  Renders a URL in breadcrumb-style hierarchical format.

  Displays URLs as: `domain / path1 / ... / page-name`

  ## Attributes
  - `url` - The full URL to display (required)
  - `link_to` - The target path for the link (default: URL detail page)
  - `max_segments` - Maximum path segments to show (default: 3)

  ## Example
      <.url_breadcrumb
        url="https://scrapfly.io/blog/web-scraping/tutorial"
        link_to="/dashboard/url?url=https://scrapfly.io/blog/web-scraping/tutorial"
      />
  """
  attr :url, :string, required: true
  attr :link_to, :string, default: nil
  attr :max_segments, :integer, default: 3

  def url_breadcrumb(assigns) do
    breadcrumb = parse_url_for_breadcrumb(assigns.url, max_segments: assigns.max_segments)

    assigns =
      assigns
      |> assign(:breadcrumb, breadcrumb)
      |> assign(:has_path, breadcrumb.segments != [])

    ~H"""
    <div class="flex items-center gap-1 font-mono text-xs sm:text-sm overflow-hidden">
      <!-- Domain (always visible, muted) -->
      <span class="text-slate-500 dark:text-slate-400 shrink-0">
        {@breadcrumb.domain}
      </span>

      <%= if @has_path do %>
        <!-- Path segments with separators -->
        <%= for segment <- @breadcrumb.segments do %>
          <span class="text-slate-400 dark:text-slate-500 shrink-0">/</span>

          <%= case segment.type do %>
            <% :ellipsis -> %>
              <span class="text-slate-400 dark:text-slate-500 shrink-0">...</span>
            <% :last -> %>
              <!-- Last segment (page name) - emphasized and clickable -->
              <a
                href={@link_to || ~p"/dashboard/url?url=#{@url}"}
                class="link link-primary font-semibold truncate hover:underline"
                title={segment.text}
              >
                {segment.text}
              </a>
            <% :path -> %>
              <!-- Middle path segment -->
              <span class="text-slate-600 dark:text-slate-300 truncate" title={segment.text}>
                {segment.text}
              </span>
          <% end %>
        <% end %>
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
  - `property_id` - Currently selected property id (optional, preserves property context)

  ## Example
      <.url_table
        urls={@urls}
        view_mode={@view_mode}
        sort_by={@sort_by}
        sort_direction={@sort_direction}
      />
  """
  attr :urls, :list, required: true
  attr :view_mode, :string, default: "basic"
  attr :sort_by, :string, default: "clicks"
  attr :sort_direction, :string, default: "desc"
  attr :period_label, :string, default: "Last 30 days"
  attr :account_id, :integer, default: nil
  attr :property_id, :string, default: nil

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
              <!-- URL column -->
              <td class={"#{if @view_mode == "all", do: "max-w-sm", else: "max-w-md"}"}>
                <div class="tooltip tooltip-right" data-tip={url.url}>
                  <% params =
                    []
                    |> maybe_put_param(:url, url.url)
                    |> maybe_put_param(:account_id, @account_id)
                    |> maybe_put_param(:property_id, @property_id) %>
                  <a
                    href={~p"/dashboard/url?#{params}"}
                    class={"link link-primary font-mono #{if @view_mode == "all", do: "text-xs", else: "text-sm"}"}
                  >
                    {truncate_url(url.url, if(@view_mode == "all", do: 40, else: 60))}
                  </a>
                </div>
                <%= if url.redirect_url do %>
                  <div class="text-xs text-gray-500 mt-1 font-mono flex items-center gap-1">
                    <span>→</span>
                    <span class="truncate" title={url.redirect_url}>
                      {truncate_url(url.redirect_url, if(@view_mode == "all", do: 35, else: 50))}
                    </span>
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
              <!-- Clicks -->
              <td class="text-right font-semibold text-green-700">
                {format_number(url.selected_clicks || 0)}
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
    # Calculate range being displayed
    start_item = (assigns.current_page - 1) * assigns.per_page + 1
    end_item = min(assigns.current_page * assigns.per_page, assigns.total_items)

    # Generate visible page numbers with ellipsis
    visible_pages = calculate_visible_pages(assigns.current_page, assigns.total_pages)

    assigns =
      assigns
      |> assign(:start_item, start_item)
      |> assign(:end_item, end_item)
      |> assign(:visible_pages, visible_pages)

    ~H"""
    <div class="flex flex-col sm:flex-row items-center justify-between gap-4 py-4 px-6 border-t border-slate-200">
      <!-- Items info -->
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
      <!-- Pagination controls -->
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

  ## Example
      <.backlinks_table
        backlinks={@insights.backlinks}
        sort_by={@backlinks_sort_by}
        sort_direction={@backlinks_sort_direction}
      />
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
                <.icon
                  name={sort_icon("source_domain", @sort_by, @sort_direction)}
                  class="h-4 w-4"
                />
              </div>
            </th>
            <th
              class={sort_header_class("anchor_text", @sort_by) <> " px-4 py-3"}
              phx-click="sort_backlinks"
              phx-value-column="anchor_text"
            >
              <div class="flex items-center gap-1">
                <span>Anchor Text</span>
                <.icon
                  name={sort_icon("anchor_text", @sort_by, @sort_direction)}
                  class="h-4 w-4"
                />
              </div>
            </th>
            <th
              class={sort_header_class("domain_rating", @sort_by) <> " px-4 py-3 text-center"}
              phx-click="sort_backlinks"
              phx-value-column="domain_rating"
            >
              <div class="flex items-center justify-center gap-1">
                <span>DR</span>
                <.icon
                  name={sort_icon("domain_rating", @sort_by, @sort_direction)}
                  class="h-4 w-4"
                />
              </div>
            </th>
            <th
              class={sort_header_class("domain_traffic", @sort_by) <> " px-4 py-3 text-right"}
              phx-click="sort_backlinks"
              phx-value-column="domain_traffic"
            >
              <div class="flex items-center justify-end gap-1">
                <span>Traffic</span>
                <.icon
                  name={sort_icon("domain_traffic", @sort_by, @sort_direction)}
                  class="h-4 w-4"
                />
              </div>
            </th>
            <th
              class={sort_header_class("first_seen_at", @sort_by) <> " px-4 py-3 text-center"}
              phx-click="sort_backlinks"
              phx-value-column="first_seen_at"
            >
              <div class="flex items-center justify-center gap-1">
                <span>First Seen</span>
                <.icon
                  name={sort_icon("first_seen_at", @sort_by, @sort_direction)}
                  class="h-4 w-4"
                />
              </div>
            </th>
            <th
              class={sort_header_class("data_source", @sort_by) <> " px-4 py-3 text-center"}
              phx-click="sort_backlinks"
              phx-value-column="data_source"
            >
              <div class="flex items-center justify-center gap-1">
                <span>Source</span>
                <.icon
                  name={sort_icon("data_source", @sort_by, @sort_direction)}
                  class="h-4 w-4"
                />
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

  # Private helper functions

  defp column_header_label(:clicks, period_label), do: "Clicks · #{period_label}"
  defp column_header_label(:impressions, period_label), do: "Impressions · #{period_label}"
  defp column_header_label(:ctr, period_label), do: "CTR · #{period_label}"
  defp column_header_label(:position, period_label), do: "Position · #{period_label}"
  defp column_header_label(_key, _period_label), do: nil

  @doc false
  defp calculate_visible_pages(_current, total) when total <= 7 do
    # If 7 or fewer pages, show all
    Enum.to_list(1..total)
  end

  defp calculate_visible_pages(current, total) when current <= 4 do
    # Near the start: [1, 2, 3, 4, 5, ..., last]
    [1, 2, 3, 4, 5, :ellipsis, total]
  end

  defp calculate_visible_pages(current, total) when current >= total - 3 do
    # Near the end: [1, ..., last-4, last-3, last-2, last-1, last]
    [1, :ellipsis, total - 4, total - 3, total - 2, total - 1, total]
  end

  defp calculate_visible_pages(current, total) do
    # In the middle: [1, ..., current-1, current, current+1, ..., last]
    [1, :ellipsis, current - 1, current, current + 1, :ellipsis, total]
  end

  @doc """
  Renders a group of toggle buttons with active state styling.

  ## Attributes
  - `options` - List of maps with :value and :label keys
  - `current_value` - The currently selected value
  - `event_name` - The Phoenix event to trigger on click
  - `value_key` - The parameter key name for the phx-value attribute

  ## Example
      <.toggle_button_group
        options={[
          %{value: "daily", label: "Daily"},
          %{value: "weekly", label: "Weekly"}
        ]}
        current_value={@chart_view}
        event_name="change_chart_view"
        value_key="chart_view"
      />
  """
  attr :options, :list, required: true
  attr :current_value, :any, required: true
  attr :event_name, :string, required: true
  attr :value_key, :string, required: true

  def toggle_button_group(assigns) do
    # Build dynamic phx-value attributes for each option
    assigns =
      assign(assigns, :options_with_attrs, fn ->
        Enum.map(assigns.options, fn option ->
          option
          |> Map.put(:phx_value_attr, %{assigns.value_key => option.value})
          |> Map.put(:active?, toggle_active?(assigns.current_value, option.value))
        end)
      end)

    ~H"""
    <div class="flex flex-wrap items-center gap-2 rounded-full border border-slate-200/60 bg-slate-100/80 p-1 text-xs font-semibold text-slate-600 shadow-sm shadow-slate-200/40">
      <button
        :for={option <- @options_with_attrs.()}
        type="button"
        phx-click={@event_name}
        {Map.new(option.phx_value_attr, fn {k, v} -> {"phx-value-#{k}", v} end)}
        class={[
          "rounded-full px-3 py-1.5 transition-all duration-150 ease-out focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:ring-slate-400",
          option.active? &&
            "bg-slate-900 text-white shadow-sm shadow-slate-900/25 hover:bg-slate-900/90",
          !option.active? &&
            "text-slate-600 hover:text-slate-900 hover:bg-white/70 hover:shadow-sm hover:shadow-slate-200/60"
        ]}
        aria-label={option.label}
        data-state={if(option.active?, do: "active", else: "inactive")}
      >
        {option.label}
      </button>
    </div>
    """
  end

  defp toggle_active?(current_value, option_value) do
    current =
      case current_value do
        value when is_binary(value) -> value
        value when is_integer(value) -> Integer.to_string(value)
        value -> to_string(value)
      end

    cond do
      option_value == "all" and current in ["all", "10000"] -> true
      true -> current == option_value
    end
  end

  @doc """
  Renders a compact select dropdown for time controls (Datafast-style).

  ## Attributes
  - `options` - List of option maps with :value and :label keys
  - `current_value` - The currently selected value
  - `event_name` - Phoenix event to trigger on change
  - `value_key` - The parameter key for the phx-value attribute
  - `class` - Optional additional CSS classes

  ## Example
      <.compact_select
        options={[
          %{value: "daily", label: "Daily"},
          %{value: "weekly", label: "Weekly"}
        ]}
        current_value={@chart_view}
        event_name="change_chart_view"
        value_key="chart_view"
      />
  """
  attr :options, :list, required: true
  attr :current_value, :any, required: true
  attr :event_name, :string, required: true
  attr :value_key, :string, required: true
  attr :class, :string, default: ""

  def compact_select(assigns) do
    ~H"""
    <select
      phx-change={@event_name}
      name={@value_key}
      class={[
        "select select-sm select-bordered bg-white dark:bg-slate-800 dark:border-slate-600 dark:text-slate-200",
        @class
      ]}
    >
      <option
        :for={option <- @options}
        value={option.value}
        selected={compact_select_active?(@current_value, option.value)}
      >
        {option.label}
      </option>
    </select>
    """
  end

  defp compact_select_active?(current_value, option_value) do
    current =
      case current_value do
        value when is_binary(value) -> value
        value when is_integer(value) -> Integer.to_string(value)
        value -> to_string(value)
      end

    cond do
      option_value == "all" and current in ["all", "10000"] -> true
      true -> current == option_value
    end
  end

  @doc """
  Renders a metric card with primary value and secondary stats.

  ## Attributes
  - `label` - The card title/label
  - `value` - The primary metric value (clicks)
  - `impressions` - Secondary metric (impressions count)
  - `ctr` - Secondary metric (CTR percentage)
  - `class` - Optional additional CSS classes

  ## Example
      <.metric_card
        label="This month"
        value={@stats.current_month.total_clicks}
        impressions={@stats.current_month.total_impressions}
        ctr={@stats.current_month.avg_ctr}
      />
  """
  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :impressions, :integer, required: true
  attr :ctr, :float, required: true
  attr :class, :string, default: ""

  def metric_card(assigns) do
    ~H"""
    <div class={"rounded-2xl border border-white/20 bg-white/10 px-5 py-4 #{@class}"}>
      <p class="text-xs uppercase tracking-[0.3em] text-slate-200">
        {@label}
      </p>
      <p class="mt-2 text-3xl font-semibold text-white">
        {format_number(@value)}
      </p>
      <p class="mt-2 text-sm text-slate-200">
        {format_number(@impressions)} impressions | {format_percentage(@ctr)} CTR
      </p>
    </div>
    """
  end

  @doc """
  Renders a property selector dropdown with favicons.

  Displays a dropdown menu for selecting Google Search Console properties.
  Shows website favicons next to property labels for better visual identification.
  Supports both map-based options (with favicon URLs) and legacy tuple format.

  ## Attributes
  - `property_options` - List of property options (maps or tuples)
  - `property_label` - Label for currently selected property
  - `property_favicon_url` - Favicon URL for currently selected property (optional)
  - `current_property_id` - ID of currently selected property
  - `empty_message` - Message to show when no property is selected (optional)

  ## Examples

      # With favicon support (recommended)
      <.property_selector
        property_options={@property_options}
        property_label={@property_label}
        property_favicon_url={@property_favicon_url}
        current_property_id={@current_property_id}
      />

      # Legacy format (tuples)
      <.property_selector
        property_options={[{"Domain: example.com", "uuid"}]}
        property_label="Domain: example.com"
        current_property_id="uuid"
      />
  """
  attr :property_options, :list, default: []
  attr :property_label, :string, default: nil
  attr :property_favicon_url, :string, default: nil
  attr :current_property_id, :string, default: nil
  attr :empty_message, :string, default: "No property selected"

  def property_selector(assigns) do
    ~H"""
    <%= if Enum.empty?(@property_options) do %>
      <%= if @property_label do %>
        <span class="text-base font-medium text-slate-900 dark:text-slate-100">
          {@property_label}
        </span>
      <% else %>
        <span class="text-base font-medium text-slate-500 dark:text-slate-400">
          {@empty_message}
        </span>
      <% end %>
    <% else %>
      <div class="dropdown dropdown-end">
        <label tabindex="0" class="btn btn-ghost gap-2 normal-case text-base font-medium">
          <%= if @property_favicon_url do %>
            <img src={@property_favicon_url} alt="" class="w-4 h-4 flex-shrink-0" />
          <% end %>
          <%= if @property_label do %>
            {@property_label}
          <% else %>
            Select property
          <% end %>
          <.icon name="hero-chevron-down" class="h-4 w-4" />
        </label>
        <ul
          tabindex="0"
          class="dropdown-content menu menu-compact rounded-box mt-3 w-80 bg-base-100 p-2 shadow-lg border border-base-300 max-h-96 overflow-y-auto"
        >
          <%= for option <- @property_options do %>
            <% {label, id, favicon_url} =
              case option do
                %{label: l, id: i, favicon_url: f} -> {l, i, f}
                {l, i} -> {l, i, nil}
              end %>
            <%= if id != @current_property_id do %>
              <li>
                <button
                  phx-click="switch_property"
                  phx-value-property_id={id}
                  class="flex items-center gap-2"
                >
                  <%= if favicon_url do %>
                    <img src={favicon_url} alt="" class="w-4 h-4 flex-shrink-0" />
                  <% else %>
                    <.icon name="hero-globe-alt" class="w-4 h-4 flex-shrink-0" />
                  <% end %>
                  <span class="truncate">{label}</span>
                </button>
              </li>
            <% end %>
          <% end %>
        </ul>
      </div>
    <% end %>
    """
  end

  @doc """
  Shared toolbar for dashboard screens (property selector, period dropdown, chart view dropdown).

  Set `show_property_selector?` to false when the property picker should be hidden (e.g. single URL view).
  """
  attr :property_options, :list, default: []
  attr :property_label, :string, default: nil
  attr :property_favicon_url, :string, default: nil
  attr :current_property_id, :string, default: nil
  attr :show_property_selector?, :boolean, default: true

  attr :period_label, :string, required: true
  attr :period_days, :any, required: true
  attr :period_event, :string, default: "change_period"

  attr :chart_view_label, :string, required: true
  attr :chart_view, :string, required: true
  attr :chart_view_event, :string, default: "change_chart_view"
  attr :chart_view_value_keys, :list, default: ["chart_view"]

  attr :period_options, :list, default: nil
  attr :chart_view_options, :list, default: nil
  attr :class, :string, default: ""

  def dashboard_controls(assigns) do
    assigns =
      assigns
      |> assign(:period_options, assigns.period_options || default_period_options())
      |> assign(:chart_view_options, assigns.chart_view_options || default_chart_view_options())

    ~H"""
    <div class={["flex flex-wrap items-center gap-3", @class]}>
      <div :if={@show_property_selector?}>
        <.property_selector
          property_options={@property_options}
          property_label={@property_label}
          property_favicon_url={@property_favicon_url}
          current_property_id={@current_property_id}
        />
      </div>

      <button
        type="button"
        class="btn btn-sm btn-circle btn-ghost"
        title="Previous period"
      >
        <.icon name="hero-chevron-left" class="h-4 w-4" />
      </button>

      <div class="dropdown dropdown-end">
        <label tabindex="0" class="btn btn-ghost gap-2 normal-case text-base font-medium">
          {@period_label}
          <.icon name="hero-chevron-down" class="h-4 w-4" />
        </label>
        <ul
          tabindex="0"
          class="dropdown-content menu menu-compact rounded-box mt-3 w-52 bg-base-100 p-2 shadow-lg border border-base-300"
        >
          <li :for={option <- @period_options}>
            <button
              phx-click={@period_event}
              phx-value-period={option.value}
              class={[
                period_active?(@period_days, option.value) && "active"
              ]}
            >
              {option.label}
            </button>
          </li>
        </ul>
      </div>

      <button
        type="button"
        class="btn btn-sm btn-circle btn-ghost"
        title="Next period"
      >
        <.icon name="hero-chevron-right" class="h-4 w-4" />
      </button>

      <div class="dropdown dropdown-end">
        <label tabindex="0" class="btn btn-ghost gap-2 normal-case text-base font-medium">
          {@chart_view_label}
          <.icon name="hero-chevron-down" class="h-4 w-4" />
        </label>
        <ul
          tabindex="0"
          class="dropdown-content menu menu-compact rounded-box mt-3 w-40 bg-base-100 p-2 shadow-lg border border-base-300"
        >
          <li :for={option <- @chart_view_options}>
            <% value_attrs =
              Enum.map(@chart_view_value_keys, fn key ->
                {"phx-value-#{key}", option.value}
              end) %>
            <button
              phx-click={@chart_view_event}
              {value_attrs}
              data-state={if(@chart_view == option.value, do: "active", else: "inactive")}
              class={[
                @chart_view == option.value && "active"
              ]}
            >
              {option.label}
            </button>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  @doc """
  Renders an interactive metric card that toggles chart series visibility.

  ## Attributes
  - `metric` - The metric identifier (:clicks, :impressions, or :ctr)
  - `value` - The metric value (number or string)
  - `label` - The metric label/name
  - `subtitle` - Description text (e.g., "Last 7 days")
  - `active` - Boolean indicating if this series is visible in the chart
  - `interactive` - Boolean indicating if this card is clickable (default: true)

  ## Example
      <.interactive_metric_card
        metric={:clicks}
        value={8144}
        label="Clicks"
        subtitle="Last 7 days"
        active={:clicks in @visible_series}
        interactive={true}
      />
  """
  attr :metric, :atom, required: true
  attr :value, :any, required: true
  attr :label, :string, required: true
  attr :subtitle, :string, required: true
  attr :active, :boolean, required: true
  attr :interactive, :boolean, default: true

  def interactive_metric_card(assigns) do
    # Define color scheme matching Chart.js series configuration
    # These colors match the ones in chartjs_performance_chart.js seriesConfig
    {border_color, check_color_light, check_color_dark, bg_color_light, bg_color_dark,
     pulse_color} =
      case assigns.metric do
        :clicks ->
          {"border-indigo-500", "text-indigo-600", "text-indigo-400", "bg-indigo-50",
           "bg-indigo-500/10", "bg-indigo-500/20"}

        :impressions ->
          {"border-emerald-500", "text-emerald-600", "text-emerald-400", "bg-emerald-50",
           "bg-emerald-500/10", "bg-emerald-500/20"}

        :ctr ->
          {"border-purple-500", "text-purple-600", "text-purple-400", "bg-purple-50",
           "bg-purple-500/10", "bg-purple-500/20"}

        :position ->
          {"border-red-500", "text-red-600", "text-red-400", "bg-red-50", "bg-red-500/10",
           "bg-red-500/20"}

        _ ->
          {"border-slate-500", "text-slate-600", "text-slate-400", "bg-slate-50",
           "bg-slate-500/10", "bg-slate-500/20"}
      end

    assigns =
      assigns
      |> assign(:border_color, border_color)
      |> assign(:check_color, "#{check_color_light} dark:#{check_color_dark}")
      |> assign(:bg_color_light, bg_color_light)
      |> assign(:bg_color_dark, bg_color_dark)
      |> assign(:pulse_color, pulse_color)

    ~H"""
    <div
      class={[
        "relative rounded-lg p-5 transition-all duration-300 ease-out",
        @interactive &&
          "cursor-pointer hover:shadow-lg hover:scale-[1.02] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:ring-indigo-500",
        @interactive && @active &&
          [
            "border-2",
            @border_color,
            @bg_color_light,
            "dark:#{@bg_color_dark}",
            "bg-white dark:bg-slate-800 shadow-md"
          ],
        @interactive && !@active &&
          "border border-slate-300 dark:border-slate-600 bg-white dark:bg-slate-800/70 hover:border-slate-400 dark:hover:border-slate-500",
        !@interactive && "border border-slate-300 dark:border-slate-600 bg-white dark:bg-slate-800/70"
      ]}
      phx-click={@interactive && "toggle_series"}
      phx-value-metric={@interactive && Atom.to_string(@metric)}
      role={@interactive && "button"}
      aria-pressed={@interactive && @active}
      tabindex={@interactive && "0"}
      aria-label={@interactive && "Toggle #{@label} series in chart"}
      aria-describedby={"#{@metric}-description"}
    >
      <%= if @interactive && @active do %>
        <div class={"absolute inset-0 rounded-lg #{@pulse_color} animate-pulse opacity-20 pointer-events-none"}>
        </div>
      <% end %>

      <div class="flex items-start justify-between relative z-10">
        <div class="flex-1">
          <h3 class="text-sm font-medium text-slate-600 dark:text-slate-400">
            {@label}
          </h3>
          <p class="mt-2 text-3xl font-semibold text-slate-900 dark:text-white transition-transform duration-200">
            {format_metric_value(@metric, @value)}
          </p>
          <p id={"#{@metric}-description"} class="mt-1 text-sm text-slate-500 dark:text-slate-400">
            {@subtitle}
          </p>
        </div>
        <%= if @interactive && @active do %>
          <div class="flex-shrink-0 transition-transform duration-200 animate-in fade-in zoom-in">
            <.icon name="hero-check-circle-solid" class={"h-6 w-6 #{@check_color}"} />
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Format metric value for display based on metric type
  defp format_metric_value(:ctr, value) when is_float(value) do
    # CTR - show as percentage
    format_percentage(value * 100)
  end

  defp format_metric_value(:position, value) when is_float(value) do
    # Position - show with 1 decimal place
    Float.round(value, 1) |> Float.to_string()
  end

  defp format_metric_value(_metric, value) when is_integer(value) do
    # Clicks, Impressions - format with commas
    format_number(value)
  end

  defp format_metric_value(_metric, value) when is_float(value) do
    # Generic float - show with 2 decimals
    Float.round(value, 2) |> Float.to_string()
  end

  defp format_metric_value(_metric, value) when is_binary(value), do: value
  defp format_metric_value(_metric, value), do: to_string(value)

  defp default_period_options do
    [
      %{value: "7", label: "Last 7 days"},
      %{value: "30", label: "Last 30 days"},
      %{value: "90", label: "Last 90 days"},
      %{value: "180", label: "Last 6 months"},
      %{value: "all", label: "Last 12 months"}
    ]
  end

  defp default_chart_view_options do
    [
      %{value: "daily", label: "Daily"},
      %{value: "weekly", label: "Weekly"},
      %{value: "monthly", label: "Monthly"}
    ]
  end

  defp period_active?(current, option_value) do
    case {current, option_value} do
      {value, "all"} when value in ["all", 10_000] -> true
      {value, opt} -> to_string(value) == to_string(opt)
    end
  end
end
