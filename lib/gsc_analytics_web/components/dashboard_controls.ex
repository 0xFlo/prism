defmodule GscAnalyticsWeb.Components.DashboardControls do
  @moduledoc """
  Dashboard selectors, toolbar controls, and metric cards broken out of the
  original `DashboardComponents` module so each concern stays focused and testable.
  """

  use GscAnalyticsWeb, :html

  import GscAnalyticsWeb.Dashboard.HTMLHelpers

  @doc """
  Renders a group of toggle buttons with active state styling.

  ## Attributes
  - `options` - List of maps with :value and :label keys
  - `current_value` - The currently selected value
  - `event_name` - The Phoenix event to trigger on click
  - `value_key` - The parameter key name for the `phx-value-*` attribute
  """
  attr :options, :list, required: true
  attr :current_value, :any, required: true
  attr :event_name, :string, required: true
  attr :value_key, :string, required: true

  def toggle_button_group(assigns) do
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
        {for {k, v} <- option.phx_value_attr, do: {"phx-value-#{k}", v}}
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
  Compact dropdown used for chart/period selectors.
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
  Renders a simple metric card used on the hero/landing dashboard.
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
  Dropdown with favicons for picking the active Search Console property.
  """
  attr :property_options, :list, default: []
  attr :property_label, :string, default: nil
  attr :property_favicon_url, :string, default: nil
  attr :current_property_id, :string, default: nil
  attr :empty_message, :string, default: "No property selected"
  attr :class, :string, default: nil

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
        <label tabindex="0" class={["btn btn-ghost gap-2 normal-case text-base font-medium", @class]}>
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
  Shared toolbar for dashboard screens (property selector + time controls).
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
    value_keys =
      assigns
      |> Map.get(:chart_view_value_keys, ["chart_view"])
      |> List.wrap()
      |> case do
        [] -> ["chart_view"]
        list -> list
      end

    assigns =
      assigns
      |> assign_new(:period_options, fn -> default_period_options() end)
      |> assign_new(:chart_view_options, fn -> default_chart_view_options() end)
      |> assign_new(:chart_view_value_keys, fn -> ["chart_view"] end)
      |> assign(:chart_view_value_keys_normalized, value_keys)

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

      <button type="button" class="btn btn-sm btn-circle btn-ghost" title="Previous period">
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
          <li :for={option <- @period_options || []}>
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

      <button type="button" class="btn btn-sm btn-circle btn-ghost" title="Next period">
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
          <li :for={option <- @chart_view_options || []}>
            <% value_attrs =
              Enum.map(@chart_view_value_keys_normalized, fn key ->
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
  Interactive card that toggles chart series visibility.
  """
  attr :metric, :atom, required: true
  attr :value, :any, required: true
  attr :label, :string, required: true
  attr :subtitle, :string, required: true
  attr :active, :boolean, required: true
  attr :interactive, :boolean, default: true

  def interactive_metric_card(assigns) do
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
      phx-click={if(@interactive, do: "toggle_series", else: nil)}
      phx-value-metric={if(@interactive, do: Atom.to_string(@metric), else: nil)}
      role={if(@interactive, do: "button", else: nil)}
      aria-pressed={if(@interactive, do: to_string(@active), else: nil)}
      tabindex={if(@interactive, do: "0", else: nil)}
    >
      <div class="flex items-start justify-between">
        <div>
          <p class="text-xs font-semibold uppercase tracking-wide text-slate-500 dark:text-slate-400">
            {@label}
          </p>
          <p class="mt-1 text-3xl font-semibold text-slate-900 dark:text-white">
            {format_metric_value(@metric, @value)}
          </p>
          <p class="mt-1 text-sm text-slate-500 dark:text-slate-400">
            {@subtitle}
          </p>
        </div>
        <div class="flex items-center gap-2">
          <div class={[
            "flex h-8 w-8 items-center justify-center rounded-full border-2",
            @border_color,
            "bg-white dark:bg-slate-900",
            @active && "shadow-inner shadow-white/30 dark:shadow-slate-900/50"
          ]}>
            <.icon
              name="hero-check"
              class={
                [
                  "h-4 w-4",
                  @check_color,
                  @active && "animate-pulse",
                  !@active && "opacity-30"
                ]
                |> Enum.reject(&(&1 in [nil, false]))
                |> Enum.join(" ")
              }
            />
          </div>
        </div>
      </div>

      <%= if @active do %>
        <div class={"absolute inset-0 -z-10 animate-pulse rounded-lg #{@pulse_color}"} />
      <% end %>
    </div>
    """
  end

  defp format_metric_value(:ctr, value) when is_float(value) do
    "#{Float.round(value, 2)}%"
  end

  defp format_metric_value(:position, value) when is_float(value) do
    Float.round(value, 1)
  end

  defp format_metric_value(_metric, value) when is_integer(value) do
    format_number(value)
  end

  defp format_metric_value(_metric, value) when is_float(value) do
    format_number(trunc(value))
  end

  defp format_metric_value(_metric, value) when is_binary(value), do: value
  defp format_metric_value(_metric, value), do: to_string(value)

  defp default_period_options do
    [
      %{value: "7", label: "Last 7 days"},
      %{value: "30", label: "Last 30 days"},
      %{value: "90", label: "Last 90 days"},
      %{value: "180", label: "Last 6 months"},
      %{value: "365", label: "Last 12 months"},
      %{value: "all", label: "All time"}
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
