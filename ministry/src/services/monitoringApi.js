import { WEB_API } from '../config/api.js'
import {
  coerceDate,
  coerceNumber,
  coerceString,
} from '../utils/formatters.js'

// ────────────────────────────────────────────────────────────────────────────
// API CLIENT UTILITIES
// ────────────────────────────────────────────────────────────────────────────

function buildQuery(params = {}) {
  const qp = new URLSearchParams()
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== null && value !== '') {
      qp.set(key, String(value))
    }
  }
  const query = qp.toString()
  return query ? `?${query}` : ''
}

function getAuthHeaders() {
  const token = globalThis?.sessionStorage?.getItem?.('auth_token') || 'dev-admin-token'
  return { Authorization: `Bearer ${token}` }
}

async function safeParseJson(res) {
  const text = await res.text()
  if (!text) return {}
  try {
    return JSON.parse(text)
  } catch {
    return { raw: text }
  }
}

export function normalizeApiResponse(json, { defaultData, defaultPagination } = {}) {
  const obj = json && typeof json === 'object' ? json : {}
  return {
    ...obj,
    status: typeof obj.status === 'string' ? obj.status : 'success',
    data: obj.data ?? defaultData,
    pagination: obj.pagination ?? defaultPagination,
  }
}

async function fetchWithErrorHandling(path, options = {}) {
  const url = `${WEB_API}${path}`
  const headers = {
    'Content-Type': 'application/json',
    ...getAuthHeaders(),
    ...options.headers,
  }

  const res = await fetch(url, {
    ...options,
    headers,
  })

  const json = await safeParseJson(res)

  if (!res.ok) {
    if (res.status === 401) throw new Error('Unauthorized: Please log in')
    if (res.status === 403) throw new Error('Forbidden: Access denied')
    throw new Error(json?.error || json?.message || `HTTP ${res.status}: ${res.statusText}`)
  }

  if (json?.status !== 'success' && !json?.data) {
    throw new Error(json?.error || 'Unknown API error')
  }

  return normalizeApiResponse(json)
}

async function fetchJson(path, params = {}) {
  const query = buildQuery(params)
  return fetchWithErrorHandling(`/monitoring${path}${query}`)
}

async function fetchWebJson(path, params = {}) {
  const query = buildQuery(params)
  return fetchWithErrorHandling(`${path}${query}`)
}

// ────────────────────────────────────────────────────────────────────────────
// DTO ADAPTERS: Normalize inconsistent response formats
// ────────────────────────────────────────────────────────────────────────────

function normalizeRegistryItem(item) {
  const base = item && typeof item === 'object' ? item : {}
  return {
    id: base.id,
    barcode: coerceString(base.barcode),
    reg_number: coerceString(base.reg_number),
    trade_name: coerceString(base.trade_name),
    dosage: coerceString(base.dosage),
    category: coerceString(base.category),
    moph_ceiling: coerceNumber(base.moph_ceiling),
    stock_units: coerceNumber(base.stock_units),
    last_sync: coerceDate(base.last_sync)?.toISOString() || null,
    stock_status: coerceString(base.stock_status) || 'safe',
    threshold: base.threshold == null ? null : coerceNumber(base.threshold, null),
  }
}

function normalizeShortageItem(item) {
  const base = item && typeof item === 'object' ? item : {}
  return {
    id: base.id,
    barcode: coerceString(base.barcode),
    medication_name: coerceString(base.medication_name || base.trade_name || base.name, 'Unknown'),
    category: coerceString(base.category, 'Uncategorized'),
    stock_units: coerceNumber(base.stock_units),
    threshold: coerceNumber(base.threshold),
    status: coerceString(base.status) || 'safe',
    region: coerceString(base.region, 'Unknown'),
    last_sync: coerceDate(base.last_sync || base.updated_at)?.toISOString() || 'N/A',
    pharmacy_name: coerceString(base.pharmacy_name, 'Unknown Pharmacy'),
    license_number: coerceString(base.license_number, 'N/A'),
  }
}

