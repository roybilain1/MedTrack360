import { useState, useMemo, useEffect, useCallback } from 'react'
import { Search, RefreshCw, Download, AlertTriangle, Wifi } from 'lucide-react'
import { AreaChart, Area, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid } from 'recharts'
import { monitoringApi } from '../services/monitoringApi.js'
import {
  buildCoverageSnapshot,
  buildScopedSubtitle,
  buildScopeSubtitle,
  normalizeStatus,
  resolveCoverageLabel,
  resolveLastSyncLabel,
  resolvePharmacyName,
  resolveRegionName,
  resolveThresholdSource,
} from './shortageSurveillance.helpers.js'

const PAGE_SIZE = 15

function StatusBadge({ status }) {
  const normalized = normalizeStatus(status)
  const cls =
    normalized === 'critical'
      ? 'bg-red-50 text-red-700 border-red-200'
      : normalized === 'low'
      ? 'bg-amber-50 text-amber-700 border-amber-200'
      : normalized === 'watch'
      ? 'bg-yellow-50 text-yellow-700 border-yellow-200'
      : normalized === 'unknown'
      ? 'bg-slate-100 text-slate-700 border-slate-200'
      : 'bg-emerald-50 text-emerald-700 border-emerald-200'

  return <span className={`px-2 py-0.5 rounded-full border text-[11px] font-semibold ${cls}`}>{normalized}</span>
}

