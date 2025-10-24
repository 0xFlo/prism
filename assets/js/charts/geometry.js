/**
 * Geometry calculations for chart positioning and scaling
 */

/**
 * Calculate default padding for chart area
 */
export function getDefaultPadding() {
  return { top: 20, right: 48, bottom: 75, left: 64 }
}

/**
 * Calculate plot dimensions from canvas size and padding
 */
export function calculatePlotDimensions(width, height, padding) {
  return {
    plotWidth: width - padding.left - padding.right,
    plotHeight: height - padding.top - padding.bottom,
    plotBottom: padding.top + (height - padding.top - padding.bottom)
  }
}

/**
 * Create X coordinate calculator for data point index
 */
export function createXScaler(seriesLength, plotWidth, paddingLeft) {
  return index => {
    if (seriesLength === 1) {
      return paddingLeft + plotWidth / 2
    }
    const ratio = index / (seriesLength - 1)
    return paddingLeft + ratio * plotWidth
  }
}

/**
 * Create Y coordinate calculator for values
 */
export function createYScaler(maxValue, plotHeight, paddingTop) {
  return value => paddingTop + (1 - value / maxValue) * plotHeight
}

/**
 * Find the nearest data point index to mouse position
 */
export function findNearestDataIndex(mouseX, series, padding, plotWidth) {
  if (!series || series.length === 0) return null

  if (series.length === 1) return 0

  let minDistance = Infinity
  let nearestIndex = 0

  for (let i = 0; i < series.length; i++) {
    const ratio = i / (series.length - 1)
    const x = padding.left + ratio * plotWidth
    const distance = Math.abs(x - mouseX)

    if (distance < minDistance) {
      minDistance = distance
      nearestIndex = i
    }
  }

  return minDistance < 20 ? nearestIndex : null
}

/**
 * Calculate maximum values from series data
 */
export function calculateMaxValues(series) {
  if (!series || series.length === 0) {
    return { maxClicks: 1, maxImpressions: 1 }
  }

  const maxClicks = Math.max(1, ...series.map(d => d.clicks || 0))
  const maxImpressions = Math.max(1, ...series.map(d => d.impressions || 0))

  return { maxClicks, maxImpressions }
}

/**
 * Check if point is within chart area
 */
export function isPointInChartArea(x, y, padding, width, height) {
  return (
    x >= padding.left &&
    x <= width - padding.right &&
    y >= padding.top &&
    y <= height - padding.bottom
  )
}