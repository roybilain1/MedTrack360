import { coerceNumber, normalizeCurrencyMinor } from '../utils/formatters.js'

export const MONITORING_VIEWS = [
  { id: 'stock', label: 'Stock Oversight' },
  { id: 'pricing', label: 'Price Compliance' },
  { id: 'hoarding', label: 'Hoarding Alerts' },
  { id: 'sync', label: 'Sync Health' },
  { id: 'medicineHistory', label: 'Medicine History' },
  { id: 'pharmacyAudit', label: 'Pharmacy Audit Trail' },
  { id: 'priceHistory', label: 'Price History' },
]

export const DEFAULT_FILTERS = {
  pharmacy: '',
  medicine: '',
  region: '',
  status: '',
  from: '',
  to: '',
  page: 1,
  pageSize: 20,
  sortBy: '',
  sortDir: 'desc',
}

export function mapPagination(payload) {
  return {
    page: coerceNumber(payload?.page, 1),
    pageSize: coerceNumber(payload?.pageSize, 20),
    total: coerceNumber(payload?.total, 0),
    totalPages: coerceNumber(payload?.totalPages, 1),
  }
}

export { normalizeCurrencyMinor }
