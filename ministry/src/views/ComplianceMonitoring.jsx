import { useMemo, useState } from 'react'
import { RefreshCw } from 'lucide-react'
import { useMonitoringData } from '../hooks/useMonitoringData'
import { MONITORING_VIEWS } from '../types/monitoring'
import MonitoringFilters from '../components/monitoring/MonitoringFilters'
import SummaryCards from '../components/monitoring/SummaryCards'
import MonitoringTable from '../components/monitoring/MonitoringTable'
import PharmacyList from '../components/monitoring/PharmacyList'
import SelectedPharmacySummary from '../components/monitoring/SelectedPharmacySummary'
import {
  formatDaysOfStock,
  formatExpiryLabel,
  stockStateClasses,
  stockStateLabel,
  statusTooltip,
  coverageTooltip,
} from './complianceStock.helpers'
import {
  formatDecimal,
  formatPercent,
  formatTimestamp,
  normalizeCurrencyMinor,
  statusBadgeClass,
  statusLabel,
} from '../utils/formatters'

function statusBadge(status) {
  const cls = statusBadgeClass(status)
  const label = statusLabel(status)
  return (
    <span className={`px-2 py-0.5 rounded-full border text-[11px] font-semibold ${cls}`}>
      {label || String(status || '—')}
    </span>
  )
}

function getScopeSubtitle(activeView, scope, rowCount) {
  if (!scope) return 'Loading scope...'

  const baseLabel = scope?.scope_label || 'All records'
  const rowInfo = rowCount > 0 ? ` • ${rowCount} result${rowCount === 1 ? '' : 's'}` : ''

  switch (activeView) {
    case 'stock':
      return `${baseLabel}${rowInfo} • Days of stock metric helps identify urgent shortages`
    case 'pricing':
      return `${baseLabel}${rowInfo} • Regulated prices vs. actual selling prices`
    case 'hoarding':
      return `${baseLabel}${rowInfo} • Unusual stock accumulation patterns detected`
    case 'sync':
      return `${baseLabel}${rowInfo} • Pharmacy network health and sync status`
    case 'medicineHistory':
      return `${baseLabel}${rowInfo} • Complete movement history for selected medicines`
    case 'pharmacyAudit':
      return `${baseLabel}${rowInfo} • Branch-scoped forensic events with business signal prioritized`
    case 'priceHistory':
      return `${baseLabel}${rowInfo} • Unified price-change timeline from branch edits, registry updates, and sync-applied events`
    default:
      return baseLabel
  }
}

