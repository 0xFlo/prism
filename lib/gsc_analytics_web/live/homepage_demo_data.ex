defmodule GscAnalyticsWeb.Live.HomepageDemoData do
  @moduledoc """
  Provides realistic demo data for the homepage landing page.

  This module generates sample GSC analytics data to showcase
  the dashboard functionality without requiring authentication.
  """

  @doc """
  Returns demo metrics for the metric cards.
  """
  def demo_metrics do
    %{
      clicks: 8_144,
      impressions: 125_300,
      ctr: 0.065,
      position: 3.2
    }
  end

  @doc """
  Returns sample time series data for the performance chart.

  Returns a list of maps with date, clicks, impressions, ctr, and position.
  """
  def demo_time_series do
    base_date = Date.utc_today() |> Date.add(-30)

    Enum.map(0..29, fn day_offset ->
      date = Date.add(base_date, day_offset)
      # Generate realistic trending data
      clicks = trunc(200 + day_offset * 8 + :rand.uniform(50))
      impressions = clicks * trunc(15 + :rand.uniform(5))
      ctr = clicks / impressions

      %{
        date: date,
        clicks: clicks,
        impressions: impressions,
        ctr: ctr,
        position: 2.5 + :rand.uniform() * 1.5
      }
    end)
  end

  @doc """
  Returns a list of sample URLs with performance metrics.
  """
  def demo_urls do
    [
      %{
        url: "https://example.com/best-web-scraping-tools-2025",
        selected_clicks: 2_450,
        selected_impressions: 35_200,
        selected_ctr: 0.0696,
        selected_position: 2.1,
        wow_growth_last4w: 15.3,
        type: "Article",
        content_category: "Tutorial",
        first_seen_date: ~D[2024-03-15],
        needs_update: false,
        redirect_url: nil
      },
      %{
        url: "https://example.com/reddit-scraping-api-guide",
        selected_clicks: 1_890,
        selected_impressions: 28_400,
        selected_ctr: 0.0666,
        selected_position: 2.8,
        wow_growth_last4w: 24.7,
        type: "Guide",
        content_category: "Documentation",
        first_seen_date: ~D[2024-05-22],
        needs_update: false,
        redirect_url: nil
      },
      %{
        url: "https://example.com/ai-overviews-seo-impact",
        selected_clicks: 1_620,
        selected_impressions: 42_100,
        selected_ctr: 0.0385,
        selected_position: 4.2,
        wow_growth_last4w: 8.2,
        type: "Article",
        content_category: "Analysis",
        first_seen_date: ~D[2024-06-10],
        needs_update: false,
        redirect_url: nil
      },
      %{
        url: "https://example.com/google-search-console-automation",
        selected_clicks: 980,
        selected_impressions: 18_700,
        selected_ctr: 0.0524,
        selected_position: 3.5,
        wow_growth_last4w: -3.1,
        type: "Tutorial",
        content_category: "How-to",
        first_seen_date: ~D[2024-01-08],
        needs_update: true,
        redirect_url: nil
      },
      %{
        url: "https://example.com/serp-tracking-reddit-results",
        selected_clicks: 745,
        selected_impressions: 12_300,
        selected_ctr: 0.0606,
        selected_position: 2.9,
        wow_growth_last4w: 18.9,
        type: "Article",
        content_category: "Feature",
        first_seen_date: ~D[2024-07-14],
        needs_update: false,
        redirect_url: nil
      }
    ]
  end

  @doc """
  Returns summary statistics for the demo data.
  """
  def demo_stats do
    %{
      total_urls: 127,
      total_clicks: 42_380,
      total_impressions: 687_200,
      avg_ctr: 0.0617,
      avg_position: 3.1,
      month_over_month_change: 12.4,
      all_time: %{
        earliest_date: ~D[2023-09-01],
        latest_date: Date.utc_today(),
        days_with_data: 245
      }
    }
  end

  @doc """
  Returns demo feature highlights for the landing page.
  """
  def feature_highlights do
    [
      %{
        icon: "hero-magnifying-glass-circle",
        title: "Reddit SERP Tracking",
        description:
          "Automatically scrape and monitor Reddit's top 3 positions in Google search results. Never miss when Reddit outranks your content.",
        color: "indigo"
      },
      %{
        icon: "hero-sparkles",
        title: "AI Overviews Monitoring",
        description:
          "Track your rankings in Google's AI-powered search overviews. Stay ahead of the AI-first search revolution.",
        color: "emerald"
      },
      %{
        icon: "hero-chart-bar",
        title: "GSC Analytics Automation",
        description:
          "Full Google Search Console integration with automated daily syncs. Your AI agent works 24/7 so you don't have to.",
        color: "purple"
      },
      %{
        icon: "hero-light-bulb",
        title: "AI-Powered Insights",
        description:
          "Get actionable recommendations on which content needs updates, where opportunities lie, and what's trending.",
        color: "amber"
      }
    ]
  end

  @doc """
  Returns pricing information.
  """
  def pricing_info do
    %{
      price: "$10,000",
      period: "year",
      features: [
        "Unlimited property monitoring",
        "Daily automated syncs",
        "Reddit top 3 tracking",
        "AI Overviews rank monitoring",
        "Advanced analytics dashboard",
        "Export & API access",
        "Priority support"
      ],
      cta_text: "Hire Your AI Agent",
      cta_subtext: "Start automating your SEO today"
    }
  end

  @doc """
  Returns testimonial placeholders (for social proof section).
  """
  def testimonials do
    [
      %{
        quote:
          "This AI agent has completely transformed how we track our SEO performance. The Reddit tracking alone is worth it.",
        author: "Sarah Chen",
        role: "Head of Growth, TechStartup Inc",
        avatar_initials: "SC"
      },
      %{
        quote:
          "Finally, a tool that actually monitors AI Overviews. This is the future of SEO tracking.",
        author: "Marcus Rodriguez",
        role: "SEO Director, Enterprise Co",
        avatar_initials: "MR"
      },
      %{
        quote:
          "Set it and forget it. The automation is flawless and the insights are actionable. Best $10k we've spent.",
        author: "Emily Thompson",
        role: "Founder, ContentScale",
        avatar_initials: "ET"
      }
    ]
  end
end
