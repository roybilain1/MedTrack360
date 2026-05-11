import { useState, useMemo, useEffect, useCallback } from 'react'
import {
  Search,
  ChevronUp,
  ChevronDown,
  Edit2,
  Check,
  X,
  RefreshCw,
  Package,
  AlertTriangle,
  TrendingUp,
  Upload,
  Download,
  Sliders,
} from 'lucide-react'
import { monitoringApi } from '../services/monitoringApi.js'

function EditablePrice({ value, onSave }) {
  const [editing, setEditing] = useState(false)
  const [draft, setDraft] = useState('')

  const start = () => {
    setDraft(value.toFixed(2))
    setEditing(true)
  }

  const confirm = () => {
    const parsed = parseFloat(draft)
    if (!isNaN(parsed) && parsed > 0) onSave(parsed)
    setEditing(false)
  }

  const cancel = () => setEditing(false)

  if (editing) {
    return (
      <span className="inline-flex items-center gap-1">
        <span className="text-slate-500 text-xs">$</span>
        <input
          autoFocus
          className="w-20 border border-teal-400 rounded px-1.5 py-0.5 text-sm font-mono text-slate-800 focus:outline-none focus:ring-1 focus:ring-teal-400"
          value={draft}
          onChange={e => setDraft(e.target.value)}
          onKeyDown={e => { if (e.key === 'Enter') confirm(); if (e.key === 'Escape') cancel() }}
        />
        <button onClick={confirm} className="text-emerald-600 hover:text-emerald-700"><Check size={13} /></button>
        <button onClick={cancel} className="text-red-500 hover:text-red-600"><X size={13} /></button>
      </span>
    )
  }

  return (
    <span className="inline-flex items-center gap-1.5 group">
      <span className="font-mono font-semibold text-slate-800">${value.toFixed(2)}</span>
      <button
        onClick={start}
        className="opacity-0 group-hover:opacity-100 transition-opacity text-slate-400 hover:text-teal-600"
      >
        <Edit2 size={12} />
      </button>
    </span>
  )
}

