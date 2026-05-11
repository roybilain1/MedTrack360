import { X, MapPin, FileText, Clock } from 'lucide-react'
import { statusBadgeClass, statusLabel } from '../../utils/formatters'

function statusBadge(badge) {
  const cls = statusBadgeClass(badge)
  const label = statusLabel(badge)
  return (
    <span className={`px-2 py-0.5 rounded-full border text-[10px] font-semibold ${cls}`}>
      {label || String(badge || '—')}
    </span>
  )
}

export default function SelectedPharmacySummary({
  pharmacy = null,
  criticalCount = 0,
  lowCount = 0,
  safeCount = 0,
  totalMedicines = 0,
  onClear = () => {},
}) {
  if (!pharmacy) return null

  function getRiskBadge() {
    if (criticalCount > 0) return 'critical'
    if (lowCount > 0) return 'low'
    return 'safe'
  }

  return (
    <div className="bg-gradient-to-r from-teal-50 to-blue-50 border border-teal-200 rounded-lg p-4 shadow-sm">
      <div className="flex items-start justify-between gap-4">
        <div className="flex-1 space-y-2">
          {/* Title and close button */}
          <div className="flex items-start justify-between">
            <div>
              <h3 className="text-base font-semibold text-slate-900">{pharmacy.pharmacy_name}</h3>
              <p className="text-xs text-slate-600 mt-0.5">
                {pharmacy.license_number} · {pharmacy.hwid}
              </p>
            </div>
            <button
              onClick={onClear}
              className="text-slate-400 hover:text-slate-600 transition-colors p-1"
              title="Close"
            >
              <X size={16} />
            </button>
          </div>

          {/* Summary row */}
          <div className="grid grid-cols-4 gap-3 text-xs">
            <div>
              <div className="text-slate-600 font-medium">Region</div>
              <div className="text-slate-800 font-semibold flex items-center gap-1 mt-0.5">
                <MapPin size={12} />
                {pharmacy.region}
              </div>
            </div>

            <div>
              <div className="text-slate-600 font-medium">Medicines</div>
              <div className="text-slate-800 font-semibold mt-0.5">{totalMedicines}</div>
            </div>

            <div>
              <div className="text-slate-600 font-medium">Status</div>
              <div className="mt-0.5">{statusBadge(getRiskBadge())}</div>
            </div>

            <div>
              <div className="text-slate-600 font-medium">Breakdown</div>
              <div className="text-slate-800 font-semibold mt-0.5 flex items-center gap-1">
                {criticalCount > 0 && <span className="text-red-600">{criticalCount}C</span>}
                {lowCount > 0 && <span className="text-amber-600">{lowCount}L</span>}
                {safeCount > 0 && <span className="text-emerald-600">{safeCount}S</span>}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
