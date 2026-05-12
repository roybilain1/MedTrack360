import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { monitoringApi } from '../services/monitoringApi.js'
import { DEFAULT_FILTERS, MONITORING_VIEWS } from '../types/monitoring.js'

const DEFAULT_PAGINATION = { page: 1, pageSize: 20, total: 0, totalPages: 1 }

function cloneFilters(base = DEFAULT_FILTERS) {
  return { ...base }
}

export function createViewFilterState(viewIds = MONITORING_VIEWS.map((v) => v.id), seed = DEFAULT_FILTERS) {
  return Object.fromEntries(viewIds.map((id) => [id, cloneFilters(seed)]))
}

export function updateViewFilterState(prev, viewId, update) {
  const current = prev?.[viewId] ? cloneFilters(prev[viewId]) : cloneFilters(DEFAULT_FILTERS)
  const nextForView = typeof update === 'function' ? update(current) : update
  return {
    ...prev,
    [viewId]: cloneFilters(nextForView || DEFAULT_FILTERS),
  }
}

export function createRequestState() {
  return { overviewSeq: 0, tableSeq: 0 }
}

export function nextOverviewSeq(requestState) {
  requestState.overviewSeq += 1
  return requestState.overviewSeq
}

export function nextTableSeq(requestState) {
  requestState.tableSeq += 1
  return requestState.tableSeq
}

export function isCurrentOverviewSeq(requestState, token) {
  return token === requestState.overviewSeq
}

export function isCurrentTableSeq(requestState, token) {
  return token === requestState.tableSeq
}

export function useMonitoringData(viewId) {
  const requestStateRef = useRef(createRequestState())
  const mountedRef = useRef(true)
  const [filtersByView, setFiltersByView] = useState(() => createViewFilterState())
  const [selectedPharmacyId, setSelectedPharmacyId] = useState(null)
  const [data, setData] = useState([])
  const [pagination, setPagination] = useState(DEFAULT_PAGINATION)
  const [meta, setMeta] = useState(null)
  const [rules, setRules] = useState(null)
  const [scope, setScope] = useState(null)
  const [overview, setOverview] = useState(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState(null)

  const filters = useMemo(() => {
    return filtersByView[viewId] || DEFAULT_FILTERS
  }, [filtersByView, viewId])

  const setFilters = useCallback((update) => {
    setFiltersByView((prev) => updateViewFilterState(prev, viewId, update))
  }, [viewId])

  const fetchOverview = useCallback(async () => {
    const seq = nextOverviewSeq(requestStateRef.current)
    try {
      const result = await monitoringApi.getOverview()
      if (!mountedRef.current || !isCurrentOverviewSeq(requestStateRef.current, seq)) return
      setOverview(result?.data || null)
    } catch {
      if (!mountedRef.current || !isCurrentOverviewSeq(requestStateRef.current, seq)) return
      setOverview(null)
    }
  }, [])

  const load = useCallback(async () => {
    const seq = nextTableSeq(requestStateRef.current)
    setLoading(true)
    setError(null)

    try {
      let response
      switch (viewId) {
        case 'stock':
          // Show every medicine of every pharmacy in one page so the
          // ministry can see all stock at once without paginating.
          response = await monitoringApi.getStock({ ...filters, page: 1, pageSize: 500 })
          break
        case 'pricing':
          response = await monitoringApi.getPricing(filters)
          break
        case 'hoarding':
          response = await monitoringApi.getHoardingAlerts(filters)
          break
        case 'sync':
          response = await monitoringApi.getSyncHealth(filters)
          break
        case 'medicineHistory':
          if (!String(filters.medicine || '').trim()) {
            response = { data: [], pagination: DEFAULT_PAGINATION, meta: { empty_reason: 'medicine_required' } }
          } else {
            response = await monitoringApi.getMedicineHistory(filters)
          }
          break
        case 'pharmacyAudit':
          response = await monitoringApi.getPharmacyAudit(filters)
          break
        case 'priceHistory':
          response = await monitoringApi.getPriceHistory(filters)
          break
        default:
          response = { data: [], pagination: DEFAULT_PAGINATION }
      }

      if (!mountedRef.current || !isCurrentTableSeq(requestStateRef.current, seq)) return
      setData(Array.isArray(response?.data) ? response.data : [])
      setPagination(response?.pagination || DEFAULT_PAGINATION)
      setMeta(response?.meta || null)
      setRules(response?.rules || null)
      setScope(response?.scope || null)
    } catch (e) {
      if (!mountedRef.current || !isCurrentTableSeq(requestStateRef.current, seq)) return
      setError(e.message)
      setMeta(null)
      setRules(null)
      setScope(null)
    } finally {
      if (mountedRef.current && isCurrentTableSeq(requestStateRef.current, seq)) {
        setLoading(false)
      }
    }
  }, [viewId, filters])

  useEffect(() => {
    mountedRef.current = true
    fetchOverview()
    return () => {
      mountedRef.current = false
    }
  }, [fetchOverview])

  useEffect(() => {
    load()
  }, [load, viewId])

  return {
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
    reload: load,
    selectedPharmacyId,
    setSelectedPharmacyId,
  }
}
