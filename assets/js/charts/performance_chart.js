import {
  createFormatterBundle,
  formatDateLabel,
  formatNumber,
  formatTooltipHeading,
  safeParseDate,
} from "./formatters"
import {buildTickIndices, shouldStaggerLabels} from "./layout"
import {
  getDefaultPadding,
  calculatePlotDimensions,
  createXScaler,
  createYScaler,
} from "./geometry"
import {
  clearCanvas,
  drawGrid,
  drawAxisLines,
  drawDataLine,
  drawCrosshair,
  drawHighlightCircle,
  drawEventMarker
} from "./drawing"

class PerformanceChartController {
  constructor(hook) {
    this.hook = hook
    this.el = hook.el
    this.canvas = document.getElementById(this.el.dataset.chartId)
    this.ctx = this.canvas?.getContext("2d")
    this.formatters = createFormatterBundle()

    this.series = []
    this.events = []
    this.xLabel = this.el.dataset.xLabel || "Date"

    this.hoveredIndex = null
    this.mousePos = {x: 0, y: 0}
    this.tooltipOpacity = 0
    this.tooltipTargetOpacity = 0

    this.cachedPadding = {top: 20, right: 48, bottom: 75, left: 64}
    this.cachedMaxClicks = 1
    this.cachedMaxImpressions = 1
    this.cachedMaxCtr = 0.02 // 2% max for CTR scale
    this.cachedMaxPosition = 100 // Fixed scale for position (1-100)
    this.visibleSeries = ["clicks", "impressions"]

    // Series configuration
    this.seriesConfig = {
      clicks: {label: "Clicks", color: "#6366f1", axis: "left"},
      impressions: {label: "Impressions", color: "#10b981", axis: "left"},
      ctr: {label: "CTR", color: "#a855f7", axis: "right", formatter: (v) => `${(v * 100).toFixed(2)}%`},
      position: {label: "Avg Position", color: "#ef4444", axis: "none", inverted: true, formatter: (v) => v.toFixed(1)}
    }
  }

  mount() {
    if (!this.canvas) return

    this.mouseMoveHandler = event => this.handleMouseMove(event)
    this.mouseLeaveHandler = () => this.handleMouseLeave()
    this.touchMoveHandler = event => this.handleTouchMove(event)
    this.touchEndHandler = () => this.handleMouseLeave()

    this.canvas.addEventListener("mousemove", this.mouseMoveHandler)
    this.canvas.addEventListener("mouseleave", this.mouseLeaveHandler)
    this.canvas.addEventListener("touchmove", this.touchMoveHandler, {passive: false})
    this.canvas.addEventListener("touchend", this.touchEndHandler)

    if (typeof ResizeObserver === "function") {
      this.resizeObserver = new ResizeObserver(() => this.drawChart())
      this.resizeObserver.observe(this.el)
    } else {
      this.resizeHandler = () => this.drawChart()
      window.addEventListener("resize", this.resizeHandler)
    }

    this.update()
  }

  destroy() {
    if (!this.canvas) return

    this.canvas.removeEventListener("mousemove", this.mouseMoveHandler)
    this.canvas.removeEventListener("mouseleave", this.mouseLeaveHandler)
    this.canvas.removeEventListener("touchmove", this.touchMoveHandler)
    this.canvas.removeEventListener("touchend", this.touchEndHandler)

    if (this.resizeObserver) {
      this.resizeObserver.disconnect()
    }
    if (this.resizeHandler) {
      window.removeEventListener("resize", this.resizeHandler)
    }
  }

  update() {
    this.series = this.readSeries()
    this.events = this.readEvents()
    this.visibleSeries = this.readVisibleSeries()
    this.xLabel = this.el.dataset.xLabel || "Date"
    this.drawChart()
  }

  readVisibleSeries() {
    try {
      const raw = JSON.parse(this.el.dataset.visibleSeries || '["clicks","impressions"]')
      if (!Array.isArray(raw)) return ["clicks", "impressions"]
      return raw.filter(s => this.seriesConfig[s])
    } catch (_err) {
      return ["clicks", "impressions"]
    }
  }

  readSeries() {
    try {
      const raw = JSON.parse(this.el.dataset.timeSeries || "[]")
      if (!Array.isArray(raw)) return []

      // Trust backend sorting - data arrives pre-sorted from TimeSeriesAggregator
      return raw.filter(point => point && point.date)
    } catch (_err) {
      return []
    }
  }

