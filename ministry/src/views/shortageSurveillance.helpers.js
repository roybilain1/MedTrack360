export function resolvePharmacyName(row) {
  if (row?.pharmacy_name) return row.pharmacy_name
  if (row?.license_number || row?.hwid) return 'Unassigned source'
  return 'No linked pharmacy'
}

export function resolveRegionName(row) {
  return row?.region || 'Region not reported'
}

export function resolveLastSyncLabel(row) {
  if (row?.last_sync_up) {
    const dt = new Date(row.last_sync_up)
    if (!Number.isNaN(dt.getTime())) {
      return dt.toISOString().slice(0, 16).replace('T', ' ')
    }
  }

  if (row?.last_sync_down) {
    const dt = new Date(row.last_sync_down)
    if (!Number.isNaN(dt.getTime())) {
      return `${dt.toISOString().slice(0, 16).replace('T', ' ')} (down)`
    }
  }

  if (row?.last_movement_at) {
    const dt = new Date(row.last_movement_at)
    if (!Number.isNaN(dt.getTime())) {
      return `${dt.toISOString().slice(0, 16).replace('T', ' ')} (movement)`
    }
  }

  return 'Never synced'
}

export function buildScopeSubtitle({ rows, refreshLabel }) {
  const meds = Array.isArray(rows) ? rows : []
  const pharmacies = new Set(
    meds
      .map((row) => row.pharmacy)
      .filter((name) => name && name !== 'No linked pharmacy' && name !== 'Unassigned source')
  )
  const pharmacyCount = pharmacies.size

  if (pharmacyCount <= 1) {
    return `Stock risk from synchronized POS inventory movements. Current visible scope: ${pharmacyCount} active pharmacy in this dataset. Refreshed ${refreshLabel}.`
  }
  return `Stock risk from synchronized POS inventory movements across ${pharmacyCount} active pharmacies in this dataset. Refreshed ${refreshLabel}.`
}

export function buildScopedSubtitle({ scopeLabel, activePharmacies, registeredNodes, refreshLabel }) {
  const scope = String(scopeLabel || '').trim()
  if (scope) {
    if (Number.isFinite(Number(registeredNodes)) && Number(registeredNodes) > 0) {
      return `${scope} (${Number(registeredNodes)} registered nodes). Refreshed ${refreshLabel}.`
    }
    return `${scope}. Refreshed ${refreshLabel}.`
  }

  const active = Number.isFinite(Number(activePharmacies)) ? Number(activePharmacies) : 0
  const registered = Number.isFinite(Number(registeredNodes)) ? Number(registeredNodes) : 0

  if (active <= 1) {
    const registeredLabel = registered > 0 ? ` out of ${registered} registered nodes` : ''
    return `Current stock risk view based on the latest synchronized inventory from ${active} active pharmacy${registeredLabel}. Refreshed ${refreshLabel}.`
  }

  const registeredLabel = registered > 0 ? ` (${registered} registered nodes)` : ''
  return `Live branch risk view derived from latest synchronized inventory across ${active} active pharmacies${registeredLabel}. Refreshed ${refreshLabel}.`
}

export function resolveThresholdSource(row) {
  const configured = Number(row?.configured_threshold)
  const threshold = Number(row?.threshold_units)

  if (Number.isFinite(configured) && configured > 0) return 'Configured threshold'
  if (Number.isFinite(threshold) && threshold > 0) return 'Derived 14-day floor'
  return 'No threshold baseline'
}

export function resolveCoverageLabel(row) {
  const basis = String(row?.coverage_basis || 'unknown')
  if (basis === 'out_of_stock') return '0 d (out of stock)'
  if (basis === 'no_demand_history') return 'No demand history'
  const days = Number(row?.daysOfStock)
  if (Number.isFinite(days) && days >= 0) return `${days.toFixed(1)} d`
  return 'Coverage unavailable'
}

export function normalizeStatus(status) {
  if (status === 'critical' || status === 'low' || status === 'safe' || status === 'watch' || status === 'unknown') {
    return status
  }
  return 'unknown'
}

export function buildCoverageSnapshot(rows) {
  const meds = Array.isArray(rows) ? rows : []
  return [...meds]
    .filter((row) => Number.isFinite(Number(row.daysOfStock)) && Number(row.daysOfStock) >= 0)
    .sort((a, b) => Number(a.daysOfStock) - Number(b.daysOfStock) || Number(b.stock || 0) - Number(a.stock || 0))
    .slice(0, 12)
    .map((row) => ({
      label: String(row.name || row.barcode || 'Unknown').slice(0, 20),
      daysOfStock: Number(Number(row.daysOfStock).toFixed(1)),
      threshold: Number(row.threshold || 0),
      stock: Number(row.stock || 0),
      status: normalizeStatus(row.status),
      pharmacy: String(row.pharmacy || 'Unknown pharmacy'),
    }))
}
