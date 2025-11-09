defmodule GscAnalyticsWeb.Live.PricingData do
  @moduledoc """
  Provides pricing tier configurations and feature comparison data.

  Enterprise-focused pricing with three tiers optimized for teams with 1 domain.
  """

  @doc """
  Returns all pricing tiers with complete configuration.
  """
  def pricing_tiers do
    [
      %{
        id: :pro,
        name: "Pro",
        price: "$2,500",
        price_annual: 2_500,
        period: "year",
        description: "Perfect for growing teams",
        cta_text: "Start Free Trial",
        cta_style: "outline",
        popular: false,
        features: tier_features(:pro)
      },
      %{
        id: :business,
        name: "Business",
        price: "$10,000",
        price_annual: 10_000,
        period: "year",
        description: "For teams that need more power",
        cta_text: "Get Started",
        cta_style: "primary",
        popular: true,
        badge: "Most Popular",
        usage_note: "Choose 5x or 20x more usage than Pro*",
        features: tier_features(:business)
      },
      %{
        id: :max,
        name: "Max",
        price: "$50,000",
        price_annual: 50_000,
        period: "year",
        description: "Autonomous AI for enterprise scale",
        cta_text: "Schedule Demo",
        cta_style: "premium",
        popular: false,
        badge: "AI Powered",
        usage_note: "20x more usage than Business*",
        features: tier_features(:max)
      }
    ]
  end

  @doc """
  Returns feature comparison data organized by category.
  """
  def feature_comparison do
    [
      %{
        category: "Monitoring & Sync",
        features: [
          %{
            name: "Domains monitored",
            pro: "1 domain",
            business: "1 domain",
            max: "1 domain",
            tooltip: "Enterprise-focused: deep analysis of your primary domain"
          },
          %{
            name: "Sync frequency",
            pro: "Weekly",
            business: "Daily",
            max: "Real-time (every 6hrs)",
            tooltip: "How often we fetch fresh data from Google Search Console"
          },
          %{
            name: "Data retention",
            pro: "3 months",
            business: "12 months",
            max: "Unlimited",
            tooltip: "Historical data available for trend analysis"
          },
          %{
            name: "Historical backfill",
            pro: false,
            business: "Up to 1 year",
            max: "Unlimited",
            tooltip: "Import historical data when you first sign up"
          }
        ]
      },
      %{
        category: "Advanced Features",
        features: [
          %{
            name: "Reddit top 3 tracking",
            pro: false,
            business: true,
            max: true,
            tooltip: "Monitor when Reddit outranks you in top 3 positions"
          },
          %{
            name: "AI Overviews monitoring",
            pro: false,
            business: true,
            max: true,
            tooltip: "Track your presence in Google's AI-generated answers"
          },
          %{
            name: "Competitor intelligence",
            pro: false,
            business: "Basic",
            max: "AI-powered",
            tooltip: "Automatic tracking and analysis of competitor rankings"
          },
          %{
            name: "Custom automation workflows",
            pro: false,
            business: false,
            max: true,
            tooltip: "Build if-then rules: e.g., if CTR drops 20% → send Slack alert"
          },
          %{
            name: "Autonomous AI agent",
            pro: false,
            business: false,
            max: true,
            tooltip: "AI runs 24/7 analysis and sends proactive insights"
          }
        ]
      },
      %{
        category: "Team & Collaboration",
        features: [
          %{
            name: "User seats",
            pro: "3 users",
            business: "10 users",
            max: "Unlimited",
            tooltip: "Team members with full dashboard access"
          },
          %{
            name: "White-label reports",
            pro: false,
            business: false,
            max: true,
            tooltip: "Custom branded PDF/email reports for clients"
          },
          %{
            name: "Export & API access",
            pro: false,
            business: true,
            max: true,
            tooltip: "Download data as CSV or connect via REST API"
          }
        ]
      },
      %{
        category: "Support & Services",
        features: [
          %{
            name: "Support level",
            pro: "Email",
            business: "Priority (chat + email)",
            max: "Dedicated account manager",
            tooltip: "Response time SLAs vary by tier"
          },
          %{
            name: "Onboarding",
            pro: "Self-service",
            business: "Assisted setup",
            max: "White-glove onboarding",
            tooltip: "Help getting your account configured and data flowing"
          },
          %{
            name: "SLA guarantee",
            pro: false,
            business: false,
            max: "99.9% uptime",
            tooltip: "Service level agreement with uptime guarantees"
          },
          %{
            name: "Feature requests",
            pro: false,
            business: false,
            max: "Priority queue",
            tooltip: "Your feature requests get built first"
          }
        ]
      }
    ]
  end

  @doc """
  Returns Max plan use cases for role-based tabs.
  """
  def max_use_cases do
    [
      %{
        id: "agency",
        role: "SEO Agencies",
        icon: "hero-building-office",
        challenge: "Managing 50+ clients with different reporting needs",
        solution: "Autonomous monitoring + white-label reports",
        artifact_title: "Multi-Client Dashboard",
        artifact_description: "Monitor all client properties in one unified view",
        output_example:
          "Weekly client reports generated at 6am Monday—delivered to client inboxes automatically. No manual work required.",
        stats: [
          %{label: "Clients managed", value: "50+"},
          %{label: "Time saved weekly", value: "15 hours"},
          %{label: "Client retention", value: "+40%"}
        ]
      },
      %{
        id: "enterprise",
        role: "Enterprise Teams",
        icon: "hero-globe-alt",
        challenge: "Global brand with 100+ international subdomains",
        solution: "Real-time anomaly detection across all properties",
        artifact_title: "Geographic Performance Heatmap",
        artifact_description: "AI-detected ranking changes by region",
        output_example:
          "AI detected 15% CTR drop in EMEA region at 3am Tuesday—sent Slack alert before it hit your OKRs. Investigation revealed Google algorithm update.",
        stats: [
          %{label: "Subdomains tracked", value: "100+"},
          %{label: "Issues caught early", value: "23/month"},
          %{label: "Average response time", value: "< 4 hours"}
        ]
      },
      %{
        id: "ecommerce",
        role: "E-commerce",
        icon: "hero-shopping-cart",
        challenge: "10,000+ product pages to optimize",
        solution: "Automated category-level analysis with priority scoring",
        artifact_title: "Product Category Performance",
        artifact_description: "AI-ranked optimization opportunities by revenue impact",
        output_example:
          "AI identified 47 high-value product pages needing meta updates—generated SEO optimization briefs automatically. Estimated revenue impact: $280K/year.",
        stats: [
          %{label: "Product pages", value: "10,000+"},
          %{label: "Auto-optimized monthly", value: "500+"},
          %{label: "Revenue uplift", value: "+18%"}
        ]
      },
      %{
        id: "multibrand",
        role: "Multi-Brand",
        icon: "hero-squares-plus",
        challenge: "Managing 12 brands with separate analytics needs",
        solution: "Unified dashboard with brand-level permissioning",
        artifact_title: "Cross-Brand Competitive Intelligence",
        artifact_description: "See how your brands compete against each other",
        output_example:
          "Cross-brand insight: Brand A losing ground to Brand C in 'sustainable fashion' queries. AI recommendation: Consolidate content on Brand A to avoid cannibalization.",
        stats: [
          %{label: "Brands managed", value: "12"},
          %{label: "Cannibalization issues fixed", value: "34"},
          %{label: "Cross-brand efficiency", value: "+65%"}
        ]
      }
    ]
  end

  @doc """
  Returns FAQ items for pricing page.
  """
  def pricing_faqs do
    [
      %{
        question: "What counts as 'usage'?",
        answer:
          "Usage includes API calls to Google Search Console, data syncs, Reddit tracking requests, AI Overviews checks, and AI agent analysis operations. We keep this intentionally flexible so you're not penalized for exploring your data."
      },
      %{
        question: "Can I change my usage multiplier later?",
        answer:
          "Yes! Business plan customers can switch between 5x and 20x usage tiers at any time. Changes take effect at your next billing cycle."
      },
      %{
        question: "What does the AI agent actually do?",
        answer:
          "The Max plan AI agent runs autonomous analysis 24/7: monitors your rankings, detects anomalies, tracks competitors, identifies content decay, and sends proactive alerts. It works while you sleep so you never miss critical changes."
      },
      %{
        question: "Do you support multi-domain tracking?",
        answer:
          "Currently, all plans focus on deep analysis of one primary domain (perfect for enterprises). Multi-domain tracking is on our roadmap for 2025—Enterprise+ plan customers will get early access."
      },
      %{
        question: "What's your refund policy?",
        answer:
          "We offer a 30-day money-back guarantee on all annual plans. If you're not satisfied within the first 30 days, we'll refund your full payment—no questions asked."
      },
      %{
        question: "Can I try before I buy?",
        answer:
          "Pro and Business plans include a 14-day free trial. For Max plan, we offer personalized demos where you can see the AI agent in action with your own data."
      }
    ]
  end

  @doc """
  Returns trust signals and social proof.
  """
  def trust_signals do
    %{
      customers: "50+",
      domains_managed: "500+",
      data_points_tracked: "2.5M+",
      customer_testimonial: %{
        quote:
          "Reduced manual reporting time by 87%—we now handle 3x more clients with the same team size.",
        author: "Sarah Chen",
        role: "Head of SEO, Growth Agency Inc"
      }
    }
  end

  # Private helpers

  defp tier_features(:pro) do
    [
      "1 domain monitoring",
      "3 user seats",
      "Weekly automated syncs",
      "3 months data retention",
      "Basic analytics dashboard",
      "Email support"
    ]
  end

  defp tier_features(:business) do
    [
      "1 domain monitoring",
      "10 user seats",
      "Daily automated syncs",
      "12 months data retention",
      "Reddit top 3 tracking",
      "AI Overviews monitoring",
      "Advanced analytics",
      "Export & API access",
      "Priority support (chat + email)",
      "Choose 5x or 20x usage*"
    ]
  end

  defp tier_features(:max) do
    [
      "1 domain monitoring",
      "Unlimited user seats",
      "Real-time syncs (every 6 hours)",
      "Unlimited data retention",
      "Autonomous AI agent (24/7)",
      "Advanced Reddit intelligence",
      "AI Overviews competitive analysis",
      "Custom automation workflows",
      "White-label reports",
      "Dedicated account manager",
      "99.9% SLA guarantee",
      "Priority feature requests",
      "20x Business plan usage*"
    ]
  end
end
