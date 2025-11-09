# Workflow Builder Architecture

## Overview

The Workflow Builder is a visual node-based workflow editor built with **React Flow** integrated into **Phoenix LiveView** via custom hooks. This document explains the architecture, key decisions, performance considerations, and how to maintain/extend the system.

## Why This Approach?

### The Problem
We needed a visual workflow editor with:
- Drag-and-drop node positioning
- Connection management between steps
- Real-time configuration panels
- Complex UI interactions that would be difficult to implement in LiveView alone

### The Solution: React Flow + LiveView Hooks

**React Flow** is a battle-tested library for node-based editors, providing:
- Canvas rendering with zoom/pan
- Node and edge management
- MiniMap for navigation
- Built-in interaction handling

**Phoenix LiveView Hooks** provide a clean integration point:
- Mount React components in specific DOM elements
- Bidirectional communication (LiveView ↔ React)
- Proper lifecycle management
- Memory leak prevention

### Validation from Production

This approach is **proven in production**:
- Stephen Bussey at Clove has used this pattern for years with complex React libraries (React Grid Layout)
- Multiple teams report shipping complex React features in LiveView in 1-3 days
- Custom hooks provide more control than third-party packages like `phoenix_live_react`

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     Phoenix LiveView                         │
│  (DashboardWorkflowBuilderLive)                             │
│                                                              │
│  - Loads workflow from DB                                   │
│  - Subscribes to PubSub for real-time updates              │
│  - Handles save_workflow / auto_save_workflow events        │
│  - Validates and persists workflow definition               │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   │ push_event("update_workflow", ...)
                   │ handleEvent("update_workflow")
                   │
┌──────────────────▼──────────────────────────────────────────┐
│              LiveView Hook (WorkflowBuilderHook)            │
│                                                              │
│  - Mounts React component in DOM                            │
│  - Receives updates from LiveView via handleEvent()         │
│  - Sends updates to LiveView via pushEventTo()              │
│  - Cleanup on destroyed() to prevent memory leaks           │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   │ ReactDOM.createRoot() + render()
                   │
┌──────────────────▼──────────────────────────────────────────┐
│                    React Components                          │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │  WorkflowBuilder (Main Component)                  │    │
│  │  - React Flow canvas                               │    │
│  │  - State management (nodes, edges)                 │    │
│  │  - Auto-save with debouncing                       │    │
│  │  - Keyboard shortcuts                              │    │
│  └────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │  CustomNode (Memoized)                             │    │
│  │  - Visual representation of workflow steps         │    │
│  │  - Step type icons and colors                      │    │
│  │  - Connection handles                              │    │
│  └────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │  StepConfigPanel (Memoized)                        │    │
│  │  - Dynamic form based on step type                 │    │
│  │  - Configuration validation                        │    │
│  │  - Save/cancel actions                             │    │
│  └────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │  ErrorBoundary                                      │    │
│  │  - Catches React errors                            │    │
│  │  - Displays fallback UI                            │    │
│  └────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────┘
```

## Data Flow

### 1. Initial Load (LiveView → React)

```elixir
# LiveView template passes initial data via data attribute
<div
  id="workflow-builder"
  phx-hook="WorkflowBuilder"
  phx-update="ignore"
  data-workflow={Jason.encode!(@workflow)}
>
```

```javascript
// Hook reads data on mount
mounted() {
  const workflow = JSON.parse(this.el.dataset.workflow);
  this.renderWorkflow(workflow);
}
```

### 2. LiveView Updates (LiveView → React)

**❌ DON'T use data-* attributes for updates** (phx-update="ignore" prevents re-reads)

**✅ DO use push_event + handleEvent:**

```elixir
# LiveView pushes update to React
{:noreply, push_event(socket, "update_workflow", %{workflow: updated_workflow})}
```

```javascript
// Hook receives update and re-renders React
this.handleEvent("update_workflow", ({ workflow }) => {
  // React is smart - updates props without destroying component
  this.renderWorkflow(workflow);
});
```

### 3. React Updates (React → LiveView)

```javascript
// React component calls callback
<WorkflowBuilder
  onSave={(data) => this.handleSave(data)}
  onAutoSave={(data) => this.handleAutoSave(data)}
/>

// Hook sends to LiveView
handleSave(data) {
  this.pushEventTo("#workflow-builder", "save_workflow", data);
}
```

```elixir
# LiveView handles event
def handle_event("save_workflow", %{"definition" => definition}, socket) do
  case Workflows.update_workflow(workflow, %{definition: definition}) do
    {:ok, updated_workflow} ->
      {:noreply, put_flash(socket, :info, "Workflow saved successfully")}
  end
