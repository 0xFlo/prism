export const getOptimalLabelCount = (availableWidth, totalPoints) => {
  if (totalPoints <= 0) return 0
  if (totalPoints === 1) return 1
  if (!Number.isFinite(availableWidth) || availableWidth <= 0) {
    return Math.min(2, totalPoints)
  }

  const targetSpacing = 90
  const maxLabels = Math.max(2, Math.floor(availableWidth / targetSpacing))
  return Math.min(maxLabels, totalPoints)
}

export const shouldStaggerLabels = (labelCount, availableWidth) => {
  if (labelCount <= 1 || !Number.isFinite(availableWidth) || availableWidth <= 0) return false
  const approxSpacing = availableWidth / labelCount
  return approxSpacing < 80
}

export const buildTickIndices = (totalPoints, availableWidth) => {
  if (!Number.isFinite(totalPoints) || totalPoints <= 0) return []
  if (totalPoints === 1) return [0]

  const maxLabels = getOptimalLabelCount(availableWidth, totalPoints)

  if (maxLabels >= totalPoints) {
    return Array.from({length: totalPoints}, (_value, index) => index)
  }

  const indices = new Set([0, totalPoints - 1])
  const step = Math.max(1, Math.round(totalPoints / maxLabels))

  for (let i = 0; i < totalPoints; i += step) {
    indices.add(i)
  }

  return Array.from(indices).sort((a, b) => a - b)
}
