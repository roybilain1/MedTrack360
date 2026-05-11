import { Calendar, Filter, Search, ArrowUpDown } from 'lucide-react'

export default function MonitoringFilters({ 
  filters, 
  onChange, 
  statusOptions = [], 
  sortOptions = [], 
  hidePharmacyFilter = false 
}) {
  function setField(key, value) {
    onChange((prev) => ({ ...prev, [key]: value, page: 1 }))
  }

  return (
    <div className="bg-white border border-slate-200 rounded-lg shadow-sm overflow-hidden">
      <div className="px-4 py-3 border-b border-slate-100 bg-slate-50">
        <h3 className="text-sm font-semibold text-slate-800">Filters</h3>
      </div>
      
      <div className="p-4 space-y-4">
        {/* Search row */}
        <div className={`grid ${hidePharmacyFilter ? 'grid-cols-1' : 'grid-cols-2'} gap-4`}>
          {!hidePharmacyFilter && (
            <label className="text-xs text-slate-700 font-medium">
              <div className="mb-2 inline-flex items-center gap-1"><Search size={12} />Pharmacy</div>
              <input className="w-full border border-slate-300 rounded px-3 py-2 text-xs placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-teal-500 focus:border-transparent" value={filters.pharmacy} onChange={(e) => setField('pharmacy', e.target.value)} placeholder="Name or license number" />
            </label>
          )}

          <label className="text-xs text-slate-700 font-medium">
            <div className="mb-2 inline-flex items-center gap-1"><Search size={12} />Medicine</div>
            <input className="w-full border border-slate-300 rounded px-3 py-2 text-xs placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-teal-500 focus:border-transparent" value={filters.medicine} onChange={(e) => setField('medicine', e.target.value)} placeholder="Barcode or trade name" />
          </label>
        </div>

        {/* Filter row */}
        <div className="grid grid-cols-3 gap-4">
          <label className="text-xs text-slate-700 font-medium">
            <div className="mb-2 inline-flex items-center gap-1"><Filter size={12} />Region</div>
            <input className="w-full border border-slate-300 rounded px-3 py-2 text-xs placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-teal-500 focus:border-transparent" value={filters.region} onChange={(e) => setField('region', e.target.value)} placeholder="All regions" />
          </label>

          <label className="text-xs text-slate-700 font-medium">
            <div className="mb-2 inline-flex items-center gap-1"><Filter size={12} />Status</div>
            <select className="w-full border border-slate-300 rounded px-3 py-2 text-xs focus:outline-none focus:ring-2 focus:ring-teal-500 focus:border-transparent bg-white" value={filters.status} onChange={(e) => setField('status', e.target.value)}>
              <option value="">All statuses</option>
              {statusOptions.map((opt) => (
                <option key={opt.value} value={opt.value}>{opt.label}</option>
              ))}
            </select>
          </label>

          <label className="text-xs text-slate-700 font-medium">
            <div className="mb-2 inline-flex items-center gap-1"><ArrowUpDown size={12} />Sort</div>
            <select className="w-full border border-slate-300 rounded px-3 py-2 text-xs focus:outline-none focus:ring-2 focus:ring-teal-500 focus:border-transparent bg-white" value={filters.sortBy} onChange={(e) => setField('sortBy', e.target.value)}>
              <option value="">Default</option>
              {sortOptions.map((opt) => (
                <option key={opt.value} value={opt.value}>{opt.label}</option>
              ))}
            </select>
          </label>
        </div>

        {/* Date range row */}
        <div className="grid grid-cols-2 gap-4">
          <label className="text-xs text-slate-700 font-medium">
            <div className="mb-2 inline-flex items-center gap-1"><Calendar size={12} />From</div>
            <input type="date" className="w-full border border-slate-300 rounded px-3 py-2 text-xs focus:outline-none focus:ring-2 focus:ring-teal-500 focus:border-transparent" value={filters.from} onChange={(e) => setField('from', e.target.value)} />
          </label>

          <label className="text-xs text-slate-700 font-medium">
            <div className="mb-2 inline-flex items-center gap-1"><Calendar size={12} />To</div>
            <input type="date" className="w-full border border-slate-300 rounded px-3 py-2 text-xs focus:outline-none focus:ring-2 focus:ring-teal-500 focus:border-transparent" value={filters.to} onChange={(e) => setField('to', e.target.value)} />
          </label>
        </div>

        {/* Reset button */}
        <div className="pt-2 border-t border-slate-200">
          <button
            className="text-xs text-teal-600 hover:text-teal-700 font-medium transition-colors"
            onClick={() =>
              onChange((prev) => ({
                ...prev,
                pharmacy: hidePharmacyFilter ? prev.pharmacy : '',
                medicine: '',
                region: '',
                status: '',
                from: '',
                to: '',
                sortBy: '',
                sortDir: 'desc',
                page: 1,
              }))
            }
          >
            Reset
          </button>
        </div>
      </div>
    </div>
  )
}