function normalizeAuditLog(item) {
  const base = item && typeof item === 'object' ? item : {}
  return {
    id: base.id,
    event_id: coerceString(base.event_id),
    event_type: coerceString(base.event_type),
    pharmacy_name: coerceString(base.pharmacy_name, '—'),
    hwid: coerceString(base.hwid, '—'),
    license_number: coerceString(base.license_number, '—'),
    region: coerceString(base.region, '—'),
    item_name: coerceString(base.item_name, '—'),
    registry_price: coerceNumber(base.registry_price),
    charged_price: base.charged_price == null ? null : coerceNumber(base.charged_price, null),
    unit_count: coerceNumber(base.unit_count),
    created_at: coerceDate(base.created_at)?.toISOString() || null,
    metadata: base.metadata && typeof base.metadata === 'object' ? base.metadata : {},
  }
}

function normalizeAuditFeedItem(item) {
  const base = item && typeof item === 'object' ? item : {}
  const quantityDelta = base.quantity_delta == null ? null : coerceNumber(base.quantity_delta, null)
  const regulated = base.regulated_price_minor == null ? null : coerceNumber(base.regulated_price_minor, null)
  const actual = base.actual_price_minor == null ? null : coerceNumber(base.actual_price_minor, null)
  const oldPrice = base.old_price_minor == null ? null : coerceNumber(base.old_price_minor, null)
  const newPrice = base.new_price_minor == null ? null : coerceNumber(base.new_price_minor, null)

  return {
    event_uuid: coerceString(base.event_uuid || base.event_id || base.id),
    event_family: coerceString(base.event_family) || 'operational',
    event_type: coerceString(base.event_type) || 'event',
    event_title: coerceString(base.event_title) || 'Operational event logged',
    event_summary: coerceString(base.event_summary),
    severity: coerceString(base.severity) || 'info',
    pharmacy_id: base.pharmacy_id == null ? null : coerceNumber(base.pharmacy_id, null),
    pharmacy_name: coerceString(base.pharmacy_name),
    license_number: coerceString(base.license_number),
    hwid: coerceString(base.hwid),
    region: coerceString(base.region),
    barcode: coerceString(base.barcode),
    medicine_name: coerceString(base.medicine_name),
    quantity_delta: quantityDelta,
    regulated_price_minor: regulated,
    actual_price_minor: actual,
    old_price_minor: oldPrice,
    new_price_minor: newPrice,
    price_delta_minor: base.price_delta_minor == null ? null : coerceNumber(base.price_delta_minor, null),
    markup_pct: base.markup_pct == null ? null : coerceNumber(base.markup_pct, null),
    reason: coerceString(base.reason),
    source: coerceString(base.source) || 'system',
    outcome: coerceString(base.outcome),
    linked_alert_id: coerceString(base.linked_alert_id),
    chain_key: coerceString(base.chain_key),
    event_time: normalizeMonitoringDate(base.event_time || base.created_at),
    is_system_event: Boolean(base.is_system_event),
    metadata: safeObject(base.metadata),
    id: coerceString(base.event_uuid || base.event_id || base.id),
  }
}

function normalizePriceHistoryItem(item) {
  const base = item && typeof item === 'object' ? item : {}
  const previous = base.previous_price_minor == null ? null : coerceNumber(base.previous_price_minor, null)
  const next = base.new_price_minor == null ? null : coerceNumber(base.new_price_minor, null)
  return {
    id: coerceString(base.event_id || base.history_uuid || base.id),
    event_id: coerceString(base.event_id || base.history_uuid || base.id),
    source_family: coerceString(base.source_family) || 'price_history',
    event_type: coerceString(base.event_type) || 'price_change',
    source_label: coerceString(base.source_label) || 'Price history',
    pharmacy_id: base.pharmacy_id == null ? null : coerceNumber(base.pharmacy_id, null),
    pharmacy_name: coerceString(base.pharmacy_name),
    license_number: coerceString(base.license_number),
    hwid: coerceString(base.hwid),
    region: coerceString(base.region),
    barcode: coerceString(base.barcode),
    medicine_name: coerceString(base.medicine_name),
    previous_price_minor: previous,
    new_price_minor: next,
    currency_code: coerceString(base.currency_code) || 'USD',
    source: coerceString(base.source) || 'price_history',
    changed_by: coerceString(base.changed_by),
    changed_at: normalizeMonitoringDate(base.changed_at),
    regulated_price_minor: base.regulated_price_minor == null ? null : coerceNumber(base.regulated_price_minor, null),
    change_pct: base.change_pct == null ? null : coerceNumber(base.change_pct, null),
    status: coerceString(base.status) || 'ok',
    suspicious_jump: Boolean(base.suspicious_jump),
    metadata: safeObject(base.metadata),
  }
}

