import React, { Suspense, lazy } from "react";
import ReactDOM from "react-dom/client";

// Lazy load WorkflowBuilder and React Flow (~250KB) - only loads when needed
const WorkflowBuilder = lazy(() => import("./components/WorkflowBuilder.jsx"));

/**
 * LiveView hook for integrating React Flow workflow builder.
 *
 * Data flow:
 * - LiveView → React: push_event("update_workflow", {workflow}) + handleEvent()
 * - React → LiveView: pushEventTo() in callbacks
 *
 * Performance:
 * - Uses phx-update="ignore" to prevent LiveView from touching React's DOM
 * - React re-renders are cheap (props update without destroying component)
 * - CODE SPLITTING: WorkflowBuilder loads on-demand (~250KB saved from initial bundle)
 */
const WorkflowBuilderHook = {
  mounted() {
    // Create React root
    const root = ReactDOM.createRoot(this.el);
    this.root = root;

    // Parse initial workflow data
    const workflow = JSON.parse(this.el.dataset.workflow || "{}");

    // Initial render
    this.renderWorkflow(workflow);

    // Listen for LiveView updates (don't use DOM for data passing after mount!)
    this.handleEvent("update_workflow", ({ workflow }) => {
      // React is smart - updates props without destroying component (cheap operation)
      this.renderWorkflow(workflow);
    });
  },

  /**
   * Render or update the React component with new workflow data
   * Wrapped in Suspense for lazy loading
   */
  renderWorkflow(workflow) {
    this.root.render(
      <Suspense
        fallback={
          <div className="flex items-center justify-center h-screen">
            <div className="text-center">
              <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-gray-900 mx-auto mb-4"></div>
              <p className="text-gray-600">Loading workflow builder...</p>
            </div>
          </div>
        }
      >
        <WorkflowBuilder
          workflow={workflow}
          onSave={(data) => this.handleSave(data)}
          onAutoSave={(data) => this.handleAutoSave(data)}
          onBack={() => this.handleBack()}
        />
      </Suspense>
    );
  },

  /**
   * Handle manual save from React component
   */
  handleSave(data) {
    this.pushEventTo("#workflow-builder", "save_workflow", data);
  },

  /**
   * Handle debounced auto-save from React component
   */
  handleAutoSave(data) {
    this.pushEventTo("#workflow-builder", "auto_save_workflow", data);
  },

  /**
   * Handle back button navigation
   */
  handleBack() {
    this.pushEventTo("#workflow-builder", "navigate_back", {});
  },

  /**
   * CRITICAL: Cleanup to prevent memory leaks
   */
  destroyed() {
    if (this.root) {
      this.root.unmount();
      this.root = null;
    }
  },
};

export default WorkflowBuilderHook;
