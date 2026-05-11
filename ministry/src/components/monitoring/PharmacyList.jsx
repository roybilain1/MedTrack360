import { ChevronRight, AlertTriangle, TrendingDown } from 'lucide-react'
import { statusBadgeClass, statusLabel } from '../../utils/formatters'

/**
 * Derives a risk badge (critical/low/safe) from counts
 */
function getRiskBadge(criticalCount, lowCount) {
  if (criticalCount > 0) return 'critical'
  if (lowCount > 0) return 'low'
  return 'safe'
}

/**
 * Groups stock rows by pharmacy and derives summary metrics
 */
function derivePharmacySummaries(stockRows = []) {
  if (!Array.isArray(stockRows) || stockRows.length === 0) {
    return []
  }

  const byPharmacy = {}

  stockRows.forEach((row) => {
    const key = row.pharmacy_id || `${row.pharmacy_name}_${row.license_number}`
    if (!byPharmacy[key]) {
      byPharmacy[key] = {
        pharmacy_id: row.pharmacy_id,
        pharmacy_name: row.pharmacy_name || 'Unknown pharmacy',
        license_number: row.license_number || 'No license',
        region: row.region || 'Unknown',
        hwid: row.hwid || 'Unknown',
        medicines: [],
        statuses: { critical: 0, low: 0, safe: 0, watch: 0, unknown: 0 },
        lastSyncUp: row.last_sync_up,
        lastSyncDown: row.last_sync_down,
      }
    }

    byPharmacy[key].medicines.push(row)

    // Count statuses
    const status = row.status || 'unknown'
    if (byPharmacy[key].statuses[status] !== undefined) {
      byPharmacy[key].statuses[status] += 1
    }
  })

  // Convert to array and compute additional summaries
  return Object.values(byPharmacy).map((pharmacy) => {
    const totalMedicines = pharmacy.medicines.length
    const { critical, low } = pharmacy.statuses
    const riskBadge = getRiskBadge(critical, low)

    // Find most recent sync time
    const syncTimes = [
      pharmacy.lastSyncUp ? new Date(pharmacy.lastSyncUp).getTime() : 0,
      pharmacy.lastSyncDown ? new Date(pharmacy.lastSyncDown).getTime() : 0,
    ].filter((t) => t > 0)
    const lastSync = syncTimes.length > 0 ? new Date(Math.max(...syncTimes)) : null

    return {
      ...pharmacy,
      total_medicines: totalMedicines,
      critical_count: critical,
      low_count: low,
      safe_count: pharmacy.statuses.safe,
      risk_badge: riskBadge,
      last_sync: lastSync ? lastSync.toISOString() : null,
    }
  })
}

/**
 * Formats time difference for "last sync" display
 */
function formatTimeDiff(isoString) {
  if (!isoString) return 'Never'
  const date = new Date(isoString)
  if (Number.isNaN(date.getTime())) return 'Unknown'

  const now = new Date()
  const diffMs = now.getTime() - date.getTime()
  const diffMins = Math.floor(diffMs / 60000)
  const diffHours = Math.floor(diffMs / 3600000)
  const diffDays = Math.floor(diffMs / 86400000)

  if (diffMins < 1) return 'Just now'
  if (diffMins < 60) return `${diffMins}m ago`
  if (diffHours < 24) return `${diffHours}h ago`
  if (diffDays < 30) return `${diffDays}d ago`
  return date.toLocaleDateString()
}

function statusBadge(badge) {
  const cls = statusBadgeClass(badge)
  const label = statusLabel(badge)
  return (
    <span className={`px-2 py-0.5 rounded-full border text-[10px] font-semibold ${cls}`}>
      {label || String(badge || '—')}
    </span>
  )
}