  readEvents() {
    try {
      const raw = JSON.parse(this.el.dataset.events || "[]")
      if (!Array.isArray(raw)) return []

      // Trust backend sorting - events arrive pre-sorted from ChartPresenter
      return raw.filter(event => event && event.date && safeParseDate(event.date))
    } catch (_err) {
      return []
    }
  }

  drawChart() {
    if (!this.ctx || !this.canvas) return

    const series = Array.isArray(this.series) ? this.series : []
    const hasData = series.length > 0
    const width = this.el.clientWidth || 640
    const height = this.el.clientHeight || 384
    const dpr = window.devicePixelRatio || 1

    this.canvas.width = width * dpr
    this.canvas.height = height * dpr
    this.canvas.style.width = `${width}px`
    this.canvas.style.height = `${height}px`
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
    this.ctx.clearRect(0, 0, width, height)

    if (!hasData) {
      this.renderEmptyState(width, height)
      return
    }

    const padding = getDefaultPadding()
    const {plotWidth, plotHeight, plotBottom} = calculatePlotDimensions(width, height, padding)

    // Extract data for each series type
    const seriesData = {
      clicks: series.map(point => Number(point.clicks) || 0),
      impressions: series.map(point => Number(point.impressions) || 0),
      ctr: series.map(point => Number(point.ctr) || 0),
      position: series.map(point => Number(point.position) || 0)
    }

    // Determine which series use left vs right axis
    const leftAxisSeries = this.visibleSeries.filter(s => this.seriesConfig[s]?.axis === "left")
    const rightAxisSeries = this.visibleSeries.filter(s => this.seriesConfig[s]?.axis === "right")

    // Build axis metadata for visible series
    let leftAxisMeta = null
    let rightAxisMeta = null

    if (leftAxisSeries.length > 0) {
      // Combine all left-axis series data to find the max
      const allLeftValues = leftAxisSeries.flatMap(s => seriesData[s])
      leftAxisMeta = this.buildYAxisMeta(allLeftValues)
    }

    if (rightAxisSeries.length > 0 && rightAxisSeries.includes("ctr")) {
      // CTR uses a fixed percentage scale (0-2%)
      rightAxisMeta = this.buildYAxisMeta(seriesData.ctr, 0.02) // Max 2%
    }

    const xForIndex = createXScaler(series.length, plotWidth, padding.left)
    const yForLeftAxis = leftAxisMeta ? createYScaler(leftAxisMeta.domainMax, plotHeight, padding.top) : null
    const yForRightAxis = rightAxisMeta ? createYScaler(rightAxisMeta.domainMax, plotHeight, padding.top) : null

    // Cache for interactive elements
    this.cachedPadding = padding
    this.cachedMaxClicks = leftAxisMeta ? leftAxisMeta.domainMax : 1
    this.cachedMaxImpressions = leftAxisMeta ? leftAxisMeta.domainMax : 1
    this.cachedMaxCtr = rightAxisMeta ? rightAxisMeta.domainMax : 0.02

    // Draw axes
    const primaryAxis = leftAxisMeta && leftAxisSeries.length > 0 ? {
      label: leftAxisSeries.length === 1 ? this.seriesConfig[leftAxisSeries[0]].label : "Count",
      color: this.seriesConfig[leftAxisSeries[0]].color,
      meta: leftAxisMeta,
      yForValue: yForLeftAxis,
    } : null

    const secondaryAxis = rightAxisMeta && rightAxisSeries.length > 0 ? {
      label: this.seriesConfig[rightAxisSeries[0]].label,
      color: this.seriesConfig[rightAxisSeries[0]].color,
      meta: rightAxisMeta,
      yForValue: yForRightAxis,
    } : null

    this.drawAxes(width, height, padding, series, xForIndex, {
      primary: primaryAxis,
      secondary: secondaryAxis,
    })

    // Draw lines for each visible series
    this.visibleSeries.forEach(seriesKey => {
      const config = this.seriesConfig[seriesKey]
      const data = seriesData[seriesKey]

      // Determine Y-scaler based on axis type
      let yScaler
      if (config.axis === "left") {
        yScaler = yForLeftAxis
      } else if (config.axis === "right") {
        yScaler = yForRightAxis
      } else if (config.axis === "none") {
        // Create custom scaler for axis-less series (like position)
        const maxValue = seriesKey === "position" ? 100 : Math.max(...data)

        if (config.inverted) {
          // Inverted Y-axis: lower values appear higher (position 1 at top, 100 at bottom)
          yScaler = value => padding.top + (value / maxValue) * plotHeight
        } else {
          yScaler = createYScaler(maxValue, plotHeight, padding.top)
        }
      }

      if (yScaler) {
        this.drawLine(data, config.color, xForIndex, yScaler, padding, plotBottom)
      }
    })

    // Build legend dynamically
    const legendItems = this.visibleSeries.map(s => [this.seriesConfig[s].label, this.seriesConfig[s].color])
    this.drawLegend(width, padding, legendItems)
    this.drawEvents(series, xForIndex, padding, plotBottom)

    this.drawInteractiveElements()
  }

