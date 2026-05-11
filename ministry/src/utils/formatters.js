function isBlank(value) {
  return value == null || (typeof value === 'string' && value.trim() === '')
}

export function coerceString(value, fallback = '') {
  if (isBlank(value)) return fallback
  return String(value)
}

export function coerceNumber(value, fallback = 0) {
  if (isBlank(value)) return fallback
  const parsed = Number(value)
  return Number.isFinite(parsed) ? parsed : fallback
}

export function coerceBoolean(value, fallback = false) {
  if (typeof value === 'boolean') return value
  if (typeof value === 'number') return value !== 0
  if (typeof value === 'string') {
    const normalized = value.trim().toLowerCase()
    if (!normalized) return fallback
    if (['true', '1', 'yes', 'y', 'on'].includes(normalized)) return true
    if (['false', '0', 'no', 'n', 'off'].includes(normalized)) return false
  }
  return fallback
}

export function coerceDate(value) {
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? null : value
  if (isBlank(value)) return null

  if (typeof value === 'number') {
    const date = new Date(value)
    return Number.isNaN(date.getTime()) ? null : date
  }

  if (typeof value === 'string') {
    const trimmed = value.trim()
    const parsedNumber = Number(trimmed)
    if (trimmed && Number.isFinite(parsedNumber) && String(parsedNumber) === trimmed) {
      const date = new Date(parsedNumber)
      return Number.isNaN(date.getTime()) ? null : date
    }

    const date = new Date(trimmed)
    return Number.isNaN(date.getTime()) ? null : date
  }

  return null
}

export function normalizeCurrencyMinor(value, fallback = '-') {
  const parsed = coerceNumber(value, Number.NaN)
  return Number.isFinite(parsed) ? (parsed / 100).toFixed(2) : fallback
}

export function formatQuantity(value, { fallback = '-', locale = 'en-US' } = {}) {
  const parsed = coerceNumber(value, Number.NaN)
  if (!Number.isFinite(parsed)) return fallback
  return new Intl.NumberFormat(locale, { maximumFractionDigits: 0 }).format(Math.trunc(parsed))
}

export function formatDecimal(value, { fallback = '-', fractionDigits = 1, locale = 'en-US' } = {}) {
  const parsed = coerceNumber(value, Number.NaN)
  if (!Number.isFinite(parsed)) return fallback
  return new Intl.NumberFormat(locale, {
    minimumFractionDigits: fractionDigits,
    maximumFractionDigits: fractionDigits,
  }).format(parsed)
}

export function formatPercent(value, { fallback = '-', fractionDigits = 1 } = {}) {
  const parsed = coerceNumber(value, Number.NaN)
  if (!Number.isFinite(parsed)) return fallback
  const asPercent = Math.abs(parsed) <= 1 ? parsed * 100 : parsed
  return `${asPercent.toFixed(fractionDigits)}%`
}

export function formatTimestamp(value, { fallback = '-' } = {}) {
  const date = coerceDate(value)
  return date ? date.toLocaleString() : fallback
}

export function formatDate(value, { fallback = '-' } = {}) {
  const date = coerceDate(value)
  return date ? date.toLocaleDateString() : fallback
}

const STATUS_LABELS = {
  healthy: 'Healthy',
  normal: 'Normal',
  open: 'Open',
  closed: 'Closed',
  high_price: 'High Price',
  high_markup: 'High Markup',
  out_of_stock: 'Out of Stock',
  low_stock: 'Low Stock',
  overdue_sync: 'Overdue Sync',
  queue_backlog: 'Queue Backlog',
  hoarding_watch: 'Hoarding Watch',
  never_synced: 'Never Synced',
  offline: 'Offline',
  syncing: 'Syncing',
  warning: 'Warning',
  critical: 'Critical',
  low: 'Low',
  watch: 'Watch',
  safe: 'Healthy',
  unknown: 'Unknown',
}

const STATUS_BADGES = {
  healthy: 'bg-emerald-100 text-emerald-700 border-emerald-200',
  normal: 'bg-slate-100 text-slate-700 border-slate-200',
  open: 'bg-indigo-100 text-indigo-700 border-indigo-200',
  closed: 'bg-slate-100 text-slate-600 border-slate-200',
  high_price: 'bg-red-100 text-red-700 border-red-200',
  high_markup: 'bg-rose-100 text-rose-700 border-rose-200',
  out_of_stock: 'bg-red-100 text-red-700 border-red-200',
  low_stock: 'bg-amber-100 text-amber-700 border-amber-200',
  overdue_sync: 'bg-orange-100 text-orange-700 border-orange-200',
  queue_backlog: 'bg-fuchsia-100 text-fuchsia-700 border-fuchsia-200',
  hoarding_watch: 'bg-yellow-100 text-yellow-700 border-yellow-200',
  never_synced: 'bg-slate-100 text-slate-700 border-slate-200',
  offline: 'bg-red-100 text-red-700 border-red-200',
  syncing: 'bg-cyan-100 text-cyan-700 border-cyan-200',
  warning: 'bg-amber-100 text-amber-700 border-amber-200',
  critical: 'bg-red-100 text-red-700 border-red-200',
  low: 'bg-amber-100 text-amber-700 border-amber-200',
  watch: 'bg-sky-100 text-sky-700 border-sky-200',
  safe: 'bg-emerald-100 text-emerald-700 border-emerald-200',
  unknown: 'bg-slate-100 text-slate-700 border-slate-200',
}

export function normalizeStatus(value, fallback = 'unknown') {
  const status = coerceString(value).trim().toLowerCase().replace(/\s+/g, '_')
  return status || fallback
}

export function statusLabel(value) {
  const status = normalizeStatus(value)
  return STATUS_LABELS[status] || value || 'N/A'
}

export function statusBadgeClass(value) {
  const status = normalizeStatus(value)
  return STATUS_BADGES[status] || 'bg-slate-100 text-slate-700 border-slate-200'
}
