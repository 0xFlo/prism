defmodule GscAnalyticsWeb.Components.PricingComponents do
  @moduledoc """
  Reusable Phoenix LiveView function components for pricing pages.

  Provides pricing tier cards, comparison tables, and feature components.
  """

  use GscAnalyticsWeb, :html

  @doc """
  Renders a pricing tier card.

  ## Attributes
  - `tier` - Pricing tier map with name, price, features, etc.
  - `class` - Optional additional CSS classes

  ## Example
      <.pricing_tier_card tier={%{
        name: "Pro",
        price: "$2,500",
        period: "year",
        description: "Perfect for growing teams",
        features: ["1 domain", "3 users", ...],
        cta_text: "Start Free Trial",
        popular: false
      }} />
  """
  attr :tier, :map, required: true
  attr :class, :string, default: ""

  def pricing_tier_card(assigns) do
    ~H"""
    <div class={[
      "relative rounded-2xl p-8 border-2 transition-all duration-300",
      @tier.popular &&
        "border-indigo-500 bg-gradient-to-br from-indigo-500/10 to-emerald-500/10 shadow-xl scale-105",
      !@tier.popular && "border-slate-700/50 bg-slate-800/50 hover:border-slate-600",
      @class
    ]}>
      <%= if @tier[:badge] do %>
        <div class="absolute -top-4 left-1/2 -translate-x-1/2">
          <span class={[
            "px-4 py-1 rounded-full text-xs font-bold shadow-lg",
            @tier.popular && "bg-indigo-500 text-white",
            !@tier.popular && "bg-emerald-500 text-white"
          ]}>
            {@tier.badge}
          </span>
        </div>
      <% end %>

      <div class="text-center mb-8">
        <h3 class="text-2xl font-bold text-white mb-2">
          {@tier.name}
        </h3>
        <p class="text-slate-400 text-sm mb-6">
          {@tier.description}
        </p>

        <div class="mb-2">
          <span class="text-5xl font-extrabold text-white">
            {@tier.price}
          </span>
          <span class="text-slate-400 text-lg">
            /{@tier.period}
          </span>
        </div>

        <%= if @tier[:usage_note] do %>
          <p class="text-xs text-slate-400 italic mt-2">
            {@tier.usage_note}
          </p>
        <% end %>
      </div>

      <ul class="space-y-3 mb-8">
        <%= for feature <- @tier.features do %>
          <li class="flex items-start gap-3 text-slate-200">
            <.icon
              name="hero-check-circle-solid"
              class="h-5 w-5 text-emerald-400 flex-shrink-0 mt-0.5"
            />
            <span class="text-sm">{feature}</span>
          </li>
        <% end %>
      </ul>

      <button
        phx-click="select_plan"
        phx-value-plan={@tier.id}
        class={[
          "btn btn-lg w-full",
          @tier.cta_style == "primary" && "btn-primary",
          @tier.cta_style == "premium" &&
            "bg-gradient-to-r from-indigo-600 to-emerald-600 hover:from-indigo-500 hover:to-emerald-500 text-white border-none",
          @tier.cta_style == "outline" && "btn-outline text-white border-white/30 hover:bg-white/10"
        ]}
      >
        {@tier.cta_text}
      </button>
    </div>
    """
  end

  @doc """
  Renders a feature comparison row for the pricing table.

  ## Attributes
  - `feature` - Feature map with name, pro, business, max values
  - `show_tooltip` - Whether to show the tooltip icon

  ## Example
      <.feature_comparison_row feature={%{
        name: "Sync frequency",
        pro: "Weekly",
        business: "Daily",
        max: "Real-time",
        tooltip: "How often we sync data"
      }} />
  """
  attr :feature, :map, required: true
  attr :show_tooltip, :boolean, default: true

  def feature_comparison_row(assigns) do
    ~H"""
    <tr class="border-b border-slate-700/30 hover:bg-slate-800/30">
      <td class="py-4 px-6">
        <div class="flex items-center gap-2">
          <span class="text-slate-200 text-sm font-medium">
            {@feature.name}
          </span>
          <%= if @show_tooltip && @feature[:tooltip] do %>
            <div class="tooltip tooltip-right" data-tip={@feature.tooltip}>
              <.icon name="hero-information-circle" class="h-4 w-4 text-slate-500" />
            </div>
          <% end %>
        </div>
      </td>

      <td class="py-4 px-6 text-center">
        <.feature_value value={@feature.pro} />
      </td>

      <td class="py-4 px-6 text-center">
        <.feature_value value={@feature.business} />
      </td>

      <td class="py-4 px-6 text-center">
        <.feature_value value={@feature.max} />
      </td>
    </tr>
    """
  end

  @doc """
  Renders a use case tab for the Max plan page.

  ## Attributes
  - `use_case` - Use case map with role, challenge, solution, etc.
  - `active` - Boolean indicating if this tab is active
  """
  attr :use_case, :map, required: true
  attr :active, :boolean, default: false

  def use_case_tab(assigns) do
    ~H"""
    <div class={[
      "transition-all duration-300",
      @active && "block",
      !@active && "hidden"
    ]}>
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-8 mb-8">
        <!-- Left: Challenge & Solution -->
        <div class="space-y-6">
          <div>
            <h3 class="text-sm font-semibold text-slate-400 uppercase tracking-wide mb-2">
              Challenge
            </h3>
            <p class="text-xl text-white font-medium">
              {@use_case.challenge}
            </p>
          </div>

          <div>
            <h3 class="text-sm font-semibold text-slate-400 uppercase tracking-wide mb-2">
              How Max Solves This
            </h3>
            <p class="text-lg text-slate-200">
              {@use_case.solution}
            </p>
          </div>
          
    <!-- Stats -->
          <div class="grid grid-cols-3 gap-4 pt-4">
            <%= for stat <- @use_case.stats do %>
              <div class="text-center">
                <div class="text-2xl font-bold text-white">{stat.value}</div>
                <div class="text-xs text-slate-400 mt-1">{stat.label}</div>
              </div>
            <% end %>
          </div>
        </div>
        
    <!-- Right: Artifact/Output -->
        <div>
          <div class="bg-slate-900/50 border border-slate-700/50 rounded-xl p-6">
            <div class="mb-4">
              <h4 class="text-sm font-semibold text-indigo-400 uppercase tracking-wide mb-1">
                {@use_case.artifact_title}
              </h4>
              <p class="text-xs text-slate-400">
                {@use_case.artifact_description}
              </p>
            </div>
            
    <!-- Artifact Visual Placeholder -->
            <div class="bg-slate-800/80 rounded-lg p-4 mb-4 border border-slate-700/30 h-48 flex items-center justify-center">
              <div class="text-center">
                <.icon name="hero-chart-bar-square" class="h-12 w-12 text-slate-600 mx-auto mb-2" />
                <p class="text-xs text-slate-500">Dashboard Preview</p>
              </div>
            </div>
            
    <!-- Real Output Example -->
            <div class="bg-emerald-500/10 border border-emerald-500/30 rounded-lg p-4">
              <div class="flex items-start gap-3">
                <.icon name="hero-sparkles" class="h-5 w-5 text-emerald-400 flex-shrink-0 mt-0.5" />
                <div>
                  <p class="text-xs text-emerald-400 font-semibold mb-1">Real Output</p>
                  <p class="text-sm text-slate-200 leading-relaxed">
                    {@use_case.output_example}
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a FAQ item with collapsible answer.

  ## Attributes
  - `faq` - FAQ map with question and answer
  - `index` - Unique index for the FAQ item
  """
  attr :faq, :map, required: true
  attr :index, :integer, required: true

  def faq_item(assigns) do
    ~H"""
    <div class="collapse collapse-plus bg-slate-800/50 border border-slate-700/50 rounded-xl">
      <input type="radio" name="pricing-faq" id={"faq-#{@index}"} />
      <div class="collapse-title text-lg font-semibold text-white">
        {@faq.question}
      </div>
      <div class="collapse-content">
        <p class="text-slate-300 leading-relaxed">
          {@faq.answer}
        </p>
      </div>
    </div>
    """
  end

  # Private helper components

  defp feature_value(%{value: value} = assigns) when is_boolean(value) do
    assigns = assign(assigns, :value, value)

    ~H"""
    <%= if @value do %>
      <.icon name="hero-check-circle-solid" class="h-6 w-6 text-emerald-400 mx-auto" />
    <% else %>
      <.icon name="hero-x-circle" class="h-6 w-6 text-slate-600 mx-auto" />
    <% end %>
    """
  end

  defp feature_value(%{value: value} = assigns) when is_binary(value) do
    assigns = assign(assigns, :value, value)

    ~H"""
    <span class="text-slate-200 text-sm">
      {@value}
    </span>
    """
  end

  defp feature_value(assigns) do
    ~H"""
    <span class="text-slate-600">—</span>
    """
  end
end
