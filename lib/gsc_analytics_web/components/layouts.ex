defmodule GscAnalyticsWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use GscAnalyticsWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :current_account, :map, default: nil, doc: "Currently selected GSC account"
  attr :current_account_id, :integer, default: nil, doc: "Current GSC account id"
  attr :account_options, :list, default: [], doc: "Available GSC accounts for selection"
  attr :current_property, :map, default: nil, doc: "Active workspace property (if any)"
  attr :current_property_id, :string, default: nil, doc: "Active workspace property id"
  attr :property_options, :list, default: [], doc: "Saved workspace properties for selection"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="drawer lg:drawer-open" id="main-drawer">
      <input id="app-drawer" type="checkbox" class="drawer-toggle" />
      <div class="drawer-content flex flex-col">
        <!-- Header with hamburger menu for mobile -->
        <header class="navbar bg-base-200 px-4 sm:px-6 lg:px-8 sticky top-0 z-30 shadow-sm">
          <div class="flex-none lg:hidden">
            <label for="app-drawer" aria-label="open sidebar" class="btn btn-square btn-ghost">
              <.icon name="hero-bars-3" class="h-6 w-6" />
            </label>
          </div>
          <div class="flex-1"></div>
          <div class="flex items-center gap-4">
            <div class="flex-none">
              <.theme_toggle />
            </div>
          </div>
        </header>
        
    <!-- Floating toggle button (shows when sidebar is collapsed on desktop) -->
        <button
          type="button"
          id="sidebar-expand-btn"
          class="hidden fixed left-4 top-20 z-50 btn btn-circle btn-primary shadow-lg"
          aria-label="expand sidebar"
          phx-click={expand_sidebar()}
        >
          <.icon name="hero-chevron-right" class="h-5 w-5" />
        </button>
        
    <!-- Main content area -->
        <main class="flex-1 bg-base-100">
          <div class="px-4 py-6 sm:px-6 lg:px-8">
            {render_slot(@inner_block)}
          </div>
        </main>

        <.flash_group flash={@flash} />
      </div>
      
    <!-- Sidebar -->
      <div class="drawer-side z-40">
        <label for="app-drawer" aria-label="close sidebar" class="drawer-overlay"></label>
        <aside class="bg-base-200 min-h-full w-52 p-3">
          <!-- Sidebar header with toggle -->
          <div class="mb-6 px-1 flex items-center justify-between">
            <.link navigate={account_nav(assigns, :root)} class="flex items-center gap-2">
              <.icon name="hero-chart-bar-square" class="h-8 w-8 text-primary" />
              <span class="text-lg font-bold">GSC Analytics</span>
            </.link>
            <button
              type="button"
              class="hidden lg:flex btn btn-square btn-ghost btn-sm"
              aria-label="collapse sidebar"
              phx-click={toggle_sidebar()}
            >
              <.icon name="hero-chevron-left" class="h-5 w-5" />
            </button>
          </div>
          
    <!-- Navigation menu -->
          <nav>
            <ul class="menu menu-compact gap-2">
              <li>
                <.link
                  navigate={account_nav(assigns, :root)}
                  class={nav_link_class(assigns, "/")}
                >
                  <.icon name="hero-home" class="h-5 w-5" /> Dashboard
                </.link>
              </li>
              <li>
                <.link
                  navigate={account_nav(assigns, :keywords)}
                  class={nav_link_class(assigns, "/dashboard/keywords")}
                >
                  <.icon name="hero-magnifying-glass" class="h-5 w-5" /> Keywords
                </.link>
              </li>
              <li>
                <.link
                  navigate={account_nav(assigns, :sync)}
                  class={nav_link_class(assigns, "/dashboard/sync")}
                >
                  <.icon name="hero-arrow-path" class="h-5 w-5" /> Sync Status
                </.link>
              </li>
              <li>
                <.link
                  navigate={account_nav(assigns, :crawler)}
                  class={nav_link_class(assigns, "/dashboard/crawler")}
                >
                  <.icon name="hero-shield-check" class="h-5 w-5" /> URL Health
                </.link>
              </li>
            </ul>
          </nav>
        </aside>
      </div>
    </div>
    """
  end

  # Helper function to determine active nav link styling
  defp nav_link_class(assigns, path) do
    current_path = Map.get(assigns, :current_path, "")

    if current_path == path or (path == "/" and current_path == "/dashboard") do
      "active"
    else
      ""
    end
  end

  defp account_nav(assigns, :root) do
    case account_query(assigns) do
      [] -> ~p"/"
      params -> ~p"/?#{params}"
    end
  end

  defp account_nav(assigns, :keywords) do
    case account_query(assigns) do
      [] -> ~p"/dashboard/keywords"
      params -> ~p"/dashboard/keywords?#{params}"
    end
  end

  defp account_nav(assigns, :sync) do
    case account_query(assigns) do
      [] -> ~p"/dashboard/sync"
      params -> ~p"/dashboard/sync?#{params}"
    end
  end

  defp account_nav(assigns, :crawler) do
    case account_query(assigns) do
      [] -> ~p"/dashboard/crawler"
      params -> ~p"/dashboard/crawler?#{params}"
    end
  end

  defp account_query(assigns) do
    property_id = Map.get(assigns, :current_property_id)

    params =
      []
      |> maybe_put(:property_id, property_id)

    Enum.reverse(params)
  end

  defp maybe_put(params, _key, nil), do: params
  defp maybe_put(params, _key, ""), do: params
  defp maybe_put(params, key, value), do: [{key, value} | params]

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end

  @doc """
  Toggles the sidebar visibility on desktop screens (collapse).
  """
  def toggle_sidebar do
    JS.remove_class("lg:drawer-open", to: "#main-drawer")
    |> JS.remove_class("hidden", to: "#sidebar-expand-btn")
    |> JS.add_class("flex", to: "#sidebar-expand-btn")
  end

  @doc """
  Expands the sidebar on desktop screens.
  """
  def expand_sidebar do
    JS.add_class("lg:drawer-open", to: "#main-drawer")
    |> JS.remove_class("flex", to: "#sidebar-expand-btn")
    |> JS.add_class("hidden", to: "#sidebar-expand-btn")
  end
end
