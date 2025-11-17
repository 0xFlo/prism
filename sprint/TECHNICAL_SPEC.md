# SERP Landscape Intelligence - Technical Specification

## Overview

Transform the single "Check SERP Position" button into a comprehensive SERP intelligence system focused on AI Overview monitoring, competitor tracking, and content type analysis.

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                      User Interface Layer                        │
├─────────────────────────────────────────────────────────────────┤
│  DashboardUrlLive                                                │
│    ├─ "Check Top Keywords" button                               │
│    └─ Quick summary cards (AI Overview presence, position)      │
│                                                                   │
│  DashboardSerpLandscapeLive (NEW)                               │
│    ├─ AI Overview Intelligence Panel                            │
│    ├─ Competitor Landscape Heatmap                              │
│    └─ Content Type Distribution Chart                           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Business Logic Layer                        │
├─────────────────────────────────────────────────────────────────┤
│  ContentInsights.SerpLandscape (NEW)                            │
│    ├─ ai_overview_stats(url)                                    │
│    ├─ competitor_positions(url)                                 │
│    ├─ content_type_distribution(url)                            │
│    └─ rank_history(url, keyword)                                │
│                                                                   │
│  ContentInsights.TopQueries (EXISTING)                          │
│    └─ list_top_queries(url, limit: N)                           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Background Jobs Layer                       │
├─────────────────────────────────────────────────────────────────┤
│  SerpCheckWorker (EXISTING, MINOR CHANGES)                      │
│    ├─ Processes 1 keyword check                                 │
│    ├─ Calls ScrapFly API (36 credits)                           │
│    ├─ HTML parsing → position detection                         │
│    ├─ AI Overview extraction                                    │
│    └─ Store in serp_snapshots                                   │
│                                                                   │
│  Oban Queue: :serp_check                                        │
│    ├─ Priority: 2                                                │
│    ├─ Max attempts: 3                                            │
│    └─ Unique: 1 hour (idempotency)                              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Data Collection Layer                        │
├─────────────────────────────────────────────────────────────────┤
│  DataSources.SERP.Core.Client (EXISTING)                        │
│    └─ fetch_serp(keyword, geo, url)                             │
│                                                                   │
│  DataSources.SERP.Core.HTMLParser (MODIFY)                      │
│    ├─ extract_position(html, target_url)                        │
│    ├─ extract_competitors(html)  → Top 10 (was 3)              │
│    └─ classify_content_type(url, title) → NEW                   │
│                                                                   │
│  DataSources.SERP.Core.AIOverviewExtractor (EXISTING)           │
│    ├─ extract(html)                                              │
│    └─ extract_citations(ao_html)                                │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                       Data Storage Layer                         │
├─────────────────────────────────────────────────────────────────┤
│  serp_snapshots table                                            │
│    ├─ keyword, position, checked_at                             │
│    ├─ competitors (array of maps with content_type)  → MODIFY   │
│    ├─ ai_overview_present, text, citations                      │
│    ├─ content_types_present → NEW                               │
│    ├─ scrapfly_mentioned_in_ao → NEW                            │
│    └─ scrapfly_citation_position → NEW                          │
│                                                                   │
│  Indexes:                                                        │
│    ├─ (account_id, property_url, url, checked_at)               │
│    └─ (ai_overview_present)                                     │
└─────────────────────────────────────────────────────────────────┘
```

---

## Database Schema Changes

### Migration: `add_serp_landscape_fields.exs`

```elixir
defmodule GscAnalytics.Repo.Migrations.AddSerpLandscapeFields do
  use Ecto.Migration

  def up do
    alter table(:serp_snapshots) do
      # Track which content types appear in this SERP
      add :content_types_present, {:array, :string}, default: []

      # Quick flag: Is ScrapFly mentioned in AI Overview?
      add :scrapfly_mentioned_in_ao, :boolean, default: false

      # Position in AI Overview citation list (1-20)
      add :scrapfly_citation_position, :integer
    end

    # Optimize queries for landscape aggregation
    create index(:serp_snapshots, [:account_id, :property_url, :url, :checked_at])

    # Filter snapshots by AI Overview presence
    create index(:serp_snapshots, [:ai_overview_present])
  end

  def down do
    drop index(:serp_snapshots, [:ai_overview_present])
    drop index(:serp_snapshots, [:account_id, :property_url, :url, :checked_at])

    alter table(:serp_snapshots) do
      remove :content_types_present
      remove :scrapfly_mentioned_in_ao
      remove :scrapfly_citation_position
    end
  end
