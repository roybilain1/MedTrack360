import { useEffect, useState } from 'react'
import {
  ChevronRight,
  Database,
  Inbox,
  Megaphone,
  Settings2,
  ShieldCheck,
  Wifi,
  Siren,
} from 'lucide-react'
import { PRIMARY_NAV_ITEMS, SYSTEM_NAV_ITEM } from '../sidebarConfig.js'
import { monitoringApi } from '../services/monitoringApi.js'

const ICONS_BY_ID = {
  registry: Database,
  monitoring: Siren,
  governance: Inbox,
  announcements: Megaphone,
}

const POLL_INTERVAL_MS = 30_000

export default function Sidebar({ activeView, onNavigate }) {
  const [pendingMedicineCount, setPendingMedicineCount] = useState(0)

  useEffect(() => {
    let cancelled = false
    async function fetchPending() {
      try {
        const res = await monitoringApi.getMedicineRequests({ status: 'pending_review', limit: 1 })
        if (cancelled) return
        const total = res?.pagination?.total
        const fallback = Array.isArray(res?.data) ? res.data.length : 0
        setPendingMedicineCount(Number.isFinite(total) ? total : fallback)
      } catch {
        if (!cancelled) setPendingMedicineCount(0)
      }
    }
    fetchPending()
    const id = setInterval(fetchPending, POLL_INTERVAL_MS)
    return () => {
      cancelled = true
      clearInterval(id)
    }
  }, [])

  const navItems = PRIMARY_NAV_ITEMS.map((item) => {
    const isGovernance = item.id === 'governance'
    return {
      ...item,
      icon: ICONS_BY_ID[item.id] || Siren,
      badge: isGovernance && pendingMedicineCount > 0 ? String(pendingMedicineCount) : null,
      badgeType: isGovernance && pendingMedicineCount > 0 ? 'red' : null,
    }
  })

  return (
    <aside className="w-64 min-w-64 h-screen bg-slate-900 flex flex-col border-r border-slate-800 overflow-hidden">
      {/* Branding */}
      <div className="px-5 pt-6 pb-5 border-b border-slate-800">
        <div className="flex items-center gap-3 mb-3">
          <div className="w-9 h-9 rounded-lg bg-teal-600 flex items-center justify-center shadow-lg">
            <ShieldCheck size={18} className="text-white" strokeWidth={2.5} />
          </div>
          <div>
            <div className="text-white text-[13px] font-bold leading-tight tracking-tight">
              MoPH Command
            </div>
            <div className="text-teal-400 text-[10px] font-medium uppercase tracking-widest">
              Center · v2.6.1
            </div>
          </div>
        </div>
        <div className="flex items-center gap-1.5 text-slate-500 text-[11px]">
          <span
            className="w-1.5 h-1.5 rounded-full bg-emerald-400 inline-block pulse-dot"
          />
          Lebanese Ministry of Public Health
        </div>
      </div>

      {/* Navigation */}
      <nav className="flex-1 px-3 py-4 overflow-y-auto space-y-0.5">
        <div className="text-slate-600 text-[10px] font-semibold uppercase tracking-widest px-2 pb-2">
          Operations
        </div>
        {navItems.map((item) => {
          const Icon = item.icon
          const isActive = activeView === item.id

          return (
            <button
              key={item.id}
              onClick={() => onNavigate(item.id)}
              className={`w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-left transition-all duration-150 group ${
                isActive
                  ? 'bg-teal-600/20 border border-teal-600/30'
                  : 'hover:bg-slate-800 border border-transparent'
              }`}
            >
              <div
                className={`w-8 h-8 rounded-lg flex items-center justify-center shrink-0 transition-colors ${
                  isActive ? 'bg-teal-600' : 'bg-slate-800 group-hover:bg-slate-700'
                }`}
              >
                <Icon
                  size={15}
                  className={isActive ? 'text-white' : 'text-slate-400'}
                  strokeWidth={2}
                />
              </div>
              <div className="flex-1 min-w-0">
                <div
                  className={`text-[13px] font-medium leading-tight truncate ${
                    isActive ? 'text-teal-300' : 'text-slate-300 group-hover:text-white'
                  }`}
                >
                  {item.label}
                </div>
                <div className="text-[10px] text-slate-500 mt-0.5 truncate">
                  {item.sublabel}
                </div>
              </div>
              {item.badge && (
                <span
                  className={`shrink-0 text-[10px] font-bold px-1.5 py-0.5 rounded-full leading-none ${
                    item.badgeType === 'red'
                      ? 'bg-red-500/20 text-red-400'
                      : item.badgeType === 'amber'
                      ? 'bg-amber-500/20 text-amber-400'
                      : 'bg-teal-500/20 text-teal-400'
                  }`}
                >
                  {item.badge}
                </span>
              )}
              {isActive && (
                <ChevronRight size={12} className="text-teal-400 shrink-0" />
              )}
            </button>
          )
        })}
      </nav>

      {/* Divider + System Tools */}
      <div className="px-3 pb-2 border-t border-slate-800 pt-3">
        <div className="text-slate-600 text-[10px] font-semibold uppercase tracking-widest px-2 pb-2">
          System
        </div>
        <button className="w-full flex items-center gap-3 px-3 py-2.5 rounded-lg hover:bg-slate-800 border border-transparent transition-all group">
          <div className="w-8 h-8 rounded-lg bg-slate-800 flex items-center justify-center">
            <Wifi size={14} className="text-emerald-400" strokeWidth={2} />
          </div>
          <div className="flex-1 min-w-0">
            <div className="text-[12px] font-medium text-slate-400 group-hover:text-white">Network Status</div>
            <div className="text-[10px] text-emerald-500">22 / 30 online</div>
          </div>
        </button>
        <button
          onClick={() => onNavigate(SYSTEM_NAV_ITEM.id)}
          className={`w-full flex items-center gap-3 px-3 py-2.5 rounded-lg border transition-all group ${
            activeView === 'settings'
              ? 'bg-teal-600/20 border-teal-600/30'
              : 'hover:bg-slate-800 border-transparent'
          }`}
        >
          <div className={`w-8 h-8 rounded-lg flex items-center justify-center ${
            activeView === 'settings' ? 'bg-teal-600' : 'bg-slate-800 group-hover:bg-slate-700'
          }`}>
            <Settings2 size={14} className={activeView === 'settings' ? 'text-white' : 'text-slate-400'} strokeWidth={2} />
          </div>
          <div className="flex-1 min-w-0">
            <div className={`text-[12px] font-medium ${
              activeView === 'settings' ? 'text-teal-300' : 'text-slate-400 group-hover:text-white'
            }`}>{SYSTEM_NAV_ITEM.label}</div>
            <div className="text-[10px] text-slate-600">{SYSTEM_NAV_ITEM.sublabel}</div>
          </div>
        </button>
      </div>

      {/* Footer */}
      <div className="px-5 pb-4 pt-2 border-t border-slate-800">
        <div className="flex items-center gap-2.5">
          <div className="w-7 h-7 rounded-full bg-teal-700 flex items-center justify-center text-white text-[10px] font-bold">
            MJ
          </div>
          <div>
            <div className="text-slate-300 text-[11px] font-semibold">
              Minister J. Mawad
            </div>
            <div className="text-slate-600 text-[10px]">Super Administrator</div>
          </div>
        </div>
      </div>
    </aside>
  )
}
