import { useState, useEffect, useCallback } from 'react'
import {
  Activity, CheckCircle2, Clock, FileText, Loader2,
  MapPin, RefreshCw, Search, Server, WifiOff, XCircle,
} from 'lucide-react'
import { monitoringApi } from '../services/monitoringApi.js'

const REG_STATUS = {
  pending_review:   { label: 'Pending Review',   cls: 'bg-amber-50 text-amber-700 border-amber-200' },
  pending_approval: { label: 'Pending Approval', cls: 'bg-blue-50 text-blue-700 border-blue-200' },
  docs_incomplete:  { label: 'Docs Incomplete',  cls: 'bg-red-50 text-red-700 border-red-200' },
  rejected:         { label: 'Rejected',          cls: 'bg-slate-100 text-slate-500 border-slate-200' },
  approved:         { label: 'Approved',          cls: 'bg-emerald-50 text-emerald-700 border-emerald-200' },
}

function NodeStatus({ status }) {
  if (status === 'online') return <span className="inline-flex items-center gap-1.5 text-[11px] font-semibold text-emerald-700"><span className="w-2 h-2 rounded-full bg-emerald-500" />Online</span>
  if (status === 'degraded') return <span className="inline-flex items-center gap-1.5 text-[11px] font-semibold text-amber-600"><span className="w-2 h-2 rounded-full bg-amber-400" />Degraded</span>
  return <span className="inline-flex items-center gap-1.5 text-[11px] font-semibold text-slate-400"><WifiOff size={12} />Offline</span>
}

function LatencyChip({ ms }) {
  if (ms == null) return <span className="text-[11px] text-slate-300">—</span>
  const color = ms <= 80 ? 'text-emerald-600' : ms <= 300 ? 'text-amber-600' : 'text-red-500'
  return <span className={`text-[12px] font-mono font-bold ${color}`}>{ms}ms</span>
}

function SyncVersionChip({ version }) {
  const isCurrent = version === '2.6.1'
  return (
    <span className={`text-[11px] font-mono px-2 py-0.5 rounded border ${isCurrent ? 'bg-emerald-50 text-emerald-700 border-emerald-200' : 'bg-amber-50 text-amber-700 border-amber-200'}`}>
      v{version}
    </span>
  )
}

