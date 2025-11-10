defmodule GscAnalyticsWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use GscAnalyticsWeb, :html

  alias GscAnalyticsWeb.PropertyRoutes

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
    <div class="drawer" id="main-drawer">
      <input id="app-drawer" type="checkbox" class="drawer-toggle" />
      <div class="drawer-content flex flex-col">
        <!-- Mobile-first top app bar -->
        <header class="navbar bg-base-200 px-4 sm:px-6 sticky top-0 z-30 shadow-sm">
          <!-- Hamburger menu (left) -->
          <div class="flex-none">
            <label for="app-drawer" aria-label="open menu" class="btn btn-square btn-ghost">
              <.icon name="hero-bars-3" class="h-6 w-6" />
            </label>
          </div>
          
    <!-- Logo/title (center) -->
          <div class="flex-1 flex justify-center">
            <.link navigate={account_nav(assigns, :root)} class="flex items-center gap-2">
              <.icon name="hero-chart-bar-square" class="h-6 w-6 text-primary" />
              <span class="text-lg font-bold">GSC Analytics</span>
            </.link>
          </div>
          
    <!-- User menu and theme toggle (right) -->
          <div class="flex-none">
            <div class="flex items-center gap-2">
              <.theme_toggle />
            </div>
          </div>
        </header>
        
    <!-- Main content area -->
        <main class="flex-1 bg-base-100">
          <div class="px-4 py-6 sm:px-6 lg:px-8">
            {render_slot(@inner_block)}
          </div>
        </main>

        <.flash_group flash={@flash} />
      </div>
      
    <!-- Hamburger overlay menu (slide-in from left) -->
      <div class="drawer-side z-40">
        <label for="app-drawer" aria-label="close menu" class="drawer-overlay"></label>
        <aside class="bg-base-200 min-h-full w-64 p-4">
          <!-- Menu header -->
          <div class="mb-6 px-2 flex items-center justify-between">
            <div class="flex items-center gap-2">
              <.icon name="hero-chart-bar-square" class="h-8 w-8 text-primary" />
              <span class="text-xl font-bold">Menu</span>
            </div>
            <label for="app-drawer" aria-label="close menu" class="btn btn-square btn-ghost btn-sm">
              <.icon name="hero-x-mark" class="h-5 w-5" />
            </label>
          </div>
          
    <!-- Navigation menu -->
          <nav>
            <ul class="menu gap-2">
              <li>
                <.link
                  navigate={account_nav(assigns, :root)}
                  class={nav_link_class(assigns, :dashboard)}
                >
                  <.icon name="hero-home" class="h-5 w-5" /> Dashboard
                </.link>
              </li>
              <li>
                <.link
                  navigate={account_nav(assigns, :keywords)}
                  class={nav_link_class(assigns, :keywords)}
                >
                  <.icon name="hero-magnifying-glass" class="h-5 w-5" /> Keywords
                </.link>
              </li>
              <li>
                <.link
                  navigate={account_nav(assigns, :sync)}
                  class={nav_link_class(assigns, :sync)}
                >
                  <.icon name="hero-arrow-path" class="h-5 w-5" /> Sync Status
                </.link>
              </li>
              <li>
                <.link
                  navigate={account_nav(assigns, :crawler)}
                  class={nav_link_class(assigns, :crawler)}
                >
                  <.icon name="hero-shield-check" class="h-5 w-5" /> URL Health
                </.link>
              </li>
              <li>
                <.link
                  navigate={account_nav(assigns, :workflows)}
                  class={nav_link_class(assigns, :workflows)}
                >
                  <.icon name="hero-cog-6-tooth" class="h-5 w-5" /> Workflows
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
  defp nav_link_class(assigns, section) do
    segments =
      assigns
      |> Map.get(:current_path, "")
      |> path_segments()

    active? =
      case {section, segments} do
        {:dashboard, ["dashboard"]} -> true
        {:dashboard, ["dashboard", _property]} -> true
        {:dashboard, ["dashboard", _property, _rest | _]} -> true
        {:keywords, ["dashboard", _property, "keywords" | _rest]} -> true
        {:sync, ["dashboard", _property, "sync" | _rest]} -> true
        {:crawler, ["dashboard", _property, "crawler" | _rest]} -> true
        {:workflows, ["dashboard", _property, "workflows" | _rest]} -> true
        _ -> false
      end

    if active?, do: "active", else: ""
  end

  defp path_segments(path) when is_binary(path) do
    path
    |> String.trim_leading("/")
    |> String.split("/", trim: true)
  end

  defp path_segments(_), do: []

  defp account_nav(assigns, section) do
    property_id = Map.get(assigns, :current_property_id)

    case {section, property_id} do
      {:root, nil} -> ~p"/dashboard"
      {:keywords, nil} -> ~p"/dashboard"
      {:sync, nil} -> ~p"/dashboard"
      {:crawler, nil} -> ~p"/dashboard"
      {:workflows, nil} -> ~p"/dashboard"
      {:root, id} -> PropertyRoutes.dashboard_path(id)
      {:keywords, id} -> PropertyRoutes.keywords_path(id)
      {:sync, id} -> PropertyRoutes.sync_path(id)
      {:crawler, id} -> PropertyRoutes.crawler_path(id)
      {:workflows, id} -> PropertyRoutes.workflows_path(id)
    end
  end

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
end