end
```

### Enhanced `competitors` Field Structure

**Before** (current):
```elixir
competitors: [
  %{position: 3, url: "https://example.com/page", title: "Example Page"}
]
```

**After** (enhanced):
```elixir
competitors: [
  %{
    position: 3,
    url: "https://example.com/page",
    title: "Example Page",
    domain: "example.com",          # NEW: Extracted for aggregation
    content_type: "website"         # NEW: reddit|youtube|paa|ai_overview|forum|website
  }
]
```

---

## API Specifications

### New Context Module: `ContentInsights.SerpLandscape`

**File**: `lib/gsc_analytics/content_insights/serp_landscape.ex`

```elixir
defmodule GscAnalytics.ContentInsights.SerpLandscape do
  @moduledoc """
  Aggregates SERP snapshot data to provide landscape intelligence.

  Focuses on:
  - AI Overview citation analysis
  - Competitor position tracking
  - Content type distribution
  - Rank history over time
  """

  import Ecto.Query
  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.SerpSnapshot

  @doc """
  Returns AI Overview statistics for a URL across all keywords.

  ## Returns

  %{
    total_keywords_checked: 7,
    keywords_with_ao: 5,
    ao_presence_percentage: 71.4,
    scrapfly_citations: 3,
    citation_breakdown: [
      %{domain: "scrapfly.io", count: 3, keywords: ["web scraping", "api"]},
      %{domain: "competitor.com", count: 5, keywords: ["web scraping", "python", "..."]}
    ],
    ao_samples: [
      %{
        keyword: "web scraping api",
        text: "Web scraping APIs allow...",
        scrapfly_cited: true,
        scrapfly_position: 2
      }
    ]
  }
  """
  @spec ai_overview_stats(String.t(), keyword()) :: map()
  def ai_overview_stats(url, opts \\ []) do
    account_id = Keyword.get(opts, :account_id)
    property_url = Keyword.get(opts, :property_url)

    snapshots =
      SerpSnapshot
      |> where([s], s.url == ^url)
      |> where([s], s.account_id == ^account_id)
      |> where([s], s.property_url == ^property_url)
      |> order_by([s], desc: s.checked_at)
      # Get latest snapshot per keyword
      |> distinct([s], s.keyword)
      |> Repo.all()

    total = length(snapshots)
    with_ao = Enum.count(snapshots, & &1.ai_overview_present)

    scrapfly_citations =
      snapshots
      |> Enum.filter(& &1.scrapfly_mentioned_in_ao)
      |> length()

    citation_breakdown = build_citation_breakdown(snapshots)
    ao_samples = build_ao_samples(snapshots)

    %{
      total_keywords_checked: total,
      keywords_with_ao: with_ao,
      ao_presence_percentage: if(total > 0, do: with_ao / total * 100, else: 0),
      scrapfly_citations: scrapfly_citations,
      citation_breakdown: citation_breakdown,
      ao_samples: ao_samples
    }
  end

  @doc """
  Returns competitor position data for heatmap visualization.

  ## Returns

  %{
    domains: ["scrapfly.io", "competitor1.com", "competitor2.com", ...],
    keywords: ["web scraping", "api", "python scraping", ...],
    positions: %{
      "scrapfly.io" => %{
        "web scraping" => 3,
        "api" => 1,
        "python scraping" => nil  # Not in top 10
      },
      "competitor1.com" => %{...}
    },
    averages: %{
      "scrapfly.io" => 4.2,
      "competitor1.com" => 6.5
    }
  }
  """
  @spec competitor_positions(String.t(), keyword()) :: map()
  def competitor_positions(url, opts \\ []) do
    snapshots = fetch_latest_snapshots(url, opts)

    # Extract all unique domains and keywords
    all_domains =
      snapshots
      |> Enum.flat_map(fn snapshot ->
        Enum.map(snapshot.competitors, & &1["domain"])
      end)
      |> Enum.uniq()
      |> Enum.sort()

    keywords = Enum.map(snapshots, & &1.keyword)

    # Build position matrix
    positions =
      all_domains
      |> Map.new(fn domain ->
        keyword_positions =
          keywords
          |> Map.new(fn keyword ->
            position = find_domain_position(snapshots, keyword, domain)
            {keyword, position}
          end)

        {domain, keyword_positions}
      end)

    # Calculate averages (excluding nil values)
    averages =
      all_domains
      |> Map.new(fn domain ->
        positions_list =
          positions[domain]
          |> Map.values()
          |> Enum.reject(&is_nil/1)

        avg = if length(positions_list) > 0 do
          Enum.sum(positions_list) / length(positions_list)
        else
          nil
        end

        {domain, avg}
      end)
      |> Enum.reject(fn {_domain, avg} -> is_nil(avg) end)
      |> Enum.sort_by(fn {_domain, avg} -> avg end)  # Best avg first
      |> Map.new()

    %{
      domains: all_domains,
      keywords: keywords,
      positions: positions,
      averages: averages
    }
  end

  @doc """
  Returns content type distribution across all snapshots.

  ## Returns

  %{
    distribution: %{
      "reddit" => 15,
      "youtube" => 10,
      "paa" => 5,
      "ai_overview" => 7,
      "website" => 50
    },
    percentages: %{
      "reddit" => 15.0,
      "youtube" => 10.0,
      ...
    },
    by_type: [
      %{
        type: "reddit",
        count: 15,
        percentage: 15.0,
        avg_position: 4.5,
        domains: ["reddit.com"]
      },
      ...
    ]
  }
  """
  @spec content_type_distribution(String.t(), keyword()) :: map()
  def content_type_distribution(url, opts \\ []) do
    snapshots = fetch_latest_snapshots(url, opts)

    # Flatten all competitors from all snapshots
    all_competitors =
      snapshots
      |> Enum.flat_map(& &1.competitors)

    total_count = length(all_competitors)

    # Group by content type
    distribution =
      all_competitors
      |> Enum.group_by(& &1["content_type"])
      |> Map.new(fn {type, list} -> {type, length(list)} end)

    percentages =
      distribution
      |> Map.new(fn {type, count} ->
        {type, count / total_count * 100}
      end)

    by_type =
      distribution
      |> Enum.map(fn {type, count} ->
        competitors_of_type = Enum.filter(all_competitors, & &1["content_type"] == type)

        avg_position =
          competitors_of_type
          |> Enum.map(& &1["position"])
          |> then(fn positions ->
            Enum.sum(positions) / length(positions)
          end)

        domains =
          competitors_of_type
          |> Enum.map(& &1["domain"])
          |> Enum.uniq()

        %{
          type: type,
          count: count,
          percentage: percentages[type],
          avg_position: avg_position,
          domains: domains
        }
      end)
      |> Enum.sort_by(& &1.count, :desc)

    %{
      distribution: distribution,
      percentages: percentages,
      by_type: by_type
    }
  end

  # Private helpers

  defp fetch_latest_snapshots(url, opts) do
    account_id = Keyword.get(opts, :account_id)
    property_url = Keyword.get(opts, :property_url)

    SerpSnapshot
    |> where([s], s.url == ^url)
    |> where([s], s.account_id == ^account_id)
    |> where([s], s.property_url == ^property_url)
    |> order_by([s], desc: s.checked_at)
    |> distinct([s], s.keyword)
    |> Repo.all()
  end

  defp build_citation_breakdown(snapshots) do
    snapshots
    |> Enum.filter(& &1.ai_overview_present)
    |> Enum.flat_map(fn snapshot ->
      Enum.map(snapshot.ai_overview_citations, fn citation ->
        Map.put(citation, "keyword", snapshot.keyword)
      end)
    end)
    |> Enum.group_by(& &1["domain"])
    |> Enum.map(fn {domain, citations} ->
      %{
        domain: domain,
        count: length(citations),
        keywords: Enum.map(citations, & &1["keyword"]) |> Enum.uniq()
      }
    end)
    |> Enum.sort_by(& &1.count, :desc)
  end

  defp build_ao_samples(snapshots) do
    snapshots
    |> Enum.filter(& &1.ai_overview_present)
    |> Enum.map(fn snapshot ->
      %{
        keyword: snapshot.keyword,
        text: snapshot.ai_overview_text,
        scrapfly_cited: snapshot.scrapfly_mentioned_in_ao,
        scrapfly_position: snapshot.scrapfly_citation_position
      }
    end)
  end

  defp find_domain_position(snapshots, keyword, domain) do
    snapshot = Enum.find(snapshots, & &1.keyword == keyword)

    if snapshot do
      competitor = Enum.find(snapshot.competitors, & &1["domain"] == domain)
      if competitor, do: competitor["position"], else: nil
    else
      nil
    end
  end
