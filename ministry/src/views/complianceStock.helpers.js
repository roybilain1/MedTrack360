import { formatDecimal } from '../utils/formatters.js'

export function formatDaysOfStock(value, coverageBasis) {
  const days = Number(value)
  if (value == null || !Number.isFinite(days)) {
    if (coverageBasis === 'no_demand_history') return 'No demand history'
    return '—'
  }
  if (days >= 3650) return '3650+ d'
  return `${formatDecimal(days, { fractionDigits: 1 })} d`
}

export function coverageTooltip(row) {
  const basis = String(row?.coverage_basis || 'unknown')
  if (basis === 'out_of_stock') return 'Coverage unavailable because stock is zero.'
  if (basis === 'recent_sales_min_rate') return 'Coverage from 30-day sales with minimum daily rate guardrail.'
  if (basis === 'recent_sales_30d') return 'Coverage = current units / average daily units sold over 30 days.'
  return 'No recent demand history; coverage is not computed as zero.'
}

export function statusTooltip(row) {
  if (row?.status_basis) {
    return `Status basis: ${String(row.status_basis).replaceAll('_', ' ')}`
  }
  return 'Status is derived from threshold and coverage rules.'
}

export function formatExpiryLabel(value) {
  if (!value) return 'No expiry'
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return 'No expiry'
  return date.toLocaleDateString('en-US', { month: 'short', year: 'numeric' })
}

export function stockStateLabel(row) {
  const stockUnits = Number(row?.stock_units)
  const status = String(row?.status || '').toLowerCase()

  if (Number.isFinite(stockUnits) && stockUnits <= 0) return 'Out of Stock'
  if (status === 'critical') return 'Low'
  if (status === 'low') return 'Low'
  if (status === 'watch') return 'Watch'
  if (row?.stock_state_label) return String(row.stock_state_label)
  return 'In Stock'
}

export function stockStateClasses(row) {
  const status = String(row?.status || '').toLowerCase()
  const stockUnits = Number(row?.stock_units)

  if (Number.isFinite(stockUnits) && stockUnits <= 0) {
    return 'border-red-200 bg-red-50 text-red-700'
  }
  if (status === 'critical') {
    return 'border-red-200 bg-red-50 text-red-700'
  }
  if (status === 'low' || status === 'watch') {
    return 'border-amber-200 bg-amber-50 text-amber-700'
  }
  return 'border-emerald-200 bg-emerald-50 text-emerald-700'
}

export function buildStockScopeSubtitle({ activeView, scope, rows, overview }) {
  if (activeView !== 'stock') {
    return 'Government monitoring console for pricing, hoarding, sync health, and pharmacy audit signals.'
  }

  const scopeLabel = String(scope?.scope_label || '').trim()
  if (scopeLabel) return scopeLabel

  const pharmacies = new Set((rows || []).map((row) => row?.pharmacy_name).filter(Boolean))
  const activePharmacies = pharmacies.size

  if (activePharmacies <= 1) {
    return 'Current stock risk view based on the latest synchronized inventory from 1 active pharmacy'
  }

  const totalNodes = Number(overview?.total_pharmacies)
  if (Number.isFinite(totalNodes) && totalNodes > 0) {
    return `Live branch risk view derived from latest synced POS inventory across ${activePharmacies} active pharmacies (${totalNodes} registered nodes)`
  }

  return `Live branch risk view derived from latest synced POS inventory across ${activePharmacies} active pharmacies`
}