end
```

## Performance: Critical Considerations

### The Problem with React Flow

**React Flow is EXTREMELY vulnerable to performance issues.** With 100 nodes, **ONE non-optimized line can cause the entire diagram to re-render on every drag.**

When you drag a node:
1. Node position changes
2. ReactFlow component refreshes
3. **If components aren't memoized, ALL 100+ nodes re-render**
4. UI becomes unusable

### Required Optimizations

#### 1. Memoize ALL Custom Nodes

```javascript
// ❌ BAD: Component re-renders on every drag
function CustomNode({ data }) {
  return <div>{data.name}</div>;
}

// ✅ GOOD: Component only re-renders when props change
const CustomNode = React.memo(({ data }) => {
  return <div>{data.name}</div>;
});
```

#### 2. Memoize ALL Callbacks

```javascript
// ❌ BAD: New function created on every render
function WorkflowBuilder() {
  const onNodesChange = (changes) => {
    setNodes(applyNodeChanges(changes, nodes));
  };
}

// ✅ GOOD: Function reference stays stable
function WorkflowBuilder() {
  const onNodesChange = useCallback((changes) => {
    setNodes((nds) => applyNodeChanges(changes, nds));
  }, []);
}
```

#### 3. Memoize ALL Objects/Arrays

```javascript
// ❌ BAD: New object created on every render
function WorkflowBuilder() {
  const nodeTypes = { custom: CustomNode };
}

// ✅ GOOD: Object reference stays stable
function WorkflowBuilder() {
  const nodeTypes = useMemo(() => ({ custom: CustomNode }), []);
}
```

#### 4. Enable onlyRenderVisibleElements

```jsx
<ReactFlow
  nodes={nodes}
  edges={edges}
  onlyRenderVisibleElements={true} // CRITICAL for 50+ nodes
/>
```

#### 5. NEVER Access nodes/edges Directly

```javascript
// ❌ BAD: Accesses all nodes, triggers re-render on every drag
function CustomNode({ data }) {
  const allNodes = useNodes(); // ← Don't do this!
  const relatedNode = allNodes.find(n => n.id === data.relatedId);
}

// ✅ GOOD: Pass required data as props
function CustomNode({ data, relatedNodeName }) {
  return <div>{relatedNodeName}</div>;
}
```

### Performance Checklist

Before deploying, verify:
- [ ] All custom nodes wrapped with `React.memo()`
- [ ] All callbacks use `useCallback()`
- [ ] All objects/arrays use `useMemo()`
- [ ] `onlyRenderVisibleElements={true}` on ReactFlow
- [ ] No direct access to nodes/edges in child components
- [ ] Test with 50+ nodes - drag should be smooth
- [ ] Check React DevTools Profiler for unnecessary re-renders

## Memory Management

### The Problem

React components mounted via LiveView hooks can cause **memory leaks** if not properly cleaned up.

### The Solution

**ALWAYS implement `destroyed()` in your hook:**

```javascript
const WorkflowBuilderHook = {
  mounted() {
    const root = ReactDOM.createRoot(this.el);
    this.root = root;
    root.render(<WorkflowBuilder />);
  },

  destroyed() {
    // CRITICAL: Prevents memory leaks
    if (this.root) {
      this.root.unmount();
      this.root = null;
    }
  }
};
```

### Verification

Test for memory leaks:
1. Open React DevTools
2. Navigate to workflow builder
3. Navigate away
4. Check that components are unmounted
5. Use Chrome Memory Profiler to verify no detached DOM trees

## File Structure

```
assets/
├── package.json                      # npm dependencies (React, React Flow)
├── js/
│   ├── app.jsx                       # Main app (renamed from .js for JSX support)
│   ├── workflow_builder_hook.js     # LiveView hook
│   └── components/
│       ├── WorkflowBuilder.jsx       # Main React Flow component
│       ├── CustomNode.jsx            # Memoized step node component
│       ├── StepConfigPanel.jsx       # Configuration sidebar
│       └── ErrorBoundary.jsx         # Error handling

lib/gsc_analytics_web/
├── live/
│   ├── dashboard_workflows_live.ex            # Workflow list
│   ├── dashboard_workflows_live.html.heex
│   ├── dashboard_workflow_builder_live.ex     # Workflow editor
│   └── dashboard_workflow_builder_live.html.heex
└── router.ex                         # Routes

