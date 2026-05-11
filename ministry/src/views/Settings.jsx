import { useMemo, useState, useEffect, useCallback } from 'react'
import {
	Settings2,
	Monitor,
	TrendingUp,
	Package,
	RefreshCw,
	Loader2,
	AlertTriangle,
	Activity,
	CheckCircle2,
	Clock3,
	ShieldAlert,
} from 'lucide-react'
import { monitoringApi } from '../services/monitoringApi.js'
import { SETTINGS_TABS, computeTerminalSummary, freshnessForTerminal } from './settings.helpers.js'

function Badge({ label, color = 'teal' }) {
	const c = {
    teal: 'bg-teal-50 text-teal-700 border-teal-100',
    emerald: 'bg-emerald-50 text-emerald-700 border-emerald-100',
    amber: 'bg-amber-50 text-amber-700 border-amber-200',
    red: 'bg-red-50 text-red-700 border-red-100',
    slate: 'bg-slate-100 text-slate-600 border-slate-200',
		blue: 'bg-blue-50 text-blue-700 border-blue-100',
  }

  return (
    <span className={`px-2 py-0.5 rounded-full text-[10px] font-semibold border ${c[color]}`}>
      {label}
    </span>
  )
}

function SummaryCard({ icon, label, value, tone = 'slate', caption }) {
	const Icon = icon
	const tones = {
		slate: 'text-slate-700 bg-slate-50',
		emerald: 'text-emerald-700 bg-emerald-50',
		red: 'text-red-700 bg-red-50',
		amber: 'text-amber-700 bg-amber-50',
		blue: 'text-blue-700 bg-blue-50',
		teal: 'text-teal-700 bg-teal-50',
	}

	return (
		<div className="rounded-lg border border-slate-200 bg-white p-4">
			<div className="flex items-start justify-between gap-3">
				<div>
					<p className="text-[10px] font-semibold uppercase tracking-wide text-slate-500">{label}</p>
					<p className="mt-1 text-2xl font-bold text-slate-800">{value}</p>
					{caption ? <p className="mt-0.5 text-[11px] text-slate-500">{caption}</p> : null}
				</div>
				<span className={`inline-flex h-8 w-8 items-center justify-center rounded-lg ${tones[tone] || tones.slate}`}>
					<Icon size={15} />
				</span>
			</div>
		</div>
	)
}

function Card({ title, subtitle, children }) {
	return (
		<div className="bg-white rounded-xl border border-slate-200 overflow-hidden">
			<div className="px-5 py-4 border-b border-slate-100">
				<h3 className="text-sm font-semibold text-slate-800">{title}</h3>
				{subtitle && <p className="text-xs text-slate-500 mt-0.5">{subtitle}</p>}
			</div>
			<div className="px-5 py-4 space-y-4">{children}</div>
		</div>
	)
}

function Table({ headers, rows, renderRow, emptyLabel = 'No data available' }) {
	return (
		<div className="overflow-hidden rounded-lg border border-slate-100">
			<table className="w-full text-[12px]">
				<thead>
					<tr className="bg-slate-50 border-b border-slate-100 text-left">
						{headers.map((h) => (
							<th
								key={h}
								className="px-3 py-2.5 font-semibold text-slate-500 uppercase tracking-wide text-[10px]"
							>
								{h}
							</th>
						))}
					</tr>
				</thead>
				<tbody>
					{rows.length > 0 ? (
						rows.map(renderRow)
					) : (
						<tr>
							<td colSpan={headers.length} className="px-3 py-8 text-center text-xs text-slate-500">
								{emptyLabel}
							</td>
						</tr>
					)}
				</tbody>
			</table>
		</div>
	)
}

function formatDateTime(value) {
	if (!value) return 'No recent activity'
	const dt = new Date(value)
	if (Number.isNaN(dt.getTime())) return 'Not available'
	return dt.toLocaleString('en-US', {
		month: 'short',
		day: 'numeric',
		hour: '2-digit',
		minute: '2-digit',
	})
}

function registrationBadge(status) {
	if (status === 'approved') return <Badge label="Approved" color="emerald" />
	if (status === 'pending_review') return <Badge label="Pending" color="amber" />
	if (status === 'rejected') return <Badge label="Rejected" color="red" />
	return <Badge label="No Request" color="slate" />
}