end
```

---

## Enhanced HTML Parser

**File**: `lib/gsc_analytics/data_sources/serp/core/html_parser.ex`

### New Function: `classify_content_type/2`

```elixir
@doc """
Classifies a SERP result by content type.

## Types
- "reddit" - Reddit discussions
- "youtube" - YouTube videos
- "paa" - People Also Ask expansions
- "ai_overview" - AI Overview section
- "forum" - Other forums (StackOverflow, Quora, etc.)
- "website" - Standard web pages

## Examples

    iex> classify_content_type("https://www.reddit.com/r/webscraping/...", "How to scrape...")
    "reddit"

    iex> classify_content_type("https://www.youtube.com/watch?v=...", "Web Scraping Tutorial")
    "youtube"

    iex> classify_content_type("https://scrapfly.io/blog/...", "Web Scraping Guide")
    "website"
"""
@spec classify_content_type(String.t(), String.t()) :: String.t()
def classify_content_type(url, title) do
  uri = URI.parse(url)
  domain = uri.host || ""

  cond do
    String.contains?(domain, "reddit.com") -> "reddit"
    String.contains?(domain, "youtube.com") -> "youtube"
    String.contains?(domain, ["stackoverflow.com", "stackexchange.com"]) -> "forum"
    String.contains?(domain, "quora.com") -> "forum"
    String.contains?(title, ["People also ask", "Related questions"]) -> "paa"
    true -> "website"
  end
