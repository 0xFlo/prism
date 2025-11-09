import React from "react";
import ReactDOM from "react-dom/client";
import WorkflowBuilder from "./components/WorkflowBuilder.jsx";

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
   */
  renderWorkflow(workflow) {
    this.root.render(
      <WorkflowBuilder
        workflow={workflow}
        onSave={(data) => this.handleSave(data)}
        onAutoSave={(data) => this.handleAutoSave(data)}
      />
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
