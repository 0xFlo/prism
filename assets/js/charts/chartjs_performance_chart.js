import Chart from "../../vendor/chart-wrapper.js"

// Chart.js includes all components pre-registered in UMD bundle

const EVENT_MARKER_PLUGIN = {
  id: "eventMarkers",
  afterDatasetsDraw(chart, _args, pluginOptions = {}) {
    const events = pluginOptions.events || []
    if (!events.length) return

    const { ctx, scales, chartArea } = chart
    if (!scales?.x || !chartArea) return

    const top = chartArea.top + 4
    const bottom = chartArea.bottom
    const lineColor = pluginOptions.lineColor || "#f97316"
    const badgeBackground = pluginOptions.badgeBackground || "rgba(249, 115, 22, 0.92)"
    const badgeBorder = pluginOptions.badgeBorder || "rgba(124, 45, 18, 0.35)"
    const badgeText = pluginOptions.badgeText || "#0f172a"
    const font = pluginOptions.font || "10px 'Inter', system-ui, sans-serif"

    ctx.save()
    ctx.lineWidth = pluginOptions.lineWidth || 1
    ctx.textAlign = "center"
    ctx.textBaseline = "middle"
    ctx.font = font

    events.forEach(event => {
      // Try to find matching label - event.date might be "2024-11-04" but label could be "2024-11-04 - 2024-11-10"
      let xPixel = scales.x.getPixelForValue(event.date)

      // If direct match fails, try to find a label that starts with the event date (for weekly/monthly views)
      if (!Number.isFinite(xPixel)) {
        const matchingLabel = chart.data.labels.find(label =>
          typeof label === 'string' && label.startsWith(event.date)
        )
        if (matchingLabel) {
          xPixel = scales.x.getPixelForValue(matchingLabel)
        }
      }

      if (!Number.isFinite(xPixel)) return

      ctx.strokeStyle = lineColor
      ctx.setLineDash(pluginOptions.lineDash || [4, 4])
      ctx.beginPath()
      ctx.moveTo(xPixel, top)
      ctx.lineTo(xPixel, bottom)
      ctx.stroke()
      ctx.setLineDash([])

      if (event.label) {
        const label = event.label
        const metrics = ctx.measureText(label)
        const paddingX = 6
        const rectWidth = metrics.width + paddingX * 2
        const rectHeight = 16
        const rectX = xPixel - rectWidth / 2
        const rectY = top + 2

        ctx.fillStyle = badgeBackground
        ctx.globalAlpha = 0.95
        ctx.fillRect(rectX, rectY, rectWidth, rectHeight)

        ctx.globalAlpha = 1
        ctx.strokeStyle = badgeBorder
        ctx.strokeRect(rectX, rectY, rectWidth, rectHeight)

        ctx.fillStyle = badgeText
        ctx.fillText(label, xPixel, rectY + rectHeight / 2)
      }
    })

    ctx.restore()
  },
}

// Register the event marker plugin with Chart.js
Chart.register(EVENT_MARKER_PLUGIN)

/**
 * Chart.js-based performance chart for GSC analytics
 * Replaces custom canvas implementation with a maintainable library solution
 */
class ChartJsPerformanceChart {
  constructor(hook) {
    this.hook = hook
    this.el = hook.el

    // Validate required data attributes
    if (!this.el.dataset.chartId) {
      console.warn('[ChartJsPerformanceChart] Missing data-chart-id attribute on hook element')
    }

    this.canvas = this.el.dataset.chartId
      ? document.getElementById(this.el.dataset.chartId)
      : null

    this.chart = null
    this.visibleSeries = ["clicks", "impressions"]

    // Font configuration
    this.fontFamily = "'Inter', system-ui, sans-serif"
    this.fonts = {
      label: {
        size: 12,
        family: this.fontFamily,
      },
      tick: {
        size: 11,
        family: this.fontFamily,
      },
      title: {
        size: 12,
        weight: "600",
        family: this.fontFamily,
      },
    }

    // Series configuration matching existing design
    this.seriesConfig = {
      clicks: {
        label: "Clicks",
        borderColor: "#6366f1",
        backgroundColor: "rgba(99, 102, 241, 0.1)",
        yAxisID: "y",
        order: 1,
      },
      impressions: {
        label: "Impressions",
        borderColor: "#10b981",
        backgroundColor: "rgba(16, 185, 129, 0.1)",
        yAxisID: "y",
        order: 2,
      },
      ctr: {
        label: "CTR",
        borderColor: "#a855f7",
        backgroundColor: "rgba(168, 85, 247, 0.1)",
        yAxisID: "y1",
        order: 3,
      },
      position: {
        label: "Avg Position",
        borderColor: "#ef4444",
        backgroundColor: "rgba(239, 68, 68, 0.1)",
        yAxisID: "y2",
        order: 4,
      },
    }
  }

