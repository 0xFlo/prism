import React, { useState, useCallback, useMemo, useEffect, useRef } from "react";
import {
  ReactFlow,
  ReactFlowProvider,
  MiniMap,
  Controls,
  Background,
  Panel,
  MarkerType,
  addEdge,
  BackgroundVariant,
  useNodesState,
  useEdgesState,
} from "@xyflow/react";
import "@xyflow/react/dist/style.css";

import ErrorBoundary from "./ErrorBoundary.jsx";
import CustomNode from "./CustomNode.jsx";
import StepConfigPanel from "./StepConfigPanel.jsx";
import STEP_TYPES, { buildDefaultNodeData } from "./stepTypes.js";

const WORKFLOW_VERSION = "1.0";
const GRID_COLUMNS = 3;
const GRID_X_SPACING = 260;
const GRID_Y_SPACING = 190;

const ensureArray = (value) => (Array.isArray(value) ? value : []);

const gridPositionForIndex = (index) => ({
  x: (index % GRID_COLUMNS) * GRID_X_SPACING,
  y: Math.floor(index / GRID_COLUMNS) * GRID_Y_SPACING,
});

const toNumber = (value) => {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
};

const normalizePosition = (position, fallbackPosition) => {
  if (!position || typeof position !== "object") {
    return fallbackPosition;
  }

  const x = toNumber(position.x ?? position["x"]);
  const y = toNumber(position.y ?? position["y"]);

  if (x === null || y === null) {
    return fallbackPosition;
  }

  return { x, y };
};

const normalizeWorkflowDefinition = (definition) => {
  if (!definition || typeof definition !== "object") {
    return { steps: [], connections: [], version: WORKFLOW_VERSION };
  }

  return {
    steps: ensureArray(definition.steps ?? definition["steps"]),
    connections: ensureArray(definition.connections ?? definition["connections"]),
    version: definition.version ?? definition["version"] ?? WORKFLOW_VERSION,
  };
};

const buildInitialNodes = (steps) =>
  ensureArray(steps).map((step, index) => {
    const fallbackPosition = gridPositionForIndex(index);

    const stepId = step.id || `step_${index + 1}`;
    const normalizedType = STEP_TYPES[step.type] ? step.type : "test";
    const defaults = buildDefaultNodeData(normalizedType);

    return {
      id: stepId,
      type: "custom",
      position: normalizePosition(step.position, fallbackPosition),
      data: {
        id: stepId,
        type: normalizedType,
        name: step.name || defaults.name,
        config: {
          ...(defaults.config || {}),
          ...(step.config || {}),
        },
      },
    };
  });