export default function PharmacyList({
  stockRows = [],
  selectedPharmacyId = null,
  onSelectPharmacy = () => {},
  regionFilter = '',
  loading = false,
}) {
  const summaries = derivePharmacySummaries(stockRows)

  // Apply region filter
  const filtered = summaries.filter((p) => {
    if (!regionFilter || regionFilter === '') return true
    return p.region.toLowerCase().includes(regionFilter.toLowerCase())
  })

  const isEmpty = filtered.length === 0

  return (
    <div className="bg-white border border-slate-200 rounded-lg shadow-sm overflow-hidden">
      <div className="px-4 py-3 border-b border-slate-100 bg-slate-50">
        <h3 className="text-sm font-semibold text-slate-800">Pharmacies</h3>
        <p className="text-xs text-slate-500 mt-1">
          {filtered.length} pharmacy{filtered.length === 1 ? '' : 'ies'} {regionFilter ? `in region "${regionFilter}"` : ''}
        </p>
      </div>

      {loading ? (
        <div className="flex flex-col items-center justify-center py-12">
          <div className="w-6 h-6 rounded-full border-2 border-slate-300 border-t-teal-600 animate-spin mb-3" />
          <p className="text-sm text-slate-500">Loading pharmacies…</p>
        </div>
      ) : isEmpty ? (
        <div className="flex flex-col items-center justify-center py-12 text-slate-500">
          <p className="text-sm font-medium">No pharmacies found</p>
          <p className="text-xs mt-1">Try adjusting your region filter</p>
        </div>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-xs">
            <thead>
              <tr className="bg-slate-100 border-b border-slate-200">
                <th className="text-left px-4 py-2.5 font-semibold text-slate-700 whitespace-nowrap">Pharmacy</th>
                <th className="text-left px-4 py-2.5 font-semibold text-slate-700 whitespace-nowrap">Region</th>
                <th className="text-left px-4 py-2.5 font-semibold text-slate-700 whitespace-nowrap">Medicines</th>
                <th className="text-left px-4 py-2.5 font-semibold text-slate-700 whitespace-nowrap">Risk</th>
                <th className="text-left px-4 py-2.5 font-semibold text-slate-700 whitespace-nowrap">Last Sync</th>
              </tr>
            </thead>
            <tbody>
              {filtered.map((pharmacy) => {
                const isSelected = selectedPharmacyId === pharmacy.pharmacy_id
                return (
                  <tr
                    key={pharmacy.pharmacy_id}
                    onClick={() => onSelectPharmacy(pharmacy.pharmacy_id)}
                    className={`border-b border-slate-100 cursor-pointer transition-colors ${
                      isSelected
                        ? 'bg-teal-50 hover:bg-teal-100'
                        : 'hover:bg-slate-50'
                    }`}
                  >
                    <td className="px-4 py-3 align-top">
                      <div className="flex items-start gap-2">
                        <div className="flex-1">
                          <div className="font-medium text-slate-800">{pharmacy.pharmacy_name}</div>
                          <div className="text-[10px] text-slate-500">
                            {pharmacy.license_number} · {pharmacy.hwid}
                          </div>
                        </div>
                        {isSelected && <ChevronRight size={14} className="text-teal-600 flex-shrink-0 mt-1" />}
                      </div>
                    </td>
                    <td className="px-4 py-3 text-slate-700 whitespace-nowrap">{pharmacy.region}</td>
                    <td className="px-4 py-3 text-right text-slate-700 whitespace-nowrap">
                      <div className="font-semibold">{pharmacy.total_medicines}</div>
                      <div className="text-[10px] text-slate-500">
                        {pharmacy.critical_count > 0 && `${pharmacy.critical_count}C `}
                        {pharmacy.low_count > 0 && `${pharmacy.low_count}L`}
                      </div>
                    </td>
                    <td className="px-4 py-3 text-center whitespace-nowrap">
                      {statusBadge(pharmacy.risk_badge)}
                    </td>
                    <td className="px-4 py-3 text-slate-600 whitespace-nowrap text-[10px]">
                      {formatTimeDiff(pharmacy.last_sync)}
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