  renderEmptyState(width, height) {
    const ctx = this.ctx
    ctx.fillStyle = "#9ca3af"
    ctx.font = "14px Inter, system-ui, sans-serif"
    ctx.textAlign = "center"
    ctx.fillText("No time series data available", width / 2, height / 2)
  }

  drawAxes(width, height, padding, series, xForIndex, axes) {
    const ctx = this.ctx
    const plotWidth = width - padding.left - padding.right

    if (axes?.primary) {
      this.drawHorizontalGridLines(
        width,
        height,
        padding,
        axes.primary.meta,
        axes.primary.yForValue,
      )
    }

    ctx.save()
    ctx.strokeStyle = "#d1d5db"
    ctx.lineWidth = 1

    ctx.beginPath()
    ctx.moveTo(padding.left, padding.top)
    ctx.lineTo(padding.left, height - padding.bottom)
    ctx.lineTo(width - padding.right, height - padding.bottom)
    if (axes?.secondary) {
      ctx.lineTo(width - padding.right, padding.top)
    }
    ctx.stroke()
    ctx.restore()

    // Y-axis tick labels removed for cleaner axis-free design
    // With multiple series (clicks, impressions, CTR %, position rank) using different scales,
    // axis labels are misleading. Users rely on legend and tooltips for values.

    // if (axes?.primary) {
    //   this.drawYAxisTicks(
    //     padding.left,
    //     padding,
    //     height,
    //     axes.primary.meta,
    //     axes.primary.color,
    //     axes.primary.label,
    //     false,
    //     axes.primary.yForValue,
    //   )
    // }

    // if (axes?.secondary) {
    //   this.drawYAxisTicks(
    //     width - padding.right,
    //     padding,
    //     height,
    //     axes.secondary.meta,
    //     axes.secondary.color,
    //     axes.secondary.label,
    //     true,
    //     axes.secondary.yForValue,
    //   )
    // }

    this.drawXAxisLabels(series, xForIndex, padding, width, height, plotWidth)
  }

  drawYAxisTicks(
    axisX,
    padding,
    height,
    axisMeta,
    color,
    label,
    alignRight = false,
    yForValue,
  ) {
    if (!axisMeta || !Array.isArray(axisMeta.ticks)) return

    const ctx = this.ctx
    const tickLength = 6
    const textOffset = tickLength + 4
    const direction = alignRight ? -1 : 1

    ctx.save()
    ctx.strokeStyle = color
    ctx.lineWidth = 1
    ctx.textAlign = alignRight ? "right" : "left"
    ctx.font = "12px Inter, system-ui, sans-serif"

    axisMeta.ticks.forEach(value => {
      const y = yForValue(value)
      ctx.beginPath()
      ctx.moveTo(axisX, y)
      ctx.lineTo(axisX + direction * tickLength, y)
      ctx.stroke()
    })

    ctx.fillStyle = "#475569"
    axisMeta.ticks.forEach(value => {
      const y = yForValue(value)
      const labelText = this.formatAxisTick(value, axisMeta.domainMax)
      ctx.fillText(labelText, axisX + direction * textOffset, y + 4)
    })

    ctx.restore()

    ctx.save()
    ctx.font = "600 11px Inter, system-ui, sans-serif"
    ctx.fillStyle = color
    ctx.textAlign = alignRight ? "right" : "left"
    ctx.textBaseline = "top"
    ctx.fillText(label, axisX + direction * 10, padding.top - 8)
    ctx.restore()
  }

