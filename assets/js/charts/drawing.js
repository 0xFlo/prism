/**
 * Canvas drawing utilities for chart rendering
 */

/**
 * Clear and prepare canvas for drawing
 */
export function clearCanvas(ctx, width, height) {
  ctx.clearRect(0, 0, width, height)
  ctx.save()
}

/**
 * Draw grid lines for the chart
 */
export function drawGrid(ctx, padding, width, height, tickCount = 5) {
  const plotWidth = width - padding.left - padding.right
  const plotHeight = height - padding.top - padding.bottom

  ctx.strokeStyle = "#e5e5e5"
  ctx.lineWidth = 1
  ctx.setLineDash([2, 2])

  // Horizontal grid lines
  for (let i = 0; i <= tickCount; i++) {
    const y = padding.top + (i * plotHeight) / tickCount
    ctx.beginPath()
    ctx.moveTo(padding.left, y)
    ctx.lineTo(padding.left + plotWidth, y)
    ctx.stroke()
  }

  ctx.setLineDash([])
}

/**
 * Draw axis lines
 */
export function drawAxisLines(ctx, padding, width, height) {
  const plotWidth = width - padding.left - padding.right
  const plotHeight = height - padding.top - padding.bottom

  ctx.strokeStyle = "#d4d4d4"
  ctx.lineWidth = 1

  // X axis
  ctx.beginPath()
  ctx.moveTo(padding.left, padding.top + plotHeight)
  ctx.lineTo(padding.left + plotWidth, padding.top + plotHeight)
  ctx.stroke()

  // Y axis
  ctx.beginPath()
  ctx.moveTo(padding.left, padding.top)
  ctx.lineTo(padding.left, padding.top + plotHeight)
  ctx.stroke()
}

/**
 * Draw a data line with gradient fill
 */
export function drawDataLine(ctx, points, color, plotBottom, alpha = 0.1) {
  if (!points || points.length === 0) return

  // Draw the line
  ctx.strokeStyle = color
  ctx.lineWidth = 2
  ctx.beginPath()
  points.forEach((point, index) => {
    if (index === 0) {
      ctx.moveTo(point.x, point.y)
    } else {
      ctx.lineTo(point.x, point.y)
    }
  })
  ctx.stroke()

  // Draw gradient fill
  ctx.beginPath()
  ctx.moveTo(points[0].x, plotBottom)
  points.forEach(point => {
    ctx.lineTo(point.x, point.y)
  })
  ctx.lineTo(points[points.length - 1].x, plotBottom)
  ctx.closePath()

  const gradient = ctx.createLinearGradient(0, 0, 0, plotBottom)
  gradient.addColorStop(0, hexToRgba(color, alpha))
  gradient.addColorStop(1, hexToRgba(color, 0))
  ctx.fillStyle = gradient
  ctx.fill()
}

/**
 * Draw vertical crosshair at x position
 */
export function drawCrosshair(ctx, x, padding, height, color = "#000", opacity = 0.2) {
  ctx.save()
  ctx.globalAlpha = opacity
  ctx.strokeStyle = color
  ctx.lineWidth = 1
  ctx.setLineDash([5, 5])

  ctx.beginPath()
  ctx.moveTo(x, padding.top)
  ctx.lineTo(x, height - padding.bottom)
  ctx.stroke()

  ctx.restore()
}

/**
 * Draw highlight circles on data points
 */
export function drawHighlightCircle(ctx, x, y, color, radius = 4) {
  // Outer circle (white background)
  ctx.fillStyle = "#ffffff"
  ctx.beginPath()
  ctx.arc(x, y, radius + 2, 0, Math.PI * 2)
  ctx.fill()

  // Inner circle (data color)
  ctx.fillStyle = color
  ctx.beginPath()
  ctx.arc(x, y, radius, 0, Math.PI * 2)
  ctx.fill()
}

/**
 * Draw event marker
 */
export function drawEventMarker(ctx, x, y, color = "#f97316") {
  const size = 6

  ctx.save()
  ctx.fillStyle = color
  ctx.strokeStyle = "#ffffff"
  ctx.lineWidth = 2

  // Draw diamond shape
  ctx.beginPath()
  ctx.moveTo(x, y - size)
  ctx.lineTo(x + size, y)
  ctx.lineTo(x, y + size)
  ctx.lineTo(x - size, y)
  ctx.closePath()

  ctx.fill()
  ctx.stroke()
  ctx.restore()
}

/**
 * Draw text with background
 */
export function drawTextWithBackground(ctx, text, x, y, options = {}) {
  const {
    font = "12px sans-serif",
    color = "#000000",
    bgColor = "#ffffff",
    padding = 4,
    borderRadius = 4
  } = options

  ctx.font = font
  const metrics = ctx.measureText(text)
  const textWidth = metrics.width
  const textHeight = 14 // Approximate height

  // Draw background
  ctx.fillStyle = bgColor
  roundRect(
    ctx,
    x - textWidth / 2 - padding,
    y - textHeight / 2 - padding,
    textWidth + padding * 2,
    textHeight + padding * 2,
    borderRadius
  )
  ctx.fill()

  // Draw text
  ctx.fillStyle = color
  ctx.textAlign = "center"
  ctx.textBaseline = "middle"
  ctx.fillText(text, x, y)
}

/**
 * Draw rounded rectangle
 */
export function roundRect(ctx, x, y, width, height, radius) {
  ctx.beginPath()
  ctx.moveTo(x + radius, y)
  ctx.lineTo(x + width - radius, y)
  ctx.quadraticCurveTo(x + width, y, x + width, y + radius)
  ctx.lineTo(x + width, y + height - radius)
  ctx.quadraticCurveTo(x + width, y + height, x + width - radius, y + height)
  ctx.lineTo(x + radius, y + height)
  ctx.quadraticCurveTo(x, y + height, x, y + height - radius)
  ctx.lineTo(x, y + radius)
  ctx.quadraticCurveTo(x, y, x + radius, y)
  ctx.closePath()
}

/**
 * Convert hex color to rgba
 */
function hexToRgba(hex, alpha) {
  const parsed = hex.replace('#', '')
  const bigint = parseInt(parsed, 16)
  const r = (bigint >> 16) & 255
  const g = (bigint >> 8) & 255
  const b = bigint & 255
  return `rgba(${r}, ${g}, ${b}, ${alpha})`
}