const buildInitialEdges = (connections) =>
  ensureArray(connections)
    .map((connection, index) => {
      const source = connection.source || connection.from;
      const target = connection.target || connection.to;

      if (!source || !target) {
        return null;
      }

      return {
        id: connection.id || `edge-${source}-${target}-${index}`,
        source,
        target,
      };
    })
    .filter(Boolean);

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
  const workflowId = workflow?.id ?? "new";
  const workflowUpdatedAt = workflow?.updated_at ?? "";
  const { steps: definitionSteps, connections: definitionConnections, version: workflowVersion } =
    useMemo(() => normalizeWorkflowDefinition(workflow?.definition), [workflow]);

  const initialNodes = useMemo(() => buildInitialNodes(definitionSteps), [definitionSteps]);
  const initialEdges = useMemo(() => buildInitialEdges(definitionConnections), [definitionConnections]);

  // State
  const [nodes, setNodes, applyNodesChange] = useNodesState(initialNodes);
  const [edges, setEdges, applyEdgesChange] = useEdgesState(initialEdges);
  const [selectedNode, setSelectedNode] = useState(null);
  const [isDirty, setIsDirty] = useState(false);
  const [reactFlowInstance, setReactFlowInstance] = useState(null);
  const reactFlowWrapperRef = useRef(null);
  const workflowMetaRef = useRef({
    id: workflowId,
    updatedAt: workflowUpdatedAt,
    version: workflowVersion,
  });
  const autoSaveTimerRef = useRef(null);
  const initialFitRef = useRef(false);
  const showEmptyState = nodes.length === 0;
  const handleFitView = useCallback(() => {
    if (reactFlowInstance) {
      reactFlowInstance.fitView({ padding: 0.2, duration: 300 });
    }
  }, [reactFlowInstance]);

  // MEMOIZE node types to prevent re-creation on every render
  const nodeTypes = useMemo(() => ({ custom: CustomNode }), []);
  const defaultEdgeOptions = useMemo(
    () => ({
      type: "smoothstep",
      markerEnd: { type: MarkerType.ArrowClosed, color: "#94a3b8" },
      style: { stroke: "#94a3b8" },
    }),
    []
  );

  const handleNodesChange = useCallback(
    (changes) => {
      applyNodesChange(changes);
      if (changes.some((change) => change.type !== "dimensions")) {
        setIsDirty(true);
      }
    },
    [applyNodesChange]
  );

  const handleEdgesChange = useCallback(
    (changes) => {
      applyEdgesChange(changes);
      if (changes.length) {
        setIsDirty(true);
      }
    },
    [applyEdgesChange]
  );

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

  const generateNodeId = useCallback(() => {
    if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
      return `step_${crypto.randomUUID()}`;
    }
    return `step_${Date.now()}_${Math.round(Math.random() * 1000)}`;
  }, []);

  const projectToCanvas = useCallback(
    (clientX, clientY) => {
      if (!reactFlowInstance || !reactFlowWrapperRef.current) {
        return { x: 0, y: 0 };
      }
      const bounds = reactFlowWrapperRef.current.getBoundingClientRect();
      return reactFlowInstance.screenToFlowPosition({
        x: clientX - bounds.left,
        y: clientY - bounds.top,
      });
    },
    [reactFlowInstance]
  );

  const getCanvasCenterPosition = useCallback(() => {
    if (!reactFlowInstance || !reactFlowWrapperRef.current) {
      return gridPositionForIndex(nodes.length);
    }
    const bounds = reactFlowWrapperRef.current.getBoundingClientRect();
    return projectToCanvas(bounds.left + bounds.width / 2, bounds.top + bounds.height / 2);
  }, [nodes.length, projectToCanvas, reactFlowInstance]);

  const addNode = useCallback(
    (stepType, position) => {
      const normalizedType = STEP_TYPES[stepType] ? stepType : "test";
      const nodeId = generateNodeId();
      const fallbackPosition = gridPositionForIndex(nodes.length);
      const newNode = {
        id: nodeId,
        type: "custom",
        position: position || fallbackPosition,
        data: {
          ...buildDefaultNodeData(normalizedType),
          id: nodeId,
        },
      };

      setNodes((nds) => [...nds, newNode]);
      setSelectedNode(newNode);
      setIsDirty(true);
    },
    [generateNodeId, nodes.length]
  );

  const handlePaletteAdd = useCallback(
    (stepType) => {
      const position = getCanvasCenterPosition();
      addNode(stepType, position);
    },
    [addNode, getCanvasCenterPosition]
  );
  const quickAddDefaultStep = useCallback(() => handlePaletteAdd("test"), [handlePaletteAdd]);

  const handleDrop = useCallback(
    (event) => {
      event.preventDefault();
      event.stopPropagation();

      const stepType = event.dataTransfer.getData("application/reactflow");
      if (!stepType) {
        return;
      }

      const position = reactFlowInstance
        ? projectToCanvas(event.clientX, event.clientY)
        : gridPositionForIndex(nodes.length);

      addNode(stepType, position);
    },
    [addNode, nodes.length, projectToCanvas, reactFlowInstance]
  );

  const handleDragOver = useCallback((event) => {
    event.preventDefault();
    event.dataTransfer.dropEffect = "move";
  }, []);

  const handleNodesDelete = useCallback(
    (deleted) => {
      if (!deleted?.length) {
        return;
      }
      const deletedIds = new Set(deleted.map((node) => node.id));
      setEdges((eds) =>
        eds.filter((edge) => !deletedIds.has(edge.source) && !deletedIds.has(edge.target))
      );
      if (selectedNode && deletedIds.has(selectedNode.id)) {
        setSelectedNode(null);
      }
      setIsDirty(true);
    },
    [selectedNode]
  );

  const serializeWorkflow = useCallback(() => {
    return {
      definition: {
        version: workflowMetaRef.current.version || WORKFLOW_VERSION,
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
  }, [nodes, edges]);

  const handleSave = useCallback(() => {
    const workflowData = serializeWorkflow();
    onSave(workflowData);
    if (autoSaveTimerRef.current) {
      clearTimeout(autoSaveTimerRef.current);
      autoSaveTimerRef.current = null;
    }
    setIsDirty(false);
  }, [serializeWorkflow, onSave]);

  const scheduleAutoSave = useCallback(() => {
    if (autoSaveTimerRef.current) {
      clearTimeout(autoSaveTimerRef.current);
    }

    autoSaveTimerRef.current = setTimeout(() => {
      if (!isDirty) return;
      onAutoSave(serializeWorkflow());
      autoSaveTimerRef.current = null;
      setIsDirty(false);
    }, 2000);
  }, [isDirty, onAutoSave, serializeWorkflow]);

  // Trigger auto-save when nodes/edges change
  useEffect(() => {
    if (!isDirty) {
      return;
    }

    scheduleAutoSave();

    return () => {
      if (autoSaveTimerRef.current) {
        clearTimeout(autoSaveTimerRef.current);
        autoSaveTimerRef.current = null;
      }
    };
  }, [nodes, edges, isDirty, scheduleAutoSave]);

  useEffect(() => {
    return () => {
      if (autoSaveTimerRef.current) {
        clearTimeout(autoSaveTimerRef.current);
      }
    };
  }, []);

  useEffect(() => {
    initialFitRef.current = false;
  }, [workflowId]);

  useEffect(() => {
    if (!reactFlowInstance || !nodes.length || initialFitRef.current) {
      return;
    }
    reactFlowInstance.fitView({ padding: 0.2, duration: 300 });
    initialFitRef.current = true;
  }, [nodes.length, reactFlowInstance]);

  // Keyboard shortcuts
  useEffect(() => {
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

  // Keep selected node in sync as the underlying nodes array changes
  useEffect(() => {
    if (!selectedNode) return;
    const nextSelected = nodes.find((node) => node.id === selectedNode.id);
    if (!nextSelected) {
      setSelectedNode(null);
    } else if (nextSelected !== selectedNode) {
      setSelectedNode(nextSelected);
    }
  }, [nodes, selectedNode]);

  // Hydrate React Flow state whenever the LiveView pushes new workflow data.
  useEffect(() => {
    const meta = workflowMetaRef.current;
    const hasChanged =
      meta.id !== workflowId ||
      meta.updatedAt !== workflowUpdatedAt ||
      meta.version !== workflowVersion;

    if (!hasChanged) {
      return;
    }

    const workflowSwitched = meta.id !== workflowId;

    if (workflowSwitched || !isDirty) {
      setNodes(initialNodes);
      setEdges(initialEdges);
      setIsDirty(false);
      if (
        workflowSwitched ||
        (selectedNode && !initialNodes.find((node) => node.id === selectedNode.id))
      ) {
        setSelectedNode(null);
      }
      workflowMetaRef.current = {
        id: workflowId,
        updatedAt: workflowUpdatedAt,
        version: workflowVersion,
      };
    }
  }, [
    initialNodes,
    initialEdges,
    isDirty,
    selectedNode,
    workflowId,
    workflowUpdatedAt,
    workflowVersion,
  ]);

  return (
    <ErrorBoundary>
      <ReactFlowProvider>
        <div className="h-screen flex">
          {/* Main canvas area */}
          <div
            className="flex-1 relative"
            ref={reactFlowWrapperRef}
            onDrop={handleDrop}
            onDragOver={handleDragOver}
          >
            <NodePalette onAddNode={handlePaletteAdd} />
            <ReactFlow
              nodes={nodes}
              edges={edges}
              onNodesChange={handleNodesChange}
              onEdgesChange={handleEdgesChange}
              onNodesDelete={handleNodesDelete}
              onConnect={onConnect}
              onNodeClick={onNodeClick}
              onPaneClick={onPaneClick}
              nodeTypes={nodeTypes}
              defaultEdgeOptions={defaultEdgeOptions}
              fitView
              panOnScroll
              snapToGrid
              snapGrid={[15, 15]}
              attributionPosition="bottom-left"
              onlyRenderVisibleElements={true} // CRITICAL for performance with 50+ nodes
              onInit={setReactFlowInstance}
            >
              <Background variant={BackgroundVariant.Dots} gap={12} size={1} />
              <Controls />
              <Panel position="top-center">
                <CanvasToolbar
                  nodeCount={nodes.length}
                  edgeCount={edges.length}
                  onAddStep={quickAddDefaultStep}
                  onFitView={handleFitView}
                />
              </Panel>
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

            {showEmptyState && (
              <CanvasEmptyState onAddStep={quickAddDefaultStep} />
            )}

            {/* Floating save button */}
            <div className="absolute top-4 right-4 z-20 flex gap-2">
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
      </ReactFlowProvider>
    </ErrorBoundary>
  );
});

WorkflowBuilder.displayName = "WorkflowBuilder";

const NodePalette = React.memo(({ onAddNode }) => {
  return (
    <div className="absolute top-4 left-4 z-20 w-64 space-y-2">
      <div className="rounded-xl border border-base-300 bg-base-100/95 shadow-xl backdrop-blur">
        <div className="px-4 pt-4 pb-2 text-xs font-semibold uppercase tracking-wide text-slate-500 flex items-center justify-between">
          <span>Step library</span>
          <span className="badge badge-ghost">{Object.keys(STEP_TYPES).length}</span>
        </div>
        <div className="px-4 pb-4 space-y-3">
          {Object.entries(STEP_TYPES).map(([type, config]) => (
            <div
              key={type}
              className="rounded-lg border border-base-300 bg-base-100 p-3 transition hover:border-primary/70"
            >
              <div
                className="flex cursor-grab items-start gap-3"
                draggable={true}
                onDragStart={(event) => {
                  event.dataTransfer.setData("application/reactflow", type);
                  event.dataTransfer.effectAllowed = "move";
                }}
              >
                <div className={`flex h-10 w-10 items-center justify-center rounded-full ${config.iconBgClass}`}>
                  <span className="text-xl" role="img" aria-label={config.label}>
                    {config.icon}
                  </span>
                </div>
                <div className="flex-1">
                  <div className="font-semibold text-sm text-slate-900 dark:text-slate-100">
                    {config.label}
                  </div>
                  <p className="text-xs text-slate-500">{config.paletteDescription}</p>
                </div>
              </div>
              <div className="mt-3 flex justify-end">
                <button
                  type="button"
                  className="btn btn-xs btn-primary"
                  onClick={(event) => {
                    event.stopPropagation();
                    event.preventDefault();
                    onAddNode(type);
                  }}
                >
                  Add step
                </button>
              </div>
            </div>
          ))}
          <p className="text-[11px] text-slate-500">
            Drag templates onto the canvas or click “Add step” to insert them at the viewport center.
          </p>
        </div>
      </div>
    </div>
  );
});

NodePalette.displayName = "NodePalette";

const CanvasEmptyState = React.memo(({ onAddStep }) => {
  return (
    <div className="pointer-events-none absolute inset-0 flex items-center justify-center">
      <div className="pointer-events-auto max-w-sm rounded-2xl border border-dashed border-base-300 bg-base-100/95 p-6 text-center shadow-2xl backdrop-blur">
        <h3 className="text-lg font-semibold text-slate-900 dark:text-slate-100">
          Build your workflow
        </h3>
        <p className="mt-2 text-sm text-slate-500">
          Drag a template from the left, drop it anywhere on the canvas, or use the quick action
          below to add your first step.
        </p>
        <button className="btn btn-primary mt-4" onClick={onAddStep}>
          Add first step
        </button>
      </div>
    </div>
  );
});

CanvasEmptyState.displayName = "CanvasEmptyState";

const CanvasToolbar = React.memo(({ nodeCount, edgeCount, onAddStep, onFitView }) => (
  <div className="flex items-center gap-3 rounded-full border border-base-300 bg-base-100/95 px-4 py-2 text-xs font-medium text-slate-600 shadow-lg backdrop-blur">
    <div>
      {nodeCount} nodes · {edgeCount} edges
    </div>
    <button className="btn btn-ghost btn-xs" onClick={onFitView}>
      Fit view
    </button>
    <button className="btn btn-primary btn-xs" onClick={onAddStep}>
      Add step
    </button>
  </div>
));

CanvasToolbar.displayName = "CanvasToolbar";

export default WorkflowBuilder;
