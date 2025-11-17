# T012: SERP Visualization

**Status:** 🔵 Not Started
**Story Points:** 1
**Priority:** 🟡 P2 Medium
**TDD Required:** No (UI feature)

## Description
Add SERP position trend chart showing position changes over time.

## Acceptance Criteria
- [ ] Chart shows position history (last 30 days)
- [ ] Displays SERP features (badges for featured snippet, PAA, etc.)
- [ ] Shows top 3 competitors
- [ ] Responsive design
- [ ] Uses existing Chart.js setup

## Implementation

```heex
<!-- lib/gsc_analytics_web/live/dashboard_url_live.html.heex -->
<div class="serp-visualization mt-6">
  <h3 class="text-lg font-semibold">SERP Position Trend</h3>

  <%= if @serp_history do %>
    <canvas id="serp-position-chart" phx-hook="SerpChart" data-snapshots={@serp_history}></canvas>

    <div class="mt-4">
      <h4 class="font-semibold">SERP Features</h4>
      <div class="flex gap-2">
        <%= for feature <- @serp_snapshot.serp_features do %>
          <span class="badge badge-info"><%= humanize_feature(feature) %></span>
        <% end %>
      </div>
    </div>

    <div class="mt-4">
      <h4 class="font-semibold">Top Competitors</h4>
      <ul>
        <%= for competitor <- Enum.take(@serp_snapshot.competitors, 3) do %>
          <li>
            #<%= competitor["position"] %> - <%= competitor["title"] %>
            <a href={competitor["url"]} target="_blank" class="text-blue-600">
              <%= competitor["url"] %>
            </a>
          </li>
        <% end %>
      </ul>
    </div>
  <% end %>
</div>
```

## Definition of Done
- [ ] Chart displays position trend
- [ ] SERP features shown
- [ ] Top competitors listed
- [ ] Manual testing complete

## 📚 Reference Documentation
- **Chart.js Integration:** See `assets/js/charts/chartjs_performance_chart.js`
