const DEFAULT_LOCALE = (typeof navigator !== "undefined" && navigator.language) || "en-US"
const TIME_ZONE = "UTC"

export const createFormatterBundle = (locale = DEFAULT_LOCALE) => ({
  monthDay: new Intl.DateTimeFormat(locale, {month: "short", day: "numeric", timeZone: TIME_ZONE}),
  monthDayYear: new Intl.DateTimeFormat(locale, {
    month: "short",
    day: "numeric",
    year: "numeric",
    timeZone: TIME_ZONE,
  }),
  month: new Intl.DateTimeFormat(locale, {month: "short", timeZone: TIME_ZONE}),
  monthYear: new Intl.DateTimeFormat(locale, {month: "short", year: "numeric", timeZone: TIME_ZONE}),
  day: new Intl.DateTimeFormat(locale, {day: "numeric", timeZone: TIME_ZONE}),
})

export const safeParseDate = value => {
  if (!value) return null
  if (value instanceof Date) return value

  const parsed = new Date(value)
  return Number.isNaN(parsed.getTime()) ? null : parsed
}

export const formatMonthDay = (date, formatters, includeYear = false) => {
  if (!date) return ""
  const formatter = includeYear ? formatters.monthDayYear : formatters.monthDay
  return formatter.format(date).replace(/,/g, "")
}

export const formatMonth = (date, formatters) => {
  if (!date) return ""
  return formatters.month.format(date)
}

export const formatMonthYear = (date, formatters) => {
  if (!date) return ""
  return formatters.monthYear.format(date).replace(/,/g, "")
}

export const formatDay = (date, formatters) => {
  if (!date) return ""
  return formatters.day.format(date)
}

export const formatRangeLabel = (start, end, formatters, includeYear = false) => {
  if (!start || !end) return ""

  const startYear = start.getUTCFullYear()
  const endYear = end.getUTCFullYear()
  const sameYear = startYear === endYear
  const sameMonth = sameYear && start.getUTCMonth() === end.getUTCMonth()

  if (!sameYear) {
    const startLabel = formatMonthDay(start, formatters, true)
    const endLabel = formatMonthDay(end, formatters, true)
    return `${startLabel} - ${endLabel}`
  }

  if (sameMonth) {
    const prefix = formatMonth(start, formatters)
    const range = `${prefix} ${formatDay(start, formatters)}-${formatDay(end, formatters)}`
    return includeYear ? `${range}, ${startYear}` : range
  }

  const range = `${formatMonthDay(start, formatters)} - ${formatMonthDay(end, formatters)}`
  return includeYear ? `${range}, ${startYear}` : range
}

export const shouldShowYearForIndex = (date, index, series) => {
  if (!date || !Array.isArray(series) || series.length === 0) return false

  const prevDate =
    index > 0 ? safeParseDate(series[index - 1]?.date || series[index - 1]) : null
  const nextDate =
    index < series.length - 1 ? safeParseDate(series[index + 1]?.date || series[index + 1]) : null

  if (prevDate && prevDate.getUTCFullYear() !== date.getUTCFullYear()) return true
  if (nextDate && nextDate.getUTCFullYear() !== date.getUTCFullYear()) return true

  if (!prevDate || !nextDate) {
    const reference = prevDate || nextDate
    if (reference && reference.getUTCFullYear() !== date.getUTCFullYear()) return true
  }

  return false
}

const formatDailyLabel = (date, index, series, formatters) => {
  if (!date) return ""

  if (shouldShowYearForIndex(date, index, series)) {
    return formatMonthDay(date, formatters, true)
  }

  const prevDate =
    index > 0 ? safeParseDate(series[index - 1]?.date || series[index - 1]) : null
  const nextDate =
    index < series.length - 1 ? safeParseDate(series[index + 1]?.date || series[index + 1]) : null

  if (!prevDate || prevDate.getUTCMonth() !== date.getUTCMonth()) {
    return formatMonthDay(date, formatters)
  }

  if (!nextDate || nextDate.getUTCMonth() !== date.getUTCMonth()) {
    return formatMonthDay(date, formatters)
  }

  return formatDay(date, formatters)
}

export const formatMonthLabel = (date, index, series, formatters) => {
  if (!date) return ""

  if (shouldShowYearForIndex(date, index, series)) {
    return formatMonthYear(date, formatters)
  }

  return formatMonth(date, formatters)
}

export const formatTooltipHeading = (dataPoint, formatters) => {
  if (dataPoint.period_end && dataPoint.date !== dataPoint.period_end) {
    const start = safeParseDate(dataPoint.date)
    const end = safeParseDate(dataPoint.period_end)
    return formatRangeLabel(start, end, formatters, true)
  }

  const date = safeParseDate(dataPoint.date)
  return formatMonthDay(date, formatters, true)
}

export const formatNumber = value => {
  if (value >= 1_000_000) return `${Math.round(value / 10_000) / 100}M`
  if (value >= 1_000) return `${Math.round(value / 10) / 100}K`
  return Math.round(value).toString()
}

export const formatDateLabel = (dataPoint, index, series, formatters) => {
  try {
    if (dataPoint.period_end && dataPoint.date !== dataPoint.period_end) {
      const start = safeParseDate(dataPoint.date)
      const end = safeParseDate(dataPoint.period_end)
      const diffMs = end && start ? end - start : 0
      const diffDays = Math.round(diffMs / (1000 * 60 * 60 * 24))

      if (diffDays >= 28) {
        return formatMonthLabel(start, index, series, formatters)
      }

      return formatRangeLabel(
        start,
        end,
        formatters,
        shouldShowYearForIndex(start, index, series) ||
          (end && end.getUTCFullYear() !== start.getUTCFullYear()),
      )
    }

    const date = safeParseDate(dataPoint.date || dataPoint)
    return formatDailyLabel(date, index, series, formatters)
  } catch (_err) {
    return dataPoint.date || dataPoint
  }
}