  drawLine(values, color, xForIndex, yForValue, padding, plotBottom) {
    const ctx = this.ctx
    if (!values.length) return

    ctx.strokeStyle = color
    ctx.lineWidth = 2.5
    ctx.beginPath()
    values.forEach((value, index) => {
      const x = xForIndex(index)
      const y = yForValue(value)
      if (index === 0) ctx.moveTo(x, y)
      else ctx.lineTo(x, y)
    })
    ctx.stroke()

    ctx.beginPath()
    ctx.moveTo(xForIndex(0), plotBottom)
    values.forEach((value, index) => {
      const x = xForIndex(index)
      const y = yForValue(value)
      ctx.lineTo(x, y)
    })
    ctx.lineTo(xForIndex(values.length - 1), plotBottom)
    ctx.closePath()

    const gradient = ctx.createLinearGradient(0, padding.top, 0, plotBottom)
    gradient.addColorStop(0, this.hexToRgba(color, 0.25))
    gradient.addColorStop(0.5, this.hexToRgba(color, 0.15))
    gradient.addColorStop(1, this.hexToRgba(color, 0.05))
    ctx.fillStyle = gradient
    ctx.fill()
  }

  drawLegend(_width, padding, items) {
    const ctx = this.ctx
    const legendY = padding.top + 8
    let cursorX = padding.left

    items.forEach(([label, color]) => {
      ctx.fillStyle = color
      ctx.fillRect(cursorX, legendY, 12, 12)
      cursorX += 18
      ctx.fillStyle = "#374151"
      ctx.font = "12px Inter, system-ui, sans-serif"
      ctx.textAlign = "left"
      ctx.fillText(label, cursorX, legendY + 10)
      cursorX += ctx.measureText(label).width + 16
    })
  }

  drawHorizontalGridLines(width, height, padding, axisMeta, yForValue) {
    if (!axisMeta || !Array.isArray(axisMeta.ticks)) return

    const ctx = this.ctx
    const rightBound = width - padding.right
    const step = axisMeta.step || axisMeta.domainMax || 1

    ctx.save()
    ctx.strokeStyle = "rgba(148, 163, 184, 0.25)"
    ctx.lineWidth = 1
    ctx.setLineDash([4, 4])

    axisMeta.ticks.forEach(value => {
      if (value <= 0) return
      if (value >= axisMeta.domainMax - step * 0.001) return
      const y = yForValue(value)
      if (y <= padding.top || y >= height - padding.bottom) return
      ctx.beginPath()
      ctx.moveTo(padding.left, y)
      ctx.lineTo(rightBound, y)
      ctx.stroke()
    })

    ctx.restore()
  }

  drawXAxisLabels(series, xForIndex, padding, width, height, plotWidth) {
    if (!Array.isArray(series) || series.length === 0) return

    const ctx = this.ctx
    const tickIndices = buildTickIndices(series.length, plotWidth)
    const stagger = shouldStaggerLabels(tickIndices.length, plotWidth)
    const axisY = height - padding.bottom
    const baseLabelY = axisY + 10

    ctx.save()
    ctx.strokeStyle = "rgba(148, 163, 184, 0.4)"
    ctx.lineWidth = 1
    ctx.font = "12px Inter, system-ui, sans-serif"
    ctx.textAlign = "center"
    ctx.textBaseline = "top"
    ctx.fillStyle = "#475569"

    tickIndices.forEach((index, order) => {
      const dataPoint = series[index]
      const label = formatDateLabel(dataPoint, index, series, this.formatters)
      const x = xForIndex(index)
      const verticalOffset = stagger && order % 2 === 1 ? 12 : 0

      ctx.beginPath()
      ctx.moveTo(x, axisY)
      ctx.lineTo(x, axisY + 6)
      ctx.stroke()

      const lines = this.splitXAxisLabel(label)
      lines.forEach((line, lineIndex) => {
        ctx.fillText(line, x, baseLabelY + verticalOffset + lineIndex * 14)
      })
    })

    ctx.restore()

    ctx.save()
    ctx.fillStyle = "#6b7280"
    ctx.font = "12px Inter, system-ui, sans-serif"
    ctx.textAlign = "center"
    ctx.fillText(
      this.xLabel,
      padding.left + plotWidth / 2,
      axisY + 44,
    )
    ctx.restore()
  }

