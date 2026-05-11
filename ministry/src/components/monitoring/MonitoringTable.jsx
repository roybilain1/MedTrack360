import { ChevronLeft, ChevronRight, Download } from 'lucide-react'
import { exportRowsToCsv } from '../../services/monitoringApi'

function renderValue(value, col, row) {
  if (col.render) {
    // Keep backward-compatible one-arg renderers used across non-stock views.
    if (typeof col.render === 'function' && col.render.length >= 2) {
      return col.render(value, row)
    }
    return col.render(value)
  }
  if (typeof value === 'object' && value !== null) return JSON.stringify(value)
  if (value == null) return '-'
  return String(value)
}

export default function MonitoringTable({
  title,
  columns,
  rows,
  loading,
  error,
  pagination,
  onPageChange,
  exportName,
}) {
  const safePagination = {
    page: Math.max(1, Number(pagination?.page || 1)),
    totalPages: Math.max(1, Number(pagination?.totalPages || 1)),
    total: Math.max(0, Number(pagination?.total || 0)),
  }

  function onExport() {
    exportRowsToCsv(exportName || 'monitoring-export.csv', columns, rows)
  }

  return (
    <div className="bg-white border border-slate-200 rounded-lg shadow-sm overflow-hidden">
      <div className="px-4 py-3 border-b border-slate-100 bg-slate-50 flex items-center justify-between">
        <h3 className="text-sm font-semibold text-slate-800">{title}</h3>
        <button onClick={onExport} className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-slate-600 hover:text-slate-900 hover:bg-white rounded border border-slate-200 transition-colors">
          <Download size={13} />Export
        </button>
      </div>

      {loading ? (
        <div className="flex flex-col items-center justify-center py-12">
          <div className="w-6 h-6 rounded-full border-2 border-slate-300 border-t-teal-600 animate-spin mb-3" />
          <p className="text-sm text-slate-500">Loading…</p>
        </div>
      ) : error ? (
        <div className="flex flex-col items-center justify-center py-12 bg-red-50 border-t border-red-200 m-4 rounded-lg p-4">
          <p className="text-sm text-red-700 font-medium mb-2">Failed to load data</p>
          <p className="text-xs text-red-600">{error}</p>
        </div>
      ) : rows.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-12 text-slate-500">
          <p className="text-sm font-medium">No records found</p>
          <p className="text-xs mt-1">Try adjusting your filters</p>
        </div>
      ) : (
        <>
          <div className="overflow-x-auto">
            <table className="w-full text-xs">
              <thead>
                <tr className="bg-slate-100 border-b border-slate-200">
                  {columns.map((col) => (
                    <th key={col.key} className={`text-left px-4 py-2.5 font-semibold text-slate-700 ${col.wrap ? '' : 'whitespace-nowrap'} ${col.headerClassName || ''}`}>{col.label}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {rows.map((row, idx) => (
                  <tr key={row.id || row.alert_id || row.event_uuid || idx} className="border-b border-slate-100 hover:bg-slate-50 transition-colors">
                    {columns.map((col) => (
                      <td key={col.key} className={`px-4 py-3 align-top ${col.wrap ? '' : 'whitespace-nowrap'} ${col.cellClassName || ''}`}>
                        {renderValue(row[col.key], col, row)}
                      </td>
                    ))}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div className="px-4 py-3 border-t border-slate-100 bg-slate-50 flex items-center justify-between text-xs text-slate-600">
            <span>Page {safePagination.page} / {safePagination.totalPages} · {safePagination.total} rows</span>
            <div className="inline-flex items-center gap-2">
              <button
                className="border border-slate-200 rounded px-2 py-1.5 hover:bg-white disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
                disabled={safePagination.page <= 1}
                onClick={() => onPageChange(Math.max(1, safePagination.page - 1))}
              >
                <ChevronLeft size={12} />
              </button>
              <button
                className="border border-slate-200 rounded px-2 py-1.5 hover:bg-white disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
                disabled={safePagination.page >= safePagination.totalPages}
                onClick={() => onPageChange(Math.min(safePagination.totalPages, safePagination.page + 1))}
              >
                <ChevronRight size={12} />
              </button>
            </div>
          </div>
        </>
      )}
    </div>
  )
}