end

@doc """
Extracts domain from URL for aggregation.

## Examples

    iex> extract_domain("https://scrapfly.io/blog/web-scraping")
    "scrapfly.io"

    iex> extract_domain("https://www.reddit.com/r/webscraping/comments/...")
    "reddit.com"
"""
@spec extract_domain(String.t()) :: String.t()
def extract_domain(url) do
  uri = URI.parse(url)
  (uri.host || "")
  |> String.replace(~r/^www\./, "")  # Remove www prefix
end
```

### Modified Function: `extract_competitors/1`

```elixir
@doc """
Extracts top 10 competitors from SERP HTML (increased from 3).

Returns list of maps with position, url, title, domain, and content_type.
"""
@spec extract_competitors(String.t()) :: [map()]
def extract_competitors(html) do
  html
  |> Floki.parse_document!()
  |> Floki.find("div.yuRUbf")  # 2025 Google organic result container
  |> Enum.take(10)  # Changed from 3 to 10
  |> Enum.with_index(1)
  |> Enum.map(fn {element, position} ->
    url = element |> Floki.find("a") |> Floki.attribute("href") |> List.first()
    title = element |> Floki.find("h3") |> Floki.text()

    domain = extract_domain(url)
    content_type = classify_content_type(url, title)

    %{
      position: position,
      url: url,
      title: title,
      domain: domain,
      content_type: content_type
    }
  end)
end
```

---

## Enhanced Worker Logic

**File**: `lib/gsc_analytics/workers/serp_check_worker.ex`

### Modified: Store Enhanced Data

```elixir
def perform(%Oban.Job{args: args}) do
  # ... existing code ...

  # After extracting position and AI Overview
  competitors = HTMLParser.extract_competitors(html)

  # Extract content types present in this SERP
  content_types_present =
    competitors
    |> Enum.map(& &1.content_type)
    |> Enum.uniq()

  # Check if ScrapFly is mentioned in AI Overview
  {scrapfly_mentioned, scrapfly_position} =
    if ai_overview_data.present do
      check_scrapfly_citation(ai_overview_data.citations)
    else
      {false, nil}
    end

  # Save snapshot with enhanced fields
  %SerpSnapshot{}
  |> SerpSnapshot.changeset(%{
    account_id: account_id,
    property_url: property_url,
    url: url,
    keyword: keyword,
    position: position,
    competitors: competitors,  # Now includes domain and content_type
    ai_overview_present: ai_overview_data.present,
    ai_overview_text: ai_overview_data.text,
    ai_overview_citations: ai_overview_data.citations,
    content_types_present: content_types_present,  # NEW
    scrapfly_mentioned_in_ao: scrapfly_mentioned,  # NEW
    scrapfly_citation_position: scrapfly_position, # NEW
    geo: geo,
    checked_at: DateTime.utc_now()
  })
  |> Repo.insert()
end

defp check_scrapfly_citation(citations) do
  scrapfly_citation =
    citations
    |> Enum.with_index(1)
    |> Enum.find(fn {citation, _pos} ->
      String.contains?(citation["domain"] || "", "scrapfly")
    end)

  case scrapfly_citation do
    {_citation, position} -> {true, position}
    nil -> {false, nil}
  end