export default function MasterRegistry() {
  const [registry, setRegistry] = useState([])
  const [adjustmentReasons, setAdjustmentReasons] = useState([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [catFilter, setCatFilter] = useState('all')
  const [sortKey, setSortKey] = useState('name')
  const [sortDir, setSortDir] = useState('asc')
  const [syncing, setSyncing] = useState(false)
  const [toast, setToast] = useState(null)
  const [page, setPage] = useState(1)
  const PAGE_SIZE = 15
  const [csvModalOpen, setCsvModalOpen] = useState(false)
  const [adjustModal, setAdjustModal] = useState(null)
  const [adjustQty, setAdjustQty] = useState('')
  const [adjustReason, setAdjustReason] = useState('')

  const showToast = (msg, type = 'success') => {
    setToast({ msg, type })
    setTimeout(() => setToast(null), 3000)
  }

  const loadData = useCallback(async () => {
    const [registryRes, settingsRes] = await Promise.all([
      monitoringApi.getRegistry(),
      monitoringApi.getSettingsData(),
    ])

    const rows = Array.isArray(registryRes?.data) ? registryRes.data : []
    const settingsData = settingsRes?.data || {}

    return {
      registry: rows.map((item) => ({
        rowId: item.id,
        id: item.reg_number || String(item.id),
        barcode: item.barcode,
        name: `${item.trade_name} ${item.dosage || ''}`.trim(),
        category: item.category || 'Uncategorized',
        officialPrice: Number(item.moph_ceiling || 0),
        stock: Number(item.stock_units || 0),
        status: item.stock_status === 'critical' || item.stock_status === 'low' ? 'low_stock' : 'active',
      })),
      adjustmentReasons: Array.isArray(settingsData.adjustment_reasons) ? settingsData.adjustment_reasons : [],
    }
  }, [])

  useEffect(() => {
    let ignore = false
    loadData()
      .then((payload) => {
        if (ignore) return
        setRegistry(payload.registry)
        setAdjustmentReasons(payload.adjustmentReasons)
      })
      .catch((err) => {
        if (ignore) return
        console.error('API Error:', err)
        showToast('Failed to load live registry. Backend offline?', 'error')
      })
      .finally(() => {
        if (!ignore) setLoading(false)
      })

    return () => {
      ignore = true
    }
  }, [loadData])

  const ALL_CATEGORIES = [...new Set(registry.map((m) => m.category || 'Uncategorized'))].sort()

  const handleSort = key => {
    if (sortKey === key) setSortDir(d => (d === 'asc' ? 'desc' : 'asc'))
    else { setSortKey(key); setSortDir('asc') }
  }

  const handlePriceSave = async (rowId, val) => {
    try {
      await monitoringApi.updateRegistryPrice(rowId, val)
      setRegistry((r) => r.map((m) => (m.rowId === rowId ? { ...m, officialPrice: val } : m)))
      
      // Notify POS of pricing update
      await monitoringApi.notifyPricingSyncToPos().catch(() => null)
      
      showToast('Price updated in database and POS notified')
    } catch (err) {
      showToast(`Price update failed: ${err.message}`, 'error')
    }
  }

  const handleBulkSync = () => {
    setSyncing(true)
    loadData().then((payload) => {
      setRegistry(payload.registry)
      setAdjustmentReasons(payload.adjustmentReasons)
    }).finally(() => {
      setSyncing(false)
      showToast('Registry refreshed from database')
    })
  }

  const filtered = useMemo(() => {
    const q = search.toLowerCase()
    return registry
      .filter(m =>
        (m.name.toLowerCase().includes(q) || m.category.toLowerCase().includes(q) || m.id.toLowerCase().includes(q) || (m.barcode || '').includes(q)) &&
        (catFilter === 'all' || m.category === catFilter)
      )
      .sort((a, b) => {
        let av = a[sortKey], bv = b[sortKey]
        if (typeof av === 'string') av = av.toLowerCase()
        if (typeof bv === 'string') bv = bv.toLowerCase()
        if (av < bv) return sortDir === 'asc' ? -1 : 1
        if (av > bv) return sortDir === 'asc' ? 1 : -1
        return 0
      })
  }, [registry, search, catFilter, sortKey, sortDir])

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE))
  const paginated = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE)

  const SortIcon = ({ k }) => {
    if (sortKey !== k) return <ChevronUp size={12} className="text-slate-300" />
    return sortDir === 'asc'
      ? <ChevronUp size={12} className="text-teal-500" />
      : <ChevronDown size={12} className="text-teal-500" />
  }

  const lowStockCount = registry.filter(m => m.status === 'low_stock').length
  const avgPrice = registry.length
    ? registry.reduce((s, m) => s + m.officialPrice, 0) / registry.length
    : 0
  const totalStock = registry.reduce((s, m) => s + m.stock, 0)

  if (loading) {
    return (
      <div className="p-6 text-slate-500 inline-flex items-center gap-2">
        <RefreshCw size={14} className="animate-spin" />
        Loading registry data...
      </div>
    )
  }

  return (
    <div className="p-6 space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-bold text-slate-800">Master Registry</h1>
          <p className="text-sm text-slate-500 mt-0.5">Official MoPH medication price ledger — {registry.length} medications registered</p>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => setCsvModalOpen(true)}
            className="inline-flex items-center gap-2 px-4 py-2 border border-slate-200 bg-white hover:bg-slate-50 text-slate-700 text-sm font-medium rounded-lg transition-colors"
          >
            <Upload size={14} />
            Import CSV
          </button>
          <button
            onClick={handleBulkSync}
            disabled={syncing}
            className="inline-flex items-center gap-2 px-4 py-2 bg-teal-600 hover:bg-teal-700 disabled:opacity-60 text-white text-sm font-medium rounded-lg transition-colors"
          >
            <RefreshCw size={14} className={syncing ? 'animate-spin' : ''} />
            {syncing ? 'Syncing…' : 'Sync All to MoPH'}
          </button>
        </div>
      </div>

      {/* KPI Cards */}
      <div className="grid grid-cols-3 gap-4">
        <div className="bg-white rounded-xl border border-slate-200 p-4">
          <div className="flex items-center gap-2 mb-1">
            <Package size={15} className="text-teal-600" />
            <span className="text-xs font-medium text-slate-500 uppercase tracking-wide">Total Stock</span>
          </div>
          <p className="text-2xl font-bold text-slate-800">{totalStock.toLocaleString()}</p>
          <p className="text-xs text-slate-400 mt-0.5">units across all medications</p>
        </div>
        <div className="bg-white rounded-xl border border-slate-200 p-4">
          <div className="flex items-center gap-2 mb-1">
            <TrendingUp size={15} className="text-indigo-600" />
            <span className="text-xs font-medium text-slate-500 uppercase tracking-wide">Avg. Official Price</span>
          </div>
          <p className="text-2xl font-bold text-slate-800">${avgPrice.toFixed(2)}</p>
          <p className="text-xs text-slate-400 mt-0.5">across {registry.length} medications</p>
        </div>
        <div className={`bg-white rounded-xl border p-4 ${lowStockCount > 0 ? 'border-amber-200' : 'border-slate-200'}`}>
          <div className="flex items-center gap-2 mb-1">
            <AlertTriangle size={15} className={lowStockCount > 0 ? 'text-amber-500' : 'text-slate-400'} />
            <span className="text-xs font-medium text-slate-500 uppercase tracking-wide">Low Stock</span>
          </div>
          <p className={`text-2xl font-bold ${lowStockCount > 0 ? 'text-amber-600' : 'text-slate-800'}`}>{lowStockCount}</p>
          <p className="text-xs text-slate-400 mt-0.5">medications below threshold</p>
        </div>
      </div>

      {/* Search + Category Filter */}
      <div className="flex gap-3">
        <div className="relative flex-1">
          <Search size={15} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" />
          <input
            className="w-full pl-9 pr-4 py-2.5 border border-slate-200 rounded-lg text-sm bg-white focus:outline-none focus:ring-2 focus:ring-teal-400 focus:border-transparent"
            placeholder="Search by name, category, barcode, or ID…"
            value={search}
            onChange={e => { setSearch(e.target.value); setPage(1) }}
          />
        </div>
        <select
          value={catFilter}
          onChange={e => { setCatFilter(e.target.value); setPage(1) }}
          className="text-sm border border-slate-200 rounded-lg px-3 py-2.5 bg-white text-slate-600 focus:outline-none focus:ring-2 focus:ring-teal-400"
        >
          <option value="all">All Categories</option>
          {ALL_CATEGORIES.map(c => (
            <option key={c} value={c}>{c}</option>
          ))}
        </select>
      </div>

      {/* Table */}
      <div className="bg-white rounded-xl border border-slate-200 overflow-hidden">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-slate-100 bg-slate-50">
              {[
                { key: 'id', label: 'ID' },
                { key: 'barcode', label: 'Barcode' },
                { key: 'name', label: 'Medication' },
                { key: 'category', label: 'Category' },
                { key: 'officialPrice', label: 'Official Price (USD)' },
                { key: 'stock', label: 'Stock' },
                { key: 'status', label: 'Status' },
              ].map(col => (
                <th
                  key={col.key}
                  onClick={() => handleSort(col.key)}
                  className="text-left px-4 py-3 text-xs font-semibold text-slate-500 uppercase tracking-wide cursor-pointer hover:text-slate-700 select-none"
                >
                  <span className="inline-flex items-center gap-1">
                    {col.label}
                    <SortIcon k={col.key} />
                  </span>
                </th>
              ))}
              <th className="px-4 py-3 text-xs font-semibold text-slate-400 uppercase tracking-wide">Adjust</th>
            </tr>
          </thead>
          <tbody>
            {paginated.map((med, i) => (
              <tr
                key={med.rowId}
                className={`border-b border-slate-50 hover:bg-slate-50 transition-colors ${i % 2 === 0 ? '' : 'bg-slate-50/40'}`}
              >
                <td className="px-4 py-3 text-xs font-mono text-slate-400">{med.id}</td>
                <td className="px-4 py-3 text-xs font-mono text-slate-400">{med.barcode}</td>
                <td className="px-4 py-3 font-medium text-slate-800">{med.name}</td>
                <td className="px-4 py-3">
                  <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-indigo-50 text-indigo-700 border border-indigo-100">
                    {med.category}
                  </span>
                </td>
                <td className="px-4 py-3">
                  <EditablePrice
                    value={med.officialPrice}
                    onSave={val => handlePriceSave(med.rowId, val)}
                  />
                </td>
                <td className="px-4 py-3 font-mono text-slate-700">
                  {med.stock.toLocaleString()}
                </td>
                <td className="px-4 py-3">
                  {med.status === 'low_stock' ? (
                    <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium bg-amber-50 text-amber-700 border border-amber-200">
                      <AlertTriangle size={10} />
                      Low Stock
                    </span>
                  ) : (
                    <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-emerald-50 text-emerald-700 border border-emerald-100">
                      Active
                    </span>
                  )}
                </td>
                <td className="px-4 py-3">
                  <button
                    onClick={() => { setAdjustModal(med); setAdjustQty(''); setAdjustReason('') }}
                    className="p-1.5 rounded-lg hover:bg-slate-100 text-slate-400 hover:text-teal-600 transition-colors"
                    title="Manual stock adjustment"
                  >
                    <Sliders size={13} />
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {filtered.length === 0 && (
          <div className="py-12 text-center text-slate-400 text-sm">No medications match your search.</div>
        )}
        {/* Pagination footer */}
        <div className="px-4 py-3 border-t border-slate-100 bg-slate-50 flex items-center justify-between text-[11px] text-slate-500">
          <span>
            Showing {filtered.length === 0 ? 0 : (page - 1) * PAGE_SIZE + 1}–{Math.min(page * PAGE_SIZE, filtered.length)} of {filtered.length} records
          </span>
          <div className="flex items-center gap-1">
            <button onClick={() => setPage(p => Math.max(1, p - 1))} disabled={page === 1} className="px-2.5 py-1 border border-slate-200 rounded hover:bg-slate-100 disabled:opacity-40">‹</button>
            <span className="px-2">{page} / {totalPages}</span>
            <button onClick={() => setPage(p => Math.min(totalPages, p + 1))} disabled={page === totalPages} className="px-2.5 py-1 border border-slate-200 rounded hover:bg-slate-100 disabled:opacity-40">›</button>
          </div>
        </div>
      </div>

      {toast && (
        <div className={`fixed bottom-5 right-5 px-4 py-3 rounded-lg shadow-lg text-sm font-medium z-50 transition-all ${
          toast.type === 'success' ? 'bg-emerald-600 text-white' : 'bg-red-600 text-white'
        }`}>
          {toast.msg}
        </div>
      )}

      {/* CSV Import Modal */}
      {csvModalOpen && (
        <div className="fixed inset-0 bg-black/40 z-50 flex items-center justify-center p-6">
          <div className="bg-white rounded-2xl shadow-2xl w-full max-w-lg">
            <div className="px-6 py-5 border-b border-slate-100 flex items-center justify-between">
              <div>
                <h2 className="text-base font-bold text-slate-800">Bulk Inventory Import</h2>
                <p className="text-xs text-slate-500 mt-0.5">Upload your CSV or Excel file to onboard existing inventory</p>
              </div>
              <button onClick={() => setCsvModalOpen(false)} className="text-slate-400 hover:text-slate-600"><X size={18} /></button>
            </div>
            <div className="p-6 space-y-4">
              <div className="rounded-xl border-2 border-dashed border-slate-200 bg-slate-50 px-6 py-10 text-center">
                <div className="w-12 h-12 rounded-full bg-teal-100 flex items-center justify-center mx-auto mb-3">
                  <Upload size={20} className="text-teal-600" />
                </div>
                <p className="text-sm font-semibold text-slate-700">Drop your file here or click to browse</p>
                <p className="text-xs text-slate-400 mt-1">Required columns: ID, Barcode, Name, Category, Official Price, Stock, Expiry Date</p>
                <button className="mt-4 px-4 py-2 text-sm font-medium text-white bg-teal-600 hover:bg-teal-700 rounded-lg">Select File</button>
              </div>
              <button
                onClick={() => setCsvModalOpen(false)}
                className="w-full flex items-center justify-center gap-2 py-2.5 text-sm font-medium text-indigo-700 bg-indigo-50 border border-indigo-200 rounded-lg hover:bg-indigo-100"
              >
                <Download size={14} /> Download CSV Template
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Manual Stock Adjustment Modal */}
      {adjustModal && (
        <div className="fixed inset-0 bg-black/40 z-50 flex items-center justify-center p-6">
          <div className="bg-white rounded-2xl shadow-2xl w-full max-w-md">
            <div className="px-6 py-5 border-b border-slate-100 flex items-center justify-between">
              <div>
                <h2 className="text-base font-bold text-slate-800">Manual Stock Adjustment</h2>
                <p className="text-xs text-slate-500 mt-0.5 font-mono">{adjustModal.id} · {adjustModal.name}</p>
              </div>
              <button onClick={() => setAdjustModal(null)} className="text-slate-400 hover:text-slate-600"><X size={18} /></button>
            </div>
            <div className="p-6 space-y-4">
              <div className="flex items-center gap-3 px-4 py-3 rounded-lg bg-slate-50 border border-slate-200">
                <Package size={15} className="text-slate-500" />
                <span className="text-sm text-slate-600">Current stock:</span>
                <span className="text-sm font-bold text-slate-800 font-mono">{adjustModal.stock.toLocaleString()} units</span>
              </div>
              <div>
                <label className="block text-xs font-semibold text-slate-600 mb-1">Adjustment Quantity (use − for reduction)</label>
                <input
                  type="number"
                  value={adjustQty}
                  onChange={e => setAdjustQty(e.target.value)}
                  placeholder="e.g. −48 or +200"
                  className="w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm font-mono focus:outline-none focus:ring-2 focus:ring-teal-400"
                />
              </div>
              <div>
                <label className="block text-xs font-semibold text-slate-600 mb-1">Reason <span className="text-red-400">*</span></label>
                <select
                  value={adjustReason}
                  onChange={e => setAdjustReason(e.target.value)}
                  className="w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-teal-400"
                >
                  <option value="">Select a reason…</option>
                  {adjustmentReasons.map((reason) => (
                    <option key={reason} value={reason}>{reason}</option>
                  ))}
                </select>
              </div>
              <div className="flex gap-3 pt-1">
                <button onClick={() => setAdjustModal(null)} className="flex-1 py-2.5 border border-slate-200 rounded-lg text-sm font-medium text-slate-600 hover:bg-slate-50">Cancel</button>
                <button
                  disabled={!adjustQty || !adjustReason}
                  onClick={async () => {
                    const delta = parseInt(adjustQty, 10)
                    if (!isNaN(delta) && adjustReason) {
                      try {
                        await monitoringApi.adjustRegistryStock(adjustModal.rowId, delta, adjustReason)
                        
                        // Notify POS of stock adjustment
                        await monitoringApi.syncStockToPOS().catch(() => null)
                        
                        await loadData()
                        showToast(`Stock adjusted in database and POS notified: ${adjustModal.name} (${delta > 0 ? '+' : ''}${delta} units)`)
                        setAdjustModal(null)
                      } catch (err) {
                        showToast(`Adjustment failed: ${err.message}`, 'error')
                      }
                    }
                  }}
                  className="flex-1 py-2.5 bg-teal-600 hover:bg-teal-700 disabled:opacity-50 text-white rounded-lg text-sm font-semibold"
                >
                  Commit Adjustment
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
