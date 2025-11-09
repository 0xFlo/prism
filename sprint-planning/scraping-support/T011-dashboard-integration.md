# T011: Dashboard LiveView Integration

**Status:** 🔵 Not Started
**Story Points:** 1
**Priority:** 🟡 P2 Medium
**TDD Required:** No (UI integration)

## Description
Add "Check SERP Position" button to dashboard URL detail page. **Must enforce auth via live_session** (Codex requirement).

## Acceptance Criteria
- [ ] Button added to `dashboard_url_live.html.heex`
- [ ] Button triggers `phx-click="check_serp_position"` event
- [ ] Event handler enqueues Oban job
- [ ] Display latest SERP snapshot if available
- [ ] **Route under `live_session :require_authenticated_user`**
- [ ] **Enforce @current_scope for property filtering**

## Implementation

1. **Update LiveView template**
```heex
<!-- lib/gsc_analytics_web/live/dashboard_url_live.html.heex -->
<div class="mt-4">
  <.button phx-click="check_serp_position" class="btn btn-secondary">
    <.icon name="hero-magnifying-glass" class="h-5 w-5" />
    Check SERP Position
  </.button>
</div>

<%= if @serp_snapshot do %>
  <div class="alert alert-info mt-4">
    <div>
      <div class="font-bold">
        SERP Position: <%= @serp_snapshot.position || "Not ranked" %>
      </div>
      <div class="text-sm">
        Checked <%= format_datetime(@serp_snapshot.checked_at) %>
        for keyword: <%= @serp_snapshot.keyword %>
      </div>
    </div>
  </div>
<% end %>
```

2. **Add event handler**
```elixir
# lib/gsc_analytics_web/live/dashboard_url_live.ex
def handle_event("check_serp_position", _params, socket) do
  url = socket.assigns.insights.url
  property_id = socket.assigns.current_property_id
  account_id = socket.assigns.current_scope.account_id

  # Infer keyword from top queries
  keyword = infer_top_keyword(socket.assigns.insights)

  # Queue Oban job
  %{
    property_id: property_id,
    url: url,
    keyword: keyword,
    account_id: account_id
  }
  |> SerpCheckWorker.new()
  |> Oban.insert()

  {:noreply, put_flash(socket, :info, "SERP check queued for '#{keyword}'")}
end
```

3. **Load snapshot in mount/handle_params**
```elixir
def handle_params(params, _uri, socket) do
  # ... existing code ...

  serp_snapshot = load_latest_serp_snapshot(property_id, url)

  {:noreply,
   socket
   |> assign(:serp_snapshot, serp_snapshot)}
end

defp load_latest_serp_snapshot(property_id, url) do
  GscAnalytics.DataSources.SERP.Core.Persistence.latest_for_url(property_id, url)
end
```

## Definition of Done
- [ ] Button added to UI
- [ ] Event handler works
- [ ] Oban job enqueued
- [ ] Latest snapshot displayed
- [ ] **Auth enforced via live_session**
- [ ] Manual testing complete

## 📚 Reference Documentation
- **LiveView:** [Research Doc](/Users/flor/Developer/prism/docs/phoenix-ecto-research.md)
- **Example:** `lib/gsc_analytics_web/live/dashboard_url_live.ex`