function normalizePharmacy(item) {
  const base = item && typeof item === 'object' ? item : {}
  return {
    id: base.id,
    name: coerceString(base.name),
    hwid: coerceString(base.hwid),
    license_number: coerceString(base.license_number),
    region: coerceString(base.region),
    status: coerceString(base.status),
    last_seen: coerceDate(base.last_seen)?.toISOString() || null,
    latency_ms: base.latency_ms == null ? null : coerceNumber(base.latency_ms, null),
    sync_version: coerceString(base.sync_version),
    sync_pct: base.sync_pct == null ? null : coerceNumber(base.sync_pct, null),
    last_sync_up: coerceDate(base.last_sync_up)?.toISOString() || null,
    last_sync_down: coerceDate(base.last_sync_down)?.toISOString() || null,
    pending_outbox: base.pending_outbox == null ? 0 : coerceNumber(base.pending_outbox),
    open_compliance_alerts: base.open_compliance_alerts == null ? 0 : coerceNumber(base.open_compliance_alerts),
    registration_status: coerceString(base.registration_status),
  }
}

function normalizeSettingsData(data) {
  const payload = data && typeof data === 'object' ? data : {}
  const terminalsSource = Array.isArray(payload.terminals) ? payload.terminals : payload.nodes
  const priceEventsSource = Array.isArray(payload.recent_price_events)
    ? payload.recent_price_events
    : payload.price_alerts

  return {
    terminals: Array.isArray(terminalsSource)
      ? terminalsSource.map(normalizePharmacy)
      : [],
    terminal_summary: payload.terminal_summary && typeof payload.terminal_summary === 'object'
      ? {
          total_terminals: coerceNumber(payload.terminal_summary.total_terminals),
          online_count: coerceNumber(payload.terminal_summary.online_count),
          offline_count: coerceNumber(payload.terminal_summary.offline_count),
          degraded_count: coerceNumber(payload.terminal_summary.degraded_count),
          unknown_version_count: coerceNumber(payload.terminal_summary.unknown_version_count),
          version_mismatch_count: coerceNumber(payload.terminal_summary.version_mismatch_count),
          never_seen_count: coerceNumber(payload.terminal_summary.never_seen_count),
          never_synced_count: coerceNumber(payload.terminal_summary.never_synced_count),
          expected_sync_version: coerceString(payload.terminal_summary.expected_sync_version),
        }
      : {},
    pricing_policy: payload.pricing_policy && typeof payload.pricing_policy === 'object'
      ? {
          regulated_medicine_count: coerceNumber(payload.pricing_policy.regulated_medicine_count),
          high_price_violations: coerceNumber(payload.pricing_policy.high_price_violations),
          last_registry_sync: coerceDate(payload.pricing_policy.last_registry_sync)?.toISOString() || null,
          last_price_event_at: coerceDate(payload.pricing_policy.last_price_event_at)?.toISOString() || null,
        }
      : {},
    recent_price_events: Array.isArray(priceEventsSource)
      ? priceEventsSource.map((item) => ({
          item_name: coerceString(item?.item_name, 'Unknown medicine'),
          barcode: coerceString(item?.barcode),
          pharmacy_name: coerceString(item?.pharmacy_name),
          license_number: coerceString(item?.license_number),
          registry_price: coerceNumber(item?.registry_price),
          charged_price: coerceNumber(item?.charged_price),
          event_type: coerceString(item?.event_type),
          status: coerceString(item?.status),
          created_at: coerceDate(item?.created_at)?.toISOString() || null,
        }))
      : [],
    adjustment_reasons: Array.isArray(payload.adjustment_reasons)
      ? payload.adjustment_reasons.map((reason) => String(reason))
      : [],
    recent_adjustments: Array.isArray(payload.recent_adjustments)
      ? payload.recent_adjustments.map((item) => ({
          pharmacy_name: coerceString(item?.pharmacy_name),
          item_name: coerceString(item?.item_name),
          unit_count: coerceNumber(item?.unit_count),
          reason: coerceString(item?.reason, 'Manual adjustment'),
          source: coerceString(item?.source),
          created_at: coerceDate(item?.created_at)?.toISOString() || null,
        }))
      : [],
    adjustment_summary: payload.adjustment_summary && typeof payload.adjustment_summary === 'object'
      ? {
          total_adjustments: coerceNumber(payload.adjustment_summary.total_adjustments),
          adjustments_last_30d: coerceNumber(payload.adjustment_summary.adjustments_last_30d),
          last_adjustment_at: coerceDate(payload.adjustment_summary.last_adjustment_at)?.toISOString() || null,
        }
      : {},
    top_adjustment_reasons: Array.isArray(payload.top_adjustment_reasons)
      ? payload.top_adjustment_reasons.map((row) => ({
          reason: coerceString(row?.reason, 'Unspecified'),
          usage_count: coerceNumber(row?.usage_count),
        }))
      : [],

    // Backward-compatible aliases for older consumers.
    nodes: Array.isArray(terminalsSource)
      ? terminalsSource.map(normalizePharmacy)
      : [],
    price_alerts: Array.isArray(priceEventsSource)
      ? priceEventsSource.map((item) => ({
          item_name: coerceString(item?.item_name, 'Unknown medicine'),
          registry_price: coerceNumber(item?.registry_price),
          charged_price: coerceNumber(item?.charged_price),
          created_at: coerceDate(item?.created_at)?.toISOString() || null,
        }))
      : [],
  }
}

