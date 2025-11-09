defmodule GscAnalyticsWeb.PricingLive do
  @moduledoc """
  Pricing comparison page showing all three tiers.

  Public page accessible without authentication. Shows Pro, Business, and Enterprise plans
  with feature comparison table.
  """
  use GscAnalyticsWeb, :live_view

  alias GscAnalyticsWeb.Live.PricingData

  # Import pricing components
  import GscAnalyticsWeb.Components.PricingComponents

  @impl true
  def mount(_params, _session, socket) do
    tiers = PricingData.pricing_tiers()
    comparison = PricingData.feature_comparison()
    faqs = PricingData.pricing_faqs()
    trust = PricingData.trust_signals()

    {:ok,
     socket
     |> assign(:page_title, "Pricing - Choose Your Plan")
     |> assign(:tiers, tiers)
     |> assign(:comparison, comparison)
     |> assign(:faqs, faqs)
     |> assign(:trust, trust)}
  end

  @impl true
  def handle_event("select_plan", %{"plan" => plan}, socket) do
    # Handle plan selection
    case plan do
      "pro" ->
        {:noreply, push_navigate(socket, to: ~p"/users/register?plan=pro")}

      "business" ->
        {:noreply, push_navigate(socket, to: ~p"/users/register?plan=business")}

      "enterprise" ->
        # For Enterprise plan, redirect to dedicated landing page
        {:noreply, push_navigate(socket, to: ~p"/pricing/enterprise")}

      _ ->
        {:noreply, socket}
    end
  end
end