config/
└── config.exs                        # esbuild config with JSX loaders
```

## Configuration

### esbuild with JSX Support

```elixir
# config/config.exs
config :esbuild,
  version: "0.25.4",
  gsc_analytics: [
    args: ~w(
      js/app.jsx
      --bundle
      --target=es2022
      --outdir=../priv/static/assets/js
      --loader:.js=jsx
      --loader:.jsx=jsx
      --external:/fonts/*
      --external:/images/*
    ),
    cd: Path.expand("../assets", __DIR__)
  ]
```

**Key points:**
- Entry point is `app.jsx` (not `app.js`)
- `--loader:.js=jsx` enables JSX in `.js` files
- `--loader:.jsx=jsx` enables JSX in `.jsx` files
- esbuild supports JSX natively - no additional config needed

### npm Dependencies

```json
{
  "dependencies": {
    "react": "^18.3.1",
    "react-dom": "^18.3.1",
    "@xyflow/react": "^12.3.2"
  }
}
```

## Common Issues & Solutions

### Issue: "JSX syntax extension is not currently enabled"

**Cause:** esbuild doesn't have JSX loader configured

**Solution:** Add `--loader:.js=jsx --loader:.jsx=jsx` to esbuild args in `config/config.exs`

### Issue: Workflow builder shows loading spinner forever

**Cause:** React component threw an error during mount

**Solution:**
1. Open browser console for error details
2. Check ErrorBoundary is wrapping WorkflowBuilder
3. Verify workflow data is valid JSON
4. Check React/React Flow are installed: `cd assets && npm list`

### Issue: Dragging nodes is extremely slow (50+ nodes)

**Cause:** Missing performance optimizations

**Solution:**
1. Verify `onlyRenderVisibleElements={true}` on ReactFlow
2. Check all custom nodes use `React.memo()`
3. Check all callbacks use `useCallback()`
4. Use React DevTools Profiler to find components re-rendering unnecessarily

### Issue: Changes not saving / "no process" errors

**Cause:** LiveView crashed or not receiving events

**Solution:**
1. Check browser console for WebSocket errors
2. Verify `pushEventTo` target matches DOM id: `#workflow-builder`
3. Check LiveView process is running: `Observer.start()` in IEx
4. Verify workflow PubSub subscription

### Issue: Memory usage grows over time

**Cause:** React components not unmounting properly

**Solution:**
1. Verify `destroyed()` callback in hook calls `root.unmount()`
2. Use Chrome DevTools Memory Profiler to find detached DOM trees
3. Check for event listeners that aren't being cleaned up

## Extending the System

### Adding New Step Types

1. **Add step type to CustomNode.jsx:**

```javascript
function getStepTypeConfig(type) {
  const configs = {
    // ... existing types
    my_new_type: {
      label: "My New Type",
      icon: "🆕",
      className: "bg-orange-50 border-orange-300",
      iconBgClass: "bg-orange-200",
    },
  };
  return configs[type] || configs.test;
}
```

2. **Add config fields to StepConfigPanel.jsx:**

```javascript
{formData.type === "my_new_type" && (
  <div className="form-control">
    <label className="label">
      <span className="label-text">Custom Field</span>
    </label>
    <input
      type="text"
      className="input input-bordered w-full"
      value={formData.config.custom_field || ""}
      onChange={(e) => handleConfigChange("custom_field", e.target.value)}
    />
  </div>
)}
```

3. **Add execution logic in Engine (Elixir):**

```elixir
# lib/gsc_analytics/workflows/engine.ex
defp execute_step(%{"type" => "my_new_type", "config" => config}, context) do
  # Implementation
  {:ok, %{result: "success"}}
end
```

### Adding Drag-and-Drop Node Palette

**Future Enhancement:** Add sidebar with draggable node templates

```jsx
// Add to WorkflowBuilder.jsx
const NodePalette = () => (
  <div className="absolute left-4 top-4 bg-white p-4 rounded shadow">
    <div draggable onDragStart={(e) => e.dataTransfer.setData("nodeType", "test")}>
      🧪 Test Step
    </div>
    {/* More node types */}
  </div>
);

// Handle drop on canvas
const onDrop = useCallback((event) => {
  const type = event.dataTransfer.getData("nodeType");
  const position = { x: event.clientX, y: event.clientY };
  addNode({ id: uuid(), type, position, data: {} });
}, []);
```

### Adding Undo/Redo

**Future Enhancement:** Track workflow history

```javascript
const [history, setHistory] = useState([]);
const [historyIndex, setHistoryIndex] = useState(-1);

const undo = useCallback(() => {
  if (historyIndex > 0) {
    const prevState = history[historyIndex - 1];
    setNodes(prevState.nodes);
    setEdges(prevState.edges);
    setHistoryIndex(historyIndex - 1);
  }
}, [history, historyIndex]);

// Keyboard shortcut
useEffect(() => {
  const handleKeyDown = (e) => {
    if ((e.ctrlKey || e.metaKey) && e.key === 'z') {
      e.preventDefault();
      undo();
    }
  };
  document.addEventListener('keydown', handleKeyDown);
  return () => document.removeEventListener('keydown', handleKeyDown);
}, [undo]);
```

## Testing Strategy

### Unit Tests (React Components)

```javascript
// test/assets/js/components/CustomNode.test.jsx
import { render } from '@testing-library/react';
import CustomNode from '../../../assets/js/components/CustomNode';