  splitXAxisLabel(label) {
    if (!label) return [""]
    const cleaned = String(label).trim()
    if (!cleaned) return [""]

    if (cleaned.includes(" - ")) {
      const parts = cleaned.split(" - ").map(part => part.trim()).filter(Boolean)
      if (parts.length >= 2) {
        const [first, ...rest] = parts
        return [first, rest.join(" - ")]
      }
    }

    const words = cleaned.split(/\s+/)
    if (words.length === 1) return [cleaned]
    if (words.length === 2) return [words[0], words[1]]

    return [words.slice(0, 2).join(" "), words.slice(2).join(" ")]
  }

  buildYAxisMeta(values, targetTickCount = 5) {
    const sanitized = Array.isArray(values)
      ? values.map(value => Number(value) || 0).filter(value => value >= 0)
      : []

    const maxValue = sanitized.length ? Math.max(...sanitized) : 0
    const {domainMax, step} = this.computeNiceScale(maxValue, targetTickCount)

    const ticks = []
    for (let current = 0; current <= domainMax + step * 0.5; current += step) {
      ticks.push(Number(current.toFixed(6)))
    }

    if (!ticks.includes(0)) ticks.unshift(0)

    const uniqueTicks = Array.from(new Set(ticks)).sort((a, b) => a - b)
    return {domainMax, step, ticks: uniqueTicks}
  }

  formatAxisTick(value, domainMax) {
    if (!Number.isFinite(value)) return "0"
    if (value === 0) return "0"

    if (domainMax >= 1_000) {
      return formatNumber(value)
    }

    if (domainMax >= 10) {
      return Math.round(value).toLocaleString()
    }

    if (domainMax >= 1) {
      return Number(value.toFixed(1)).toString()
    }

    return Number(value.toFixed(2)).toString()
  }

  computeNiceScale(maxValue, targetTickCount = 5) {
    const safeMax = Number.isFinite(maxValue) && maxValue > 0 ? maxValue : 1
    const roughStep = safeMax / Math.max(1, targetTickCount)
    const step = this.niceNumber(roughStep)
    const domainMax = step * Math.max(1, Math.ceil(safeMax / step))

    return {domainMax, step}
  }

  niceNumber(value) {
    if (!Number.isFinite(value) || value <= 0) return 1

    const exponent = Math.floor(Math.log10(value))
    const fraction = value / Math.pow(10, exponent)
    let niceFraction

    if (fraction <= 1) niceFraction = 1
    else if (fraction <= 2) niceFraction = 2
    else if (fraction <= 2.5) niceFraction = 2.5
    else if (fraction <= 5) niceFraction = 5
    else niceFraction = 10

    return niceFraction * Math.pow(10, exponent)
  }

  drawEvents(series, xForIndex, padding, plotBottom) {
    if (!Array.isArray(this.events) || this.events.length === 0) return
    const ctx = this.ctx
    const labels = series.map(point => point.date)

    this.events.forEach(event => {
      const dataIndex = labels.indexOf(event.date)
      if (dataIndex === -1) return

      const x = xForIndex(dataIndex)
      const color = "#f97316"

      ctx.save()
      ctx.strokeStyle = color
      ctx.lineWidth = 1.5
      ctx.setLineDash([6, 4])
      ctx.beginPath()
      ctx.moveTo(x, padding.top)
      ctx.lineTo(x, plotBottom)
      ctx.stroke()
      ctx.setLineDash([])

      ctx.fillStyle = color
      ctx.beginPath()
      const markerY = padding.top - 6
      ctx.arc(x, markerY, 4, 0, Math.PI * 2)
      ctx.fill()

      if (event.label) {
        ctx.font = "10px Inter, system-ui, sans-serif"
        ctx.textAlign = "center"
        ctx.fillStyle = color
        const labelY = Math.max(padding.top - 14, 12)
        ctx.fillText(event.label, x, labelY)
      }

      ctx.restore()
    })
  }

  handleMouseMove(event) {
    if (!this.canvas || !this.series || this.series.length === 0) return

    const rect = this.canvas.getBoundingClientRect()
    this.mousePos.x = event.clientX - rect.left
    this.mousePos.y = event.clientY - rect.top

    const nearestIndex = this.findNearestDataPoint(this.mousePos.x)

    if (nearestIndex !== this.hoveredIndex) {
      this.hoveredIndex = nearestIndex
      this.tooltipTargetOpacity = 1
      this.animateTooltip()
    }
  }