end
```

---

## UI Components

### New Component Module: `SerpComponents`

**File**: `lib/gsc_analytics_web/components/serp_components.ex`

```elixir
defmodule GscAnalyticsWeb.Components.SerpComponents do
  use Phoenix.Component
  import GscAnalyticsWeb.CoreComponents

  @doc """
  Renders AI Overview intelligence panel.

  Shows:
  - AI Overview presence percentage
  - Citation analysis table
  - ScrapFly highlights
  - Sample AI Overview texts
  """
  attr :stats, :map, required: true
  attr :class, :string, default: ""

  def ai_overview_panel(assigns) do
    ~H"""
    <div class={["card bg-base-100 shadow-xl", @class]}>
      <div class="card-body">
        <h2 class="card-title">
          <.icon name="hero-sparkles" class="h-5 w-5" />
          AI Overview Intelligence
        </h2>

        <!-- Presence Card -->
        <div class="stats shadow">
          <div class="stat">
            <div class="stat-title">AI Overview Presence</div>
            <div class="stat-value">
              <%= @stats.keywords_with_ao %> / <%= @stats.total_keywords_checked %>
            </div>
            <div class="stat-desc">
              <%= Float.round(@stats.ao_presence_percentage, 1) %>% of keywords
            </div>
          </div>

          <div class="stat">
            <div class="stat-title">ScrapFly Citations</div>
            <div class="stat-value text-primary">
              <%= @stats.scrapfly_citations %>
            </div>
            <div class="stat-desc">
              Mentions in AI Overviews
            </div>
          </div>
        </div>

        <!-- Citation Breakdown Table -->
        <div class="overflow-x-auto">
          <table class="table table-zebra">
            <thead>
              <tr>
                <th>Domain</th>
                <th>Citations</th>
                <th>Keywords Cited In</th>
              </tr>
            </thead>
            <tbody>
              <%= for citation <- @stats.citation_breakdown do %>
                <tr class={if String.contains?(citation.domain, "scrapfly"), do: "bg-primary/10"}>
                  <td class="font-semibold">
                    <%= if String.contains?(citation.domain, "scrapfly") do %>
                      <.icon name="hero-star-solid" class="inline h-4 w-4 text-primary" />
                    <% end %>
                    <%= citation.domain %>
                  </td>
                  <td><span class="badge badge-lg"><%= citation.count %></span></td>
                  <td class="text-sm">
                    <%= Enum.join(citation.keywords, ", ") %>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>

        <!-- AI Overview Samples -->
        <div class="mt-4">
          <h3 class="text-lg font-semibold mb-2">Sample AI Overviews</h3>
          <div class="space-y-3">
            <%= for sample <- Enum.take(@stats.ao_samples, 3) do %>
              <div class="collapse collapse-arrow bg-base-200">
                <input type="checkbox" />
                <div class="collapse-title font-medium">
                  <%= sample.keyword %>
                  <%= if sample.scrapfly_cited do %>
                    <span class="badge badge-primary ml-2">ScrapFly Cited</span>
                  <% end %>
                </div>
                <div class="collapse-content">
                  <p class="text-sm"><%= sample.text %></p>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders competitor position heatmap.
  """
  attr :data, :map, required: true
  attr :class, :string, default: ""

  def competitor_heatmap(assigns) do
    ~H"""
    <div class={["card bg-base-100 shadow-xl", @class]}>
      <div class="card-body">
        <h2 class="card-title">
          <.icon name="hero-chart-bar" class="h-5 w-5" />
          Competitor Landscape
        </h2>

        <div class="overflow-x-auto">
          <table class="table table-xs">
            <thead>
              <tr>
                <th>Domain</th>
                <th>Avg Pos</th>
                <%= for keyword <- @data.keywords do %>
                  <th class="text-center text-xs"><%= String.slice(keyword, 0..15) %></th>
                <% end %>
              </tr>
            </thead>
            <tbody>
              <%= for domain <- Enum.take(@data.domains, 20) do %>
                <tr class={if String.contains?(domain, "scrapfly"), do: "bg-primary/10"}>
                  <td class="font-semibold text-sm"><%= domain %></td>
                  <td>
                    <%= if @data.averages[domain] do %>
                      <span class="badge badge-sm">
                        <%= Float.round(@data.averages[domain], 1) %>
                      </span>
                    <% end %>
                  </td>
                  <%= for keyword <- @data.keywords do %>
                    <td class="text-center">
                      <%= case @data.positions[domain][keyword] do %>
                        <% nil -> %>
                          <span class="text-gray-400">-</span>
                        <% position -> %>
                          <span class={[
                            "badge badge-sm",
                            position_color(position)
                          ]}>
                            <%= position %>
                          </span>
                      <% end %>
                    </td>
                  <% end %>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders content type distribution chart.
  """
  attr :data, :map, required: true
  attr :class, :string, default: ""

  def content_type_chart(assigns) do
    ~H"""
    <div class={["card bg-base-100 shadow-xl", @class]}>
      <div class="card-body">
        <h2 class="card-title">
          <.icon name="hero-squares-2x2" class="h-5 w-5" />
          Content Type Analysis
        </h2>

        <!-- Simple bar chart with percentages -->
        <div class="space-y-2">
          <%= for item <- @data.by_type do %>
            <div>
              <div class="flex justify-between text-sm mb-1">
                <span class="font-medium capitalize"><%= item.type %></span>
                <span class="text-gray-600">
                  <%= item.count %> (<%= Float.round(item.percentage, 1) %>%)
                </span>
              </div>
              <progress
                class="progress progress-primary w-full"
                value={item.percentage}
                max="100"
              ></progress>
            </div>
          <% end %>
        </div>

        <!-- Details Table -->
        <div class="overflow-x-auto mt-4">
          <table class="table table-sm">
            <thead>
              <tr>
                <th>Type</th>
                <th>Count</th>
                <th>Avg Position</th>
                <th>Example Domains</th>
              </tr>
            </thead>
            <tbody>
              <%= for item <- @data.by_type do %>
                <tr>
                  <td class="capitalize"><%= item.type %></td>
                  <td><span class="badge"><%= item.count %></span></td>
                  <td><%= Float.round(item.avg_position, 1) %></td>
                  <td class="text-xs">
                    <%= item.domains |> Enum.take(3) |> Enum.join(", ") %>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  # Helpers

  defp position_color(position) when position <= 3, do: "badge-success"
  defp position_color(position) when position <= 5, do: "badge-info"
  defp position_color(position) when position <= 7, do: "badge-warning"
  defp position_color(_), do: "badge-ghost"
end
```

---

## LiveView Implementation

### Modified: `DashboardUrlLive`

**File**: `lib/gsc_analytics_web/live/dashboard_url_live.ex`

#### New Event Handler: `check_top_keywords`

```elixir
def handle_event("check_top_keywords", _params, socket) do
  url = socket.assigns.url
  account_id = socket.assigns.current_account.id
  property_url = socket.assigns.property_url

  # Get top N keywords from GSC data
  top_queries =
    ContentInsights.list_top_queries(
      account_id: account_id,
      property_url: property_url,
      url: url,
      sort_by: "clicks",
      limit: 7
    )

  keywords = Enum.map(top_queries, & &1.query)

  # Enqueue jobs for each keyword
  jobs_created =
    Enum.map(keywords, fn keyword ->
      %{
        account_id: account_id,
        property_url: property_url,
        url: url,
        keyword: keyword,
        geo: "us"
      }
      |> SerpCheckWorker.new()
      |> Oban.insert()
    end)

  # Subscribe to completion events
  Phoenix.PubSub.subscribe(GscAnalytics.PubSub, "serp_check:#{account_id}")

  # Show progress modal
  socket =
    socket
    |> assign(:checking_keywords, keywords)
    |> assign(:checked_count, 0)
    |> assign(:show_progress_modal, true)
    |> put_flash(:info, "Checking #{length(keywords)} keywords...")

  {:noreply, socket}
end

def handle_info({:serp_check_complete, keyword}, socket) do
  checked_count = socket.assigns.checked_count + 1
  total = length(socket.assigns.checking_keywords)

  socket = assign(socket, :checked_count, checked_count)

  if checked_count >= total do
    # All checks complete
    socket =
      socket
      |> assign(:show_progress_modal, false)
      |> put_flash(:info, "✅ Checked #{total} keywords! View SERP Landscape →")
      |> push_event("scroll_to_serp", %{})

    {:noreply, socket}
  else
    {:noreply, socket}
  end
end
```

#### Modified Template Section

**File**: `lib/gsc_analytics_web/live/dashboard_url_live.html.heex`

```heex
<!-- Replace single check button -->
<div class="card bg-base-100 shadow-xl">
  <div class="card-body">
    <h3 class="card-title">SERP Analysis</h3>

    <%= if @top_queries && length(@top_queries) > 0 do %>
      <button
        phx-click="check_top_keywords"
        phx-throttle="5000"
        class="btn btn-primary w-full gap-2"
      >
        <.icon name="hero-magnifying-glass-circle" class="h-5 w-5" />
        Check SERP Landscape (Top <%= min(length(@top_queries), 7) %> Keywords)
      </button>

      <p class="text-sm text-gray-600 mt-2">
        Estimated cost: ~<%= min(length(@top_queries), 7) * 36 %> credits
      </p>

      <%= if @latest_serp_check do %>
        <.link
          navigate={~p"/dashboard/url/serp-landscape?#{[url: @url, account_id: @current_account.id, property_url: @property_url]}"}
          class="btn btn-outline btn-sm mt-2"
        >
          View Full SERP Landscape →
        </.link>

        <p class="text-xs text-gray-500 mt-1">
          Last checked: <%= Calendar.strftime(@latest_serp_check.checked_at, "%b %d, %H:%M") %>
        </p>
      <% end %>
    <% else %>
      <div class="alert alert-info">
        <p>No top queries available. Sync GSC data first to enable SERP checking.</p>
      </div>
    <% end %>
  </div>
</div>

<!-- Progress Modal -->
<%= if @show_progress_modal do %>
  <div class="modal modal-open">
    <div class="modal-box">
      <h3 class="font-bold text-lg">Checking SERP Positions</h3>
      <p class="py-4">
        Progress: <%= @checked_count %> / <%= length(@checking_keywords) %> keywords
      </p>
      <progress
        class="progress progress-primary w-full"
        value={@checked_count}
        max={length(@checking_keywords)}
      ></progress>
      <div class="text-sm mt-2 space-y-1">
        <%= for {keyword, idx} <- Enum.with_index(@checking_keywords, 1) do %>
          <div class="flex items-center gap-2">
            <%= if idx <= @checked_count do %>
              <.icon name="hero-check-circle-solid" class="h-4 w-4 text-success" />
            <% else %>
              <.icon name="hero-clock" class="h-4 w-4 text-gray-400" />
            <% end %>
            <span class={if idx <= @checked_count, do: "text-gray-600", else: "text-gray-400"}>
              <%= keyword %>
            </span>
          </div>
        <% end %>
      </div>
    </div>
  </div>
<% end %>
```

### New: `DashboardSerpLandscapeLive`

**File**: `lib/gsc_analytics_web/live/dashboard_serp_landscape_live.ex`

```elixir
defmodule GscAnalyticsWeb.DashboardSerpLandscapeLive do
  use GscAnalyticsWeb, :live_view

  alias GscAnalytics.ContentInsights.SerpLandscape

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    url = params["url"]
    account_id = String.to_integer(params["account_id"] || "0")
    property_url = params["property_url"]

    # Fetch all SERP intelligence data
    ai_stats = SerpLandscape.ai_overview_stats(url, account_id: account_id, property_url: property_url)
    competitor_data = SerpLandscape.competitor_positions(url, account_id: account_id, property_url: property_url)
    content_type_data = SerpLandscape.content_type_distribution(url, account_id: account_id, property_url: property_url)

    socket =
      socket
      |> assign(:url, url)
      |> assign(:account_id, account_id)
      |> assign(:property_url, property_url)
      |> assign(:ai_stats, ai_stats)
      |> assign(:competitor_data, competitor_data)
      |> assign(:content_type_data, content_type_data)
      |> assign(:page_title, "SERP Landscape - #{url}")

    {:noreply, socket}
  end
end
```

**File**: `lib/gsc_analytics_web/live/dashboard_serp_landscape_live.html.heex`

```heex
<div class="p-6 space-y-6">
  <!-- Page Header -->
  <div class="flex items-center justify-between">
    <div>
      <h1 class="text-3xl font-bold">SERP Landscape Intelligence</h1>
      <p class="text-gray-600 mt-1"><%= @url %></p>
    </div>

    <.link navigate={~p"/dashboard/url?#{[url: @url]}"} class="btn btn-ghost">
      ← Back to URL Details
    </.link>
  </div>

  <!-- Three-Panel Layout -->
  <div class="grid grid-cols-1 xl:grid-cols-2 gap-6">
    <!-- AI Overview Panel (Full Width Priority) -->
    <div class="xl:col-span-2">
      <.ai_overview_panel stats={@ai_stats} />
    </div>

    <!-- Competitor Heatmap -->
    <div class="xl:col-span-2">
      <.competitor_heatmap data={@competitor_data} />
    </div>

    <!-- Content Type Distribution -->
    <div class="xl:col-span-1">
      <.content_type_chart data={@content_type_data} />
    </div>
  </div>
</div>
```

---

## Testing Strategy

### Unit Tests

**File**: `test/gsc_analytics/content_insights/serp_landscape_test.exs`

```elixir
defmodule GscAnalytics.ContentInsights.SerpLandscapeTest do
  use GscAnalytics.DataCase

  alias GscAnalytics.ContentInsights.SerpLandscape
  alias GscAnalytics.Schemas.SerpSnapshot

  describe "ai_overview_stats/2" do
    test "calculates AI Overview presence percentage" do
      # Insert 7 snapshots, 5 with AI Overview
      insert_snapshots_with_ao(5, 2)

      stats = SerpLandscape.ai_overview_stats("https://example.com/page", account_id: 1, property_url: "sc-domain:example.com")

      assert stats.total_keywords_checked == 7
      assert stats.keywords_with_ao == 5
      assert_in_delta stats.ao_presence_percentage, 71.4, 0.1
    end

    test "identifies ScrapFly citations" do
      insert_snapshot_with_scrapfly_citation()

      stats = SerpLandscape.ai_overview_stats("https://example.com/page", account_id: 1, property_url: "sc-domain:example.com")

      assert stats.scrapfly_citations == 1

      scrapfly_breakdown = Enum.find(stats.citation_breakdown, & String.contains?(&1.domain, "scrapfly"))
      assert scrapfly_breakdown.count == 1
    end
  end

  describe "competitor_positions/2" do
    test "builds heatmap data structure" do
      insert_competitor_snapshots()

      data = SerpLandscape.competitor_positions("https://example.com/page", account_id: 1, property_url: "sc-domain:example.com")

      assert length(data.domains) > 0
      assert length(data.keywords) > 0
      assert is_map(data.positions)
      assert is_map(data.averages)
    end

    test "calculates average positions correctly" do
      # Insert snapshots where scrapfly.io ranks #3, #1, #5 across 3 keywords
      insert_scrapfly_rankings([3, 1, 5])

      data = SerpLandscape.competitor_positions("https://example.com/page", account_id: 1, property_url: "sc-domain:example.com")

      assert_in_delta data.averages["scrapfly.io"], 3.0, 0.1
    end
  end

  describe "content_type_distribution/2" do
    test "calculates type percentages" do
      insert_mixed_content_types()

      data = SerpLandscape.content_type_distribution("https://example.com/page", account_id: 1, property_url: "sc-domain:example.com")

      assert data.distribution["reddit"] > 0
      assert data.distribution["youtube"] > 0
      assert data.distribution["website"] > 0

      total_percentage = data.percentages |> Map.values() |> Enum.sum()
      assert_in_delta total_percentage, 100.0, 0.1
    end
  end
end
```

### Integration Tests

**File**: `test/gsc_analytics_web/live/dashboard_serp_landscape_live_test.exs`

```elixir
defmodule GscAnalyticsWeb.DashboardSerpLandscapeLiveTest do
  use GscAnalyticsWeb.ConnCase
  import Phoenix.LiveViewTest

  test "renders SERP landscape page", %{conn: conn} do
    # Setup: Create snapshots
    insert_test_snapshots()

    {:ok, view, html} = live(conn, ~p"/dashboard/url/serp-landscape?#{[url: "https://example.com/page", account_id: 1, property_url: "sc-domain:example.com"]}")

    assert html =~ "SERP Landscape Intelligence"
    assert html =~ "AI Overview Intelligence"
    assert html =~ "Competitor Landscape"
    assert html =~ "Content Type Analysis"
  end

  test "displays AI Overview citation data", %{conn: conn} do
    insert_snapshot_with_citations()

    {:ok, _view, html} = live(conn, ~p"/dashboard/url/serp-landscape?#{[url: "https://example.com/page", account_id: 1, property_url: "sc-domain:example.com"]}")

    assert html =~ "scrapfly.io"
    assert html =~ "Citations"
  end
end
```

---

## Deployment Checklist

### Pre-Deployment

- [ ] Run migration: `mix ecto.migrate`
- [ ] Run full test suite: `mix test`
- [ ] Test in staging with real ScrapFly API calls
- [ ] Verify ScrapFly credit balance sufficient
- [ ] Review audit logs for any errors

### Deployment Steps

1. Merge feature branch to main
2. Deploy to production
3. Run migration in production
4. Monitor error logs for 24 hours
5. Verify first bulk check completes successfully
6. Check database indexes created properly

### Post-Deployment

- [ ] Test bulk keyword checking with 7 keywords
- [ ] Verify AI Overview detection accuracy
- [ ] Confirm content type classification works
- [ ] Check competitor heatmap renders correctly
- [ ] Monitor ScrapFly API costs
- [ ] Gather user feedback

---

## Performance Considerations

### Database Queries

**Optimization**: Use `distinct` with `order_by` to fetch latest snapshot per keyword:

```elixir
SerpSnapshot
|> order_by([s], desc: s.checked_at)
|> distinct([s], s.keyword)
|> Repo.all()
```

**Indexing**: Composite index on `(account_id, property_url, url, checked_at)` for fast filtering.

### Bulk Checks

**Oban Concurrency**: Default queue limits prevent overwhelming ScrapFly API.

**Rate Limiting**: Existing `SerpCheckWorker` includes retry logic and snooze on 429 errors.

### UI Rendering

**Limit Display**: Show top 20 competitors max to avoid DOM bloat.

**Lazy Loading**: Use collapse components for AI Overview text samples.

**Streaming**: Consider using LiveView streams if snapshots exceed 100 records.

---

## Cost Management

### Per-Check Cost

- **Single keyword**: 36 ScrapFly credits (~$0.036)
- **7 keywords**: 252 credits (~$0.25)
- **10 keywords**: 360 credits (~$0.36)

### Monthly Estimates

**Conservative Usage**:
- 50 URLs × 7 keywords × 1 check/month = 17,500 credits (~$17.50/month)

**Active Usage**:
- 200 URLs × 7 keywords × 2 checks/month = 140,000 credits (~$140/month)

**Note**: On-demand approach keeps costs predictable and scales with usage.

---

## Future Enhancements (Post-MVP)

### Automated Scheduling
- Weekly checks for priority URLs
- Smart scheduling based on volatility
- Workspace-level keyword lists

### Historical Tracking
- Rank change graphs over time
- Position volatility metrics
- AI Overview appearance trends

### Alerts & Notifications
- Email when AI Overview mentions ScrapFly
- Slack alerts for rank changes >5 positions
- Weekly SERP landscape digests

### Advanced Analytics
- SERP feature correlations
- Seasonality detection
- Competitor strategy insights

---

## References

- **ScrapFly SERP API**: https://scrapfly.io/docs/scrape-api/serp
- **Phoenix LiveView**: https://hexdocs.pm/phoenix_live_view
- **Oban Background Jobs**: https://hexdocs.pm/oban
- **Ecto Query**: https://hexdocs.pm/ecto/Ecto.Query.html
- **Floki HTML Parser**: https://hexdocs.pm/floki

---

**Document Version**: 1.0
**Last Updated**: 2025-11-17
**Author**: Claude Code
**Status**: Ready for Implementation
