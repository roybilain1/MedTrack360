export const SETTINGS_TABS = [
  { id: 'terminals', label: 'POS Terminals' },
  { id: 'pricing', label: 'Pricing Policy' },
  { id: 'adjustments', label: 'Stock Adjustment' },
]

export function freshnessForTerminal(node, now = Date.now()) {
  const source = node?.last_sync_up || node?.last_seen
  if (!source) return { label: 'Never synced', color: 'slate' }

  const dt = new Date(source)
  if (Number.isNaN(dt.getTime())) return { label: 'Unknown freshness', color: 'slate' }

  const minutes = Math.floor((now - dt.getTime()) / 60000)
  if (minutes <= 15) return { label: 'Fresh', color: 'emerald' }
  if (minutes <= 60) return { label: 'Delayed', color: 'amber' }
  return { label: 'Stale', color: 'red' }
}

export function computeTerminalSummary(terminals = [], apiSummary = {}) {
  const list = Array.isArray(terminals) ? terminals : []
  return {
    total_terminals: apiSummary.total_terminals ?? list.length,
    online_count: apiSummary.online_count ?? list.filter((t) => t?.status === 'online').length,
    offline_count: apiSummary.offline_count ?? list.filter((t) => t?.status === 'offline').length,
    degraded_count: apiSummary.degraded_count ?? list.filter((t) => t?.status === 'degraded').length,
    version_mismatch_count: apiSummary.version_mismatch_count ?? 0,
    never_synced_count: apiSummary.never_synced_count ?? list.filter((t) => !t?.last_sync_up && !t?.last_sync_down).length,
    expected_sync_version: apiSummary.expected_sync_version || null,
  }
}