  mount() {
    if (!this.canvas) {
      if (this.el.dataset.chartId) {
        console.warn(
          `[ChartJsPerformanceChart] Canvas element not found with id: ${this.el.dataset.chartId}`
        )
      }
      return
    }

    this.visibleSeries = this.readVisibleSeries()
    this.createChart()
  }

  destroy() {
    if (this.chart) {
      this.chart.destroy()
      this.chart = null
    }
  }

  update() {
    this.visibleSeries = this.readVisibleSeries()

    if (this.chart) {
      this.updateChart()
    } else {
      this.createChart()
    }
  }

  /**
   * Generic data attribute reader with JSON parsing and validation
   * @param {string} attributeName - Name of the data attribute (e.g., 'visibleSeries')
   * @param {*} defaultValue - Value to return on error or invalid data
   * @param {function} [validator] - Optional function to validate/filter parsed data
   * @returns {*} Parsed and validated data or default value
   */
  readDataAttribute(attributeName, defaultValue, validator = null) {
    try {
      const rawValue = this.el.dataset[attributeName]
      if (!rawValue) return defaultValue

      const parsed = JSON.parse(rawValue)
      if (!Array.isArray(parsed)) return defaultValue

      return validator ? validator(parsed) : parsed
    } catch (_err) {
      return defaultValue
    }
  }

  readVisibleSeries() {
    return this.readDataAttribute(
      'visibleSeries',
      ['clicks', 'impressions'],
      raw => raw.filter(s => this.seriesConfig[s])
    )
  }

  readTimeSeries() {
    return this.readDataAttribute(
      'timeSeries',
      [],
      raw => raw.filter(point => point && point.date)
    )
  }

  readEvents() {
    return this.readDataAttribute(
      'events',
      [],
      raw => raw.filter(event => event && event.date)
    )
  }

  /**
   * Get theme-specific colors for chart styling
   * Detects dark mode and returns appropriate color values
   */
  getThemeColors() {
    const isDark = document.documentElement.dataset.theme === "dark"
    return {
      isDark,
      gridColor: isDark ? "rgba(75, 85, 99, 0.3)" : "rgba(229, 231, 235, 0.5)",
      textColorPrimary: isDark ? "#f3f4f6" : "#374151",
      textColorSecondary: isDark ? "#f3f4f6" : "#6b7280",
    }
  }

  createChart() {
    const timeSeries = this.readTimeSeries()
    if (!timeSeries.length) return

    const labels = this.buildLabels(timeSeries)

    const datasets = this.buildDatasets(timeSeries)
    const scales = this.buildScales()

    const theme = this.getThemeColors()
    const events = this.readEvents()

    this.chart = new Chart(this.canvas, {
      type: "line",
      data: {
        labels,
        datasets,
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        interaction: {
          mode: "index",
          intersect: false,
        },
        plugins: {
          eventMarkers: {
            events: events,
            lineColor: theme.isDark ? "#fb923c" : "#f97316",
            badgeBackground: theme.isDark ? "rgba(251, 146, 60, 0.92)" : "rgba(249, 115, 22, 0.92)",
            badgeBorder: theme.isDark ? "rgba(194, 65, 12, 0.4)" : "rgba(124, 45, 18, 0.35)",
            badgeText: "#0f172a",
            font: "10px 'Inter', system-ui, sans-serif",
            lineWidth: 1,
            lineDash: [4, 4]
          },
          legend: {
            display: false, // Hide legend - metric cards serve as the legend
          },
          tooltip: {
            enabled: true,
            backgroundColor: theme.isDark ? "rgba(31, 41, 55, 0.95)" : "rgba(255, 255, 255, 0.95)",
            titleColor: theme.textColorPrimary,
            bodyColor: theme.textColorPrimary,
            borderColor: theme.isDark ? "rgba(75, 85, 99, 0.6)" : "rgba(229, 231, 235, 0.8)",
            borderWidth: 1,
            padding: 12,
            displayColors: true,
            callbacks: {
              label: context => {
                const label = context.dataset.label || ""
                const value = context.parsed.y

                // Format based on series type
                if (label === "CTR") {
                  return `${label}: ${(value * 100).toFixed(2)}%`
                } else if (label === "Avg Position") {
                  return `${label}: ${value.toFixed(1)}`
                } else {
                  return `${label}: ${value.toLocaleString()}`
                }
              },
            },
          },
        },
        scales,
        elements: {
          line: {
            borderWidth: 2.5,
            tension: 0.1,
          },
          point: {
            radius: 0,
            hoverRadius: 6,
            hitRadius: 8,
            backgroundColor: 'rgba(0, 0, 0, 0)', // Transparent by default
          },
        },
        animations: {
          tension: {
            duration: 400,
            easing: "easeInOutQuad",
          },
          radius: false, // Disable point radius animations to prevent bubbles flashing
        },
      },
    })
  }

