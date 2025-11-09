defmodule GscAnalyticsWeb.PricingEnterpriseLive do
  @moduledoc """
  Dedicated landing page for the Enterprise plan (premium tier).

  Inspired by Claude's Enterprise plan approach: sells through demonstrated capability
  rather than feature lists. Shows role-based use cases with real outputs.
  """
  use GscAnalyticsWeb, :live_view

  alias GscAnalyticsWeb.Live.PricingData

  # Import pricing components
  import GscAnalyticsWeb.Components.PricingComponents

  @impl true
  def mount(_params, _session, socket) do
    use_cases = PricingData.enterprise_use_cases()
    enterprise_tier = PricingData.pricing_tiers() |> Enum.find(&(&1.id == :enterprise))
    faqs = PricingData.pricing_faqs()
    trust = PricingData.trust_signals()

    {:ok,
     socket
     |> assign(:page_title, "Enterprise Plan - Autonomous AI SEO Agent")
     |> assign(:use_cases, use_cases)
     |> assign(:enterprise_tier, enterprise_tier)
     |> assign(:faqs, faqs)
     |> assign(:trust, trust)
     |> assign(:active_use_case, "agency")}
  end

  @impl true
  def handle_event("switch_use_case", %{"use_case" => use_case_id}, socket) do
    {:noreply, assign(socket, :active_use_case, use_case_id)}
  end

  @impl true
  def handle_event("schedule_demo", _params, socket) do
    # In a real app, this would open a demo scheduling modal
    # For now, redirect to contact/demo page or show a form
    {:noreply,
     socket
     |> put_flash(:info, "Demo scheduling coming soon! Contact sales@prism-ai.com")
     |> push_navigate(to: ~p"/users/register?plan=enterprise")}
  end
end
