import { useState, useMemo, useEffect, useCallback } from 'react'
import { Search, ShieldAlert, Eye, AlertOctagon, Link2, CheckCircle2, XCircle, ScanLine, Loader2, RefreshCw } from 'lucide-react'
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts'
import { monitoringApi } from '../services/monitoringApi.js'

const FLAG_MAP = {
  critical: { label: 'CRITICAL', cls: 'bg-red-600 text-white', rowCls: 'bg-red-50/60 border-l-2 border-l-red-500' },
  suspicious: { label: 'SUSPICIOUS', cls: 'bg-amber-500 text-white', rowCls: 'bg-amber-50/40 border-l-2 border-l-amber-400' },
  watch: { label: 'WATCH', cls: 'bg-slate-200 text-slate-700', rowCls: 'bg-white border-l-2 border-l-slate-300' },
}

export default function HoardingAnalytics() {
  const [anomalies, setAnomalies] = useState([])
  const [selected, setSelected] = useState(null)
  const [search, setSearch] = useState('')
  const [trend, setTrend] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [toast, setToast] = useState(null)

  const [barcode, setBarcode] = useState('')
  const [trace, setTrace] = useState(null)
  const [traceChecked, setTraceChecked] = useState(false)

  const loadLive = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const json = await monitoringApi.getHoardingAnomalies()
      const rows = Array.isArray(json?.data) ? json.data : []
      const mapped = rows.map((r) => ({
        id: r.id,
        pharmacy: r.pharmacy_name || 'Unknown',
        license: r.license_number || 'N/A',
        hwid: r.hwid || 'N/A',
        region: r.region || 'Unknown',
        incoming: Number(r.incoming_units || 0),
        outgoing: Number(r.outgoing_units || 0),
        ratio: Number(r.ratio || 0),
        score: Number(r.score || 0),
        flag: r.flag || 'watch',
        items: Array.isArray(r.flagged_items) ? r.flagged_items : [],
      }))
      setAnomalies(mapped)
      setSelected((prev) => mapped.find((m) => m.id === prev?.id) || mapped[0] || null)
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    loadLive()
  }, [loadLive])

  const filtered = useMemo(() => {
    const q = search.toLowerCase()
    return anomalies.filter((a) => a.pharmacy.toLowerCase().includes(q) || a.license.toLowerCase().includes(q) || a.region.toLowerCase().includes(q))
  }, [anomalies, search])

  useEffect(() => {
    if (!selected?.id) {
      setTrend([])
      return
    }

    let ignore = false
    async function loadTrend() {
      try {
        const json = await monitoringApi.getHoardingTrend(selected.id)
        const rows = Array.isArray(json?.data) ? json.data : []
        if (!ignore) setTrend(rows)
      } catch {
        if (!ignore) setTrend([])
      }
    }

    loadTrend()
    return () => {
      ignore = true
    }
  }, [selected])

  function action(msg) {
    setToast(msg)
    setTimeout(() => setToast(null), 3000)
  }

  async function verifyBarcode() {
    const b = barcode.trim()
    if (!b) return
    setTraceChecked(true)
    try {
      const json = await monitoringApi.getChainOfCustody(b)
      if (json.status === 'success' && json.data) {
        const d = json.data
        setTrace({
          medication: `${d.trade_name || 'Unknown'} ${d.dosage || ''}`.trim(),
          barcode: d.barcode || b,
          regNumber: d.reg_number || 'N/A',
          manufacturer: d.manufacturer || 'N/A',
          category: d.category || 'N/A',
          updatedAt: d.updated_at ? new Date(d.updated_at).toISOString().slice(0, 10) : 'N/A',
        })
      } else {
        setTrace(null)
      }
    } catch {
      setTrace(null)
    }
  }

  if (loading) return <div className="p-6 text-slate-500 inline-flex items-center gap-2"><Loader2 size={14} className="animate-spin" />Loading live anomaly data...</div>
  if (error) return <div className="p-6 text-red-600">Failed to load data: {error}</div>

  return (
    <div className="p-6 space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-bold text-slate-900">Hoarding & Anomaly Detection</h1>
          <p className="text-xs text-slate-500">Live records from PostgreSQL (`hoarding_alerts` + registry)</p>
        </div>
        <button onClick={loadLive} className="px-3 py-2 rounded bg-teal-700 text-white text-xs inline-flex items-center gap-1"><RefreshCw size={12} />Refresh</button>
      </div>

      <div className="grid grid-cols-5 gap-4">
        <div className="col-span-2 bg-white border rounded overflow-hidden">
          <div className="p-3 border-b">
            <div className="relative">
              <Search size={12} className="absolute left-2 top-1/2 -translate-y-1/2 text-slate-400" />
              <input className="w-full border rounded pl-7 pr-2 py-1.5 text-xs" placeholder="Search pharmacy/license/region" value={search} onChange={(e) => setSearch(e.target.value)} />
            </div>
          </div>
          <div className="max-h-140 overflow-y-auto divide-y">
            {filtered.map((a) => {
              const info = FLAG_MAP[a.flag] || FLAG_MAP.watch
              return (
                <div key={a.id} onClick={() => setSelected(a)} className={`${info.rowCls} p-3 cursor-pointer ${selected?.id === a.id ? 'ring-1 ring-teal-300' : ''}`}>
                  <div className="flex justify-between">
                    <div>
                      <div className="font-semibold text-sm">{a.pharmacy}</div>
                      <div className="text-[11px] text-slate-500 font-mono">{a.license} · {a.hwid}</div>
                    </div>
                    <span className={`text-[10px] px-2 py-0.5 rounded-full ${info.cls}`}>{info.label}</span>
                  </div>
                  <div className="text-xs text-slate-600 mt-1">In {a.incoming.toLocaleString()} · Out {a.outgoing.toLocaleString()} · Ratio {a.ratio}x · Score {a.score}</div>
                </div>
              )
            })}
          </div>
        </div>

        <div className="col-span-3 space-y-4">
          {selected && (
            <>
              <div className="bg-white border rounded p-4">
                <div className="flex items-center justify-between mb-2">
                  <h2 className="font-bold">{selected.pharmacy}</h2>
                  <span className={`text-[10px] px-2 py-0.5 rounded-full ${(FLAG_MAP[selected.flag] || FLAG_MAP.watch).cls}`}>{(FLAG_MAP[selected.flag] || FLAG_MAP.watch).label}</span>
                </div>
                <div className="text-xs text-slate-500 mb-3">{selected.license} · {selected.hwid} · {selected.region}</div>
                <div className="grid grid-cols-4 gap-2 text-xs">
                  <div className="bg-slate-50 border rounded p-2">Incoming<br/><b>{selected.incoming.toLocaleString()}</b></div>
                  <div className="bg-slate-50 border rounded p-2">Outgoing<br/><b>{selected.outgoing.toLocaleString()}</b></div>
                  <div className="bg-slate-50 border rounded p-2">Ratio<br/><b>{selected.ratio}x</b></div>
                  <div className="bg-slate-50 border rounded p-2">Risk Score<br/><b>{selected.score}/100</b></div>
                </div>
              </div>

              <div className="bg-white border rounded p-4">
                <div className="text-sm font-semibold mb-2">Stock vs Sales (derived from live row)</div>
                <div style={{ height: 180 }}>
                  <ResponsiveContainer width="100%" height="100%">
                    <BarChart data={trend}>
                      <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" />
                      <XAxis dataKey="week" tick={{ fontSize: 10 }} />
                      <YAxis tick={{ fontSize: 10 }} />
                      <Tooltip />
                      <Bar dataKey="incoming" fill="#f87171" />
                      <Bar dataKey="outgoing" fill="#0d9488" />
                    </BarChart>
                  </ResponsiveContainer>
                </div>
              </div>

              <div className="bg-white border rounded p-4">
                <div className="text-sm font-semibold mb-2">Flagged Medications ({selected.items.length})</div>
                <div className="flex flex-wrap gap-2">
                  {selected.items.map((it) => (
                    <span key={it} className="px-2 py-1 rounded-full text-xs border bg-amber-50 border-amber-200 text-amber-700 inline-flex items-center gap-1"><AlertOctagon size={11} />{it}</span>
                  ))}
                </div>
                <div className="mt-3 space-y-2">
                  <button onClick={() => action(`Inspection filed for ${selected.pharmacy}`)} className="w-full py-2 rounded bg-red-600 text-white text-xs inline-flex items-center justify-center gap-1"><ShieldAlert size={12} />Flag for Inspection</button>
                  <button onClick={() => action(`Violation report submitted for ${selected.pharmacy}`)} className="w-full py-2 rounded bg-amber-500 text-white text-xs inline-flex items-center justify-center gap-1"><Eye size={12} />Submit Violation</button>
                </div>
              </div>
            </>
          )}
        </div>
      </div>

      <div className="bg-white border rounded p-4">
        <div className="text-sm font-semibold mb-2 inline-flex items-center gap-1"><Link2 size={14} />Supply Chain Traceability (live)</div>
        <div className="flex gap-2 mb-3">
          <div className="relative flex-1">
            <ScanLine size={12} className="absolute left-2 top-1/2 -translate-y-1/2 text-slate-400" />
            <input className="w-full border rounded pl-7 pr-2 py-2 text-xs font-mono" placeholder="Enter barcode" value={barcode} onChange={(e) => setBarcode(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && verifyBarcode()} />
          </div>
          <button onClick={verifyBarcode} className="px-3 py-2 rounded bg-teal-700 text-white text-xs">Verify</button>
        </div>

        {traceChecked && !trace && (
          <div className="p-3 rounded border bg-red-50 border-red-200 text-red-700 text-xs inline-flex items-center gap-1"><XCircle size={12} />Barcode not found in registry database</div>
        )}

        {trace && (
          <div className="p-3 rounded border bg-emerald-50 border-emerald-200 text-xs">
            <div className="font-semibold text-emerald-800 inline-flex items-center gap-1"><CheckCircle2 size={12} />Registry Match Found</div>
            <div className="mt-1">Medication: <b>{trace.medication}</b></div>
            <div>Barcode: <span className="font-mono">{trace.barcode}</span></div>
            <div>Reg No: <span className="font-mono">{trace.regNumber}</span></div>
            <div>Manufacturer: {trace.manufacturer}</div>
            <div>Category: {trace.category}</div>
            <div>Updated: {trace.updatedAt}</div>
          </div>
        )}
      </div>

      {toast && <div className="fixed bottom-4 right-4 bg-slate-900 text-white text-xs px-3 py-2 rounded">{toast}</div>}
    </div>
  )
}