function toArray(value) {
  if (Array.isArray(value)) return value
  if (value && typeof value === 'object') {
    if (Array.isArray(value.rows)) return value.rows
    if (Array.isArray(value.items)) return value.items
    if (Array.isArray(value.results)) return value.results
  }
  return []
}

function normalizeRegistrationRequest(item) {
  const base = item && typeof item === 'object' ? item : {}
  return {
    id: base.id,
    reg_id: coerceString(base.reg_id || base.registration_id),
    name: coerceString(base.name || base.pharmacy_name || base.owner, 'Unnamed request'),
    owner: coerceString(base.owner || base.requested_by || base.contact_name, '—'),
    region: coerceString(base.region, '—'),
    submitted_date: coerceString(base.submitted_date || base.created_at),
    status: coerceString(base.status, 'pending_review'),
    docs_count: coerceNumber(base.docs_count),
    missing_count: coerceNumber(base.missing_count),
  }
}

function normalizeMedicineRequest(item) {
  const base = item && typeof item === 'object' ? item : {}
  return {
    id: base.id,
    request_uuid: coerceString(base.request_uuid),
    barcode: coerceString(base.barcode),
    requested_name: coerceString(base.requested_name || base.trade_name || base.name, 'Unnamed medicine'),
    generic_name: coerceString(base.generic_name),
    dosage: coerceString(base.dosage),
    category: coerceString(base.category),
    proposed_price_minor: base.proposed_price_minor == null ? null : coerceNumber(base.proposed_price_minor, null),
    stock_units: coerceNumber(base.stock_units),
    expiry: coerceString(base.expiry),
    request_status: coerceString(base.request_status, 'pending_review'),
    review_notes: coerceString(base.review_notes),
    official_medicine_id: base.official_medicine_id == null ? null : coerceNumber(base.official_medicine_id, null),
    pharmacy_name: coerceString(base.pharmacy_name, 'Unknown Pharmacy'),
    license_number: coerceString(base.license_number, 'N/A'),
    region: coerceString(base.region, 'Unknown'),
    created_at: coerceDate(base.created_at)?.toISOString() || null,
    updated_at: coerceDate(base.updated_at)?.toISOString() || null,
    reviewed_at: coerceDate(base.reviewed_at)?.toISOString() || null,
    metadata: safeObject(base.metadata),
  }
}

function normalizeHoardingTrendRow(item) {
  const base = item && typeof item === 'object' ? item : {}
  return {
    week: coerceString(base.week, 'N/A'),
    incoming: coerceNumber(base.incoming),
    outgoing: coerceNumber(base.outgoing),
  }
}

function normalizeChainOfCustody(data) {
  const base = data && typeof data === 'object' ? data : {}
  return {
    ...base,
    barcode: coerceString(base.barcode),
    trade_name: coerceString(base.trade_name || base.medication_name || base.name),
    dosage: coerceString(base.dosage),
    reg_number: coerceString(base.reg_number || base.official_code),
    manufacturer: coerceString(base.manufacturer),
    category: coerceString(base.category),
    updated_at: coerceDate(base.updated_at)?.toISOString() || null,
  }
}