  /**
   * Dynamically assign axes based on visible series
   * Uses static rules - Chart.js will auto-scale based on actual data
   */
  assignAxes() {
    const visible = this.visibleSeries
    const assignments = {}

    // Check which metrics are visible
    const ctrVisible = visible.includes('ctr')
    const positionVisible = visible.includes('position')
    const clicksVisible = visible.includes('clicks')
    const impressionsVisible = visible.includes('impressions')

    // CTR and Position always get dedicated axes due to their unique scales
    if (ctrVisible) {
      assignments.ctr = { axisID: 'y_ctr', position: 'right', type: 'percentage' }
    }
    if (positionVisible) {
      assignments.position = { axisID: 'y_position', position: 'right', type: 'inverted' }
    }

    // Smart assignment for Clicks and Impressions
    // Always use separate axes for better visibility (Google's approach)
    if (clicksVisible && impressionsVisible) {
      // Both visible - impressions on left (usually larger), clicks on right
      assignments.impressions = { axisID: 'y_left', position: 'left', type: 'count' }
      assignments.clicks = { axisID: 'y_right', position: 'right', type: 'count' }
    } else if (clicksVisible) {
      // Only clicks visible
      assignments.clicks = { axisID: 'y_left', position: 'left', type: 'count' }
    } else if (impressionsVisible) {
      // Only impressions visible
      assignments.impressions = { axisID: 'y_left', position: 'left', type: 'count' }
    }

    return assignments
  }

  buildDatasets(timeSeries) {
    const datasets = []
    const axisAssignments = this.assignAxes()

    // Always build ALL datasets, use 'hidden' property to control visibility
    Object.keys(this.seriesConfig).forEach(seriesKey => {
      const config = this.seriesConfig[seriesKey]
      const isVisible = this.visibleSeries.includes(seriesKey)

      // Get dynamically assigned axis for visible series only
      // Hidden series should not have axis assignments to prevent Chart.js from creating unused axes
      const assignment = axisAssignments[seriesKey]
      const yAxisID = assignment ? assignment.axisID : 'y_hidden'

      datasets.push({
        label: config.label,
        data: timeSeries.map(point => {
          const value = Number(point[seriesKey]) || 0
          return value
        }),
        borderColor: config.borderColor,
        backgroundColor: config.backgroundColor,
        yAxisID: yAxisID, // Use dynamically assigned axis or 'y_hidden' for invisible series
        fill: true,
        order: config.order,
        hidden: !isVisible,
        pointRadius: 0, // Hide points by default
        pointHoverRadius: 6, // Show point on hover
        pointHitRadius: 8, // Larger hover detection area
      })
    })

    return datasets
  }

  buildLabels(timeSeries) {
    return timeSeries.map(point => {
      if (point.period_end) {
        return `${point.date} - ${point.period_end}`
      }
      return point.date
    })
  }

