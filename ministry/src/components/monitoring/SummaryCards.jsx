import { AlertTriangle, ShieldAlert, Stethoscope, WifiOff } from 'lucide-react'
import { formatQuantity } from '../../utils/formatters'

const CARD_META = [
  { key: 'high_price_count', label: 'High Price Alerts', icon: AlertTriangle, cls: 'text-red-600 bg-red-50 border-red-200' },
  { key: 'hoarding_count', label: 'Hoarding Signals', icon: ShieldAlert, cls: 'text-amber-700 bg-amber-50 border-amber-200' },
  { key: 'unhealthy_pharmacies', label: 'Unhealthy Sync Nodes', icon: WifiOff, cls: 'text-sky-700 bg-sky-50 border-sky-200' },
  { key: 'open_alerts', label: 'Open Compliance Alerts', icon: Stethoscope, cls: 'text-fuchsia-700 bg-fuchsia-50 border-fuchsia-200' },
]

export default function SummaryCards({ overview }) {
  if (!overview) {
    return (
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
        {[...Array(4)].map((_, i) => (
          <div key={i} className="h-24 rounded-lg border border-slate-200 bg-white animate-pulse" />
        ))}
      </div>
    )
  }

  return (
    <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
      {CARD_META.map((card) => {
        const Icon = card.icon
        return (
          <div key={card.key} className={`rounded-lg border ${card.cls} p-4 shadow-sm`}>
            <div className="flex items-start justify-between mb-3">
              <span className="text-xs font-semibold text-slate-600 uppercase tracking-wide leading-tight">
                {card.label}
              </span>
              <Icon size={14} className="text-slate-500 shrink-0 mt-0.5" />
            </div>
            <div className="text-3xl font-bold text-slate-900">{formatQuantity(overview[card.key])}</div>
            {card.key === 'unhealthy_pharmacies' && (
              <div className="text-xs text-slate-600 mt-2.5">
                of {formatQuantity(overview.total_pharmacies)} nodes
              </div>
            )}
          </div>
        )
      })}
    </div>
  )
}