function normalizeHoardingAnomaly(item) {
  const base = item && typeof item === 'object' ? item : {}
  return {
    id: base.id,
    pharmacy_name: coerceString(base.pharmacy_name),
    license_number: coerceString(base.license_number),
    hwid: coerceString(base.hwid),
    region: coerceString(base.region),
    incoming_units: coerceNumber(base.incoming_units),
    outgoing_units: coerceNumber(base.outgoing_units),
    ratio: coerceNumber(base.ratio),
    score: coerceNumber(base.score),
    flag: coerceString(base.flag || base.status) || 'watch',
    flagged_items: Array.isArray(base.flagged_items) ? base.flagged_items : [],
  }
}

function normalizeMonitoringNumber(value, fallback = 0) {
  return coerceNumber(value, fallback)
}

function normalizeMonitoringDate(value) {
  return coerceDate(value)?.toISOString() || null
}

function safeObject(value) {
  if (value && typeof value === 'object' && !Array.isArray(value)) return value
  if (typeof value === 'string' && value.trim()) {
    try {
      const parsed = JSON.parse(value)
      return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : {}
    } catch {
      return {}
    }
  }
  return {}
}

function normalizeOverview(data) {
  const payload = data && typeof data === 'object' ? data : {}
  return {
    high_price_count: normalizeMonitoringNumber(payload.high_price_count),
    hoarding_count: normalizeMonitoringNumber(payload.hoarding_count),
    unhealthy_pharmacies: normalizeMonitoringNumber(payload.unhealthy_pharmacies),
    total_pharmacies: normalizeMonitoringNumber(payload.total_pharmacies),
    open_alerts: normalizeMonitoringNumber(payload.open_alerts),
  }
}

