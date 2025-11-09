defmodule GscAnalyticsWeb.AiropsAlternativeLive do
  @moduledoc """
  Landing page positioning Prism AI SEO as managed service alternative to AirOps platform.

  Targets B2B SaaS companies looking for content automation without the platform complexity,
  learning curve, and pricing opacity of DIY solutions like AirOps.

  Key positioning: Managed service vs DIY platform, transparent pricing, B2B SaaS specialization.
  """
  use GscAnalyticsWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       :page_title,
       "AirOps Alternative for B2B SaaS | Managed AI Content Automation - Prism AI SEO"
     )
     |> assign(
       :meta_description,
       "Skip the $60K platform and 45-day setup. Get managed AI content automation for B2B SaaS with transparent pricing and 14-day delivery."
     )
     |> assign(:comparison_data, comparison_table())
     |> assign(:case_studies, case_studies())
     |> assign(:service_packages, service_packages())
     |> assign(:faqs, faqs())}
  end

  @impl true
  def handle_event("book_discovery_call", _params, socket) do
    # Redirect to Calendly or contact form
    # For now, placeholder - implement Calendly integration
    {:noreply, socket |> put_flash(:info, "Redirecting to calendar...")}
  end

  # Data helpers

  defp comparison_table do
    [
      %{
        feature: "Pricing Model",
        airops: "$50-60K/year + task credits",
        prism: "$10-12K fixed projects",
        advantage: :prism
      },
      %{
        feature: "Service Model",
        airops: "DIY Platform (you learn & manage)",
        prism: "Managed Service (we do the work)",
        advantage: :prism
      },
      %{
        feature: "Time to Production",
        airops: "30+ days + 2-3 weeks refinement",
        prism: "14 days to production-ready",
        advantage: :prism
      },
      %{
        feature: "Learning Curve",
        airops: "30-40% remains after training",
        prism: "Zero (managed service)",
        advantage: :prism
      },
      %{
        feature: "Industry Focus",
        airops: "Generic (learning as they go)",
        prism: "B2B SaaS specialized",
        advantage: :prism
      },
      %{
        feature: "Tool Integrations",
        airops: "SEMrush only",
        prism: "Multi-tool (Ahrefs, SEMrush, etc.)",
        advantage: :prism
      },
      %{
        feature: "Content Execution",
        airops: "You draft & publish",
        prism: "We publish & execute",
        advantage: :prism
      },
      %{
        feature: "Pricing Transparency",
        airops: "\"Bane of my existence\" per sales rep",
        prism: "Clear, predictable pricing",
        advantage: :prism
      }
    ]
  end

  defp case_studies do
    [
      %{
        company: "Scrapfly",
        industry: "B2B SaaS - Developer Tools API",
        challenge: "50% traffic decline from Google AI Overviews",
        solution: "AI-powered content audit and recovery strategy",
        results: [
          "Audited 467 posts in 112 seconds (vs 40 hours manual)",
          "Generated 1,783 prioritized recommendations",
          "40% traffic restoration achieved",
          "2-3x conversion improvements on key pages"
        ],
        timeframe: "90 days"
      }
    ]
  end

  defp service_packages do
    [
      %{
        name: "90-Day AI Recovery Sprint",
        price: "$10,000",
        ideal_for: "B2B SaaS companies hit by Google AI Overviews (20-50% traffic decline)",
        promise: "40% traffic restoration + 2-3x conversion improvement",
        guarantee: "Double guarantee: Traffic OR conversion refund",
        includes: [
          "Custom AI audit agent (analyzes entire site in minutes)",
          "1,783+ prioritized recommendations",
          "Implementation roadmap with conversion focus",
          "AI Overview optimization strategy",
          "90-day execution partnership"
        ]
      },
      %{
        name: "90-Day CAC Killer",
        price: "$12,000",
        ideal_for: "High-growth B2B SaaS with high CAC ($150+)",
        promise: "40% CAC reduction through organic engine",
        guarantee: "CAC reduction guarantee or Month 4 free",
        includes: [
          "Full SEO audit and conversion analysis",
          "Content strategy for bottom-funnel keywords",
          "Technical SEO optimization",
          "Internal linking architecture",
          "Automated tracking and reporting"
        ]
      },
      %{
        name: "30-Day Conversion Sprint",
        price: "$3,500",
        ideal_for: "Testing engagement or smaller budgets",
        promise: "2-3x conversion improvement on top 10 pages",
        guarantee: "100% refund if <50% improvement",
        includes: [
          "Top 10 pages audit and analysis",
          "Conversion-focused rewrites",
          "A/B testing strategy",
          "Performance tracking setup",
          "30-day optimization cycle"
        ]
      }
    ]
  end

  defp faqs do
    [
      %{
        question: "Why choose a managed service over a platform like AirOps?",
        answer:
          "Platforms require you to learn the system, build workflows, and manage ongoing optimization. That's a 60-70% learning curve reduction at best - meaning 30-40% of the complexity remains. With our managed service, we handle everything from strategy to execution. You get results in 14 days, not 45+. Plus, our pricing is transparent ($10-12K projects) vs confusing task-based credits their own sales rep calls 'bane of my existence.'"
      },
      %{
        question: "Can you scale like a platform solution?",
        answer:
          "Absolutely. For Scrapfly, we built custom AI agents that audited 467 posts in 112 seconds - work that would take 40 hours manually. We use the same AI automation as platforms, but you don't have to learn or manage it. You get the scale without the complexity."
      },
      %{
        question: "What if we have a technical team?",
        answer:
          "Perfect. We augment your team, not replace them. Your devs keep building product; we handle the SEO content automation. Many of our B2B SaaS clients have strong technical teams but don't want to divert engineering resources to content workflows. We integrate with your stack (Ahrefs, SEMrush, whatever you use) and deliver production-ready work."
      },
      %{
        question: "How is B2B SaaS specialization different?",
        answer:
          "AirOps uses generic templates and is 'learning' verticals like healthcare as they onboard clients. We've been working exclusively with B2B SaaS companies - developer tools, APIs, SaaS platforms. We understand your audience (technical buyers), your metrics (CAC, LTV, conversion), and your content needs (bottom-funnel, product-led). No learning curve on our end."
      },
      %{
        question: "What's included in the 14-day delivery?",
        answer:
          "Production-ready content, not just drafts. We audit, strategize, create, optimize for SEO, and deliver publish-ready content. AirOps takes 30+ days for first use case, then 2-3 weeks refinement (45+ days total). We ship in 14 days because we're not teaching you a platform - we're delivering finished work."
      },
      %{
        question: "Do you offer guarantees?",
        answer:
          "Yes. All packages include performance guarantees. 90-Day AI Recovery Sprint: Double guarantee (traffic OR conversion refund). CAC Killer: CAC reduction guarantee or Month 4 free. Conversion Sprint: 100% refund if <50% improvement. Platforms don't offer guarantees because you're doing the work. We deliver results, so we stand behind them."
      }
    ]
  end
end
