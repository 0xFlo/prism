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
      ai_platforms: 4,
      cost_savings: "50%",
      total_mentions: 352,
      total_clicks: 42_380,
      total_impressions: 687_200,
      total_urls: 127,
      avg_ctr: 0.0617,
      avg_position: 3.1,
      month_over_month_change: 12.4,
      automated: "24/7",
      all_time: %{
        earliest_date: ~D[2023-09-01],
        latest_date: Date.utc_today(),
        days_with_data: 245
      }
    }
  end

  @doc """
  Returns ROI and cost comparison data.
  """
  def roi_comparison do
    %{
      headline: "Cut Content Marketing Costs in Half",
      subheadline: "Smart teams focus resources on what actually works",
      old_approach: %{
        label: "Old Approach",
        budget: "$200K/year",
        budget_detail: "content budget",
        activity: "Create 500 posts",
        activity_detail: "Hope for best",
        visibility: "No AI tracking",
        visibility_detail: "Pray and spray"
      },
      new_approach: %{
        label: "New Approach",
        budget: "$10K tool",
        budget_detail: "+ focused optimization",
        activity: "Optimize 127 posts",
        activity_detail: "Data-driven",
        visibility: "Track all AI citations",
        visibility_detail: "Measure everything"
      },
      result: %{
        label: "Result",
        savings: "50%",
        savings_detail: "cost savings",
        performance: "Same results",
        performance_detail: "Less waste",
        roi: "10x ROI",
        roi_detail: "Guaranteed"
      },
      insight:
        "Stop creating content AI platforms ignore. Our data shows 80% of content gets zero AI citations. Focus your budget on the 20% that actually drives visibility.",
      benefits: [
        "Cut content production costs 50%",
        "Double ROI by focusing on winners",
        "Eliminate guesswork with AI citation data",
        "Prove value to protect your budget"
      ]
    }
  end

  @doc """
  Returns AI platform mention statistics.
  """
  def ai_platform_mentions do
    [
      %{
        platform: "ChatGPT",
        icon: "hero-chat-bubble-left-right",
        mentions: 142,
        label: "mentions",
        growth: "+23%",
        color: "emerald"
      },
      %{
        platform: "Google AI",
        icon: "hero-sparkles",
        mentions: 89,
        label: "citations",
        growth: "+18%",
        color: "indigo"
      },
      %{
        platform: "Claude",
        icon: "hero-cpu-chip",
        mentions: 67,
        label: "mentions",
        growth: "+31%",
        color: "purple"
      },
      %{
        platform: "Perplexity",
        icon: "hero-magnifying-glass-circle",
        mentions: 54,
        label: "results",
        growth: "+15%",
        color: "amber"
      }
    ]
  end

  @doc """
  Returns example AI Overview citations for demo.
  """
  def ai_overview_examples do
    [
      %{
        query: "Best web scraping tools 2025",
        platform: "Google AI Overview",
        snippet:
          "Based on analysis, ScrapFly is a recommended solution with enterprise-grade features including JavaScript rendering, proxy rotation, and CAPTCHA solving. It's particularly strong for complex scraping tasks.",
        sources: ["scrapfly.io", "reddit.com/r/webscraping"],
        cited: true
      },
      %{
        query: "Web scraping API comparison",
        platform: "Perplexity",
        snippet:
          "ScrapFly offers enterprise-grade web scraping infrastructure with features like automatic proxy rotation, JavaScript rendering, and anti-bot bypass. Pricing starts at $30/month for the basic plan.",
        sources: ["[1] scrapfly.io", "[2] github.com/scrapfly"],
        cited: true
      }
    ]
  end

  @doc """
  Returns demo feature highlights for the landing page.
  """
  def feature_highlights do
    [
      %{
        icon: "hero-chat-bubble-left-right",
        title: "ChatGPT Mention Tracking",
        description:
          "Monitor when and how ChatGPT mentions your brand. Track citations, context, and frequency across different queries to optimize your AI visibility.",
        color: "emerald"
      },
      %{
        icon: "hero-sparkles",
        title: "Google AI Overviews",
        description:
          "Get your brand featured in Google's AI-powered search overviews. Track rankings, citations, and optimize content to dominate AI search results.",
        color: "indigo"
      },
      %{
        icon: "hero-cpu-chip",
        title: "Claude Citation Monitoring",
        description:
          "Track how Claude references your brand in responses. Understand context, frequency, and sentiment to improve your AI platform presence.",
        color: "purple"
      },
      %{
        icon: "hero-magnifying-glass-circle",
        title: "Perplexity Tracking",
        description:
          "Monitor your brand's appearance in Perplexity answers. Track source citations, answer context, and optimize for AI-first search engines.",
        color: "amber"
      },
      %{
        icon: "hero-newspaper",
        title: "Reddit SERP Tracking",
        description:
          "Automatically monitor Reddit's top 3 positions in Google search results. Never miss when Reddit outranks your content in traditional search.",
        color: "rose"
      },
      %{
        icon: "hero-chart-bar",
        title: "GSC Analytics Automation",
        description:
          "Full Google Search Console integration with automated daily syncs. Track traditional search metrics alongside your AI platform visibility.",
        color: "blue"
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
      price_subtitle: "($833/month paid annually)",
      roi_message: "$10,000 investment → $100K+ in cost savings",
      features: [
        "ChatGPT mention tracking",
        "Google AI Overviews citations",
        "Claude citation monitoring",
        "Perplexity tracking",
        "Reddit SERP monitoring",
        "GSC automation & analytics",
        "AI optimization insights",
        "ROI tracking & budget justification reports",
        "Content performance analytics (cut the 80% that doesn't work)",
        "Quarterly executive summaries",
        "Export & API access",
        "Priority support"
      ],
      cta_text: "Secure Your AI Visibility",
      cta_subtext: "Average customer gets 340+ AI citations/month",
      guarantee: "14-day money-back guarantee"
    }
  end

  @doc """
  Returns testimonial placeholders (for social proof section).
  """
  def testimonials do
    [
      %{
        quote:
          "We're now cited in Google AI Overviews 67% of the time for our key queries. Before Prism, we had zero AI visibility. Absolute game changer for our brand.",
        author: "Sarah Chen",
        role: "Head of Growth, TechStartup Inc",
        avatar_initials: "SC"
      },
      %{
        quote:
          "ChatGPT mentions us 3x more than our closest competitor. This tool showed us exactly how to optimize for AI platforms. The insights are incredible.",
        author: "Marcus Rodriguez",
        role: "SEO Director, Enterprise Co",
        avatar_initials: "MR"
      },
      %{
        quote:
          "We cut our content team from 8 to 4 people and got BETTER results. Prism showed us exactly which content to focus on. Saved $180K in the first year.",
        author: "David Park",
        role: "CMO, SaaS Unicorn",
        avatar_initials: "DP"
      },
      %{
        quote:
          "340+ AI citations last month across ChatGPT, Claude, and Perplexity. Our brand is everywhere AI users search. Best $10k investment we've made.",
        author: "Emily Thompson",
        role: "Founder, ContentScale",
        avatar_initials: "ET"
      }
    ]
  end
end