function normalizeMonitoringRow(view, item) {
  const base = item && typeof item === 'object' ? item : {}
  switch (view) {
    case 'stock':
      return {
        ...base,
        pharmacy_id: base.pharmacy_id == null ? null : normalizeMonitoringNumber(base.pharmacy_id, null),
        pharmacy_name: coerceString(base.pharmacy_name) || 'Unknown pharmacy',
        license_number: coerceString(base.license_number),
        hwid: coerceString(base.hwid),
        region: coerceString(base.region) || 'Unknown',
        medicine_name: coerceString(base.medicine_name) || 'Unknown medicine',
        dosage: coerceString(base.dosage),
        barcode: coerceString(base.barcode),
        category: coerceString(base.category) || 'Uncategorized',
        stock_units: normalizeMonitoringNumber(base.stock_units),
        sales_30d: normalizeMonitoringNumber(base.sales_30d),
        purchases_30d: normalizeMonitoringNumber(base.purchases_30d),
        days_of_stock: base.days_of_stock == null ? null : normalizeMonitoringNumber(base.days_of_stock, null),
        avg_daily_sales: base.avg_daily_sales == null ? null : normalizeMonitoringNumber(base.avg_daily_sales, null),
        threshold_units: base.threshold_units == null ? null : normalizeMonitoringNumber(base.threshold_units, null),
        coverage_basis: coerceString(base.coverage_basis) || 'unknown',
        status_basis: coerceString(base.status_basis),
        risk_rank: normalizeMonitoringNumber(base.risk_rank),
        repeated_accumulation_count: normalizeMonitoringNumber(base.repeated_accumulation_count),
        status: coerceString(base.status) || 'unknown',
        current_price_minor: base.current_price_minor == null ? null : normalizeMonitoringNumber(base.current_price_minor, null),
        regulated_price_minor: base.regulated_price_minor == null ? null : normalizeMonitoringNumber(base.regulated_price_minor, null),
        expiry_at: base.expiry_at == null ? null : coerceString(base.expiry_at),
        stock_state_label: coerceString(base.stock_state_label),
      }
    case 'hoarding':
      return {
        ...base,
        pharmacy_name: coerceString(base.pharmacy_name) || 'Unknown pharmacy',
        license_number: coerceString(base.license_number),
        hwid: coerceString(base.hwid),
        region: coerceString(base.region) || 'Unknown',
        medicine_name: coerceString(base.medicine_name),
        barcode: coerceString(base.barcode),
        category: coerceString(base.category) || 'Uncategorized',
        stock_units: normalizeMonitoringNumber(base.stock_units),
        sales_30d: normalizeMonitoringNumber(base.sales_30d),
        purchases_30d: normalizeMonitoringNumber(base.purchases_30d),
        days_of_stock: base.days_of_stock == null ? null : normalizeMonitoringNumber(base.days_of_stock, null),
        repeated_accumulation_count: normalizeMonitoringNumber(base.repeated_accumulation_count),
        alert_type: coerceString(base.alert_type || base.status) || 'watch',
        status: coerceString(base.status || base.alert_type) || 'watch',
      }
    case 'pricing':
      return {
        ...base,
        pharmacy_name: coerceString(base.pharmacy_name) || 'Unknown pharmacy',
        medicine_name: coerceString(base.medicine_name) || 'Unknown medicine',
        barcode: coerceString(base.barcode),
        regulated_price_minor: base.regulated_price_minor == null ? null : normalizeMonitoringNumber(base.regulated_price_minor, null),
        avg_selling_price_minor: base.avg_selling_price_minor == null ? null : normalizeMonitoringNumber(base.avg_selling_price_minor, null),
        markup_pct: base.markup_pct == null ? null : normalizeMonitoringNumber(base.markup_pct, null),
        status: coerceString(base.status) || 'ok',
      }
    case 'sync':
      return {
        ...base,
        pharmacy_name: coerceString(base.pharmacy_name) || 'Unknown pharmacy',
        license_number: coerceString(base.license_number),
        region: coerceString(base.region) || 'Unknown',
        pharmacy_status: coerceString(base.pharmacy_status || base.status) || 'unknown',
        health_status: coerceString(base.health_status || base.status) || 'healthy',
        hours_since_sync: normalizeMonitoringNumber(base.hours_since_sync),
        pending_outbox: normalizeMonitoringNumber(base.pending_outbox),
        open_alerts: normalizeMonitoringNumber(base.open_alerts),
        sync_pct: base.sync_pct == null ? null : normalizeMonitoringNumber(base.sync_pct, null),
        latency_ms: base.latency_ms == null ? null : normalizeMonitoringNumber(base.latency_ms, null),
        status: coerceString(base.status || base.health_status) || 'healthy',
      }
    case 'medicineHistory':
      return {
        ...base,
        source: coerceString(base.source) || 'unknown',
        medicine_name: coerceString(base.medicine_name) || 'Unknown medicine',
        barcode: coerceString(base.barcode),
        pharmacy_name: coerceString(base.pharmacy_name) || 'Unknown pharmacy',
        event_type: coerceString(base.event_type) || 'unknown',
        quantity_delta: normalizeMonitoringNumber(base.quantity_delta),
        unit_price_minor: base.unit_price_minor == null ? null : normalizeMonitoringNumber(base.unit_price_minor, null),
        event_time: normalizeMonitoringDate(base.event_time),
      }
    case 'pharmacyAudit':
      return normalizeAuditFeedItem(base)
    case 'priceHistory':
      return {
        ...base,
        pharmacy_name: coerceString(base.pharmacy_name) || 'Unknown pharmacy',
        medicine_name: coerceString(base.medicine_name) || 'Unknown medicine',
        barcode: coerceString(base.barcode),
        previous_price_minor: base.previous_price_minor == null ? null : normalizeMonitoringNumber(base.previous_price_minor, null),
        new_price_minor: base.new_price_minor == null ? null : normalizeMonitoringNumber(base.new_price_minor, null),
        change_pct: base.change_pct == null ? null : normalizeMonitoringNumber(base.change_pct, null),
        suspicious_jump: Boolean(base.suspicious_jump),
        changed_at: normalizeMonitoringDate(base.changed_at),
      }
    default:
      return base
  }
}

// ────────────────────────────────────────────────────────────────────────────
// CENTRALIZED MONITORING API
// ────────────────────────────────────────────────────────────────────────────

