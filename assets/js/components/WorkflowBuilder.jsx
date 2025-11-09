import React, { useState, useCallback, useMemo } from "react";
import {
  ReactFlow,
  ReactFlowProvider,
  MiniMap,
  Controls,
  Background,
  addEdge,
  applyNodeChanges,
  applyEdgeChanges,
  BackgroundVariant,
} from "@xyflow/react";
import "@xyflow/react/dist/style.css";

import ErrorBoundary from "./ErrorBoundary.jsx";
import CustomNode from "./CustomNode.jsx";
import StepConfigPanel from "./StepConfigPanel.jsx";

/**
 * Workflow Builder - Visual node-based workflow editor using React Flow.
 *
 * PERFORMANCE CRITICAL:
 * - ALL callbacks memoized with useCallback()
 * - ALL objects/arrays memoized with useMemo()
 * - Custom nodes memoized with React.memo()
 * - onlyRenderVisibleElements={true} for large graphs
 * - NEVER access nodes/edges directly in child components
 *
 * With 100 nodes, ONE non-optimized line can cause re-render on every drag!
 */
const WorkflowBuilder = React.memo(({ workflow, onSave, onAutoSave }) => {
  // Convert workflow definition to React Flow format
  const initialNodes = useMemo(() => {
    const steps = workflow?.definition?.steps || [];
    return steps.map((step) => ({
      id: step.id,
      type: "custom",
      position: step.position || { x: 0, y: 0 },
      data: {
        name: step.name,
        type: step.type,
        config: step.config || {},
      },
    }));
  }, [workflow]);

  const initialEdges = useMemo(() => {
    const connections = workflow?.definition?.connections || [];
    return connections.map((conn, idx) => ({
      id: `edge-${idx}`,
      source: conn.from,
      target: conn.to,
    }));
  }, [workflow]);

  // State
  const [nodes, setNodes] = useState(initialNodes);
  const [edges, setEdges] = useState(initialEdges);
  const [selectedNode, setSelectedNode] = useState(null);
  const [isDirty, setIsDirty] = useState(false);

  // MEMOIZE node types to prevent re-creation on every render
  const nodeTypes = useMemo(() => ({ custom: CustomNode }), []);

  // MEMOIZE callbacks to prevent re-renders
  const onNodesChange = useCallback((changes) => {
    setNodes((nds) => applyNodeChanges(changes, nds));
    setIsDirty(true);
  }, []);

  const onEdgesChange = useCallback((changes) => {
    setEdges((eds) => applyEdgeChanges(changes, eds));
    setIsDirty(true);
  }, []);

  const onConnect = useCallback((connection) => {
    setEdges((eds) => addEdge(connection, eds));
    setIsDirty(true);
  }, []);

  const onNodeClick = useCallback((event, node) => {
    setSelectedNode(node);
  }, []);

  const onPaneClick = useCallback(() => {
    setSelectedNode(null);
  }, []);

  const onUpdateNode = useCallback((nodeId, newData) => {
    setNodes((nds) =>
      nds.map((node) => {
        if (node.id === nodeId) {
          return {
            ...node,
            data: {
              ...node.data,
              ...newData,
            },
          };
        }
        return node;
      })
    );
    setIsDirty(true);
  }, []);

  const handleSave = useCallback(() => {
    const workflowData = {
      definition: {
        version: "1.0",
        steps: nodes.map((node) => ({
          id: node.id,
          type: node.data.type,
          name: node.data.name,
          config: node.data.config,
          position: node.position,
        })),
        connections: edges.map((edge) => ({
          from: edge.source,
          to: edge.target,
        })),
      },
    };

    onSave(workflowData);
    setIsDirty(false);
  }, [nodes, edges, onSave]);

  // Auto-save with debounce
  const debouncedAutoSave = useMemo(() => {
    let timeout;
    return () => {
      clearTimeout(timeout);
      timeout = setTimeout(() => {
        if (isDirty) {
          const workflowData = {
            definition: {
              version: "1.0",
              steps: nodes.map((node) => ({
                id: node.id,
                type: node.data.type,
                name: node.data.name,
                config: node.data.config,
                position: node.position,
              })),
              connections: edges.map((edge) => ({
                from: edge.source,
                to: edge.target,
              })),
            },
          };
          onAutoSave(workflowData);
        }
      }, 2000);
    };
  }, [nodes, edges, isDirty, onAutoSave]);

  // Trigger auto-save when nodes/edges change
  React.useEffect(() => {
    if (isDirty) {
      debouncedAutoSave();
    }
  }, [nodes, edges, isDirty, debouncedAutoSave]);

  // Keyboard shortcuts
  React.useEffect(() => {
    const handleKeyDown = (e) => {
      // Ctrl+S / Cmd+S to save
      if ((e.ctrlKey || e.metaKey) && e.key === "s") {
        e.preventDefault();
        handleSave();
      }

      // Delete key to remove selected node
      if (e.key === "Delete" && selectedNode) {
        setNodes((nds) => nds.filter((n) => n.id !== selectedNode.id));
        setEdges((eds) =>
          eds.filter((e) => e.source !== selectedNode.id && e.target !== selectedNode.id)
        );
        setSelectedNode(null);
        setIsDirty(true);
      }
    };

    document.addEventListener("keydown", handleKeyDown);
    return () => document.removeEventListener("keydown", handleKeyDown);
  }, [selectedNode, handleSave]);

  return (
    <ErrorBoundary>
      <div className="h-screen flex">
        {/* Main canvas area */}
        <div className="flex-1 relative">
          <ReactFlowProvider>
            <ReactFlow
              nodes={nodes}
              edges={edges}
              onNodesChange={onNodesChange}
              onEdgesChange={onEdgesChange}
              onConnect={onConnect}
              onNodeClick={onNodeClick}
              onPaneClick={onPaneClick}
              nodeTypes={nodeTypes}
              fitView
              attributionPosition="bottom-left"
              onlyRenderVisibleElements={true} // CRITICAL for performance with 50+ nodes
              snapToGrid={true}
              snapGrid={[15, 15]}
            >
              <Background variant={BackgroundVariant.Dots} gap={12} size={1} />
              <Controls />
              <MiniMap
                nodeColor={(node) => {
                  switch (node.data.type) {
                    case "test":
                      return "#a78bfa";
                    case "gsc_query":
                      return "#60a5fa";
                    case "api":
                      return "#34d399";
                    case "llm":
                      return "#818cf8";
                    case "conditional":
                      return "#fbbf24";
                    case "code":
                      return "#94a3b8";
                    default:
                      return "#a78bfa";
                  }
                }}
                maskColor="rgb(0, 0, 0, 0.1)"
              />
            </ReactFlow>
          </ReactFlowProvider>

          {/* Floating save button */}
          <div className="absolute top-4 right-4 z-10 flex gap-2">
            {isDirty && (
              <div className="badge badge-warning gap-2">
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  className="h-4 w-4"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={2}
                    d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
                  />
                </svg>
                Unsaved changes
              </div>
            )}
            <button onClick={handleSave} className="btn btn-primary gap-2">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                className="h-5 w-5"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
              >
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={2}
                  d="M8 7H5a2 2 0 00-2 2v9a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-3m-1 4l-3 3m0 0l-3-3m3 3V4"
                />
              </svg>
              Save Workflow
            </button>
          </div>
        </div>

        {/* Right sidebar - Step configuration */}
        <div className="w-80 bg-base-200 border-l border-base-300 overflow-y-auto">
          <StepConfigPanel
            selectedNode={selectedNode}
            onUpdateNode={onUpdateNode}
            onClose={() => setSelectedNode(null)}
          />
        </div>
      </div>
    </ErrorBoundary>
  );
});

WorkflowBuilder.displayName = "WorkflowBuilder";

export default WorkflowBuilder;
