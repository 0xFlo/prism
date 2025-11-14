---
ticket_id: "09"
title: "Update LiveView UI with Priority Badges and Page Types"
status: pending
priority: P2
milestone: 3
estimate_days: 3
dependencies: ["07", "08"]
blocks: []
success_metrics:
  - "Priority badges (P1-P4) displayed in URL tables"
  - "Page type labels shown for therapist directory pages"
  - "Priority filter dropdown added to dashboard"
  - "UI updates are responsive and accessible"
---

# Ticket 09: Update LiveView UI with Priority Badges and Page Types

## Context

Update LiveView dashboard components to display priority badges (P1-P4) and page type labels (profile, directory, location) for URLs. Add filter controls to let users filter by priority tier. Ensure UI is visually clear and accessible.

## Acceptance Criteria

1. ✅ Add priority badge component (P1=green, P2=blue, P3=yellow, P4=gray)
2. ✅ Display page_type label next to URL
3. ✅ Add priority filter dropdown to dashboard controls
4. ✅ Update URL table columns to include metadata
5. ✅ Style badges with Tailwind CSS
6. ✅ Add tooltips explaining priority tiers
7. ✅ Ensure accessibility (ARIA labels, keyboard navigation)
8. ✅ Add integration tests for LiveView components

## Technical Specifications

### Priority Badge Component

```elixir
defmodule PrismWeb.Components.PriorityBadge do
  use Phoenix.Component

  attr :priority, :string, required: true

  def priority_badge(assigns) do
    ~H"""
    <span class={"badge " <> badge_color(@priority)} title={"Priority: " <> @priority}>
      <%= @priority %>
    </span>
    """
  end

  defp badge_color("P1"), do: "bg-green-100 text-green-800"
  defp badge_color("P2"), do: "bg-blue-100 text-blue-800"
  defp badge_color("P3"), do: "bg-yellow-100 text-yellow-800"
  defp badge_color("P4"), do: "bg-gray-100 text-gray-800"
  defp badge_color(_), do: "bg-gray-50 text-gray-500"
end
```

### Updated URL Table

```heex
<table>
  <thead>
    <tr>
      <th>Priority</th>
      <th>URL</th>
      <th>Page Type</th>
      <th>Clicks</th>
      <th>Impressions</th>
    </tr>
  </thead>
  <tbody>
    <%= for url <- @urls do %>
      <tr>
        <td>
          <%= if url.update_priority do %>
            <.priority_badge priority={url.update_priority} />
          <% end %>
        </td>
        <td><%= url.url %></td>
        <td>
          <%= if url.page_type do %>
            <span class="text-sm text-gray-600"><%= url.page_type %></span>
          <% end %>
        </td>
        <td><%= url.clicks %></td>
        <td><%= url.impressions %></td>
      </tr>
    <% end %>
  </tbody>
</table>
```

### Priority Filter Dropdown

```heex
<div class="filter-control">
  <label>Priority Tier</label>
  <select phx-change="filter_priority" multiple>
    <option value="P1">P1 - Highest Priority</option>
    <option value="P2">P2 - High Priority</option>
    <option value="P3">P3 - Medium Priority</option>
    <option value="P4">P4 - Lower Priority</option>
  </select>
</div>
```

## Testing Requirements

```elixir
test "displays priority badges correctly" do
  {:ok, view, _html} = live(conn, "/dashboard")

  # Verify P1 badge is green
  assert has_element?(view, ".badge.bg-green-100", "P1")
end

test "priority filter works" do
  {:ok, view, _html} = live(conn, "/dashboard")

  # Select P1 filter
  view |> element("select") |> render_change(%{"priority" => ["P1"]})

  # Verify only P1 URLs shown
  assert has_element?(view, ".badge", "P1")
  refute has_element?(view, ".badge", "P2")
end
```

## Success Metrics

- ✓ Priority badges visible and styled correctly
- ✓ Page types displayed accurately
- ✓ Filter dropdown functional
- ✓ Accessible (WCAG 2.1 AA compliant)

## Related Files

- `07-url-performance-metadata-joins.md` - Provides data
- `08-filters-stored-metadata.md` - Filter logic
