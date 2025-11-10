defmodule GscAnalyticsWeb.HomepageLive do
  @moduledoc """
  Public landing page showcasing the AI SEO Agent product.

  This LiveView displays:
  - Hero section with product value proposition
  - Live dashboard preview with demo data
  - Feature highlights (Reddit tracking, AI Overviews, etc.)
  - Pricing information
  - Social proof and CTAs
  """
  use GscAnalyticsWeb, :live_view

  alias GscAnalyticsWeb.Live.HomepageDemoData
  alias GscAnalyticsWeb.Presenters.ChartDataPresenter
  alias GscAnalyticsWeb.PropertyContext

  # Import component functions for template
  import GscAnalyticsWeb.Components.DashboardComponents
  import GscAnalyticsWeb.ChartComponents

  @impl true
  def mount(_params, _session, socket) do
    current_scope = Map.get(socket.assigns, :current_scope)

    if authenticated_scope?(current_scope) do
      {:ok, push_navigate(socket, to: PropertyContext.default_dashboard_path(current_scope))}
    else
      # Load demo data for public landing page
      metrics = HomepageDemoData.demo_metrics()
      time_series = HomepageDemoData.demo_time_series()
      urls = HomepageDemoData.demo_urls()
      stats = HomepageDemoData.demo_stats()
      features = HomepageDemoData.feature_highlights()
      pricing = HomepageDemoData.pricing_info()
      testimonials = HomepageDemoData.testimonials()

      {:ok,
       socket
       |> assign(:page_title, "AI SEO Agent - Automate Your Search Console Analytics")
       |> assign(:metrics, metrics)
       |> assign(:time_series, time_series)
       |> assign(:time_series_json, ChartDataPresenter.encode_time_series(time_series))
       |> assign(:urls, urls)
       |> assign(:stats, stats)
       |> assign(:features, features)
       |> assign(:pricing, pricing)
       |> assign(:testimonials, testimonials)
       |> assign(:visible_series, [:clicks, :impressions])
       |> assign(:view_mode, "basic")
       |> assign(:sort_by, "clicks")
       |> assign(:sort_direction, "desc")
       |> assign(:period_label, "Last 30 days")}
    end
  end

  @impl true
  def handle_event("toggle_series", %{"metric" => metric_str}, socket) do
    # Allow toggling chart series on demo
    metric = String.to_existing_atom(metric_str)
    current_series = socket.assigns.visible_series

    new_series =
      if metric in current_series do
        List.delete(current_series, metric)
      else
        [metric | current_series]
      end

    # Enforce at least one series visible
    new_series = if Enum.empty?(new_series), do: [metric], else: new_series

    {:noreply, assign(socket, :visible_series, new_series)}
  end

  @impl true
  def handle_event("cta_click", %{"type" => type}, socket) do
    # Track CTA clicks (could integrate with analytics)
    # For now, just redirect to registration
    case type do
      "primary" ->
        {:noreply, push_navigate(socket, to: ~p"/users/register")}

      "secondary" ->
        # Could open a demo modal or link to docs
        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("social_click", %{"platform" => platform}, socket) do
    # Track social clicks for analytics
    # The actual navigation happens via the link's href
    _ = platform
    {:noreply, socket}
  end

  # Helper functions for template

  defp feature_color_classes(color) do
    case color do
      "indigo" ->
        %{
          border: "border-indigo-500/30",
          bg: "bg-indigo-500/10",
          icon: "text-indigo-400"
        }

      "emerald" ->
        %{
          border: "border-emerald-500/30",
          bg: "bg-emerald-500/10",
          icon: "text-emerald-400"
        }

      "purple" ->
        %{
          border: "border-purple-500/30",
          bg: "bg-purple-500/10",
          icon: "text-purple-400"
        }

      "amber" ->
        %{
          border: "border-amber-500/30",
          bg: "bg-amber-500/10",
          icon: "text-amber-400"
        }

      _ ->
        %{
          border: "border-slate-500/30",
          bg: "bg-slate-500/10",
          icon: "text-slate-400"
        }
    end
  end

  defp authenticated_scope?(%{user: user}) when is_map(user), do: true
  defp authenticated_scope?(_), do: false
end