test('renders step name', () => {
  const { getByText } = render(
    <CustomNode data={{ name: 'Test Step', type: 'test' }} />
  );
  expect(getByText('Test Step')).toBeInTheDocument();
});
```

### Integration Tests (LiveView)

```elixir
# test/gsc_analytics_web/live/dashboard_workflow_builder_live_test.exs
test "loads workflow builder", %{conn: conn, workflow: workflow} do
  {:ok, view, html} = live(conn, ~p"/dashboard/workflows/#{workflow.id}/edit")

  assert html =~ workflow.name
  assert has_element?(view, "#workflow-builder[phx-hook='WorkflowBuilder']")
end

test "saves workflow definition", %{conn: conn, workflow: workflow} do
  {:ok, view, _html} = live(conn, ~p"/dashboard/workflows/#{workflow.id}/edit")

  new_definition = %{
    "version" => "1.0",
    "steps" => [%{"id" => "step_1", "type" => "test"}],
    "connections" => []
  }

  view
  |> element("#workflow-builder")
  |> render_hook("save_workflow", %{"definition" => new_definition})

  updated = Repo.get!(Workflow, workflow.id)
  assert updated.definition == new_definition
end
```

### Performance Tests

```elixir
test "handles large workflows (50+ nodes) without performance degradation" do
  workflow = create_workflow_with_n_nodes(100)
  {:ok, view, _html} = live(conn, ~p"/dashboard/workflows/#{workflow.id}/edit")

  # Measure rendering time
  {time_us, _result} = :timer.tc(fn ->
    render(view)
  end)

  # Should render in < 500ms even with 100 nodes
  assert time_us < 500_000
end
```

## Deployment Considerations

### Bundle Size

- **Development build:** ~2.0 MB (includes source maps)
- **Production build:** ~500 KB minified (React + React Flow)
- **Gzip:** ~150 KB

**Optimization:** Consider code splitting if bundle size becomes an issue

```javascript
// Lazy load workflow builder
const WorkflowBuilder = React.lazy(() => import('./components/WorkflowBuilder'));

<Suspense fallback={<div>Loading...</div>}>
  <WorkflowBuilder />
</Suspense>
```

### Browser Compatibility

React Flow requires:
- ES2017+ support
- Modern CSS features (flexbox, grid)
- WebGL for canvas rendering

**Minimum supported browsers:**
- Chrome 90+
- Firefox 88+
- Safari 14+
- Edge 90+

### CDN Considerations

If deploying behind a restrictive firewall:
1. Verify access to `npmjs.org` for package downloads
2. Consider vendoring React Flow if external access is blocked
3. Test asset compilation in deployment environment

## Maintenance

### Regular Tasks

1. **Update dependencies monthly:**
   ```bash
   cd assets
   npm update
   npm audit fix
   ```

2. **Monitor bundle size:**
   ```bash
   mix assets.build
   # Check output size of app.js
   ```

3. **Profile performance with 100+ nodes:**
   - Use React DevTools Profiler
   - Check for unnecessary re-renders
   - Verify `onlyRenderVisibleElements` working

### Breaking Changes to Watch

**React Flow:** Major version updates may change:
- Node/edge data structure
- Event handler signatures
- CSS class names

**React:** Updates from 18.x to 19.x may require:
- Updating `createRoot` API
- Checking for deprecated lifecycle methods
- Testing Suspense behavior changes

## Resources

### Documentation
- [React Flow Docs](https://reactflow.dev/learn)
- [Phoenix LiveView Hooks](https://hexdocs.pm/phoenix_live_view/js-interop.html#client-hooks)
- [React Performance Optimization](https://react.dev/learn/react-compiler)

### Production Examples
- [Stephen Bussey's Blog - LiveView + React](https://www.stephenbussey.com/2023/02/21/integrating-react-into-phoenix-liveview.html)
- [Clove Engineering - Drag & Drop Canvas](https://clove.tech)

### Community
- [Elixir Forum - LiveView + React](https://elixirforum.com/t/integrating-react-with-phoenix-liveview)
- [React Flow Discord](https://discord.gg/Bqt6xrs)

## Conclusion

This React Flow + Phoenix LiveView integration is a **proven, production-ready approach** for building complex visual editors in Phoenix applications. The key to success is:

1. **Understanding the data flow** (handleEvent > data-attributes)
2. **Aggressive performance optimization** (memoization everywhere)
3. **Proper memory management** (cleanup in destroyed())
4. **Testing at scale** (50+ nodes early in development)

When done correctly, you get the best of both worlds: React's rich ecosystem for complex UI and LiveView's real-time capabilities and developer experience.