export const monitoringApi = {
  // Compliance Monitoring endpoints
  getOverview(params) {
    return fetchJson('/overview', params).then((res) => ({
      ...res,
      data: normalizeOverview(res?.data),
    }))
  },
  getStock(params) {
    return fetchJson('/stock', params).then((res) => ({
      ...res,
      data: Array.isArray(res?.data) ? res.data.map((item) => normalizeMonitoringRow('stock', item)) : [],
      rules: res?.rules && typeof res.rules === 'object' ? res.rules : {},
      scope: res?.scope && typeof res.scope === 'object' ? res.scope : {},
    }))
  },
  getPricing(params) {
    return fetchJson('/pricing', params).then((res) => ({
      ...res,
      data: Array.isArray(res?.data) ? res.data.map((item) => normalizeMonitoringRow('pricing', item)) : [],
    }))
  },
  getHoardingAlerts(params) {
    return fetchJson('/hoarding-alerts', params).then((res) => ({
      ...res,
      data: Array.isArray(res?.data) ? res.data.map((item) => normalizeMonitoringRow('hoarding', item)) : [],
    }))
  },
  getSyncHealth(params) {
    return fetchJson('/sync-health', params).then((res) => ({
      ...res,
      data: Array.isArray(res?.data) ? res.data.map((item) => normalizeMonitoringRow('sync', item)) : [],
    }))
  },
  getMedicineHistory(params) {
    return fetchJson('/medicine-history', params).then((res) => ({
      ...res,
      data: Array.isArray(res?.data) ? res.data.map((item) => normalizeMonitoringRow('medicineHistory', item)) : [],
    }))
  },
  getPharmacyAudit(params) {
    return fetchJson('/pharmacy-audit', params).then((res) => ({
      ...res,
      data: Array.isArray(res?.data) ? res.data.map((item) => normalizeMonitoringRow('pharmacyAudit', item)) : [],
    }))
  },
  getAuditFeed(params) {
    return fetchJson('/audit-feed', params).then((res) => ({
      ...res,
      data: Array.isArray(res?.data) ? res.data.map((item) => normalizeAuditFeedItem(item)) : [],
    }))
  },
  getPriceHistory(params) {
    return fetchJson('/price-history', params).then((res) => ({
      ...res,
      data: Array.isArray(res?.data) ? res.data.map((item) => normalizePriceHistoryItem(item)) : [],
    }))
  },

  // Shortage Surveillance endpoints
  getShortage(params) {
    return fetchWebJson('/shortage', params).then((res) => ({
      ...res,
      data: Array.isArray(res?.data) ? res.data.map(normalizeShortageItem) : [],
    }))
  },
  getPharmacies(params) {
    return fetchWebJson('/pharmacies', params).then((res) => ({
      ...res,
      data: Array.isArray(res?.data) ? res.data.map(normalizePharmacy) : [],
    }))
  },

  // Hoarding Analytics endpoints
  getHoardingAnomalies(params) {
    return fetchWebJson('/hoarding-anomalies', params).then((res) => ({
      ...res,
      data: Array.isArray(res?.data) ? res.data.map(normalizeHoardingAnomaly) : [],
    }))
  },
  getHoardingTrend(id) {
    return fetchWebJson(`/hoarding-anomalies/${encodeURIComponent(id)}/trend`).then((res) => ({
      ...res,
      data: toArray(res?.data).map(normalizeHoardingTrendRow),
    }))
  },
  getChainOfCustody(barcode) {
    return fetchWebJson(`/chain-of-custody/${encodeURIComponent(barcode)}`).then((res) => ({
      ...res,
      data: normalizeChainOfCustody(res?.data),
    }))
  },

  // Master Registry endpoints (NEW - moved from direct fetch)
  getRegistry(params) {
    return fetchWebJson('/registry', params).then((res) => ({
      ...res,
      data: Array.isArray(res?.data) ? res.data.map(normalizeRegistryItem) : [],
    }))
  },
  updateRegistryPrice(id, price) {
    return fetchWithErrorHandling(`/registry/${encodeURIComponent(id)}/price`, {
      method: 'POST',
      body: JSON.stringify({ price: Number(price) }),
    })
  },
  adjustRegistryStock(id, delta, reason) {
    return fetchWithErrorHandling(`/registry/${encodeURIComponent(id)}/adjust-stock`, {
      method: 'POST',
      body: JSON.stringify({ delta: Number(delta), reason }),
    })
  },
  getSettingsData(params) {
    return fetchWebJson('/settings-data', params).then((res) => ({
      ...res,
      data: normalizeSettingsData(res?.data),
    }))
  },
  notifyPricingSyncToPos() {
    return fetchWithErrorHandling('/sync-pricing-to-pos', {
      method: 'POST',
      body: JSON.stringify({}),
    })
  },

  // Audit Trail endpoints (NEW - moved from direct fetch)
  getAuditLogs(params) {
    return fetchWebJson('/audit-logs', params).then((res) => ({
      ...res,
      data: Array.isArray(res?.data) ? res.data.map(normalizeAuditLog) : [],
    }))
  },
  getPriceViolationsSummary(params) {
    return fetchWebJson('/price-violations-summary', params).then((res) => ({
      ...res,
      data: Array.isArray(res?.data) ? res.data.map(normalizeAuditLog) : [],
    }))
  },
  createAuditLog(payload) {
    return fetchWithErrorHandling('/audit-logs', {
      method: 'POST',
      body: JSON.stringify(payload),
    })
  },

  // Sync Health endpoints
  getSyncHealthStatus(params) {
    return fetchWebJson('/sync-health', params).then((res) => ({
      ...res,
      data: toArray(res?.data).map(normalizePharmacy),
    }))
  },

  // Compliance Alerts endpoints
  getComplianceAlerts(params) {
    return fetchWebJson('/compliance-alerts', params).then((res) => ({
      ...res,
      data: toArray(res?.data),
    }))
  },

  // Pharmacy flagging endpoints
  flagPharmacy(pharmacyId, flagType, note) {
    return fetchWithErrorHandling(`/pharmacies/${encodeURIComponent(pharmacyId)}/flag`, {
      method: 'POST',
      body: JSON.stringify({ flag_type: flagType, note: note || '' }),
    })
  },

  // System Governance - Registration Requests endpoints (NEW)
  getRegistrationRequests(params) {
    return fetchWebJson('/registration-requests', params).then((res) => ({
      ...res,
      data: toArray(res?.data).map(normalizeRegistrationRequest),
    }))
  },
  approveRegistration(regId) {
    return fetchWithErrorHandling(`/registration-requests/${encodeURIComponent(regId)}/approve`, {
      method: 'POST',
      body: JSON.stringify({}),
    })
  },
  rejectRegistration(regId) {
    return fetchWithErrorHandling(`/registration-requests/${encodeURIComponent(regId)}/reject`, {
      method: 'POST',
      body: JSON.stringify({}),
    })
  },

  getMedicineRequests(params) {
    return fetchWebJson('/medicine-requests', params).then((res) => ({
      ...res,
      data: toArray(res?.data).map(normalizeMedicineRequest),
    }))
  },

  approveMedicineRequest(id, payload = {}) {
    return fetchWithErrorHandling(`/medicine-requests/${encodeURIComponent(id)}/approve`, {
      method: 'POST',
      body: JSON.stringify(payload),
    })
  },

  rejectMedicineRequest(id, payload = {}) {
    return fetchWithErrorHandling(`/medicine-requests/${encodeURIComponent(id)}/reject`, {
      method: 'POST',
      body: JSON.stringify(payload),
    })
  },

  // Stock sync endpoint
  syncStockToPOS() {
    return fetchWithErrorHandling('/sync-stock-to-pos', {
      method: 'POST',
      body: JSON.stringify({}),
    })
  },
}

export const announcementsApi = {
  list({ includeInactive = false } = {}) {
    const query = includeInactive ? '?include_inactive=true' : ''
    return fetchWithErrorHandling(`/announcements${query}`)
  },
  create({ title, body, audience = 'both' }) {
    return fetchWithErrorHandling('/announcements', {
      method: 'POST',
      body: JSON.stringify({ title, body, audience }),
    })
  },
  deactivate(id) {
    return fetchWithErrorHandling(`/announcements/${encodeURIComponent(id)}/deactivate`, {
      method: 'PATCH',
    })
  },
}

export function exportRowsToCsv(filename, columns, rows) {
  const header = columns.map((col) => col.label).join(',')
  const lines = rows.map((row) =>
    columns
      .map((col) => {
        const value = row[col.key]
        if (value == null) return ''
        const str = typeof value === 'object' ? JSON.stringify(value) : String(value)
        return `"${str.replaceAll('"', '""')}"`
      })
      .join(',')
  )

  const blob = new Blob([[header, ...lines].join('\n')], { type: 'text/csv' })
  const a = document.createElement('a')
  a.href = URL.createObjectURL(blob)
  a.download = filename
  a.click()
  URL.revokeObjectURL(a.href)
}

export { buildQuery }