  handleTouchMove(event) {
    if (!this.canvas || !this.series || this.series.length === 0) return

    event.preventDefault()
    const touch = event.touches[0]
    const rect = this.canvas.getBoundingClientRect()
    this.mousePos.x = touch.clientX - rect.left
    this.mousePos.y = touch.clientY - rect.top

    const nearestIndex = this.findNearestDataPoint(this.mousePos.x)

    if (nearestIndex !== this.hoveredIndex) {
      this.hoveredIndex = nearestIndex
      this.tooltipTargetOpacity = 1
      this.animateTooltip()
    }
  }

  handleMouseLeave() {
    if (this.hoveredIndex !== null) {
      this.hoveredIndex = null
      this.tooltipTargetOpacity = 0
      this.animateTooltip()
    }
  }

  animateTooltip() {
    const step = () => {
      const diff = this.tooltipTargetOpacity - this.tooltipOpacity
      if (Math.abs(diff) > 0.01) {
        this.tooltipOpacity += diff * 0.2
        this.drawChart()
        requestAnimationFrame(step)
      } else {
        this.tooltipOpacity = this.tooltipTargetOpacity
        this.drawChart()
      }
    }
    step()
  }

  findNearestDataPoint(mouseX) {
    const series = this.series
    if (!series || series.length === 0) return null

    const padding = this.cachedPadding
    const width = this.el.clientWidth || 640
    const plotWidth = width - padding.left - padding.right

    if (series.length === 1) return 0

    let nearestIndex = 0
    let minDistance = Infinity

    series.forEach((_, index) => {
      const ratio = index / (series.length - 1)
      const x = padding.left + ratio * plotWidth
      const distance = Math.abs(x - mouseX)

      if (distance < minDistance) {
        minDistance = distance
        nearestIndex = index
      }
    })

    return nearestIndex
  }

  drawInteractiveElements() {
    if (this.tooltipOpacity < 0.01) return
    if (this.hoveredIndex === null || !this.series || this.series.length === 0) return

    const dataPoint = this.series[this.hoveredIndex]
    const width = this.el.clientWidth || 640
    const height = this.el.clientHeight || 384
    const padding = this.cachedPadding
    const plotWidth = width - padding.left - padding.right

    const xPos =
      this.series.length === 1
        ? padding.left + plotWidth / 2
        : padding.left + (this.hoveredIndex / (this.series.length - 1)) * plotWidth

    this.drawCrosshair(xPos, padding, height, this.tooltipOpacity)
    this.drawHighlightPoints(dataPoint, xPos, padding, height, this.tooltipOpacity)
    this.drawTooltip(dataPoint, xPos, this.mousePos.y, this.tooltipOpacity)
  }

  drawCrosshair(x, padding, height, opacity = 1) {
    const ctx = this.ctx
    ctx.save()
    ctx.globalAlpha = opacity
    ctx.strokeStyle = "rgba(107, 114, 128, 0.6)"
    ctx.lineWidth = 1.5
    ctx.setLineDash([4, 4])
    ctx.beginPath()
    ctx.moveTo(x, padding.top)
    ctx.lineTo(x, height - padding.bottom)
    ctx.stroke()
    ctx.setLineDash([])
    ctx.restore()
  }

  drawHighlightPoints(dataPoint, xPos, padding, height, opacity = 1) {
    const ctx = this.ctx
    const plotHeight = height - padding.top - padding.bottom

    // Draw highlight points for each visible series
    this.visibleSeries.forEach(seriesKey => {
      const config = this.seriesConfig[seriesKey]
      const value = Number(dataPoint[seriesKey]) || 0

      // Get the appropriate max value and calculate Y position
      let maxValue, yPos

      if (config.axis === "left") {
        maxValue = this.cachedMaxClicks // Use cached left axis max
        yPos = padding.top + (1 - value / maxValue) * plotHeight
      } else if (config.axis === "right") {
        maxValue = this.cachedMaxCtr // Use cached CTR max
        yPos = padding.top + (1 - value / maxValue) * plotHeight
      } else if (config.axis === "none") {
        maxValue = seriesKey === "position" ? this.cachedMaxPosition : 100
        if (config.inverted) {
          // Inverted Y-axis for position
          yPos = padding.top + (value / maxValue) * plotHeight
        } else {
          yPos = padding.top + (1 - value / maxValue) * plotHeight
        }
      }

      // Draw outer glow
      ctx.save()
      ctx.globalAlpha = opacity
      ctx.fillStyle = this.hexToRgba(config.color, 0.2)
      ctx.beginPath()
      ctx.arc(xPos, yPos, 10, 0, Math.PI * 2)
      ctx.fill()

      // Draw main circle
      ctx.fillStyle = config.color
      ctx.strokeStyle = "#ffffff"
      ctx.lineWidth = 2.5
      ctx.beginPath()
      ctx.arc(xPos, yPos, 7, 0, Math.PI * 2)
      ctx.fill()
      ctx.stroke()
      ctx.restore()
    })
  }