function useColumns(activeView, selectedPharmacyId = null) {
  return useMemo(() => {
    const columnSets = {
      stock: (() => {
        // For selected pharmacy view, show cleaner operational columns
        if (selectedPharmacyId) {
          return [
            {
              key: 'medicine_name',
              label: 'Medicine',
              wrap: true,
              headerClassName: 'min-w-[260px]',
              cellClassName: 'min-w-[260px]',
              render: (_, row) => (
                <div className="space-y-1">
                  <div className="font-semibold text-slate-900 text-[13px] leading-5">
                    {row.medicine_name || row.barcode || 'Unknown medicine'}
                  </div>
                  <div className="text-[11px] text-slate-500 leading-4">
                    {row.dosage || 'No strength listed'}
                  </div>
                  <div className="text-[11px] text-slate-500 font-mono">
                    {row.barcode || 'No barcode'}
                  </div>
                </div>
              ),
            },
            {
              key: 'category',
              label: 'Category',
              wrap: true,
              headerClassName: 'min-w-[130px]',
              cellClassName: 'min-w-[130px]',
              render: (_, row) => (
                <span className="inline-flex items-center rounded-full border border-teal-200 bg-teal-50 px-2.5 py-1 text-[11px] font-semibold text-teal-700">
                  {row.category || 'Uncategorized'}
                </span>
              ),
            },
            {
              key: 'stock_units',
              label: 'Stock',
              wrap: true,
              headerClassName: 'min-w-[180px]',
              cellClassName: 'min-w-[180px]',
              render: (_, row) => (
                <div className="space-y-1">
                  <div className="flex items-center gap-2">
                    <span className={`inline-flex h-2.5 w-2.5 rounded-full border ${stockStateClasses(row)}`} />
                    <div className="font-semibold text-slate-900 text-[13px]">
                      {Number(row.stock_units || 0)} units
                    </div>
                  </div>
                  <div className="text-[11px] font-medium text-slate-600">
                    {stockStateLabel(row)}
                  </div>
                  <div className="text-[11px] text-slate-500">
                    {row.threshold_units == null ? 'No threshold' : `Threshold: ${row.threshold_units}`}
                  </div>
                  <div className="text-[11px] text-slate-500">
                    {formatDaysOfStock(row.days_of_stock, row.coverage_basis)}
                  </div>
                </div>
              ),
            },
            {
              key: 'expiry_at',
              label: 'Expiry',
              wrap: true,
              headerClassName: 'min-w-[110px]',
              cellClassName: 'min-w-[110px]',
              render: (_, row) => (
                <div className="text-[11px] text-slate-600">
                  {formatExpiryLabel(row.expiry_at)}
                </div>
              ),
            },
            {
              key: 'current_price_minor',
              label: 'Prices',
              wrap: true,
              headerClassName: 'min-w-[170px]',
              cellClassName: 'min-w-[170px]',
              render: (_, row) => {
                const localPrice = normalizeCurrencyMinor(row.current_price_minor)
                const govPrice = normalizeCurrencyMinor(row.regulated_price_minor)

                return (
                  <div className="space-y-1">
                    <div className="text-[11px] font-semibold text-slate-900">
                      Local: {localPrice === '-' ? 'No local price' : localPrice}
                    </div>
                    <div className="text-[11px] text-slate-500">
                      Gov: {govPrice === '-' ? 'No gov price' : govPrice}
                    </div>
                  </div>
                )
              },
            },
            {
              key: 'status',
              label: 'Compliance',
              wrap: true,
              headerClassName: 'min-w-[170px]',
              cellClassName: 'min-w-[170px]',
              render: (_, row) => (
                <div className="space-y-1" title={statusTooltip(row)}>
                  <div>{statusBadge(row.status)}</div>
                  <div className="text-[11px] text-slate-500">{row.status_basis ? row.status_basis.replaceAll('_', ' ') : 'Derived from stock coverage'}</div>
                  <div className="text-[11px] text-slate-500">{coverageTooltip(row)}</div>
                </div>
              ),
            },
          ]
        }

        // Default view (pharmacy list showing, no selection) - show all columns
        return [
          {
            key: 'pharmacy_name',
            label: 'Pharmacy',
            wrap: true,
            render: (_, row) => (
              <div>
                <div className="font-medium text-slate-800">{row.pharmacy_name || 'Unknown pharmacy'}</div>
                <div className="text-[11px] text-slate-500">{row.license_number || 'No license'} · {row.hwid || 'No HWID'} · {row.region || 'Unknown region'}</div>
              </div>
            ),
          },
          {
            key: 'medicine_name',
            label: 'Medicine',
            wrap: true,
            render: (_, row) => (
              <div>
                <div className="font-medium text-slate-800">{row.medicine_name || row.barcode || 'Unknown medicine'}</div>
                <div className="text-[11px] text-slate-500">{row.category || 'Uncategorized'}</div>
              </div>
            ),
          },
          { key: 'barcode', label: 'Barcode' },
          {
            key: 'stock_units',
            label: 'Stock / Threshold',
            render: (_, row) => {
              const threshold = row.threshold_units == null ? 'No threshold' : row.threshold_units
              return `${row.stock_units} u / ${threshold}`
            },
          },
          { key: 'sales_30d', label: 'Sales(30d) Units', render: (v) => `${v} u` },
          { key: 'purchases_30d', label: 'Purchases(30d) Units', render: (v) => `${v} u` },
          {
            key: 'days_of_stock',
            label: 'Days of Stock',
            wrap: true,
            render: (_, row) => (
              <span title={coverageTooltip(row)}>{formatDaysOfStock(row.days_of_stock, row.coverage_basis)}</span>
            ),
          },
          {
            key: 'status',
            label: 'Status',
            wrap: true,
            render: (_, row) => (
              <span title={statusTooltip(row)}>{statusBadge(row.status)}</span>
            ),
          },
        ]
      })(),
      pricing: [
        { key: 'pharmacy_name', label: 'Pharmacy' },
        { key: 'medicine_name', label: 'Medicine' },
        { key: 'barcode', label: 'Barcode' },
        { key: 'regulated_price_minor', label: 'Regulated', render: normalizeCurrencyMinor },
        { key: 'avg_selling_price_minor', label: 'Actual', render: normalizeCurrencyMinor },
        {
          key: 'markup_pct',
          label: 'Markup %',
          render: (v) => (Number.isFinite(Number(v)) ? `${(Number(v) * 100).toFixed(1)}%` : '-'),
        },
        { key: 'status', label: 'Rule', render: statusBadge },
      ],
      hoarding: [
        { key: 'pharmacy_name', label: 'Pharmacy' },
        { key: 'medicine_name', label: 'Medicine' },
        { key: 'stock_units', label: 'Stock' },
        { key: 'sales_30d', label: 'Sales(30d)' },
        { key: 'purchases_30d', label: 'Purchases(30d)' },
        { key: 'days_of_stock', label: 'Days of Stock' },
        { key: 'repeated_accumulation_count', label: 'Accumulation Repeats' },
        { key: 'alert_type', label: 'Alert Type', render: statusBadge },
      ],
      sync: [
        { key: 'pharmacy_name', label: 'Pharmacy' },
        { key: 'license_number', label: 'License' },
        { key: 'region', label: 'Region' },
        {
        key: 'pharmacy_status',
        label: 'Pharmacy Status',
        wrap: true,
        render: (_, row) => statusBadge(row.pharmacy_status || row.status || 'unknown'),
      },
      {
        key: 'health_status',
        label: 'Health',
        wrap: true,
        render: (_, row) => statusBadge(row.health_status || row.status || 'healthy'),
      },
        { key: 'hours_since_sync', label: 'Hours Since Sync', render: (v) => formatDecimal(v, { fallback: '-', fractionDigits: 1 }) },
        { key: 'pending_outbox', label: 'Pending Outbox' },
        { key: 'open_alerts', label: 'Open Alerts' },
      ],
      medicineHistory: [
        { key: 'source', label: 'Source' },
        { key: 'medicine_name', label: 'Medicine' },
        { key: 'barcode', label: 'Barcode' },
        { key: 'pharmacy_name', label: 'Pharmacy' },
        { key: 'event_type', label: 'Event' },
        { key: 'quantity_delta', label: 'Qty Δ' },
        { key: 'unit_price_minor', label: 'Unit Price', render: normalizeCurrencyMinor },
        { key: 'event_time', label: 'Time', render: formatTimestamp },
      ],
      pharmacyAudit: [
        {
          key: 'event_family',
          label: 'Family',
          render: (value, row) => statusBadge(row.is_system_event ? 'system' : value),
        },
        {
          key: 'event_title',
          label: 'Event',
          wrap: true,
          render: (_, row) => (
            <div>
              <div className="font-medium text-slate-800">{row.event_title || 'Event logged'}</div>
              <div className="text-[11px] text-slate-500">{row.event_summary || row.event_type || '-'}</div>
            </div>
          ),
        },
        {
          key: 'pharmacy_name',
          label: 'Pharmacy',
          wrap: true,
          render: (_, row) => (
            <div>
              <div className="font-medium text-slate-800">{row.pharmacy_name || 'Unresolved pharmacy'}</div>
              <div className="text-[11px] text-slate-500">{row.license_number || 'No license'} · {row.hwid || 'No HWID'}</div>
            </div>
          ),
        },
        {
          key: 'medicine_name',
          label: 'Medicine',
          wrap: true,
          render: (_, row) => (
            <div>
              <div className="font-medium text-slate-800">{row.medicine_name || row.barcode || 'Unresolved medicine'}</div>
              <div className="text-[11px] text-slate-500">{row.barcode || 'No barcode'}</div>
            </div>
          ),
        },
        {
          key: 'quantity_delta',
          label: 'Qty Δ',
          render: (value) => (value == null ? '-' : (value > 0 ? `+${value}` : `${value}`)),
        },
        {
          key: 'actual_price_minor',
          label: 'Pricing',
          wrap: true,
          render: (_, row) => {
            const regulated = normalizeCurrencyMinor(row.regulated_price_minor)
            const actual = normalizeCurrencyMinor(row.actual_price_minor)
            if (row.old_price_minor != null || row.new_price_minor != null) {
              return `${normalizeCurrencyMinor(row.old_price_minor)} → ${normalizeCurrencyMinor(row.new_price_minor)}`
            }
            if (actual === '-' && regulated === '-') return '-'
            return `${actual} / ${regulated}`
          },
        },
        { key: 'severity', label: 'Severity', render: statusBadge },
        { key: 'event_time', label: 'Time', render: formatTimestamp },
      ],
      priceHistory: [
        { key: 'pharmacy_name', label: 'Pharmacy' },
        { key: 'medicine_name', label: 'Medicine' },
        { key: 'barcode', label: 'Barcode' },
        {
          key: 'source_label',
          label: 'Source',
          wrap: true,
          render: (_, row) => (
            <div>
              <div className="font-medium text-slate-800">{row.source_label || 'Price history'}</div>
              <div className="text-[11px] text-slate-500">{row.source || '-'}</div>
            </div>
          ),
        },
        { key: 'previous_price_minor', label: 'Previous', render: normalizeCurrencyMinor },
        { key: 'new_price_minor', label: 'New', render: normalizeCurrencyMinor },
        {
          key: 'change_pct',
          label: 'Change %',
          render: formatPercent,
        },
        { key: 'status', label: 'Status', render: statusBadge },
        { key: 'suspicious_jump', label: 'Jump Rule', render: (v) => statusBadge(v ? 'high_markup' : 'normal') },
        { key: 'changed_at', label: 'Changed', render: formatTimestamp },
      ],
    }

    return columnSets[activeView] || columnSets.stock
  }, [activeView, selectedPharmacyId])
}