function statusBadge(status) {
	if (status === 'online') return <Badge label="Online" color="emerald" />
	if (status === 'degraded') return <Badge label="Degraded" color="amber" />
	if (status === 'offline') return <Badge label="Offline" color="red" />
	return <Badge label="Unknown" color="slate" />
}

const TABS = SETTINGS_TABS.map((tab) => ({
	...tab,
	icon: tab.id === 'terminals' ? Monitor : tab.id === 'pricing' ? TrendingUp : Package,
}))

export default function Settings() {
	const [activeTab, setActiveTab] = useState('terminals')
	const [loading, setLoading] = useState(true)
	const [error, setError] = useState(null)
	const [generatedAt, setGeneratedAt] = useState(null)
	const [selectedTerminal, setSelectedTerminal] = useState(null)
	const [data, setData] = useState({
		terminals: [],
		terminal_summary: {},
		pricing_policy: {},
		recent_price_events: [],
		adjustment_reasons: [],
		recent_adjustments: [],
		adjustment_summary: {},
		top_adjustment_reasons: [],
	})

	const fetchSettingsData = useCallback(async () => {
		setLoading(true)
		setError(null)
		try {
			const json = await monitoringApi.getSettingsData()
			setData({
				terminals: Array.isArray(json?.data?.terminals) ? json.data.terminals : [],
				terminal_summary: json?.data?.terminal_summary || {},
				pricing_policy: json?.data?.pricing_policy || {},
				recent_price_events: Array.isArray(json?.data?.recent_price_events) ? json.data.recent_price_events : [],
				adjustment_reasons: Array.isArray(json?.data?.adjustment_reasons) ? json.data.adjustment_reasons : [],
				recent_adjustments: Array.isArray(json?.data?.recent_adjustments) ? json.data.recent_adjustments : [],
				adjustment_summary: json?.data?.adjustment_summary || {},
				top_adjustment_reasons: Array.isArray(json?.data?.top_adjustment_reasons) ? json.data.top_adjustment_reasons : [],
			})
			setGeneratedAt(json?.meta?.generated_at || null)
		} catch (e) {
			setError(e.message)
		} finally {
			setLoading(false)
		}
	}, [])

	useEffect(() => {
		fetchSettingsData()
	}, [fetchSettingsData])

	useEffect(() => {
		if (!data.terminals.length) {
			setSelectedTerminal(null)
			return
		}
		if (!selectedTerminal) {
			setSelectedTerminal(data.terminals[0])
			return
		}
		const next = data.terminals.find((row) => row.hwid === selectedTerminal.hwid)
		if (next) setSelectedTerminal(next)
	}, [data.terminals, selectedTerminal])

	const terminalSummary = useMemo(() => {
		return computeTerminalSummary(data.terminals, data.terminal_summary)
	}, [data.terminals, data.terminal_summary])

	const renderTerminals = () => (
		<div className="space-y-4">
			<div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-6">
				<SummaryCard icon={Monitor} label="Total Terminals" value={terminalSummary.total_terminals || 0} tone="slate" />
				<SummaryCard icon={CheckCircle2} label="Online" value={terminalSummary.online_count || 0} tone="emerald" />
				<SummaryCard icon={AlertTriangle} label="Offline" value={terminalSummary.offline_count || 0} tone="red" />
				<SummaryCard icon={Activity} label="Degraded" value={terminalSummary.degraded_count || 0} tone="amber" />
				<SummaryCard icon={ShieldAlert} label="Version Mismatch" value={terminalSummary.version_mismatch_count || 0} tone="amber" caption={terminalSummary.expected_sync_version ? `Target v${terminalSummary.expected_sync_version}` : undefined} />
				<SummaryCard icon={Clock3} label="Never Synced" value={terminalSummary.never_synced_count || 0} tone="blue" />
			</div>

			<Card title="Terminal Readiness & Sync Health" subtitle="Operational node view aligned with sync-health and compliance alert data.">
				<Table
					headers={['Hardware ID', 'Pharmacy', 'License', 'Region', 'Sync Version', 'Status', 'Last Seen', 'Last Sync', 'Pending Outbox', 'Health', 'Registration']}
					rows={data.terminals}
					emptyLabel="No terminal records available"
					renderRow={(node, idx) => {
						const freshness = freshnessForTerminal(node)
						const active = selectedTerminal?.hwid === node.hwid
						return (
							<tr
								key={`${node.hwid || node.id}-${idx}`}
								onClick={() => setSelectedTerminal(node)}
								className={`cursor-pointer border-b border-slate-50 ${idx % 2 === 1 ? 'bg-slate-50/40' : ''} ${active ? 'bg-teal-50/60' : ''}`}
							>
								<td className="px-3 py-2.5 font-mono text-slate-500">{node.hwid || 'Unknown'}</td>
								<td className="px-3 py-2.5 font-medium text-slate-700">{node.name || 'Unnamed pharmacy'}</td>
								<td className="px-3 py-2.5 text-slate-500">{node.license_number || 'No license'}</td>
								<td className="px-3 py-2.5 text-slate-500">{node.region || 'Unknown region'}</td>
								<td className="px-3 py-2.5 font-mono text-slate-500">{node.sync_version ? `v${node.sync_version}` : 'Unknown'}</td>
								<td className="px-3 py-2.5">{statusBadge(node.status)}</td>
								<td className="px-3 py-2.5 text-slate-500">{formatDateTime(node.last_seen)}</td>
								<td className="px-3 py-2.5 text-slate-500">{formatDateTime(node.last_sync_up || node.last_sync_down)}</td>
								<td className="px-3 py-2.5 font-mono text-slate-600">{node.pending_outbox || 0}</td>
								<td className="px-3 py-2.5"><Badge label={freshness.label} color={freshness.color} /></td>
								<td className="px-3 py-2.5">{registrationBadge(node.registration_status)}</td>
							</tr>
						)
					}}
				/>

				{selectedTerminal && (
					<div className="rounded-lg border border-slate-200 bg-slate-50 p-4">
						<p className="text-xs font-semibold uppercase tracking-wide text-slate-500">Selected Terminal Detail</p>
						<div className="mt-2 grid gap-2 sm:grid-cols-2 lg:grid-cols-3 text-sm">
							<p><span className="font-medium text-slate-700">Pharmacy:</span> <span className="text-slate-600">{selectedTerminal.name || 'Unnamed pharmacy'}</span></p>
							<p><span className="font-medium text-slate-700">Hardware ID:</span> <span className="font-mono text-slate-600">{selectedTerminal.hwid || 'Unknown'}</span></p>
							<p><span className="font-medium text-slate-700">Version:</span> <span className="font-mono text-slate-600">{selectedTerminal.sync_version ? `v${selectedTerminal.sync_version}` : 'Unknown'}</span></p>
							<p><span className="font-medium text-slate-700">Open Alerts:</span> <span className="text-slate-600">{selectedTerminal.open_compliance_alerts || 0}</span></p>
							<p><span className="font-medium text-slate-700">Last Seen:</span> <span className="text-slate-600">{formatDateTime(selectedTerminal.last_seen)}</span></p>
							<p><span className="font-medium text-slate-700">Last Sync:</span> <span className="text-slate-600">{formatDateTime(selectedTerminal.last_sync_up || selectedTerminal.last_sync_down)}</span></p>
						</div>
					</div>
				)}
			</Card>
		</div>
	)

	const renderPricing = () => {
		const policy = data.pricing_policy || {}
		const events = data.recent_price_events || []
		return (
			<div className="space-y-4">
				<div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
					<SummaryCard icon={Package} label="Regulated Medicines" value={policy.regulated_medicine_count || 0} tone="teal" />
					<SummaryCard icon={ShieldAlert} label="Open High-Price Alerts" value={policy.high_price_violations || 0} tone="red" />
					<SummaryCard icon={TrendingUp} label="Recent Pricing Events" value={events.length} tone="blue" />
					<SummaryCard icon={Clock3} label="Last Registry Price Update" value={policy.last_registry_sync ? formatDateTime(policy.last_registry_sync) : 'No updates logged'} tone="slate" />
				</div>

				<Card title="Pricing Policy Visibility" subtitle="Read-only policy context from MoPH registry, compliance alerts, and change logs.">
					<div className="grid gap-3 sm:grid-cols-2 text-sm">
						<div className="rounded-lg border border-slate-200 bg-slate-50 p-3">
							<p className="font-semibold text-slate-700">Authoritative Price Source</p>
							<p className="mt-1 text-slate-600">Official regulated prices are pulled from the MoPH registry table and compared against POS-reported charged prices.</p>
						</div>
						<div className="rounded-lg border border-slate-200 bg-slate-50 p-3">
							<p className="font-semibold text-slate-700">Violation Detection Rule</p>
							<p className="mt-1 text-slate-600">A pricing event is flagged when charged price exceeds regulated ceiling. Open high-price compliance alerts are counted above.</p>
						</div>
					</div>
				</Card>

				<Card title="Recent Pricing Events" subtitle="Latest recorded price-hike events with compliance outcome status.">
					<Table
						headers={['Medicine', 'Barcode', 'Pharmacy', 'Regulated', 'Charged', 'Delta', 'Status', 'Recorded']}
						rows={events}
						emptyLabel="No pricing events were recorded recently"
						renderRow={(event, idx) => {
							const delta = Number(event.charged_price || 0) - Number(event.registry_price || 0)
							return (
								<tr key={`${event.item_name}-${event.created_at}-${idx}`} className={`border-b border-slate-50 ${idx % 2 === 1 ? 'bg-slate-50/40' : ''}`}>
									<td className="px-3 py-2.5 font-medium text-slate-700">{event.item_name || 'Unknown medicine'}</td>
									<td className="px-3 py-2.5 font-mono text-slate-500">{event.barcode || 'No barcode'}</td>
									<td className="px-3 py-2.5 text-slate-500">{event.pharmacy_name || 'Unknown pharmacy'}</td>
									<td className="px-3 py-2.5 font-mono text-slate-600">${Number(event.registry_price || 0).toFixed(2)}</td>
									<td className="px-3 py-2.5 font-mono text-slate-700">${Number(event.charged_price || 0).toFixed(2)}</td>
									<td className={`px-3 py-2.5 font-mono ${delta > 0 ? 'text-red-600' : 'text-emerald-600'}`}>{delta >= 0 ? '+' : ''}${delta.toFixed(2)}</td>
									<td className="px-3 py-2.5">{event.status === 'violation' ? <Badge label="Violation" color="red" /> : <Badge label="OK" color="emerald" />}</td>
									<td className="px-3 py-2.5 text-slate-500">{formatDateTime(event.created_at)}</td>
								</tr>
							)
						}}
					/>
				</Card>
			</div>
		)
	}

	const renderAdjustments = () => {
		const summary = data.adjustment_summary || {}
		const reasons = data.adjustment_reasons || []
		const recent = data.recent_adjustments || []
		const topReasons = data.top_adjustment_reasons || []

		return (
			<div className="space-y-4">
				<div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
					<SummaryCard icon={Package} label="Total Adjustments Logged" value={summary.total_adjustments || 0} tone="teal" />
					<SummaryCard icon={Activity} label="Adjustments (30d)" value={summary.adjustments_last_30d || 0} tone="blue" />
					<SummaryCard icon={Clock3} label="Last Adjustment" value={summary.last_adjustment_at ? formatDateTime(summary.last_adjustment_at) : 'No adjustment history'} tone="slate" />
					<SummaryCard icon={ShieldAlert} label="Allowed Reasons" value={reasons.length} tone="amber" />
				</div>

				<div className="grid gap-4 lg:grid-cols-2">
					<Card title="Allowed Adjustment Reasons" subtitle="Reference reasons accepted by stock-adjust workflows.">
						<div className="flex flex-wrap gap-2">
							{reasons.length > 0 ? (
								reasons.map((reason) => (
									<span key={reason} className="rounded-full border border-slate-200 bg-slate-50 px-3 py-1 text-xs text-slate-700">
										{reason}
									</span>
								))
							) : (
								<p className="text-sm text-slate-500">No adjustment reasons are configured in the backend source.</p>
							)}
						</div>
					</Card>

					<Card title="Most Used Reasons" subtitle="Top adjustment reasons observed in audit activity logs.">
						<div className="space-y-2">
							{topReasons.length > 0 ? (
								topReasons.map((row) => (
									<div key={row.reason} className="flex items-center justify-between rounded-lg border border-slate-200 bg-slate-50 px-3 py-2 text-sm">
										<span className="text-slate-700">{row.reason}</span>
										<span className="font-mono text-slate-600">{row.usage_count}</span>
									</div>
								))
							) : (
								<p className="text-sm text-slate-500">No reason usage history is available yet.</p>
							)}
						</div>
					</Card>
				</div>

				<Card title="Recent Adjustment Activity" subtitle="Read-only audit trail of stock adjustment events.">
					<Table
						headers={['Pharmacy', 'Medicine', 'Quantity Delta', 'Reason', 'Source', 'Recorded']}
						rows={recent}
						emptyLabel="No stock adjustment audit events were found"
						renderRow={(row, idx) => (
							<tr key={`${row.item_name}-${row.created_at}-${idx}`} className={`border-b border-slate-50 ${idx % 2 === 1 ? 'bg-slate-50/40' : ''}`}>
								<td className="px-3 py-2.5 text-slate-700">{row.pharmacy_name || 'Unknown pharmacy'}</td>
								<td className="px-3 py-2.5 text-slate-700">{row.item_name || 'Unknown medicine'}</td>
								<td className={`px-3 py-2.5 font-mono ${Number(row.unit_count || 0) < 0 ? 'text-red-600' : 'text-emerald-700'}`}>
									{Number(row.unit_count || 0) > 0 ? '+' : ''}
									{Number(row.unit_count || 0)}
								</td>
								<td className="px-3 py-2.5 text-slate-600">{row.reason || 'Manual adjustment'}</td>
								<td className="px-3 py-2.5 text-slate-600">{row.source || 'manual_adjustment'}</td>
								<td className="px-3 py-2.5 text-slate-500">{formatDateTime(row.created_at)}</td>
							</tr>
						)}
					/>
				</Card>

				<Card title="Adjustment Policy Notes" subtitle="Current policy behavior as implemented in stock adjustment flow.">
					<div className="grid gap-3 sm:grid-cols-2 text-sm">
						<div className="rounded-lg border border-slate-200 bg-slate-50 p-3">
							<p className="font-semibold text-slate-700">Required Context</p>
							<p className="mt-1 text-slate-600">Adjustment quantity and reason are captured and logged into audit trails for traceability.</p>
						</div>
						<div className="rounded-lg border border-slate-200 bg-slate-50 p-3">
							<p className="font-semibold text-slate-700">Central Sync Behavior</p>
							<p className="mt-1 text-slate-600">Stock adjustments emit audit and change-log entries that downstream POS sync logic can consume.</p>
						</div>
					</div>
				</Card>
			</div>
		)
	}

	const renderTab = () => {
		if (activeTab === 'terminals') return renderTerminals()
		if (activeTab === 'pricing') return renderPricing()
		return renderAdjustments()
	}

	return (
		<div className="p-6 space-y-6">
			<div className="flex items-start justify-between gap-3">
				<div className="flex items-start gap-3">
					<div className="w-9 h-9 rounded-xl bg-slate-800 flex items-center justify-center mt-0.5">
						<Settings2 size={17} className="text-teal-400" />
					</div>
					<div>
						<h1 className="text-xl font-bold text-slate-800">Settings & Operations Console</h1>
						<p className="text-sm text-slate-500 mt-0.5">Terminal readiness, pricing-policy visibility, and stock-adjustment governance powered by live DB data.</p>
						<p className="text-xs text-slate-400 mt-1">Last refresh: {generatedAt ? formatDateTime(generatedAt) : 'No refresh timestamp available'}</p>
					</div>
				</div>
				<button
					onClick={fetchSettingsData}
					className="inline-flex items-center gap-1.5 px-3 py-2 text-xs font-medium text-teal-700 bg-teal-50 border border-teal-200 rounded-lg hover:bg-teal-100"
				>
					<RefreshCw size={12} />
					Refresh DB Data
				</button>
			</div>

			<div className="flex gap-1 bg-slate-100 p-1 rounded-xl w-fit flex-wrap">
				{TABS.map((tab) => {
					const Icon = tab.icon
					const active = activeTab === tab.id
					return (
						<button
							key={tab.id}
							onClick={() => setActiveTab(tab.id)}
							className={`inline-flex items-center gap-2 px-4 py-2 rounded-lg text-[13px] font-medium transition-all ${active ? 'bg-white text-slate-800 shadow-sm' : 'text-slate-500 hover:text-slate-700'}`}
						>
							<Icon size={13} />
							{tab.label}
						</button>
					)
				})}
			</div>

			{loading ? (
				<div className="p-8 text-slate-500 inline-flex items-center gap-2">
					<Loader2 size={16} className="animate-spin" />
					Loading settings from database...
				</div>
			) : error ? (
				<div className="p-8 text-red-700 bg-red-50 border border-red-200 rounded-lg">Failed to load settings data: {error}</div>
			) : (
				renderTab()
			)}
		</div>
	)
}
