import React from "react";
import { Handle, Position } from "@xyflow/react";

/**
 * Custom node component for workflow steps.
 *
 * PERFORMANCE CRITICAL:
 * - Memoized with React.memo() to prevent re-renders on every drag
 * - NEVER access nodes/edges array directly (causes re-render on every drag)
 * - All props should be primitive values or memoized objects
 */
const CustomNode = React.memo(({ data, isConnectable }) => {
  // Get step type configuration
  const typeConfig = getStepTypeConfig(data.type);

  return (
    <div className={`px-4 py-3 shadow-lg rounded-lg border-2 ${typeConfig.className} min-w-[200px]`}>
      {/* Input handle */}
      <Handle
        type="target"
        position={Position.Top}
        isConnectable={isConnectable}
        className="w-3 h-3"
      />

      {/* Node content */}
      <div className="flex items-center gap-2">
        {/* Step type icon */}
        <div className={`flex-shrink-0 w-8 h-8 rounded-full flex items-center justify-center ${typeConfig.iconBgClass}`}>
          <span className="text-lg">{typeConfig.icon}</span>
        </div>

        {/* Step info */}
        <div className="flex-1 min-w-0">
          <div className="text-xs font-medium text-slate-500 dark:text-slate-400 uppercase tracking-wide">
            {typeConfig.label}
          </div>
          <div className="font-semibold text-slate-900 dark:text-slate-100 truncate">
            {data.name || data.id}
          </div>
        </div>
      </div>

      {/* Output handle */}
      <Handle
        type="source"
        position={Position.Bottom}
        isConnectable={isConnectable}
        className="w-3 h-3"
      />
    </div>
  );
});

CustomNode.displayName = "CustomNode";

/**
 * Get visual configuration for each step type.
 * This data will eventually come from the step types registry.
 */
function getStepTypeConfig(type) {
  const configs = {
    test: {
      label: "Test Step",
      icon: "🧪",
      className: "bg-purple-50 border-purple-300 dark:bg-purple-900/20 dark:border-purple-700",
      iconBgClass: "bg-purple-200 dark:bg-purple-800",
    },
    gsc_query: {
      label: "GSC Query",
      icon: "🔍",
      className: "bg-blue-50 border-blue-300 dark:bg-blue-900/20 dark:border-blue-700",
      iconBgClass: "bg-blue-200 dark:bg-blue-800",
    },
    api: {
      label: "API Call",
      icon: "🌐",
      className: "bg-green-50 border-green-300 dark:bg-green-900/20 dark:border-green-700",
      iconBgClass: "bg-green-200 dark:bg-green-800",
    },
    llm: {
      label: "AI/LLM",
      icon: "🤖",
      className: "bg-indigo-50 border-indigo-300 dark:bg-indigo-900/20 dark:border-indigo-700",
      iconBgClass: "bg-indigo-200 dark:bg-indigo-800",
    },
    conditional: {
      label: "Conditional",
      icon: "🔀",
      className: "bg-yellow-50 border-yellow-300 dark:bg-yellow-900/20 dark:border-yellow-700",
      iconBgClass: "bg-yellow-200 dark:bg-yellow-800",
    },
    code: {
      label: "Code",
      icon: "💻",
      className: "bg-slate-50 border-slate-300 dark:bg-slate-900/20 dark:border-slate-700",
      iconBgClass: "bg-slate-200 dark:bg-slate-800",
    },
  };

  return configs[type] || configs.test;
}

export default CustomNode;