export default function ComplianceMonitoring() {
  const [activeView, setActiveView] = useState('stock')
  const {
    filters,
    setFilters,
    data,
    pagination,
    meta,
    rules,
    scope,
    overview,
    loading,
    error,
    reload,
    selectedPharmacyId,
    setSelectedPharmacyId,
  } = useMonitoringData(activeView)

  const columns = useColumns(activeView, selectedPharmacyId)

  const statusOptionsByView = {
    stock: [
      { value: 'critical', label: 'Critical' },
      { value: 'low', label: 'Low' },
      { value: 'watch', label: 'Watch' },
      { value: 'safe', label: 'Healthy' },
      { value: 'unknown', label: 'Unknown' },
    ],
    pricing: [
      { value: 'high_price', label: 'High Price' },
      { value: 'high_markup', label: 'High Markup' },
      { value: 'ok', label: 'Compliant' },
    ],
    hoarding: [
      { value: 'high_days_of_stock', label: 'High Days of Stock' },
      { value: 'repeated_accumulation_low_sales', label: 'Repeated Accumulation' },
      { value: 'purchase_outpaces_dispensing', label: 'Purchase Outpaces Dispensing' },
      { value: 'suspicious_retention_high_demand', label: 'Suspicious Retention' },
    ],
    sync: [
      { value: 'overdue_sync', label: 'Overdue Sync' },
      { value: 'queue_backlog', label: 'Queue Backlog' },
      { value: 'never_synced', label: 'Never Synced' },
      { value: 'offline', label: 'Offline' },
      { value: 'healthy', label: 'Healthy' },
    ],
    pharmacyAudit: [
      { value: 'critical', label: 'Critical' },
      { value: 'high', label: 'High' },
      { value: 'medium', label: 'Medium' },
      { value: 'low', label: 'Low' },
      { value: 'info', label: 'Info' },
    ],
    priceHistory: [
      { value: 'high_price', label: 'High Price' },
      { value: 'ok', label: 'OK' },
    ],
  }

  const sortOptionsByView = {
    stock: [
      { value: 'risk_rank', label: 'Highest Risk First' },
      { value: 'stock_units', label: 'Stock Units' },
      { value: 'days_of_stock', label: 'Days of Stock' },
      { value: 'sales_30d', label: 'Sales Velocity (30d)' },
      { value: 'pharmacy_name', label: 'Pharmacy' },
      { value: 'medicine_name', label: 'Medicine' },
    ],
    pricing: [
      { value: 'markup_pct', label: 'Markup %' },
      { value: 'avg_selling_price_minor', label: 'Actual Price' },
      { value: 'regulated_price_minor', label: 'Regulated Price' },
      { value: 'pharmacy_name', label: 'Pharmacy' },
    ],
    hoarding: [
      { value: 'days_of_stock', label: 'Days of Stock' },
      { value: 'purchases_30d', label: 'Purchases 30d' },
      { value: 'sales_30d', label: 'Sales 30d' },
    ],
    sync: [
      { value: 'hours_since_sync', label: 'Hours Since Sync' },
      { value: 'pharmacy_name', label: 'Pharmacy' },
    ],
    medicineHistory: [
      { value: 'event_time', label: 'Event Time' },
      { value: 'medicine_name', label: 'Medicine' },
    ],
    pharmacyAudit: [
      { value: 'event_time', label: 'Event Time' },
      { value: 'severity', label: 'Severity' },
      { value: 'event_family', label: 'Family' },
      { value: 'pharmacy_name', label: 'Pharmacy' },
    ],
    priceHistory: [
      { value: 'changed_at', label: 'Changed Time' },
      { value: 'change_pct', label: 'Change %' },
      { value: 'pharmacy_name', label: 'Pharmacy' },
    ],
  }

  // Derive pharmacy summary for selected pharmacy
  const selectedPharmacyInfo = useMemo(() => {
    if (!selectedPharmacyId || activeView !== 'stock') return null
    
    const rows = Array.isArray(data) ? data : []
    const pharmacyRows = rows.filter((r) => r.pharmacy_id === selectedPharmacyId)
    
    if (pharmacyRows.length === 0) return null

    const first = pharmacyRows[0]
    const statuses = { critical: 0, low: 0, safe: 0, watch: 0, unknown: 0 }
    
    pharmacyRows.forEach((row) => {
      const status = row.status || 'unknown'
      if (statuses[status] !== undefined) {
        statuses[status] += 1
      }
    })

    return {
      pharmacy_id: first.pharmacy_id,
      pharmacy_name: first.pharmacy_name,
      license_number: first.license_number,
      region: first.region,
      hwid: first.hwid,
      statuses,
    }
  }, [selectedPharmacyId, activeView, data])

  // Filter data based on selected pharmacy for stock view
  const displayData = useMemo(() => {
    if (activeView !== 'stock' || !selectedPharmacyId) {
      return Array.isArray(data) ? data : []
    }
    
    return (Array.isArray(data) ? data : []).filter((r) => r.pharmacy_id === selectedPharmacyId)
  }, [activeView, selectedPharmacyId, data])

  const subtitle = getScopeSubtitle(activeView, scope, displayData.length, overview)

  // For stock view, adjust pagination and table title based on selection
  const detailTableTitle = selectedPharmacyId
    ? selectedPharmacyInfo
      ? `${selectedPharmacyInfo.pharmacy_name} — Stock Inventory`
      : 'Selected Pharmacy — Stock Inventory'
    : 'Stock Oversight — Select a Pharmacy'

  return (
    <div className="p-6 space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-black text-slate-900">Compliance & Stock Oversight</h1>
          <p className="text-xs text-slate-500">{subtitle}</p>
        </div>
        <button onClick={reload} className="px-3 py-2 border rounded inline-flex items-center gap-1 text-xs">
          <RefreshCw size={12} />Refresh
        </button>
      </div>

      <SummaryCards overview={overview} />

      <div className="bg-white border border-slate-200 rounded-lg shadow-sm overflow-hidden">
        <div className="flex border-b border-slate-200">
          {MONITORING_VIEWS.map((view) => (
            <button
              key={view.id}
              className={`flex-1 px-4 py-3 text-sm font-medium border-b-2 transition-colors ${
                activeView === view.id
                  ? 'text-teal-600 border-b-teal-600 bg-teal-50/30'
                  : 'text-slate-600 border-b-transparent hover:text-slate-900 hover:bg-slate-50'
              }`}
              onClick={() => {
                setActiveView(view.id)
                if (view.id !== 'stock') {
                  setSelectedPharmacyId(null)
                }
              }}
            >
              {view.label}
            </button>
          ))}
        </div>
      </div>

      {/* Stock Oversight - Pharmacy-First Flow */}
      {activeView === 'stock' && (
        <>
          <PharmacyList
            stockRows={Array.isArray(data) ? data : []}
            selectedPharmacyId={selectedPharmacyId}
            onSelectPharmacy={setSelectedPharmacyId}
            regionFilter={filters.region}
            loading={loading}
          />

          {selectedPharmacyId && selectedPharmacyInfo && (
            <>
              <SelectedPharmacySummary
                pharmacy={selectedPharmacyInfo}
                criticalCount={selectedPharmacyInfo.statuses.critical}
                lowCount={selectedPharmacyInfo.statuses.low}
                safeCount={selectedPharmacyInfo.statuses.safe}
                totalMedicines={
                  (Array.isArray(data) ? data : []).filter(
                    (r) => r.pharmacy_id === selectedPharmacyId
                  ).length
                }
                onClear={() => setSelectedPharmacyId(null)}
              />

              <MonitoringFilters
                filters={filters}
                onChange={setFilters}
                statusOptions={statusOptionsByView[activeView] || []}
                sortOptions={sortOptionsByView[activeView] || []}
                hidePharmacyFilter={true}
              />
            </>
          )}

          {!selectedPharmacyId && (
            <div className="bg-blue-50 border border-blue-200 rounded-lg p-4 text-center">
              <p className="text-sm font-medium text-blue-900">Select a pharmacy above to view its stock inventory</p>
              <p className="text-xs text-blue-700 mt-1">Use the region filter to narrow the pharmacy list</p>
            </div>
          )}

          <div className="bg-white border rounded-xl p-3 text-xs text-slate-600">
            <div className="font-semibold text-slate-800 mb-1">Scoring Logic</div>
            <div>
              Status combines threshold and coverage rules: critical when out of stock or urgent threshold/coverage breach; low when near threshold or low coverage; watch for abnormal inbound-vs-dispensing patterns; unknown when demand history and threshold are insufficient.
            </div>
            <div className="mt-1">
              Days of Stock = current units / average daily units sold (30d), with minimum daily rate guardrail{' '}
              {formatDecimal(rules?.minimumDailyRate, { fallback: '0.25', fractionDigits: 2 })} and readable cap at 3650+ days.
            </div>
            {meta?.filters?.from || meta?.filters?.to ? (
              <div className="mt-1 text-slate-500">
                Date filter narrows movement-derived metrics (sales, purchases, coverage) to the selected period.
              </div>
            ) : null}
          </div>

          {selectedPharmacyId && (
            <MonitoringTable
              title={detailTableTitle}
              columns={columns}
              rows={displayData}
              loading={loading}
              error={error}
              pagination={pagination}
              onPageChange={(nextPage) => setFilters((prev) => ({ ...prev, page: nextPage }))}
              exportName={`stock-${selectedPharmacyInfo?.pharmacy_name || 'pharmacy'}.csv`}
            />
          )}
        </>
      )}

      {/* Other Views - Unchanged */}
      {activeView !== 'stock' && (
        <>
          <MonitoringFilters
            filters={filters}
            onChange={setFilters}
            statusOptions={statusOptionsByView[activeView] || []}
            sortOptions={sortOptionsByView[activeView] || []}
          />

          <MonitoringTable
            title={MONITORING_VIEWS.find((v) => v.id === activeView)?.label || 'Monitoring'}
            columns={columns}
            rows={displayData}
            loading={loading}
            error={error}
            pagination={pagination}
            onPageChange={(nextPage) => setFilters((prev) => ({ ...prev, page: nextPage }))}
            exportName={`monitoring-${activeView}.csv`}
          />
        </>
      )}
    </div>
  )
}
