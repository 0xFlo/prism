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
  findNearestDataIndex,
  calculateMaxValues
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
    this.xLabel = this.el.dataset.xLabel || "Date"
    this.drawChart()
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

    const padding = {top: 20, right: 48, bottom: 75, left: 64}
    const plotWidth = width - padding.left - padding.right
    const plotHeight = height - padding.top - padding.bottom
    const plotBottom = padding.top + plotHeight

    const clicks = series.map(point => Number(point.clicks) || 0)
    const impressions = series.map(point => Number(point.impressions) || 0)

    const maxClicks = this.nicelyRoundedMax(Math.max(...clicks))
    const maxImpressions = this.nicelyRoundedMax(Math.max(...impressions))

    this.cachedPadding = padding
    this.cachedMaxClicks = maxClicks
    this.cachedMaxImpressions = maxImpressions

    const xForIndex = index => {
      if (series.length === 1) {
        return padding.left + plotWidth / 2
      }
      const ratio = index / (series.length - 1)
      return padding.left + ratio * plotWidth
    }

    const yForClicks = value => padding.top + (1 - value / maxClicks) * plotHeight
    const yForImpressions = value =>
      padding.top + (1 - value / maxImpressions) * plotHeight

    this.drawAxes(width, height, padding, series, maxClicks, maxImpressions)
    this.drawLine(clicks, "#6366f1", xForIndex, yForClicks, padding, plotBottom)
    this.drawLine(
      impressions,
      "#10b981",
      xForIndex,
      yForImpressions,
      padding,
      plotBottom,
    )
    this.drawLegend(width, padding, [
      ["Clicks", "#6366f1"],
      ["Impressions", "#10b981"],
    ])
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

  drawAxes(width, height, padding, series, maxClicks, maxImpressions) {
    const ctx = this.ctx
    ctx.strokeStyle = "#d1d5db"
    ctx.lineWidth = 1

    ctx.beginPath()
    ctx.moveTo(padding.left, padding.top)
    ctx.lineTo(padding.left, height - padding.bottom)
    ctx.lineTo(width - padding.right, height - padding.bottom)
    ctx.stroke()

    ctx.fillStyle = "#6b7280"
    ctx.font = "12px Inter, system-ui, sans-serif"
    ctx.textAlign = "center"
    ctx.fillText(
      this.xLabel,
      padding.left + (width - padding.left - padding.right) / 2,
      height - padding.bottom + 60,
    )

    this.drawYAxisTicks(padding.left, padding, height, maxClicks, "#6366f1", "Clicks")
    this.drawYAxisTicks(
      width - padding.right,
      padding,
      height,
      maxImpressions,
      "#10b981",
      "Impressions",
      true,
    )

    const ctxWidth = width - padding.left - padding.right
    const tickIndices = buildTickIndices(series.length, ctxWidth)
    const stagger = shouldStaggerLabels(tickIndices.length, ctxWidth)

    tickIndices.forEach((index, order) => {
      const dataPoint = series[index]
      const label = formatDateLabel(dataPoint, index, series, this.formatters)
      const x =
        series.length === 1
          ? padding.left + ctxWidth / 2
          : padding.left + (index / (series.length - 1)) * ctxWidth

      const baseY = height - padding.bottom + 26
      const yOffset = stagger && order % 2 === 1 ? 18 : 0

      ctx.save()
      ctx.translate(x, baseY + yOffset)
      ctx.rotate(-Math.PI / 6)
      ctx.fillText(label, 0, 0)
      ctx.restore()
    })

    ctx.strokeStyle = "rgba(203, 213, 225, 0.5)"
    ctx.setLineDash([2, 3])
    ctx.lineWidth = 1

    const gridLines = 4
    for (let i = 1; i <= gridLines; i++) {
      const y = padding.top + (i / (gridLines + 1)) * (height - padding.top - padding.bottom)
      ctx.beginPath()
      ctx.moveTo(padding.left, y)
      ctx.lineTo(width - padding.right, y)
      ctx.stroke()
    }

    ctx.setLineDash([])
    ctx.lineWidth = 1
  }

  drawYAxisTicks(axisX, padding, height, maxValue, color, label, alignRight = false) {
    const ctx = this.ctx
    ctx.fillStyle = color
    ctx.strokeStyle = color
    ctx.lineWidth = 1
    ctx.textAlign = alignRight ? "right" : "left"
    ctx.font = "12px Inter, system-ui, sans-serif"

    const ticks = 4
    for (let i = 0; i <= ticks; i++) {
      const value = (i / ticks) * maxValue
      const y = padding.top + (1 - i / ticks) * (height - padding.top - padding.bottom)
      ctx.beginPath()
      const length = 6
      const dir = alignRight ? -1 : 1
      ctx.moveTo(axisX, y)
      ctx.lineTo(axisX + dir * length, y)
      ctx.stroke()
      ctx.fillText(formatNumber(value), axisX + dir * (length + 4), y + 4)
    }

    ctx.save()
    ctx.font = "bold 12px Inter, system-ui, sans-serif"
    ctx.textAlign = alignRight ? "right" : "left"
    ctx.fillText(label, alignRight ? axisX - 10 : axisX + 10, padding.top - 6)
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
    const clicks = Number(dataPoint.clicks) || 0
    const impressions = Number(dataPoint.impressions) || 0

    const maxClicks = this.cachedMaxClicks
    const maxImpressions = this.cachedMaxImpressions
    const plotHeight = height - padding.top - padding.bottom

    const yClicks = padding.top + (1 - clicks / maxClicks) * plotHeight
    const yImpressions = padding.top + (1 - impressions / maxImpressions) * plotHeight

    ctx.save()
    ctx.globalAlpha = opacity
    ctx.fillStyle = this.hexToRgba("#6366f1", 0.2)
    ctx.beginPath()
    ctx.arc(xPos, yClicks, 10, 0, Math.PI * 2)
    ctx.fill()
    ctx.fillStyle = "#6366f1"
    ctx.strokeStyle = "#ffffff"
    ctx.lineWidth = 2.5
    ctx.beginPath()
    ctx.arc(xPos, yClicks, 7, 0, Math.PI * 2)
    ctx.fill()
    ctx.stroke()
    ctx.restore()

    ctx.save()
    ctx.globalAlpha = opacity
    ctx.fillStyle = this.hexToRgba("#10b981", 0.2)
    ctx.beginPath()
    ctx.arc(xPos, yImpressions, 10, 0, Math.PI * 2)
    ctx.fill()
    ctx.fillStyle = "#10b981"
    ctx.strokeStyle = "#ffffff"
    ctx.lineWidth = 2.5
    ctx.beginPath()
    ctx.arc(xPos, yImpressions, 7, 0, Math.PI * 2)
    ctx.fill()
    ctx.stroke()
    ctx.restore()
  }

  drawTooltip(dataPoint, chartX, mouseY, opacity = 1) {
    const ctx = this.ctx
    const width = this.el.clientWidth || 640

    const dateHeader = formatTooltipHeading(dataPoint, this.formatters)
    const clicks = formatNumber(dataPoint.clicks || 0)
    const impressions = formatNumber(dataPoint.impressions || 0)
    const ctr = `${((dataPoint.ctr || 0) * 100).toFixed(2)}%`
    const position = (dataPoint.position || 0).toFixed(1)

    const tooltipPadding = 14
    const lineHeight = 24
    const headerHeight = 28
    const tooltipWidth = 230
    const tooltipHeight = headerHeight + lineHeight * 4 + tooltipPadding * 2 + 4

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

    ctx.fillStyle = "#6366f1"
    ctx.beginPath()
    ctx.arc(tooltipX + tooltipPadding + 6, currentY - 5, 5, 0, Math.PI * 2)
    ctx.fill()

    ctx.fillStyle = textColor
    ctx.font = "12px Inter, system-ui, sans-serif"
    ctx.fillText("Clicks", tooltipX + tooltipPadding + 18, currentY - 2)
    ctx.font = "600 13px Inter, system-ui, sans-serif"
    ctx.fillText(clicks, tooltipX + tooltipWidth - tooltipPadding - 4, currentY - 2)
    ctx.textAlign = "right"

    currentY += lineHeight

    ctx.textAlign = "left"
    ctx.fillStyle = "#10b981"
    ctx.beginPath()
    ctx.arc(tooltipX + tooltipPadding + 6, currentY - 5, 5, 0, Math.PI * 2)
    ctx.fill()

    ctx.fillStyle = textColor
    ctx.font = "12px Inter, system-ui, sans-serif"
    ctx.fillText("Impressions", tooltipX + tooltipPadding + 18, currentY - 2)
    ctx.font = "600 13px Inter, system-ui, sans-serif"
    ctx.textAlign = "right"
    ctx.fillText(impressions, tooltipX + tooltipWidth - tooltipPadding - 4, currentY - 2)

    currentY += lineHeight
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
