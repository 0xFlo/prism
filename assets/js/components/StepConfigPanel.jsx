import React, { useState, useCallback } from "react";

/**
 * Step configuration panel for editing node properties.
 *
 * PERFORMANCE: Memoized with React.memo() to prevent unnecessary re-renders.
 */
const StepConfigPanel = React.memo(({ selectedNode, onUpdateNode, onClose }) => {
  const [formData, setFormData] = useState({
    name: selectedNode?.data?.name || "",
    type: selectedNode?.data?.type || "test",
    config: selectedNode?.data?.config || {},
  });

  const handleChange = useCallback((field, value) => {
    setFormData((prev) => ({
      ...prev,
      [field]: value,
    }));
  }, []);

  const handleConfigChange = useCallback((key, value) => {
    setFormData((prev) => ({
      ...prev,
      config: {
        ...prev.config,
        [key]: value,
      },
    }));
  }, []);

  const handleSave = useCallback(() => {
    if (selectedNode) {
      onUpdateNode(selectedNode.id, formData);
      onClose();
    }
  }, [selectedNode, formData, onUpdateNode, onClose]);

  if (!selectedNode) {
    return (
      <div className="p-6 text-center text-slate-500 dark:text-slate-400">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          className="h-12 w-12 mx-auto mb-3 opacity-50"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
        >
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth={2}
            d="M15 15l-2 5L9 9l11 4-5 2zm0 0l5 5M7.188 2.239l.777 2.897M5.136 7.965l-2.898-.777M13.95 4.05l-2.122 2.122m-5.657 5.656l-2.12 2.122"
          />
        </svg>
        <p className="text-sm">Select a node to configure</p>
      </div>
    );
  }

  return (
    <div className="p-6 space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between pb-4 border-b border-slate-200 dark:border-slate-700">
        <h3 className="text-lg font-semibold text-slate-900 dark:text-slate-100">
          Configure Step
        </h3>
        <button
          onClick={onClose}
          className="btn btn-ghost btn-sm btn-circle"
          aria-label="Close"
        >
          ✕
        </button>
      </div>

      {/* Form fields */}
      <div className="space-y-4">
        {/* Step Name */}
        <div className="form-control">
          <label className="label">
            <span className="label-text">Step Name</span>
          </label>
          <input
            type="text"
            className="input input-bordered w-full"
            value={formData.name}
            onChange={(e) => handleChange("name", e.target.value)}
            placeholder="Enter step name"
          />
        </div>

        {/* Step Type */}
        <div className="form-control">
          <label className="label">
            <span className="label-text">Step Type</span>
          </label>
          <select
            className="select select-bordered w-full"
            value={formData.type}
            onChange={(e) => handleChange("type", e.target.value)}
          >
            <option value="test">Test Step</option>
            <option value="gsc_query">GSC Query</option>
            <option value="api">API Call</option>
            <option value="llm">AI/LLM</option>
            <option value="conditional">Conditional</option>
            <option value="code">Code</option>
          </select>
        </div>

        {/* Type-specific config fields */}
        {formData.type === "test" && (
          <div className="form-control">
            <label className="label">
              <span className="label-text">Delay (ms)</span>
            </label>
            <input
              type="number"
              className="input input-bordered w-full"
              value={formData.config.delay_ms || 1000}
              onChange={(e) => handleConfigChange("delay_ms", parseInt(e.target.value))}
              placeholder="1000"
            />
          </div>
        )}

        {formData.type === "api" && (
          <div className="form-control">
            <label className="label">
              <span className="label-text">API URL</span>
            </label>
            <input
              type="url"
              className="input input-bordered w-full"
              value={formData.config.url || ""}
              onChange={(e) => handleConfigChange("url", e.target.value)}
              placeholder="https://api.example.com/endpoint"
            />
          </div>
        )}

        {formData.type === "llm" && (
          <div className="form-control">
            <label className="label">
              <span className="label-text">Model</span>
            </label>
            <select
              className="select select-bordered w-full"
              value={formData.config.model || "claude-3-7-sonnet"}
              onChange={(e) => handleConfigChange("model", e.target.value)}
            >
              <option value="claude-3-7-sonnet">Claude 3.7 Sonnet</option>
              <option value="claude-3-opus">Claude 3 Opus</option>
              <option value="gpt-4">GPT-4</option>
            </select>
          </div>
        )}

        {formData.type === "code" && (
          <div className="form-control">
            <label className="label">
              <span className="label-text">Code</span>
            </label>
            <textarea
              className="textarea textarea-bordered w-full h-32 font-mono text-sm"
              value={formData.config.code || ""}
              onChange={(e) => handleConfigChange("code", e.target.value)}
              placeholder="# Elixir code here"
            />
          </div>
        )}
      </div>

      {/* Action buttons */}
      <div className="flex gap-2 pt-4">
        <button onClick={handleSave} className="btn btn-primary flex-1">
          Save Changes
        </button>
        <button onClick={onClose} className="btn btn-ghost">
          Cancel
        </button>
      </div>
    </div>
  );
});

StepConfigPanel.displayName = "StepConfigPanel";

export default StepConfigPanel;