  drawTooltip(dataPoint, chartX, mouseY, opacity = 1) {
    const ctx = this.ctx
    const width = this.el.clientWidth || 640

    const dateHeader = formatTooltipHeading(dataPoint, this.formatters)

    // Build metrics list from visible series
    const metrics = this.visibleSeries.map(seriesKey => {
      const config = this.seriesConfig[seriesKey]
      const value = dataPoint[seriesKey] || 0

      // Format value based on series type
      let formattedValue
      if (config.formatter) {
        formattedValue = config.formatter(value)
      } else {
        formattedValue = formatNumber(value)
      }

      return {label: config.label, value: formattedValue, color: config.color}
    })

    // Always show CTR and Position at the bottom
    const ctr = `${((dataPoint.ctr || 0) * 100).toFixed(2)}%`
    const position = (dataPoint.position || 0).toFixed(1)

    const tooltipPadding = 14
    const lineHeight = 24
    const headerHeight = 28
    const tooltipWidth = 230
    const tooltipHeight =
      headerHeight + lineHeight * (metrics.length + 2) + tooltipPadding * 2 + 4

    let tooltipX = chartX + 15
    if (tooltipX + tooltipWidth > width - 10) {
      tooltipX = chartX - tooltipWidth - 15
    }

    let tooltipY = mouseY - tooltipHeight / 2
    tooltipY = Math.max(
      10,
      Math.min(tooltipY, (this.el.clientHeight || 384) - tooltipHeight - 10),
    )

    const isDark = document.documentElement.dataset.theme === "dark"
    const bgColor = isDark ? "rgba(31, 41, 55, 0.85)" : "rgba(255, 255, 255, 0.85)"
    const borderColor = isDark ? "rgba(75, 85, 99, 0.6)" : "rgba(229, 231, 235, 0.8)"
    const textColor = isDark ? "#f3f4f6" : "#1f2937"
    const secondaryTextColor = isDark ? "#9ca3af" : "#6b7280"

    ctx.save()
    ctx.globalAlpha = opacity

    // Subtle scale animation on appear
    const scale = 0.92 + (opacity * 0.08)
    const centerX = tooltipX + tooltipWidth / 2
    const centerY = tooltipY + tooltipHeight / 2
    ctx.translate(centerX, centerY)
    ctx.scale(scale, scale)
    ctx.translate(-centerX, -centerY)

    ctx.shadowColor = "rgba(0, 0, 0, 0.1)"
    ctx.shadowBlur = 8
    ctx.shadowOffsetX = 0
    ctx.shadowOffsetY = 2

    ctx.fillStyle = bgColor
    ctx.strokeStyle = borderColor
    ctx.lineWidth = 1
    this.roundRect(ctx, tooltipX, tooltipY, tooltipWidth, tooltipHeight, 8)
    ctx.fill()
    ctx.stroke()

    ctx.shadowColor = "transparent"
    ctx.shadowBlur = 0

    ctx.fillStyle = isDark ? "rgba(55, 65, 81, 0.4)" : "rgba(243, 244, 246, 0.5)"
    this.roundRect(ctx, tooltipX, tooltipY, tooltipWidth, headerHeight, 8, true, false)
    ctx.fill()

    ctx.fillStyle = secondaryTextColor
    ctx.font = "bold 12px Inter, system-ui, sans-serif"
    ctx.textAlign = "left"
    ctx.fillText(dateHeader, tooltipX + tooltipPadding, tooltipY + 18)

    ctx.strokeStyle = isDark ? "rgba(75, 85, 99, 0.5)" : "rgba(226, 232, 240, 0.8)"
    ctx.lineWidth = 1
    ctx.beginPath()
    ctx.moveTo(tooltipX + tooltipPadding, tooltipY + headerHeight)
    ctx.lineTo(tooltipX + tooltipWidth - tooltipPadding, tooltipY + headerHeight)
    ctx.stroke()

    let currentY = tooltipY + headerHeight + tooltipPadding + 16

    metrics.forEach(metric => {
      ctx.textAlign = "left"
      ctx.fillStyle = metric.color
      ctx.beginPath()
      ctx.arc(tooltipX + tooltipPadding + 6, currentY - 5, 5, 0, Math.PI * 2)
      ctx.fill()

      ctx.fillStyle = textColor
      ctx.font = "12px Inter, system-ui, sans-serif"
      ctx.fillText(metric.label, tooltipX + tooltipPadding + 18, currentY - 2)
      ctx.font = "600 13px Inter, system-ui, sans-serif"
      ctx.textAlign = "right"
      ctx.fillText(metric.value, tooltipX + tooltipWidth - tooltipPadding - 4, currentY - 2)

      currentY += lineHeight
    })

    ctx.textAlign = "left"
    ctx.fillStyle = secondaryTextColor
    ctx.font = "12px Inter, system-ui, sans-serif"
    ctx.fillText("CTR", tooltipX + tooltipPadding, currentY - 2)
    ctx.textAlign = "right"
    ctx.font = "600 13px Inter, system-ui, sans-serif"
    ctx.fillStyle = textColor
    ctx.fillText(ctr, tooltipX + tooltipWidth - tooltipPadding - 4, currentY - 2)

    currentY += lineHeight
    ctx.textAlign = "left"
    ctx.fillStyle = secondaryTextColor
    ctx.font = "12px Inter, system-ui, sans-serif"
    ctx.fillText("Avg Position", tooltipX + tooltipPadding, currentY - 2)
    ctx.textAlign = "right"
    ctx.font = "600 13px Inter, system-ui, sans-serif"
    ctx.fillStyle = textColor
    ctx.fillText(position, tooltipX + tooltipWidth - tooltipPadding - 4, currentY - 2)

    ctx.restore()
  }

