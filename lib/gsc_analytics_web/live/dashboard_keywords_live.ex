defmodule GscAnalyticsWeb.DashboardKeywordsLive do
  use GscAnalyticsWeb, :live_view

  alias GscAnalytics.ContentInsights
  alias GscAnalytics.Dashboard, as: DashboardUtils
  alias GscAnalyticsWeb.Live.AccountHelpers
  alias GscAnalyticsWeb.Layouts
  alias GscAnalyticsWeb.PropertyRoutes

  import GscAnalyticsWeb.Dashboard.HTMLHelpers

  @impl true
  def mount(params, _session, socket) do
    # LiveView best practice: Use assign_new/3 for safe defaults
    # This prevents runtime errors from missing assigns
    {socket, account, _property} =
      AccountHelpers.init_account_and_property_assigns(socket, params)

    # Redirect to Settings if no workspaces exist
    if is_nil(account) do
      {:ok,
       socket
       |> put_flash(
         :info,
         "Please add a Google Search Console workspace to get started."
       )
       |> redirect(to: ~p"/users/settings")}
    else
      {:ok,
       socket
       |> assign_new(:page_title, fn -> "Top Keywords - GSC Analytics" end)
       |> assign_new(:keywords, fn -> [] end)
       |> assign_new(:sort_by, fn -> "clicks" end)
       |> assign_new(:sort_direction, fn -> "desc" end)
       |> assign_new(:limit, fn -> 50 end)
       |> assign_new(:page, fn -> 1 end)
       |> assign_new(:total_pages, fn -> 1 end)
       |> assign_new(:total_count, fn -> 0 end)
       |> assign_new(:period_days, fn -> 30 end)
       |> assign_new(:search, fn -> "" end)}
    end
  end

  @impl true
  def handle_params(params, uri, socket) do
    socket =
      socket
      |> AccountHelpers.assign_current_account(params)
      |> AccountHelpers.assign_current_property(params)

    account_id = socket.assigns.current_account_id
    property = socket.assigns.current_property
    property_url = property && property.property_url

    # Parse URL parameters for state management
    limit = DashboardUtils.normalize_limit(params["limit"])
    page = DashboardUtils.normalize_page(params["page"])
    sort_by = params["sort_by"] || "clicks"
    sort_direction = DashboardUtils.normalize_sort_direction(params["sort_direction"])
    period_days = parse_period(params["period"])
    search = params["search"] || ""

    # Extract path for active nav detection
    current_path = URI.parse(uri).path || "/dashboard/keywords"

    {result, socket} =
      if property_url do
        data =
          ContentInsights.list_keywords(%{
            limit: limit,
            page: page,
            sort_by: sort_by,
            sort_direction: sort_direction,
            period_days: period_days,
            search: search,
            account_id: account_id,
            property_url: property_url
          })

        {data, socket}
      else
        socket = maybe_warn_no_property(socket)
        {empty_keywords_result(page), socket}
      end

    {:noreply,
     socket
     |> assign(:current_path, current_path)
     |> assign(:keywords, result.keywords)
     |> assign(:page, result.page)
     |> assign(:total_pages, result.total_pages)
     |> assign(:total_count, result.total_count)
     |> assign(:sort_by, sort_by)
     |> assign(:sort_direction, Atom.to_string(sort_direction))
     |> assign(:limit, limit)
     |> assign(:period_days, period_days)
     |> assign(:search, search)}
  end

  @impl true
  def handle_event("search", %{"search" => search_term}, socket) do
    # Update search - reset to page 1 when searching
    params = build_params(socket, %{search: search_term, page: 1})

    {:noreply,
     push_patch(
       socket,
       to: PropertyRoutes.keywords_path(socket.assigns.current_property_id, params)
     )}
  end

  @impl true
  def handle_event("change_period", %{"period" => period}, socket) do
    # Update period - reset to page 1 since data changes
    params = build_params(socket, %{period: period, page: 1})

    {:noreply,
     push_patch(
       socket,
       to: PropertyRoutes.keywords_path(socket.assigns.current_property_id, params)
     )}
  end

  @impl true
  def handle_event("switch_property", %{"property_id" => property_id}, socket) do
    params = build_params(socket, %{})
    {:noreply, push_patch(socket, to: PropertyRoutes.keywords_path(property_id, params))}
  end

  @impl true
  def handle_event("sort_column", %{"column" => column}, socket) do
    # Toggle direction if same column, default for new column
    new_direction =
      if socket.assigns.sort_by == column do
        if socket.assigns.sort_direction == "asc", do: "desc", else: "asc"
      else
        # Position: ascending (lower is better), others: descending
        if column == "position", do: "asc", else: "desc"
      end

    params = build_params(socket, %{sort_by: column, sort_direction: new_direction, page: 1})

    {:noreply,
     push_patch(
       socket,
       to: PropertyRoutes.keywords_path(socket.assigns.current_property_id, params)
     )}
  end

  @impl true
  def handle_event("goto_page", %{"page" => page}, socket) do
    page_num = DashboardUtils.normalize_page(page)
    page_num = max(1, min(page_num, socket.assigns.total_pages))

    params = build_params(socket, %{page: page_num})

    {:noreply,
     push_patch(
       socket,
       to: PropertyRoutes.keywords_path(socket.assigns.current_property_id, params)
     )}
  end

  @impl true
  def handle_event("next_page", _params, socket) do
    next_page = min(socket.assigns.page + 1, socket.assigns.total_pages)
    params = build_params(socket, %{page: next_page})

    {:noreply,
     push_patch(
       socket,
       to: PropertyRoutes.keywords_path(socket.assigns.current_property_id, params)
     )}
  end

  @impl true
  def handle_event("prev_page", _params, socket) do
    prev_page = max(socket.assigns.page - 1, 1)
    params = build_params(socket, %{page: prev_page})

    {:noreply,
     push_patch(
       socket,
       to: PropertyRoutes.keywords_path(socket.assigns.current_property_id, params)
     )}
  end

  # Helper to build URL params preserving current state
  defp build_params(socket, overrides) do
    base = %{
      sort_by: Map.get(overrides, :sort_by, socket.assigns.sort_by),
      sort_direction: Map.get(overrides, :sort_direction, socket.assigns.sort_direction),
      limit: Map.get(overrides, :limit, socket.assigns.limit),
      page: Map.get(overrides, :page, socket.assigns.page),
      period: Map.get(overrides, :period, socket.assigns.period_days),
      search: Map.get(overrides, :search, socket.assigns.search)
    }

    base
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp empty_keywords_result(page) do
    %{keywords: [], total_count: 0, total_pages: 1, page: page}
  end

  defp maybe_warn_no_property(socket) do
    if socket.assigns[:no_property_warned] != true do
      socket
      |> put_flash(
        :warning,
        "Please select a Search Console property from Settings to view data."
      )
      |> assign(:no_property_warned, true)
    else
      socket
    end
  end

  defp parse_period(nil), do: 30
  defp parse_period("7"), do: 7
  defp parse_period("30"), do: 30
  defp parse_period("90"), do: 90
  defp parse_period("180"), do: 180
  defp parse_period("365"), do: 365
  defp parse_period("all"), do: 10000

  defp parse_period(value) when is_binary(value) do
    case Integer.parse(value) do
      {days, ""} when days > 0 -> days
      _ -> 30
    end
  end

  defp parse_period(_), do: 30

  # Template rendering
  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_account={@current_account}
      current_account_id={@current_account_id}
      account_options={@account_options}
      current_property={@current_property}
      current_property_id={@current_property_id}
      property_options={@property_options}
    >
      <div class="mx-auto max-w-7xl">
        <div class="mb-6">
          <h1 class="text-3xl font-bold text-gray-900 dark:text-gray-100">
            Top Performing Keywords
          </h1>
          <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
            Site-wide keyword performance aggregated across all URLs
          </p>
        </div>
        
    <!-- Filters -->
        <div class="mb-6 flex flex-col sm:flex-row gap-4">
          <!-- Period Selector -->
          <div class="flex-1">
            <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
              Time Period
            </label>
            <select
              class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 dark:bg-gray-700 dark:border-gray-600 dark:text-gray-100"
              phx-change="change_period"
              name="period"
            >
              <option value="7" selected={@period_days == 7}>Last 7 days</option>
              <option value="30" selected={@period_days == 30}>Last 30 days</option>
              <option value="90" selected={@period_days == 90}>Last 90 days</option>
              <option value="180" selected={@period_days == 180}>Last 180 days</option>
              <option value="365" selected={@period_days == 365}>Last 365 days</option>
              <option value="all" selected={@period_days == 10000}>All time</option>
            </select>
          </div>
          
    <!-- Search Box -->
          <div class="flex-1">
            <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
              Search Keywords
            </label>
            <form phx-submit="search" class="relative">
              <input
                type="text"
                name="search"
                value={@search}
                placeholder="Filter by keyword..."
                class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 dark:bg-gray-700 dark:border-gray-600 dark:text-gray-100"
              />
            </form>
          </div>
        </div>
        
    <!-- Summary Stats -->
        <div class="mb-6 bg-white dark:bg-gray-800 rounded-lg shadow p-4">
          <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
            <div>
              <p class="text-sm text-gray-600 dark:text-gray-400">Total Keywords</p>
              <p class="text-2xl font-semibold text-gray-900 dark:text-gray-100">
                {format_number(@total_count)}
              </p>
            </div>
            <div>
              <p class="text-sm text-gray-600 dark:text-gray-400">Time Period</p>
              <p class="text-2xl font-semibold text-gray-900 dark:text-gray-100">
                {format_period(@period_days)}
              </p>
            </div>
            <div>
              <p class="text-sm text-gray-600 dark:text-gray-400">Showing</p>
              <p class="text-2xl font-semibold text-gray-900 dark:text-gray-100">
                Page {@page} of {@total_pages}
              </p>
            </div>
          </div>
        </div>
        
    <!-- Keywords Table -->
        <div class="bg-white dark:bg-gray-800 rounded-lg shadow overflow-hidden">
          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
              <thead class="bg-gray-50 dark:bg-gray-900">
                <tr>
                  <th
                    scope="col"
                    class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-800"
                    phx-click="sort_column"
                    phx-value-column="query"
                  >
                    <div class="flex items-center gap-2">
                      Keyword {render_sort_icon(@sort_by, @sort_direction, "query")}
                    </div>
                  </th>
                  <th
                    scope="col"
                    class="px-6 py-3 text-right text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-800"
                    phx-click="sort_column"
                    phx-value-column="clicks"
                  >
                    <div class="flex items-center justify-end gap-2">
                      Clicks {render_sort_icon(@sort_by, @sort_direction, "clicks")}
                    </div>
                  </th>
                  <th
                    scope="col"
                    class="px-6 py-3 text-right text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-800"
                    phx-click="sort_column"
                    phx-value-column="impressions"
                  >
                    <div class="flex items-center justify-end gap-2">
                      Impressions {render_sort_icon(@sort_by, @sort_direction, "impressions")}
                    </div>
                  </th>
                  <th
                    scope="col"
                    class="px-6 py-3 text-right text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-800"
                    phx-click="sort_column"
                    phx-value-column="ctr"
                  >
                    <div class="flex items-center justify-end gap-2">
                      CTR % {render_sort_icon(@sort_by, @sort_direction, "ctr")}
                    </div>
                  </th>
                  <th
                    scope="col"
                    class="px-6 py-3 text-right text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-800"
                    phx-click="sort_column"
                    phx-value-column="position"
                  >
                    <div class="flex items-center justify-end gap-2">
                      Avg Position {render_sort_icon(@sort_by, @sort_direction, "position")}
                    </div>
                  </th>
                  <th
                    scope="col"
                    class="px-6 py-3 text-right text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-800"
                    phx-click="sort_column"
                    phx-value-column="url_count"
                  >
                    <div class="flex items-center justify-end gap-2">
                      URL Count {render_sort_icon(@sort_by, @sort_direction, "url_count")}
                    </div>
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white dark:bg-gray-800 divide-y divide-gray-200 dark:divide-gray-700">
                <%= if @keywords == [] do %>
                  <tr>
                    <td colspan="6" class="px-6 py-12 text-center text-gray-500 dark:text-gray-400">
                      <div class="flex flex-col items-center gap-2">
                        <svg
                          class="w-12 h-12 text-gray-400"
                          fill="none"
                          stroke="currentColor"
                          viewBox="0 0 24 24"
                        >
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="2"
                            d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
                          />
                        </svg>
                        <p class="text-lg font-medium">No keywords found</p>
                        <p class="text-sm">
                          Try adjusting your filters or sync more data from Google Search Console
                        </p>
                      </div>
                    </td>
                  </tr>
                <% else %>
                  <%= for keyword <- @keywords do %>
                    <tr class="hover:bg-gray-50 dark:hover:bg-gray-700">
                      <td class="px-6 py-4 text-sm font-medium text-gray-900 dark:text-gray-100">
                        {keyword.query}
                      </td>
                      <td class="px-6 py-4 text-sm text-right text-gray-900 dark:text-gray-100">
                        {format_number(keyword.clicks)}
                      </td>
                      <td class="px-6 py-4 text-sm text-right text-gray-500 dark:text-gray-400">
                        {format_number(keyword.impressions)}
                      </td>
                      <td class="px-6 py-4 text-sm text-right text-gray-500 dark:text-gray-400">
                        {format_ctr(keyword.ctr)}
                      </td>
                      <td class="px-6 py-4 text-sm text-right text-gray-500 dark:text-gray-400">
                        {if keyword.position, do: format_position(keyword.position), else: "—"}
                      </td>
                      <td class="px-6 py-4 text-sm text-right text-gray-500 dark:text-gray-400">
                        {keyword.url_count}
                      </td>
                    </tr>
                  <% end %>
                <% end %>
              </tbody>
            </table>
          </div>
          
    <!-- Pagination -->
          <%= if @total_pages > 1 do %>
            <div class="bg-white dark:bg-gray-800 px-4 py-3 border-t border-gray-200 dark:border-gray-700 sm:px-6">
              <div class="flex items-center justify-between">
                <div class="flex-1 flex justify-between sm:hidden">
                  <button
                    phx-click="prev_page"
                    disabled={@page == 1}
                    class="relative inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    Previous
                  </button>
                  <button
                    phx-click="next_page"
                    disabled={@page == @total_pages}
                    class="ml-3 relative inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    Next
                  </button>
                </div>
                <div class="hidden sm:flex-1 sm:flex sm:items-center sm:justify-between">
                  <div>
                    <p class="text-sm text-gray-700 dark:text-gray-300">
                      Showing page <span class="font-medium">{@page}</span>
                      of <span class="font-medium">{@total_pages}</span>
                      (<span class="font-medium"><%= format_number(@total_count) %></span> total keywords)
                    </p>
                  </div>
                  <div>
                    <nav class="relative z-0 inline-flex rounded-md shadow-sm -space-x-px">
                      <button
                        phx-click="prev_page"
                        disabled={@page == 1}
                        class="relative inline-flex items-center px-2 py-2 rounded-l-md border border-gray-300 bg-white text-sm font-medium text-gray-500 hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed dark:bg-gray-700 dark:border-gray-600 dark:text-gray-300"
                      >
                        ← Previous
                      </button>
                      <button
                        phx-click="next_page"
                        disabled={@page == @total_pages}
                        class="relative inline-flex items-center px-2 py-2 rounded-r-md border border-gray-300 bg-white text-sm font-medium text-gray-500 hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed dark:bg-gray-700 dark:border-gray-600 dark:text-gray-300"
                      >
                        Next →
                      </button>
                    </nav>
                  </div>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # Helper functions for formatting
  defp format_ctr(nil), do: "0.00%"
  defp format_ctr(ctr) when is_float(ctr), do: format_percentage(ctr * 100)
  defp format_ctr(_), do: "0.00%"

  defp format_period(7), do: "7 days"
  defp format_period(30), do: "30 days"
  defp format_period(90), do: "90 days"
  defp format_period(180), do: "180 days"
  defp format_period(365), do: "1 year"
  defp format_period(10000), do: "All time"
  defp format_period(days), do: "#{days} days"

  defp render_sort_icon(current_sort, direction, column) do
    if current_sort == column do
      if direction == "asc" do
        "↑"
      else
        "↓"
      end
    else
      "↕"
    end
  end
end
