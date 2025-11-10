const STEP_TYPES = {
  test: {
    key: "test",
    label: "Test Step",
    icon: "🧪",
    paletteDescription: "Simulate delays or placeholder steps",
    className: "bg-purple-50 border-purple-300 dark:bg-purple-900/20 dark:border-purple-700",
    iconBgClass: "bg-purple-200 dark:bg-purple-800",
    defaultName: "Test Step",
    defaultConfig: { delay_ms: 1000 },
  },
  gsc_query: {
    key: "gsc_query",
    label: "GSC Query",
    icon: "🔍",
    paletteDescription: "Fetch Search Console data",
    className: "bg-blue-50 border-blue-300 dark:bg-blue-900/20 dark:border-blue-700",
    iconBgClass: "bg-blue-200 dark:bg-blue-800",
    defaultName: "GSC Query",
    defaultConfig: {},
  },
  api: {
    key: "api",
    label: "API Call",
    icon: "🌐",
    paletteDescription: "Call external HTTP APIs",
    className: "bg-green-50 border-green-300 dark:bg-green-900/20 dark:border-green-700",
    iconBgClass: "bg-green-200 dark:bg-green-800",
    defaultName: "API Request",
    defaultConfig: { url: "https://" },
  },
  llm: {
    key: "llm",
    label: "AI / LLM",
    icon: "🤖",
    paletteDescription: "Summaries, analysis, drafting",
    className: "bg-indigo-50 border-indigo-300 dark:bg-indigo-900/20 dark:border-indigo-700",
    iconBgClass: "bg-indigo-200 dark:bg-indigo-800",
    defaultName: "AI Step",
    defaultConfig: { model: "claude-3-7-sonnet" },
  },
  conditional: {
    key: "conditional",
    label: "Conditional",
    icon: "🔀",
    paletteDescription: "Branch based on conditions",
    className: "bg-yellow-50 border-yellow-300 dark:bg-yellow-900/20 dark:border-yellow-700",
    iconBgClass: "bg-yellow-200 dark:bg-yellow-800",
    defaultName: "Branch",
    defaultConfig: { condition: "" },
  },
  code: {
    key: "code",
    label: "Code",
    icon: "💻",
    paletteDescription: "Run custom Elixir code",
    className: "bg-slate-50 border-slate-300 dark:bg-slate-900/20 dark:border-slate-700",
    iconBgClass: "bg-slate-200 dark:bg-slate-800",
    defaultName: "Code",
    defaultConfig: { code: "# TODO" },
  },
};

export const STEP_TYPES_LIST = Object.values(STEP_TYPES);

export const getStepTypeConfig = (type) => STEP_TYPES[type] || STEP_TYPES.test;

export const buildDefaultNodeData = (type) => {
  const config = getStepTypeConfig(type);
  return {
    type: config.key,
    name: config.defaultName,
    config: { ...(config.defaultConfig || {}) },
  };
};

export default STEP_TYPES;
