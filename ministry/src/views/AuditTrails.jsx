import { useCallback, useEffect, useMemo, useState } from 'react'
import {
  AlertTriangle,
  Clock,
  FileSearch,
  Filter,
  Loader2,
  RefreshCw,
  Search,
  ShieldCheck,
} from 'lucide-react'
import {
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'
import { monitoringApi, exportRowsToCsv } from '../services/monitoringApi.js'
import { normalizeCurrencyMinor, formatTimestamp } from '../types/monitoring.js'

const FAMILY_LABELS = {
  sales: 'Sales',
  price_change: 'Price Changes',
  stock_adjustment: 'Stock Adjustments',
  inventory_movement: 'Inventory Movements',
  compliance: 'Compliance',
  sync_governance: 'System Events',
}

const SEVERITY_STYLES = {
  critical: 'bg-red-50 border-red-200 text-red-700',
  high: 'bg-amber-50 border-amber-200 text-amber-700',
  medium: 'bg-orange-50 border-orange-200 text-orange-700',
  low: 'bg-blue-50 border-blue-200 text-blue-700',
  info: 'bg-slate-50 border-slate-200 text-slate-700',
}

function severityChip(value) {
  const key = String(value || 'info').toLowerCase()
  const cls = SEVERITY_STYLES[key] || SEVERITY_STYLES.info
  return (
    <span className={`inline-flex items-center px-2 py-0.5 rounded-full border text-[10px] font-semibold ${cls}`}>
      {key.toUpperCase()}
    </span>
  )
}

function toCsvRows(rows) {
  return rows.map((row) => ({
    event_time: row.event_time,
    event_family: row.event_family,
    event_type: row.event_type,
    event_title: row.event_title,
    pharmacy_name: row.pharmacy_name,
    medicine_name: row.medicine_name,
    barcode: row.barcode,
    quantity_delta: row.quantity_delta,
    regulated_price_minor: row.regulated_price_minor,
    actual_price_minor: row.actual_price_minor,
    severity: row.severity,
    source: row.source,
    outcome: row.outcome,
    linked_alert_id: row.linked_alert_id,
    chain_key: row.chain_key,
  }))
}

export default function AuditTrails() {
  const [events, setEvents] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [selected, setSelected] = useState(null)
  const [page, setPage] = useState(1)
  const [pagination, setPagination] = useState({ page: 1, pageSize: 25, total: 0, totalPages: 1 })
  const [meta, setMeta] = useState(null)

  const [search, setSearch] = useState('')
  const [family, setFamily] = useState('')
  const [severity, setSeverity] = useState('')
  const [source, setSource] = useState('')
  const [fromDate, setFromDate] = useState('')
  const [toDate, setToDate] = useState('')
  const [complianceOnly, setComplianceOnly] = useState(false)
  const [includeSystem, setIncludeSystem] = useState(false)

  const fetchEvents = useCallback(async () => {
    setLoading(true)
    setError(null)

    try {
      const res = await monitoringApi.getAuditFeed({
        pharmacy: search,
        medicine: search,
        family,
        severity,
        source,
        complianceOnly,
        includeSystem,
        from: fromDate || undefined,
        to: toDate || undefined,
        page,
        pageSize: 25,
        sortBy: 'event_time',
        sortDir: 'desc',
      })

      setEvents(Array.isArray(res?.data) ? res.data : [])
      setPagination(res?.pagination || { page: 1, pageSize: 25, total: 0, totalPages: 1 })
      setMeta(res?.meta || null)
      if (selected) {
        const stillExists = (res?.data || []).some((row) => row.event_uuid === selected.event_uuid)
        if (!stillExists) setSelected(null)
      }
    } catch (e) {
      setError(e.message)
      setEvents([])
      setPagination({ page: 1, pageSize: 25, total: 0, totalPages: 1 })
      setMeta(null)
    } finally {
      setLoading(false)
    }
  }, [search, family, severity, source, complianceOnly, includeSystem, fromDate, toDate, page, selected])

  useEffect(() => {
    fetchEvents()
  }, [fetchEvents])

  useEffect(() => {
    setPage(1)
  }, [search, family, severity, source, complianceOnly, includeSystem, fromDate, toDate])

  const summary = useMemo(() => {
    const meaningful = events.filter((row) => !row.is_system_event)
    const violations = events.filter((row) => row.event_family === 'compliance' || row.outcome === 'warning' || row.outcome === 'blocked')
    const stockAdjustments = events.filter((row) => row.event_family === 'stock_adjustment')
    const critical = events.filter((row) => row.severity === 'critical' || row.severity === 'high')
    const overchargeMinor = events.reduce((sum, row) => {
      if (row.actual_price_minor == null || row.regulated_price_minor == null) return sum
      if (row.actual_price_minor <= row.regulated_price_minor) return sum
      const units = Number.isFinite(Number(row.quantity_delta)) && Number(row.quantity_delta) > 0 ? Number(row.quantity_delta) : 1
      return sum + ((row.actual_price_minor - row.regulated_price_minor) * units)
    }, 0)

    return {
      meaningfulEvents: meaningful.length,
      activeViolations: violations.length,
      stockAdjustments: stockAdjustments.length,
      criticalEvents: critical.length,
      overchargeMinor,
    }
  }, [events])

  const eventTrend = useMemo(() => {
    const byDay = new Map()
    events.forEach((row) => {
      const date = row.event_time ? String(row.event_time).slice(0, 10) : 'unknown'
      const existing = byDay.get(date) || { date, total: 0, critical: 0 }
      existing.total += 1
      if (row.severity === 'critical' || row.severity === 'high') existing.critical += 1
      byDay.set(date, existing)
    })
    return Array.from(byDay.values()).sort((a, b) => String(a.date).localeCompare(String(b.date))).slice(-14)
  }, [events])

  const familyMix = useMemo(() => {
    const map = new Map()
    events.forEach((row) => {
      const key = row.event_family || 'operational'
      map.set(key, (map.get(key) || 0) + 1)
    })
    return Array.from(map.entries())
      .map(([key, count]) => ({ key, label: FAMILY_LABELS[key] || key, count }))
      .sort((a, b) => b.count - a.count)
  }, [events])

  const canExport = events.length > 0

  return (
    <div className="min-h-full bg-slate-50">
      <div className="bg-white border-b border-slate-200 px-8 py-5">
        <div className="flex items-center justify-between gap-6">
          <div>
            <h1 className="text-slate-900 text-xl font-bold">Audit Trail & Forensic Ledger</h1>
            <p className="text-slate-500 text-[12px] mt-0.5">
              Investigation-grade timeline for sales, pricing, stock adjustments, compliance actions, and optional system events.
            </p>
          </div>
          <button
            onClick={fetchEvents}
            className="flex items-center gap-1.5 px-3 py-2 border border-slate-200 rounded-lg text-slate-500 text-[12px] hover:bg-slate-50"
          >
            <RefreshCw size={13} />Refresh
          </button>
        </div>
      </div>

      <div className="px-8 py-6 space-y-5">
        <div className="grid grid-cols-5 gap-3">
          <div className="rounded-xl border border-slate-200 bg-white p-3">
            <div className="text-[10px] uppercase tracking-wide text-slate-500 font-semibold">Meaningful Events</div>
            <div className="text-xl font-bold text-slate-800 mt-1">{summary.meaningfulEvents}</div>
          </div>
          <div className="rounded-xl border border-amber-200 bg-amber-50 p-3">
            <div className="text-[10px] uppercase tracking-wide text-amber-700 font-semibold">Active Violations</div>
            <div className="text-xl font-bold text-amber-700 mt-1">{summary.activeViolations}</div>
          </div>
          <div className="rounded-xl border border-blue-200 bg-blue-50 p-3">
            <div className="text-[10px] uppercase tracking-wide text-blue-700 font-semibold">Stock Adjustments</div>
            <div className="text-xl font-bold text-blue-700 mt-1">{summary.stockAdjustments}</div>
          </div>
          <div className="rounded-xl border border-red-200 bg-red-50 p-3">
            <div className="text-[10px] uppercase tracking-wide text-red-700 font-semibold">Critical/High</div>
            <div className="text-xl font-bold text-red-700 mt-1">{summary.criticalEvents}</div>
          </div>
          <div className="rounded-xl border border-slate-200 bg-white p-3">
            <div className="text-[10px] uppercase tracking-wide text-slate-500 font-semibold">Overcharge (Visible Set)</div>
            <div className="text-xl font-bold text-slate-800 mt-1">{normalizeCurrencyMinor(summary.overchargeMinor)}</div>
          </div>
        </div>

        <div className="grid grid-cols-3 gap-5">
          <div className="col-span-2 bg-white rounded-xl border border-slate-200 shadow-sm p-4">
            <div className="flex items-center justify-between mb-2">
              <h2 className="text-[13px] font-bold text-slate-800">Event Volume Trend</h2>
              <span className="text-[10px] text-slate-500">Last 14 buckets from current filters</span>
            </div>
            {eventTrend.length === 0 ? (
              <div className="text-xs text-slate-500 py-8 text-center">No trend data for the current filter set.</div>
            ) : (
              <div style={{ height: 130 }}>
                <ResponsiveContainer width="100%" height="100%">
                  <LineChart data={eventTrend} margin={{ top: 5, right: 8, left: -30, bottom: 0 }}>
                    <CartesianGrid strokeDasharray="3 3" stroke="#e2e8f0" />
                    <XAxis dataKey="date" tick={{ fontSize: 10, fill: '#64748b' }} tickLine={false} axisLine={false} />
                    <YAxis tick={{ fontSize: 10, fill: '#64748b' }} tickLine={false} axisLine={false} allowDecimals={false} />
                    <Tooltip contentStyle={{ fontSize: 11, borderRadius: 8, border: '1px solid #e2e8f0' }} />
                    <Line type="monotone" dataKey="total" stroke="#0f766e" strokeWidth={2} dot={{ r: 2 }} />
                    <Line type="monotone" dataKey="critical" stroke="#dc2626" strokeWidth={2} dot={{ r: 2 }} />
                  </LineChart>
                </ResponsiveContainer>
              </div>
            )}
          </div>

          <div className="bg-white rounded-xl border border-slate-200 shadow-sm p-4">
            <h2 className="text-[13px] font-bold text-slate-800 mb-2">Event Mix</h2>
            <div className="space-y-2">
              {familyMix.length === 0 ? (
                <div className="text-xs text-slate-500">No events available.</div>
              ) : familyMix.map((row) => (
                <div key={row.key} className="flex items-center justify-between text-[12px]">
                  <span className="text-slate-600">{row.label}</span>
                  <span className="font-semibold text-slate-800">{row.count}</span>
                </div>
              ))}
            </div>
          </div>
        </div>

        <div className="bg-white rounded-xl border border-slate-200 shadow-sm p-4">
          <div className="flex items-center gap-2 flex-wrap">
            <Filter size={13} className="text-slate-400" />
            <div className="relative min-w-64 flex-1">
              <Search size={13} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" />
              <input
                type="text"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Search pharmacy, medicine, barcode, license..."
                className="w-full pl-8 pr-3 py-2 text-[12px] border border-slate-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-teal-500/30"
              />
            </div>
            <select value={family} onChange={(e) => setFamily(e.target.value)} className="text-[11px] border border-slate-200 rounded-lg px-3 py-2 bg-white text-slate-600">
              <option value="">All Families</option>
              <option value="sales">Sales</option>
              <option value="price_change">Price Changes</option>
              <option value="stock_adjustment">Stock Adjustments</option>
              <option value="inventory_movement">Inventory Movements</option>
              <option value="compliance">Compliance</option>
              <option value="sync_governance">System Events</option>
            </select>
            <select value={severity} onChange={(e) => setSeverity(e.target.value)} className="text-[11px] border border-slate-200 rounded-lg px-3 py-2 bg-white text-slate-600">
              <option value="">All Severities</option>
              <option value="critical">Critical</option>
              <option value="high">High</option>
              <option value="medium">Medium</option>
              <option value="low">Low</option>
              <option value="info">Info</option>
            </select>
            <input
              value={source}
              onChange={(e) => setSource(e.target.value)}
              placeholder="Source (pos, web, compliance_engine)"
              className="w-52 px-3 py-2 text-[11px] border border-slate-200 rounded-lg"
            />
            <input type="date" value={fromDate} onChange={(e) => setFromDate(e.target.value)} className="text-[11px] border border-slate-200 rounded-lg px-3 py-2" />
            <input type="date" value={toDate} onChange={(e) => setToDate(e.target.value)} className="text-[11px] border border-slate-200 rounded-lg px-3 py-2" />
            <label className="inline-flex items-center gap-1.5 text-[11px] text-slate-600">
              <input type="checkbox" checked={complianceOnly} onChange={(e) => setComplianceOnly(e.target.checked)} />
              Compliance Focus
            </label>
            <label className="inline-flex items-center gap-1.5 text-[11px] text-slate-600">
              <input type="checkbox" checked={includeSystem} onChange={(e) => setIncludeSystem(e.target.checked)} />
              Include System Events
            </label>
            <button
              disabled={!canExport}
              onClick={() => {
                exportRowsToCsv(
                  `forensic-audit-${new Date().toISOString().slice(0, 10)}.csv`,
                  [
                    { key: 'event_time', label: 'Time' },
                    { key: 'event_family', label: 'Family' },
                    { key: 'event_type', label: 'Type' },
                    { key: 'event_title', label: 'Title' },
                    { key: 'pharmacy_name', label: 'Pharmacy' },
                    { key: 'medicine_name', label: 'Medicine' },
                    { key: 'barcode', label: 'Barcode' },
                    { key: 'quantity_delta', label: 'Qty Delta' },
                    { key: 'severity', label: 'Severity' },
                    { key: 'source', label: 'Source' },
                  ],
                  toCsvRows(events)
                )
              }}
              className="ml-auto text-[11px] text-teal-700 border border-teal-200 bg-teal-50 px-2.5 py-1 rounded-lg disabled:opacity-40"
            >
              Export CSV
            </button>
          </div>
        </div>

        <div className="grid grid-cols-3 gap-5">
          <div className="col-span-2 bg-white rounded-xl border border-slate-200 shadow-sm overflow-hidden">
            {loading ? (
              <div className="py-16 text-center text-slate-500 text-sm">
                <Loader2 className="animate-spin inline mr-2" size={16} />Loading forensic events...
              </div>
            ) : error ? (
              <div className="py-16 text-center px-6">
                <p className="text-red-600 text-sm font-medium mb-2">Unable to load forensic audit data</p>
                <p className="text-red-500 text-xs mb-3">{error}</p>
                <button onClick={fetchEvents} className="px-3 py-2 rounded-lg text-xs bg-teal-600 text-white">Retry</button>
              </div>
            ) : events.length === 0 ? (
              <div className="py-16 text-center text-slate-400 text-sm">
                <FileSearch size={28} className="mx-auto mb-2 text-slate-300" />No forensic events found for current filters.
              </div>
            ) : (
              <>
                <div className="divide-y divide-slate-100">
                  {events.map((row) => {
                    const active = selected?.event_uuid === row.event_uuid
                    return (
                      <button
                        key={row.event_uuid}
                        onClick={() => setSelected(active ? null : row)}
                        className={`w-full text-left px-4 py-3 hover:bg-slate-50 transition-colors ${active ? 'bg-teal-50/50' : 'bg-white'}`}
                      >
                        <div className="flex items-start justify-between gap-3">
                          <div className="min-w-0 flex-1">
                            <div className="flex items-center gap-2 mb-1 flex-wrap">
                              <span className="text-[10px] px-2 py-0.5 rounded-full border border-slate-200 text-slate-600 font-semibold">
                                {FAMILY_LABELS[row.event_family] || row.event_family}
                              </span>
                              {severityChip(row.severity)}
                              {row.is_system_event ? (
                                <span className="text-[10px] px-2 py-0.5 rounded-full border border-slate-200 text-slate-500">System</span>
                              ) : null}
                            </div>
                            <div className="text-[13px] font-semibold text-slate-800">{row.event_title}</div>
                            <div className="text-[11px] text-slate-600 mt-0.5">{row.event_summary || row.event_type}</div>
                            <div className="text-[10px] text-slate-500 mt-1">
                              {(row.pharmacy_name || 'Unresolved pharmacy')} · {(row.medicine_name || row.barcode || 'Unresolved medicine')} · {row.source || 'unknown source'}
                            </div>
                          </div>
                          <div className="text-[10px] text-slate-400 inline-flex items-center gap-1 shrink-0">
                            <Clock size={10} />{formatTimestamp(row.event_time)}
                          </div>
                        </div>
                      </button>
                    )
                  })}
                </div>
                <div className="px-4 py-3 border-t border-slate-100 bg-slate-50 text-[11px] text-slate-600 flex items-center justify-between">
                  <span>
                    Page {pagination.page} / {pagination.totalPages} · {pagination.total} events
                  </span>
                  <div className="flex items-center gap-1">
                    <button
                      onClick={() => setPage((p) => Math.max(1, p - 1))}
                      disabled={pagination.page <= 1}
                      className="px-2.5 py-1 border border-slate-200 rounded hover:bg-white disabled:opacity-40"
                    >
                      ‹
                    </button>
                    <button
                      onClick={() => setPage((p) => Math.min(pagination.totalPages || 1, p + 1))}
                      disabled={pagination.page >= (pagination.totalPages || 1)}
                      className="px-2.5 py-1 border border-slate-200 rounded hover:bg-white disabled:opacity-40"
                    >
                      ›
                    </button>
                  </div>
                </div>
              </>
            )}
          </div>

          <div className="space-y-4">
            <div className="bg-white rounded-xl border border-slate-200 shadow-sm p-4">
              <h3 className="text-[13px] font-bold text-slate-800 mb-2">Event Detail</h3>
              {!selected ? (
                <div className="text-[12px] text-slate-500">Select an event to inspect facts, linked context, and diagnostics.</div>
              ) : (
                <div className="space-y-2 text-[11px]">
                  <div className="flex items-start justify-between gap-2">
                    <span className="text-slate-400">Title</span>
                    <span className="text-right font-semibold text-slate-700">{selected.event_title}</span>
                  </div>
                  <div className="flex items-start justify-between gap-2">
                    <span className="text-slate-400">Family/Type</span>
                    <span className="text-right font-semibold text-slate-700">{selected.event_family} · {selected.event_type}</span>
                  </div>
                  <div className="flex items-start justify-between gap-2">
                    <span className="text-slate-400">Pharmacy</span>
                    <span className="text-right font-semibold text-slate-700">{selected.pharmacy_name || 'Unresolved pharmacy'}</span>
                  </div>
                  <div className="flex items-start justify-between gap-2">
                    <span className="text-slate-400">Medicine</span>
                    <span className="text-right font-semibold text-slate-700">{selected.medicine_name || selected.barcode || 'Unresolved medicine'}</span>
                  </div>
                  <div className="flex items-start justify-between gap-2">
                    <span className="text-slate-400">Quantity Δ</span>
                    <span className="text-right font-semibold text-slate-700">{selected.quantity_delta == null ? '-' : selected.quantity_delta}</span>
                  </div>
                  <div className="flex items-start justify-between gap-2">
                    <span className="text-slate-400">Regulated / Actual</span>
                    <span className="text-right font-semibold text-slate-700">{normalizeCurrencyMinor(selected.regulated_price_minor)} / {normalizeCurrencyMinor(selected.actual_price_minor)}</span>
                  </div>
                  <div className="flex items-start justify-between gap-2">
                    <span className="text-slate-400">Outcome</span>
                    <span className="text-right font-semibold text-slate-700">{selected.outcome || '-'}</span>
                  </div>
                  <div className="flex items-start justify-between gap-2">
                    <span className="text-slate-400">Linked Alert</span>
                    <span className="text-right font-semibold text-slate-700">{selected.linked_alert_id || '-'}</span>
                  </div>
                  <div className="flex items-start justify-between gap-2">
                    <span className="text-slate-400">Chain Key</span>
                    <span className="text-right font-semibold text-slate-700 break-all">{selected.chain_key || '-'}</span>
                  </div>
                  <details className="pt-1">
                    <summary className="cursor-pointer text-slate-600 font-medium">Diagnostic Metadata (raw)</summary>
                    <pre className="mt-2 text-[10px] bg-slate-50 border border-slate-200 rounded p-2 overflow-x-auto">{JSON.stringify(selected.metadata || {}, null, 2)}</pre>
                  </details>
                </div>
              )}
            </div>

            <div className="bg-white rounded-xl border border-slate-200 shadow-sm p-4">
              <h3 className="text-[12px] font-bold text-slate-800 mb-2">Feed Policy</h3>
              <div className="text-[11px] text-slate-600 space-y-1">
                <p>Default feed prioritizes business and compliance events.</p>
                <p>System sync plumbing is hidden unless Include System Events is enabled.</p>
                <p>Metrics reconcile against current filtered result set.</p>
              </div>
              {meta?.filters ? (
                <div className="mt-3 text-[10px] text-slate-500 border-t border-slate-100 pt-2">
                  Active filters: {JSON.stringify(meta.filters)}
                </div>
              ) : null}
            </div>

            {events.length === 0 && !loading && !error ? (
              <div className="bg-emerald-50 border border-emerald-200 rounded-xl p-4 text-[11px] text-emerald-800">
                <ShieldCheck size={14} className="inline mr-1" />No active forensic signals in current scope.
              </div>
            ) : null}
            {events.some((row) => row.severity === 'critical' || row.severity === 'high') ? (
              <div className="bg-red-50 border border-red-200 rounded-xl p-4 text-[11px] text-red-800">
                <AlertTriangle size={14} className="inline mr-1" />High-severity signals detected. Review event details and linked chains.
              </div>
            ) : null}
          </div>
        </div>
      </div>
    </div>
  )
}