  parseBoolean(value) {
    if (value === undefined) return true
    const normalized = String(value).toLowerCase()
    return !["false", "0", "off"].includes(normalized)
  }

  nicelyRoundedMax(value) {
    const safeValue = Number.isFinite(value) && value > 0 ? value : 1
    const exponent = Math.floor(Math.log10(safeValue))
    const magnitude = Math.pow(10, exponent)
    return Math.ceil(safeValue / magnitude) * magnitude
  }

  hexToRgba(hex, alpha) {
    const parsed = hex.replace("#", "")
    const bigint = parseInt(parsed, 16)
    const r = (bigint >> 16) & 255
    const g = (bigint >> 8) & 255
    const b = bigint & 255
    return `rgba(${r}, ${g}, ${b}, ${alpha})`
  }

  roundRect(ctx, x, y, width, height, radius, topOnly = false, bottomOnly = false) {
    ctx.beginPath()
    if (topOnly) {
      ctx.moveTo(x + radius, y)
      ctx.lineTo(x + width - radius, y)
      ctx.arcTo(x + width, y, x + width, y + radius, radius)
      ctx.lineTo(x + width, y + height)
      ctx.lineTo(x, y + height)
      ctx.lineTo(x, y + radius)
      ctx.arcTo(x, y, x + radius, y, radius)
    } else if (bottomOnly) {
      ctx.moveTo(x, y)
      ctx.lineTo(x + width, y)
      ctx.lineTo(x + width, y + height - radius)
      ctx.arcTo(x + width, y + height, x + width - radius, y + height, radius)
      ctx.lineTo(x + radius, y + height)
      ctx.arcTo(x, y + height, x, y + height - radius, radius)
      ctx.lineTo(x, y)
    } else {
      ctx.moveTo(x + radius, y)
      ctx.lineTo(x + width - radius, y)
      ctx.arcTo(x + width, y, x + width, y + radius, radius)
      ctx.lineTo(x + width, y + height - radius)
      ctx.arcTo(x + width, y + height, x + width - radius, y + height, radius)
      ctx.lineTo(x + radius, y + height)
      ctx.arcTo(x, y + height, x, y + height - radius, radius)
      ctx.lineTo(x, y + radius)
      ctx.arcTo(x, y, x + radius, y, radius)
    }
    ctx.closePath()
  }
}

export const PerformanceChartHook = {
  mounted() {
    this.controller = new PerformanceChartController(this)
    this.controller.mount()
  },
  updated() {
    this.controller?.update()
  },
  destroyed() {
    this.controller?.destroy()
  },
}

export default PerformanceChartHook