  /**
   * Dynamically build scales based on current axis assignments
   * Leverages Chart.js built-in autoscaling for optimal performance
   */
  buildScales() {
    const theme = this.getThemeColors()

    const scales = {
      x: {
        type: "category",
        grid: {
          color: theme.gridColor,
          drawOnChartArea: true,
        },
        ticks: {
          color: theme.textColorSecondary,
          font: this.fonts.tick,
          maxRotation: 45,
          minRotation: 0,
        },
      },
    }

    // Get axis assignments dynamically (fast - no data iteration)
    const assignments = this.assignAxes()

    // Collect all axis IDs that will be used
    const activeAxisIDs = new Set(
      Object.values(assignments).map(a => a.axisID)
    )

    // List of all possible axis IDs that might exist from previous renders
    const allPossibleAxisIDs = [
      'y', 'y1', 'y2', // Default axis IDs
      'y_left', 'y_right', // Count axes
      'y_ctr', // CTR axis
      'y_position', // Position axis
      'y_hidden', // Hidden datasets axis
    ]

    // Explicitly hide all unused axes to prevent Chart.js from rendering ghosts
    allPossibleAxisIDs.forEach(axisID => {
      if (!activeAxisIDs.has(axisID)) {
        scales[axisID] = { display: false }
      }
    })

    // Build axes dynamically based on assignments
    Object.entries(assignments).forEach(([seriesKey, assignment]) => {
      const { axisID, position, type } = assignment
      const config = this.seriesConfig[seriesKey]

      if (type === 'count') {
        // Count-based axis (Clicks/Impressions)
        // Chart.js will auto-calculate min/max from data
        scales[axisID] = {
          type: "linear",
          position: position,
          beginAtZero: true, // Always start count axes at 0
          grid: {
            color: theme.gridColor,
            drawOnChartArea: position === 'left', // Only left axis shows grid
          },
          ticks: {
            color: config.borderColor,
            font: this.fonts.tick,
            callback: value => this.formatAxisValue(value),
          },
          title: {
            display: true,
            text: config.label,
            color: config.borderColor,
            font: this.fonts.title,
          },
        }
      } else if (type === 'percentage') {
        // CTR axis - use suggestedMax for flexibility
        scales[axisID] = {
          type: "linear",
          position: position,
          beginAtZero: true,
          suggestedMax: 0.02, // Suggest 2% but allow Chart.js to extend if needed
          grid: {
            drawOnChartArea: false,
          },
          ticks: {
            color: config.borderColor,
            font: this.fonts.tick,
            callback: value => `${(value * 100).toFixed(1)}%`,
          },
          title: {
            display: true,
            text: "CTR",
            color: config.borderColor,
            font: this.fonts.title,
          },
        }
      } else if (type === 'inverted') {
        // Position axis (lower is better)
        scales[axisID] = {
          type: "linear",
          position: position,
          reverse: true,
          suggestedMin: 1,
          suggestedMax: 100, // Suggest range but allow Chart.js to adjust
          grid: {
            drawOnChartArea: false,
          },
          ticks: {
            color: config.borderColor,
            font: this.fonts.tick,
            callback: value => value.toFixed(0),
          },
          title: {
            display: true,
            text: "Position",
            color: config.borderColor,
            font: this.fonts.title,
          },
        }
      }
    })

    return scales
  }

  formatAxisValue(value) {
    if (value >= 1_000_000) {
      return `${(value / 1_000_000).toFixed(1)}M`
    } else if (value >= 1_000) {
      return `${(value / 1_000).toFixed(1)}K`
    }
    return value.toLocaleString()
  }

  addEventMarkers() {
    const events = this.readEvents()
    if (!events.length || !this.chart) return

    // Update plugin options with events and theme colors
    const theme = this.getThemeColors()

    this.chart.options.plugins.eventMarkers = {
      events: events,
      lineColor: theme.isDark ? "#fb923c" : "#f97316",
      badgeBackground: theme.isDark ? "rgba(251, 146, 60, 0.92)" : "rgba(249, 115, 22, 0.92)",
      badgeBorder: theme.isDark ? "rgba(194, 65, 12, 0.4)" : "rgba(124, 45, 18, 0.35)",
      badgeText: "#0f172a",
      font: "10px 'Inter', system-ui, sans-serif",
      lineWidth: 1,
      lineDash: [4, 4]
    }

    this.chart.update('none') // Update without animation
  }

  updateChart() {
    if (!this.chart) return

    const timeSeries = this.readTimeSeries()
    if (!timeSeries.length) {
      this.destroy()
      return
    }

    // Replace labels/data wholesale so new time series actually renders
    this.chart.data.labels = this.buildLabels(timeSeries)
    this.chart.data.datasets = this.buildDatasets(timeSeries)

    // Rebuild scales dynamically (Chart.js handles autoscaling)
    this.chart.options.scales = this.buildScales()

    // Update event markers with latest events and theme
    const events = this.readEvents()
    const theme = this.getThemeColors()

    this.chart.options.plugins.eventMarkers = {
      events: events,
      lineColor: theme.isDark ? "#fb923c" : "#f97316",
      badgeBackground: theme.isDark ? "rgba(251, 146, 60, 0.92)" : "rgba(249, 115, 22, 0.92)",
      badgeBorder: theme.isDark ? "rgba(194, 65, 12, 0.4)" : "rgba(124, 45, 18, 0.35)",
      badgeText: "#0f172a",
      font: "10px 'Inter', system-ui, sans-serif",
      lineWidth: 1,
      lineDash: [4, 4]
    }

    // Ensure canvas dimensions are correct before update
    this.chart.resize()

    // Update without animation to prevent points from flashing
    this.chart.update('none')
  }
}

export const ChartJsPerformanceChartHook = {
  mounted() {
    this.controller = new ChartJsPerformanceChart(this)
    this.controller.mount()
  },
  updated() {
    this.controller?.update()
  },
  destroyed() {
    this.controller?.destroy()
  },
}

export default ChartJsPerformanceChartHook