export default function SystemGovernance() {
  const [nodes, setNodes] = useState([])
  const [queue, setQueue] = useState([])
  const [medicineQueue, setMedicineQueue] = useState([])
  const [nodeSearch, setNodeSearch] = useState('')
  const [nodeFilter, setNodeFilter] = useState('all')
  const [ticking, setTicking] = useState(true)
  const [pingActive, setPingActive] = useState(false)
  const [selectedReg, setSelectedReg] = useState(null)
  const [selectedMedicine, setSelectedMedicine] = useState(null)
  const [loading, setLoading] = useState(true)
  const [actionLoading, setActionLoading] = useState(null)
  const [toast, setToast] = useState(null)

  function showToast(msg, color = 'bg-slate-900') {
    setToast({ msg, color })
    setTimeout(() => setToast(null), 3500)
  }

  const fetchAll = useCallback(async () => {
    setLoading(true)
    try {
      const [nodesRes, queueRes, medicineRes] = await Promise.all([
        monitoringApi.getPharmacies(),
        monitoringApi.getRegistrationRequests(),
        monitoringApi.getMedicineRequests(),
      ])
      if (nodesRes.status === 'success') {
        setNodes(nodesRes.data.map(n => ({
          id: n.id,
          hwid: n.hwid || '—',
          pharmacy: n.name || 'Unnamed pharmacy',
          region: n.region || '—',
          license: n.license_number || '—',
          status: n.status || 'online',
          lastSeen: n.last_seen || '—',
          latencyMs: n.latency_ms,
          syncVersion: n.sync_version || 'N/A',
          syncPct: n.sync_pct ?? 100,
        })))
      }
      if (queueRes.status === 'success') {
        setQueue(queueRes.data.map(r => ({
          id: r.id,
          regId: r.reg_id || r.id,
          name: r.name || 'Unnamed request',
          owner: r.owner || '—',
          region: r.region || '—',
          submitted: r.submitted_date ? r.submitted_date.slice(0, 10) : '—',
          status: r.status || 'pending_review',
          docs: r.docs_count || 0,
          missing: r.missing_count || 0,
        })))
      }
      if (medicineRes.status === 'success') {
        setMedicineQueue(medicineRes.data.map(r => ({
          id: r.id,
          requestUuid: r.request_uuid,
          barcode: r.barcode || '—',
          name: r.requested_name || 'Unnamed medicine',
          genericName: r.generic_name || '—',
          dosage: r.dosage || '—',
          category: r.category || '—',
          proposedPrice: r.proposed_price_minor == null ? '—' : `$${(r.proposed_price_minor / 100).toFixed(2)}`,
          stockUnits: r.stock_units || 0,
          expiry: r.expiry || '—',
          status: r.request_status || 'pending_review',
          region: r.region || '—',
          pharmacyName: r.pharmacy_name || 'Unknown Pharmacy',
          licenseNumber: r.license_number || 'N/A',
          reviewedAt: r.reviewed_at || null,
          reviewNotes: r.review_notes || '',
        })))
      }
    } catch (e) {
      showToast(`Backend offline: ${e.message}`, 'bg-red-700')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { fetchAll() }, [fetchAll])

  // Poll live values from DB instead of simulating jitter in the client.
  useEffect(() => {
    if (!ticking) return
    const interval = setInterval(() => {
      fetchAll()
    }, 15000)
    return () => clearInterval(interval)
  }, [ticking, fetchAll])

  function handlePingAll() {
    setPingActive(true)
    fetchAll().finally(() => setPingActive(false))
  }

  async function approveReg(reg) {
    setActionLoading(reg.id)
    try {
      const json = await monitoringApi.approveRegistration(reg.id)
      if (json.status === 'success') {
        setQueue(prev => prev.map(x => x.id === reg.id ? { ...x, status: 'approved' } : x))
        setSelectedReg(null)
        showToast(`✓ ${reg.name} approved`, 'bg-emerald-700')
      }
    } catch (e) { showToast(`Error: ${e.message}`, 'bg-red-700') }
    finally { setActionLoading(null) }
  }

  async function rejectReg(reg) {
    setActionLoading(reg.id)
    try {
      const json = await monitoringApi.rejectRegistration(reg.id)
      if (json.status === 'success') {
        setQueue(prev => prev.map(x => x.id === reg.id ? { ...x, status: 'rejected' } : x))
        setSelectedReg(null)
        showToast(`✗ ${reg.name} rejected`, 'bg-red-700')
      }
    } catch (e) { showToast(`Error: ${e.message}`, 'bg-red-700') }
    finally { setActionLoading(null) }
  }

  async function approveMedicine(request) {
    setActionLoading(request.id)
    try {
      const json = await monitoringApi.approveMedicineRequest(request.id, {})
      if (json.status === 'success') {
        setMedicineQueue(prev => prev.map(x => x.id === request.id ? { ...x, status: 'approved' } : x))
        setSelectedMedicine(null)
        showToast(`✓ ${request.name} approved into the registry`, 'bg-emerald-700')
      }
    } catch (e) { showToast(`Error: ${e.message}`, 'bg-red-700') }
    finally { setActionLoading(null) }
  }

  async function rejectMedicine(request) {
    setActionLoading(request.id)
    try {
      const json = await monitoringApi.rejectMedicineRequest(request.id, { review_notes: request.reviewNotes || '' })
      if (json.status === 'success') {
        setMedicineQueue(prev => prev.map(x => x.id === request.id ? { ...x, status: 'rejected' } : x))
        setSelectedMedicine(null)
        showToast(`✗ ${request.name} rejected`, 'bg-red-700')
      }
    } catch (e) { showToast(`Error: ${e.message}`, 'bg-red-700') }
    finally { setActionLoading(null) }
  }

  const filteredNodes = nodes.filter(n => {
    const m = n.pharmacy.toLowerCase().includes(nodeSearch.toLowerCase()) || n.hwid.toLowerCase().includes(nodeSearch.toLowerCase()) || n.license.toLowerCase().includes(nodeSearch.toLowerCase())
    return m && (nodeFilter === 'all' || n.status === nodeFilter)
  })

  const onlineCount = nodes.filter(n => n.status === 'online').length
  const offlineCount = nodes.filter(n => n.status === 'offline').length
  const degradedCount = nodes.filter(n => n.status === 'degraded').length
  const outdatedCount = nodes.filter(n => n.syncVersion !== 'N/A' && n.syncVersion !== '2.6.1').length

  if (loading) return <div className="flex items-center justify-center h-full py-32 text-slate-400"><Loader2 className="animate-spin mr-2" size={20} />Loading system data…</div>

  return (
    <div className="min-h-full bg-slate-50">
      <div className="bg-white border-b border-slate-200 px-8 py-5">
        <div className="flex items-center justify-between">
          <div>
            <div className="flex items-center gap-2 mb-0.5">
              <span className="text-[10px] font-semibold text-teal-600 uppercase tracking-widest">MoPH Command Center</span>
              <span className="text-slate-300">›</span>
              <span className="text-[10px] font-semibold text-slate-500 uppercase tracking-widest">System Governance</span>
            </div>
            <h1 className="text-slate-900 text-xl font-bold">System Governance & Network Pulse</h1>
            <p className="text-slate-500 text-[12px] mt-0.5">Pharmacy onboarding queue and real-time synchronization health of all registered POS nodes</p>
          </div>
          <div className="flex items-center gap-2">
            <button onClick={fetchAll} className="flex items-center gap-1.5 px-3 py-2 border border-slate-200 rounded-lg text-slate-500 text-[12px] hover:bg-slate-50"><RefreshCw size={13} />Refresh</button>
            <button onClick={() => setTicking(t => !t)} className={`flex items-center gap-1.5 px-3 py-2 rounded-lg border text-[12px] font-medium transition-colors ${ticking ? 'bg-teal-50 border-teal-200 text-teal-700' : 'bg-white border-slate-200 text-slate-500'}`}>
              <Activity size={13} className={ticking ? 'text-teal-600' : 'text-slate-400'} />{ticking ? 'Live' : 'Paused'}
            </button>
            <button onClick={handlePingAll} disabled={pingActive} className={`flex items-center gap-1.5 px-4 py-2 rounded-lg text-white text-[12px] font-semibold shadow-sm transition-all ${pingActive ? 'bg-teal-400 cursor-not-allowed' : 'bg-teal-700 hover:bg-teal-600'}`}>
              <RefreshCw size={13} className={pingActive ? 'animate-spin' : ''} />{pingActive ? 'Pinging…' : 'Ping All Nodes'}
            </button>
          </div>
        </div>
      </div>

      {/* Stats */}
      <div className="px-8 pt-6 grid grid-cols-4 gap-4 mb-6">
        {[
          { label: 'Online', value: onlineCount, color: 'text-emerald-600', bg: 'bg-emerald-50 border-emerald-200' },
          { label: 'Degraded', value: degradedCount, color: 'text-amber-600', bg: 'bg-amber-50 border-amber-200' },
          { label: 'Offline', value: offlineCount, color: 'text-red-500', bg: 'bg-red-50 border-red-200' },
          { label: 'Outdated Version', value: outdatedCount, color: 'text-slate-600', bg: 'bg-slate-50 border-slate-200' },
        ].map(({ label, value, color, bg }) => (
          <div key={label} className={`flex items-center gap-4 rounded-xl border p-4 shadow-sm ${bg}`}>
            <div><div className={`text-2xl font-extrabold ${color}`}>{value}</div><div className="text-[10px] text-slate-500 font-semibold uppercase tracking-wider">{label}</div></div>
          </div>
        ))}
      </div>

      <div className="px-8 pb-8 grid grid-cols-3 gap-6">
        {/* Registration Queue */}
        <div className="col-span-1 flex flex-col gap-5">
          <div className="bg-white rounded-xl border border-slate-200 shadow-sm overflow-hidden">
            <div className="px-5 py-4 border-b border-slate-100 flex items-center justify-between">
              <div>
                <h2 className="text-[14px] font-bold text-slate-800">Registration Queue</h2>
                <p className="text-[11px] text-slate-500 mt-0.5">{queue.filter(r => !['approved','rejected'].includes(r.status)).length} pending</p>
              </div>
              <span className="text-[10px] bg-amber-50 text-amber-600 border border-amber-200 px-2.5 py-1 rounded-full font-semibold">
                {queue.filter(r => r.status === 'pending_approval').length} ready to approve
              </span>
            </div>
            <div className="divide-y divide-slate-100">
              {queue.map(reg => {
                const statusInfo = REG_STATUS[reg.status] || REG_STATUS.pending_review
                const isActive = selectedReg?.id === reg.id
                return (
                  <div key={reg.id} onClick={() => setSelectedReg(isActive ? null : reg)}
                    className={`px-5 py-4 cursor-pointer transition-all hover:bg-slate-50 ${isActive ? 'bg-teal-50/40 ring-1 ring-inset ring-teal-400/30' : ''}`}>
                    <div className="flex items-start justify-between mb-1">
                      <div className="text-[13px] font-bold text-slate-800">{reg.name}</div>
                      <span className={`text-[9px] font-bold px-2 py-0.5 rounded-full border uppercase tracking-wider ${statusInfo.cls}`}>{statusInfo.label}</span>
                    </div>
                    <div className="text-[11px] text-slate-500 mb-1">{reg.owner} · {reg.region}</div>
                    <div className="flex items-center justify-between text-[10px] text-slate-400">
                      <span className="flex items-center gap-1"><FileText size={9} />{reg.docs}/5 docs{reg.missing > 0 && <span className="text-red-500 font-semibold ml-1">({reg.missing} missing)</span>}</span>
                      <span>{reg.submitted}</span>
                    </div>
                  </div>
                )
              })}
            </div>
          </div>

          {selectedReg && (
            <div className="bg-white rounded-xl border border-slate-200 shadow-sm p-5">
              <h3 className="text-[13px] font-bold text-slate-800 mb-3">Review: {selectedReg.name}</h3>
              <div className="space-y-2 text-[11px] mb-4">
                {[
                  { label: 'ID', value: selectedReg.regId },
                  { label: 'Owner', value: selectedReg.owner },
                  { label: 'Region', value: selectedReg.region },
                  { label: 'Documents', value: `${selectedReg.docs}/5 submitted` },
                  { label: 'Missing', value: selectedReg.missing > 0 ? `${selectedReg.missing} required` : 'None', highlight: selectedReg.missing > 0 },
                ].map(({ label, value, highlight }) => (
                  <div key={label} className="flex justify-between">
                    <span className="text-slate-400">{label}</span>
                    <span className={`font-semibold ${highlight ? 'text-red-500' : 'text-slate-700'}`}>{value}</span>
                  </div>
                ))}
              </div>
              <div className="flex gap-2">
                <button onClick={() => approveReg(selectedReg)} disabled={selectedReg.missing > 0 || ['approved','rejected'].includes(selectedReg.status) || actionLoading === selectedReg.id}
                  className="flex-1 flex items-center justify-center gap-1.5 py-2 bg-emerald-600 hover:bg-emerald-700 disabled:bg-slate-200 disabled:text-slate-400 text-white rounded-lg text-[12px] font-semibold transition-colors">
                  {actionLoading === selectedReg.id ? <Loader2 size={13} className="animate-spin" /> : <CheckCircle2 size={13} />}Approve
                </button>
                <button onClick={() => rejectReg(selectedReg)} disabled={['approved','rejected'].includes(selectedReg.status) || actionLoading === selectedReg.id}
                  className="flex-1 flex items-center justify-center gap-1.5 py-2 bg-red-50 hover:bg-red-100 disabled:opacity-50 text-red-600 border border-red-200 rounded-lg text-[12px] font-semibold transition-colors">
                  {actionLoading === selectedReg.id ? <Loader2 size={13} className="animate-spin" /> : <XCircle size={13} />}Reject
                </button>
              </div>
            </div>
          )}

          <div className="bg-white rounded-xl border border-slate-200 shadow-sm overflow-hidden">
            <div className="px-5 py-4 border-b border-slate-100 flex items-center justify-between">
              <div>
                <h2 className="text-[14px] font-bold text-slate-800">Medicine Requests</h2>
                <p className="text-[11px] text-slate-500 mt-0.5">{medicineQueue.filter(r => !['approved','rejected'].includes(r.status)).length} pending review</p>
              </div>
              <span className="text-[10px] bg-blue-50 text-blue-600 border border-blue-200 px-2.5 py-1 rounded-full font-semibold">
                {medicineQueue.filter(r => r.status === 'pending_review').length} in queue
              </span>
            </div>
            <div className="divide-y divide-slate-100 max-h-105 overflow-auto">
              {medicineQueue.map(request => {
                const isActive = selectedMedicine?.id === request.id
                const badgeClass = request.status === 'approved'
                  ? 'bg-emerald-50 text-emerald-700 border-emerald-200'
                  : request.status === 'rejected'
                    ? 'bg-slate-100 text-slate-500 border-slate-200'
                    : 'bg-amber-50 text-amber-700 border-amber-200'
                return (
                  <div key={request.id} onClick={() => setSelectedMedicine(isActive ? null : request)}
                    className={`px-5 py-4 cursor-pointer transition-all hover:bg-slate-50 ${isActive ? 'bg-blue-50/40 ring-1 ring-inset ring-blue-400/30' : ''}`}>
                    <div className="flex items-start justify-between mb-1">
                      <div className="text-[13px] font-bold text-slate-800">{request.name}</div>
                      <span className={`text-[9px] font-bold px-2 py-0.5 rounded-full border uppercase tracking-wider ${badgeClass}`}>{request.status.replaceAll('_', ' ')}</span>
                    </div>
                    <div className="text-[11px] text-slate-500 mb-1">{request.barcode} · {request.category}</div>
                    <div className="flex items-center justify-between text-[10px] text-slate-400">
                      <span className="flex items-center gap-1"><FileText size={9} />{request.pharmacyName}</span>
                      <span>{request.proposedPrice}</span>
                    </div>
                  </div>
                )
              })}
            </div>
          </div>

          {selectedMedicine && (
            <div className="bg-white rounded-xl border border-slate-200 shadow-sm p-5">
              <h3 className="text-[13px] font-bold text-slate-800 mb-3">Medicine Review: {selectedMedicine.name}</h3>
              <div className="space-y-2 text-[11px] mb-4">
                {[
                  { label: 'Barcode', value: selectedMedicine.barcode },
                  { label: 'Pharmacy', value: selectedMedicine.pharmacyName },
                  { label: 'License', value: selectedMedicine.licenseNumber },
                  { label: 'Dosage', value: selectedMedicine.dosage },
                  { label: 'Category', value: selectedMedicine.category },
                  { label: 'Proposed Price', value: selectedMedicine.proposedPrice },
                  { label: 'Stock', value: String(selectedMedicine.stockUnits) },
                  { label: 'Expiry', value: selectedMedicine.expiry },
                  { label: 'Review Notes', value: selectedMedicine.reviewNotes || 'None' },
                ].map(({ label, value }) => (
                  <div key={label} className="flex justify-between gap-3">
                    <span className="text-slate-400">{label}</span>
                    <span className="font-semibold text-slate-700 text-right">{value}</span>
                  </div>
                ))}
              </div>
              <div className="flex gap-2">
                <button onClick={() => approveMedicine(selectedMedicine)} disabled={['approved','rejected'].includes(selectedMedicine.status) || actionLoading === selectedMedicine.id}
                  className="flex-1 flex items-center justify-center gap-1.5 py-2 bg-emerald-600 hover:bg-emerald-700 disabled:bg-slate-200 disabled:text-slate-400 text-white rounded-lg text-[12px] font-semibold transition-colors">
                  {actionLoading === selectedMedicine.id ? <Loader2 size={13} className="animate-spin" /> : <CheckCircle2 size={13} />}Approve
                </button>
                <button onClick={() => rejectMedicine(selectedMedicine)} disabled={['approved','rejected'].includes(selectedMedicine.status) || actionLoading === selectedMedicine.id}
                  className="flex-1 flex items-center justify-center gap-1.5 py-2 bg-red-50 hover:bg-red-100 disabled:opacity-50 text-red-600 border border-red-200 rounded-lg text-[12px] font-semibold transition-colors">
                  {actionLoading === selectedMedicine.id ? <Loader2 size={13} className="animate-spin" /> : <XCircle size={13} />}Reject
                </button>
              </div>
            </div>
          )}
        </div>

        {/* Sync Health Grid */}
        <div className="col-span-2">
          <div className="bg-white rounded-xl border border-slate-200 shadow-sm overflow-hidden">
            <div className="px-5 py-4 border-b border-slate-100 flex items-center gap-3">
              <h2 className="text-[14px] font-bold text-slate-800">Synchronization Health Grid</h2>
              <div className="relative flex-1 max-w-xs">
                <Search size={13} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" />
                <input type="text" placeholder="Search hardware, pharmacy…" value={nodeSearch} onChange={e => setNodeSearch(e.target.value)}
                  className="w-full pl-8 pr-3 py-1.5 text-[11px] border border-slate-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-teal-500/30" />
              </div>
              <select value={nodeFilter} onChange={e => setNodeFilter(e.target.value)}
                className="text-[11px] border border-slate-200 rounded-lg px-2 py-1.5 bg-white text-slate-600 focus:outline-none">
                <option value="all">All Nodes</option>
                <option value="online">Online</option>
                <option value="degraded">Degraded</option>
                <option value="offline">Offline</option>
              </select>
              <span className="text-[11px] text-slate-400 ml-auto whitespace-nowrap">{filteredNodes.length} nodes</span>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full">
                <thead>
                  <tr className="bg-slate-50 border-b border-slate-100">
                    {['Hardware ID','Pharmacy','Region','Status','Last Seen','Latency','Version','Sync'].map(h => (
                      <th key={h} className="text-left px-4 py-2.5 text-[10px] font-semibold text-slate-400 uppercase tracking-wider whitespace-nowrap">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-50">
                  {filteredNodes.map(node => {
                    const syncColor = node.syncPct >= 95 ? 'bg-emerald-500' : node.syncPct >= 60 ? 'bg-amber-400' : 'bg-red-500'
                    return (
                      <tr key={node.id} className={`transition-colors hover:bg-slate-50 ${node.status === 'offline' ? 'opacity-60' : ''}`}>
                        <td className="px-4 py-3 text-[11px] font-mono text-slate-500 whitespace-nowrap">{node.hwid}</td>
                        <td className="px-4 py-3"><div className="text-[12px] font-semibold text-slate-800">{node.pharmacy}</div><div className="text-[10px] font-mono text-slate-400">{node.license}</div></td>
                        <td className="px-4 py-3 text-[11px] text-slate-500 whitespace-nowrap"><div className="flex items-center gap-1"><MapPin size={10} className="text-slate-300" />{node.region}</div></td>
                        <td className="px-4 py-3 whitespace-nowrap"><NodeStatus status={node.status} /></td>
                        <td className="px-4 py-3 text-[11px] text-slate-400 whitespace-nowrap"><div className="flex items-center gap-1"><Clock size={10} />{node.lastSeen}</div></td>
                        <td className="px-4 py-3 whitespace-nowrap"><LatencyChip ms={node.latencyMs} /></td>
                        <td className="px-4 py-3 whitespace-nowrap"><SyncVersionChip version={node.syncVersion} /></td>
                        <td className="px-4 py-3 min-w-28">
                          <div className="flex items-center gap-2">
                            <div className="flex-1 h-1.5 bg-slate-100 rounded-full overflow-hidden"><div className={`h-full rounded-full ${syncColor} transition-all`} style={{ width: `${node.syncPct}%` }} /></div>
                            <span className="text-[10px] font-bold text-slate-500 w-8 text-right">{node.syncPct}%</span>
                          </div>
                        </td>
                      </tr>
                    )
                  })}
                  {filteredNodes.length === 0 && <tr><td colSpan={8} className="px-4 py-12 text-center text-[13px] text-slate-400"><Server size={28} className="mx-auto mb-2 text-slate-300" />No nodes match your filters.</td></tr>}
                </tbody>
              </table>
            </div>
            <div className="px-5 py-3 border-t border-slate-100 bg-slate-50 flex items-center justify-between text-[11px] text-slate-400">
              <span>Latency updates every 15s · <span className={ticking ? 'text-emerald-600' : 'text-slate-400'}>Live mode {ticking ? 'ON' : 'OFF'}</span></span>
              <span>Current version: <span className="font-semibold text-teal-600">v2.6.1</span></span>
            </div>
          </div>
        </div>
      </div>

      {toast && <div className={`fixed bottom-6 right-6 z-50 px-4 py-3 ${toast.color} text-white text-[12px] font-medium rounded-xl shadow-2xl max-w-sm`}>{toast.msg}</div>}
    </div>
  )
}