export default function ShortageSurveillance() {
  const [medications, setMedications] = useState([])
  const [syncNodes, setSyncNodes] = useState([])
  const [stockScope, setStockScope] = useState(null)
  const [stockRules, setStockRules] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState('all')
  const [page, setPage] = useState(1)
  const [refreshSecs, setRefreshSecs] = useState(0)

  const fetchLiveData = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const [stockRes, pharmRes] = await Promise.all([
        monitoringApi.getStock({ pageSize: 500, sortBy: 'days_of_stock', sortDir: 'asc' }),
        monitoringApi.getSyncHealth({ pageSize: 500 }),
      ])

      const stockRows = Array.isArray(stockRes?.data) ? stockRes.data : []
      const syncRows = Array.isArray(pharmRes?.data) ? pharmRes.data : []

      setStockScope(stockRes?.scope || null)
      setStockRules(stockRes?.rules || null)

      setMedications(
        stockRows.map((m) => ({
          id: `${m.pharmacy_id || 'no-pharmacy'}-${m.barcode || 'no-barcode'}`,
          pharmacyId: m.pharmacy_id ?? null,
          barcode: m.barcode || '-',
          name: m.medicine_name || m.barcode || 'Unnamed medication',
          pharmacy: resolvePharmacyName(m),
          license: m.license_number || 'No license',
          category: m.category || 'Uncategorized',
          stock: Number(m.stock_units || 0),
          threshold: m.threshold_units == null ? null : Number(m.threshold_units || 0),
          configuredThreshold: m.configured_threshold == null ? null : Number(m.configured_threshold),
          thresholdSource: resolveThresholdSource(m),
          status: normalizeStatus(m.status),
          statusBasis: m.status_basis || 'Status basis unavailable',
          region: resolveRegionName(m),
          lastSync: resolveLastSyncLabel(m),
          lastSyncUp: m.last_sync_up || null,
          lastSyncDown: m.last_sync_down || null,
          coverageBasis: m.coverage_basis || 'unknown',
          coverageLabel: resolveCoverageLabel({ ...m, daysOfStock: m.days_of_stock }),
          daysOfStock: m.days_of_stock == null ? null : Number(m.days_of_stock),
        }))
      )
      setSyncNodes(syncRows)
      setRefreshSecs(0)
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    fetchLiveData()
  }, [fetchLiveData])

  useEffect(() => {
    const t = setInterval(() => setRefreshSecs((s) => s + 1), 1000)
    return () => clearInterval(t)
  }, [])

  const refreshLabel = refreshSecs < 60 ? `${refreshSecs}s ago` : `${Math.floor(refreshSecs / 60)} min ago`

  const stockCoverageSnapshot = useMemo(() => {
    return buildCoverageSnapshot(medications)
  }, [medications])

  const filtered = useMemo(() => {
    return medications.filter((m) => {
      const q = search.toLowerCase()
      const ms = m.name.toLowerCase().includes(q) || m.barcode.includes(search)
      const mf = statusFilter === 'all' || m.status === statusFilter
      return ms && mf
    })
  }, [medications, search, statusFilter])

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE))
  const safePage = Math.min(page, totalPages)
  const paginated = filtered.slice((safePage - 1) * PAGE_SIZE, safePage * PAGE_SIZE)

  const criticalCount = medications.filter((m) => m.status === 'critical').length
  const lowCount = medications.filter((m) => m.status === 'low').length
  const watchCount = medications.filter((m) => m.status === 'watch').length
  const onlineCount = syncNodes.filter((p) => p.pharmacy_status === 'online').length
  const subtitle = buildScopedSubtitle({
    scopeLabel: stockScope?.scope_label,
    activePharmacies: stockScope?.active_pharmacies,
    registeredNodes: syncNodes.length,
    refreshLabel,
  })

  const legacySubtitle = !stockScope?.scope_label ? buildScopeSubtitle({ rows: medications, refreshLabel }) : null

  function exportCSV() {
    const headers = ['Barcode', 'Medication', 'Category', 'Stock', 'Threshold', 'Status', 'Region', 'Last Sync']
    const rows = medications.map((m) => [m.barcode, `"${m.name}"`, m.category, m.stock, m.threshold, m.status, m.region, m.lastSync].join(','))
    const csv = [headers.join(','), ...rows].join('\n')
    const blob = new Blob([csv], { type: 'text/csv' })
    const a = document.createElement('a')
    a.href = URL.createObjectURL(blob)
    a.download = 'shortage-live.csv'
    a.click()
    URL.revokeObjectURL(a.href)
  }

  if (loading) return <div className="p-6 text-slate-500">Loading live database shortage data...</div>
  if (error) return <div className="p-6 text-red-600">Failed to load data: {error}</div>

  return (
    <div className="p-6 space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-bold text-slate-900">National Stock Surveillance</h1>
          <p className="text-xs text-slate-500">{subtitle}</p>
        </div>
        <div className="flex gap-2">
          <button onClick={exportCSV} className="px-3 py-2 border rounded text-xs inline-flex items-center gap-1"><Download size={12} />Export</button>
          <button onClick={fetchLiveData} className="px-3 py-2 bg-teal-700 text-white rounded text-xs inline-flex items-center gap-1"><RefreshCw size={12} />Refresh</button>
        </div>
      </div>

      <div className="grid grid-cols-3 gap-3">
        <div className="bg-white border rounded p-3 text-sm">Critical alerts: <b>{criticalCount}</b></div>
        <div className="bg-white border rounded p-3 text-sm">Low alerts: <b>{lowCount}</b></div>
        <div className="bg-white border rounded p-3 text-sm inline-flex items-center gap-2"><Wifi size={14} />Online nodes: <b>{onlineCount}/{syncNodes.length}</b></div>
      </div>
      <div className="bg-white border rounded p-3 text-xs text-slate-600">
        <div className="font-semibold text-slate-800 mb-1">Operational Scope</div>
        <div>{subtitle}</div>
        {legacySubtitle ? <div className="mt-1 text-slate-500">Fallback scope check: {legacySubtitle}</div> : null}
      </div>

      <div className="bg-white border rounded p-3">
        <div className="text-sm font-semibold mb-2">Most Constrained Medicines by Days-of-Stock</div>
        <div className="text-xs text-slate-500 mb-2">
          Snapshot metric: top 12 items with the lowest computed days-of-stock from synchronized branch inventory movement over the last 30 days.
        </div>
        {stockCoverageSnapshot.length < 2 ? (
          <div className="rounded border bg-slate-50 p-5 text-xs text-slate-500">Not enough records with computable coverage to plot this snapshot.</div>
        ) : (
          <div style={{ height: 140 }}>
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart data={stockCoverageSnapshot}>
                <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" />
                <XAxis dataKey="label" tick={{ fontSize: 10 }} />
                <YAxis tick={{ fontSize: 10 }} />
                <Tooltip
                  formatter={(value, key) => {
                    if (key === 'daysOfStock') return [`${value} days`, 'Coverage']
                    return [value, key]
                  }}
                  labelFormatter={(label, payload) => {
                    const p = Array.isArray(payload) && payload.length > 0 ? payload[0].payload : null
                    if (!p) return label
                    const threshold = p.threshold == null ? 'No threshold baseline' : `${p.threshold} threshold units`
                    return `${label} · ${p.pharmacy} · ${p.stock} stock units · ${threshold}`
                  }}
                />
                <Area type="monotone" dataKey="daysOfStock" stroke="#0f766e" fill="#ccfbf1" />
              </AreaChart>
            </ResponsiveContainer>
          </div>
        )}
      </div>

      <div className="bg-white border rounded">
        <div className="p-3 border-b flex items-center justify-between gap-2">
          <div className="relative flex-1 max-w-sm">
            <Search size={12} className="absolute left-2 top-1/2 -translate-y-1/2 text-slate-400" />
            <input value={search} onChange={(e) => { setSearch(e.target.value); setPage(1) }} placeholder="Search medication or barcode" className="w-full border rounded pl-7 pr-2 py-1.5 text-xs" />
          </div>
          <select value={statusFilter} onChange={(e) => { setStatusFilter(e.target.value); setPage(1) }} className="border rounded px-2 py-1.5 text-xs">
            <option value="all">All</option>
            <option value="critical">Critical</option>
            <option value="low">Low</option>
            <option value="watch">Watch</option>
            <option value="unknown">Unknown</option>
            <option value="safe">Safe</option>
          </select>
        </div>
        <table className="w-full text-xs">
          <thead>
            <tr className="bg-slate-50 border-b">
              <th className="text-left p-2">Barcode</th>
              <th className="text-left p-2">Medication</th>
              <th className="text-left p-2">Pharmacy</th>
              <th className="text-left p-2">Stock</th>
              <th className="text-left p-2">Coverage</th>
              <th className="text-left p-2">Status</th>
              <th className="text-left p-2">Region</th>
              <th className="text-left p-2">Node Sync (Pharmacy)</th>
            </tr>
          </thead>
          <tbody>
            {paginated.map((m) => (
              <tr key={m.id} className="border-b">
                <td className="p-2 font-mono">{m.barcode}</td>
                <td className="p-2"><div className="font-medium">{m.name}</div><div className="text-slate-400">{m.category}</div></td>
                <td className="p-2"><div>{m.pharmacy}</div><div className="text-slate-400 font-mono">{m.license}</div></td>
                <td className="p-2">
                  <div>{m.stock} / {m.threshold == null ? 'No threshold' : m.threshold}</div>
                  <div className="text-slate-400">{m.thresholdSource}</div>
                </td>
                <td className="p-2">{m.coverageLabel}</td>
                <td className="p-2"><span title={m.statusBasis}><StatusBadge status={m.status} /></span></td>
                <td className="p-2">{m.region}</td>
                <td className="p-2">{m.lastSync}</td>
              </tr>
            ))}
          </tbody>
        </table>
        <div className="p-2 text-xs flex justify-between">
          <span>Showing {filtered.length === 0 ? 0 : (safePage - 1) * PAGE_SIZE + 1}-{Math.min(safePage * PAGE_SIZE, filtered.length)} of {filtered.length}</span>
          <div className="flex gap-2">
            <button className="border rounded px-2" onClick={() => setPage((p) => Math.max(1, p - 1))}>Prev</button>
            <span>{safePage}/{totalPages}</span>
            <button className="border rounded px-2" onClick={() => setPage((p) => Math.min(totalPages, p + 1))}>Next</button>
          </div>
        </div>
      </div>

      <div className="bg-white border rounded p-3 text-xs text-slate-500 inline-flex items-center gap-2">
        <AlertTriangle size={12} />
        Status uses configured thresholds when available, otherwise a 14-day demand-derived floor. Coverage uses 30-day sales with a minimum daily guardrail of {stockRules?.minimumDailyRate ?? 0.25} and critical/low floors at {stockRules?.criticalDaysFloor ?? 3}/{stockRules?.lowDaysFloor ?? 7} days.
      </div>
      <div className="bg-white border rounded p-3 text-xs text-slate-500">
        Additional risk signal: watch items ({watchCount}) indicate purchases outpacing dispensing despite positive stock.
      </div>
    </div>
  )
}
