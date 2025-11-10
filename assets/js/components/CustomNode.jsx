import React from "react";
import { Handle, Position } from "@xyflow/react";
import { getStepTypeConfig } from "./stepTypes.js";

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

export default CustomNode;
