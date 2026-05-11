import test from 'node:test'
import assert from 'node:assert/strict'

import { buildQuery, normalizeApiResponse, monitoringApi } from './monitoringApi.js'
import { mapPagination, normalizeCurrencyMinor } from '../types/monitoring.js'

test('buildQuery omits empty params and serializes valid ones', () => {
  const query = buildQuery({
    pharmacy: 'Al-Amin',
    medicine: '',
    region: 'Beirut',
    page: 2,
    status: null,
    pageSize: 20,
  })

  assert.equal(query.includes('pharmacy=Al-Amin'), true)
  assert.equal(query.includes('region=Beirut'), true)
  assert.equal(query.includes('page=2'), true)
  assert.equal(query.includes('pageSize=20'), true)
  assert.equal(query.includes('medicine='), false)
  assert.equal(query.includes('status='), false)
})

test('mapPagination normalizes pagination payload', () => {
  const mapped = mapPagination({ page: '2', pageSize: '25', total: '100', totalPages: '4' })
  assert.deepEqual(mapped, { page: 2, pageSize: 25, total: 100, totalPages: 4 })
})

test('normalizeCurrencyMinor formats minor units', () => {
  assert.equal(normalizeCurrencyMinor(255), '2.55')
  assert.equal(normalizeCurrencyMinor('1000'), '10.00')
  assert.equal(normalizeCurrencyMinor('x'), '-')
})

test('normalizeApiResponse backfills missing envelope fields', () => {
  const normalized = normalizeApiResponse({}, {
    defaultData: [],
    defaultPagination: { page: 1, pageSize: 20, total: 0, totalPages: 1 },
  })

  assert.equal(normalized.status, 'success')
  assert.deepEqual(normalized.data, [])
  assert.deepEqual(normalized.pagination, { page: 1, pageSize: 20, total: 0, totalPages: 1 })
})

test('getRegistrationRequests normalizes array-like payloads for governance UI', async () => {
  const originalFetch = globalThis.fetch

  globalThis.fetch = async () => ({
    ok: true,
    status: 200,
    statusText: 'OK',
    text: async () => JSON.stringify({
      status: 'success',
      data: {
        rows: [
          {
            id: 11,
            registration_id: 'REG-11',
            pharmacy_name: 'Apex Pharmacy',
            requested_by: 'Owner Name',
            created_at: '2026-04-08T00:00:00.000Z',
          },
        ],
      },
    }),
  })

  try {
    const res = await monitoringApi.getRegistrationRequests()
    assert.equal(Array.isArray(res.data), true)
    assert.equal(res.data.length, 1)
    assert.equal(res.data[0].reg_id, 'REG-11')
    assert.equal(res.data[0].name, 'Apex Pharmacy')
    assert.equal(res.data[0].owner, 'Owner Name')
    assert.equal(res.data[0].status, 'pending_review')
  } finally {
    globalThis.fetch = originalFetch
  }
})

test('hoarding trend and chain-of-custody adapters coerce render-safe values', async () => {
  const originalFetch = globalThis.fetch
  const calls = []

  globalThis.fetch = async (url) => {
    calls.push(String(url))
    if (String(url).includes('/hoarding-anomalies/7/trend')) {
      return {
        ok: true,
        status: 200,
        statusText: 'OK',
        text: async () => JSON.stringify({
          status: 'success',
          data: [{ week: 'Wk 14', incoming: '7', outgoing: null }],
        }),
      }
    }

    return {
      ok: true,
      status: 200,
      statusText: 'OK',
      text: async () => JSON.stringify({
        status: 'success',
        data: {
          barcode: '6250',
          medication_name: 'Amoxil',
          updated_at: '2026-04-08T00:00:00.000Z',
        },
      }),
    }
  }

  try {
    const trend = await monitoringApi.getHoardingTrend(7)
    const custody = await monitoringApi.getChainOfCustody('6250')

    assert.equal(calls.length, 2)
    assert.equal(trend.data[0].incoming, 7)
    assert.equal(trend.data[0].outgoing, 0)
    assert.equal(custody.data.trade_name, 'Amoxil')
    assert.equal(typeof custody.data.updated_at, 'string')
  } finally {
    globalThis.fetch = originalFetch
  }
})

test('getStock preserves no-demand coverage as null and keeps zero stock as zero days', async () => {
  const originalFetch = globalThis.fetch

  globalThis.fetch = async () => ({
    ok: true,
    status: 200,
    statusText: 'OK',
    text: async () => JSON.stringify({
      status: 'success',
      data: [
        { barcode: 'A', stock_units: 0, days_of_stock: 0, coverage_basis: 'out_of_stock', dosage: '', expiry_at: null },
        { barcode: 'B', stock_units: 10, days_of_stock: null, coverage_basis: 'no_demand_history', dosage: '500mg', expiry_at: '2026-12-01T00:00:00.000Z' },
      ],
    }),
  })

  try {
    const res = await monitoringApi.getStock()
    assert.equal(res.data[0].days_of_stock, 0)
    assert.equal(res.data[1].days_of_stock, null)
    assert.equal(res.data[1].coverage_basis, 'no_demand_history')
    assert.equal(res.data[1].dosage, '500mg')
    assert.equal(res.data[1].expiry_at, '2026-12-01T00:00:00.000Z')
  } finally {
    globalThis.fetch = originalFetch
  }
})

test('getAuditFeed normalizes forensic event fields without unknown placeholder coercion', async () => {
  const originalFetch = globalThis.fetch

  globalThis.fetch = async () => ({
    ok: true,
    status: 200,
    statusText: 'OK',
    text: async () => JSON.stringify({
      status: 'success',
      data: [
        {
          event_uuid: 'evt-1',
          event_family: 'sales',
          event_type: 'sale_recorded',
          event_title: 'Sold 6 units above regulated ceiling',
          severity: 'high',
          pharmacy_name: null,
          medicine_name: null,
          barcode: '6289201012345',
          regulated_price_minor: 2000,
          actual_price_minor: 2500,
          quantity_delta: 6,
          source: 'pos',
          outcome: 'warning',
          event_time: '2026-04-16T12:00:00.000Z',
          metadata: { receipt_id: 'R-1' },
        },
      ],
    }),
  })

  try {
    const res = await monitoringApi.getAuditFeed({ includeSystem: false })
    assert.equal(Array.isArray(res.data), true)
    assert.equal(res.data.length, 1)
    assert.equal(res.data[0].event_family, 'sales')
    assert.equal(res.data[0].pharmacy_name, '')
    assert.equal(res.data[0].medicine_name, '')
    assert.equal(res.data[0].barcode, '6289201012345')
    assert.equal(res.data[0].quantity_delta, 6)
    assert.equal(res.data[0].metadata.receipt_id, 'R-1')
  } finally {
    globalThis.fetch = originalFetch
  }
})

test('getPriceHistory normalizes source-labeled rows and preserves partial values', async () => {
  const originalFetch = globalThis.fetch

  globalThis.fetch = async () => ({
    ok: true,
    status: 200,
    statusText: 'OK',
    text: async () => JSON.stringify({
      status: 'success',
      data: [
        {
          event_id: 'ph-1',
          source_family: 'price_history',
          event_type: 'branch_price_edit',
          source_label: 'Branch price edit',
          pharmacy_name: 'Al-Amin Pharmacy',
          medicine_name: 'Amoxil',
          barcode: '6250',
          previous_price_minor: 400,
          new_price_minor: 500,
          regulated_price_minor: 450,
          change_pct: 0.25,
          source: 'pos',
          status: 'high_price',
          changed_at: '2026-04-16T12:00:00.000Z',
        },
      ],
    }),
  })

  try {
    const res = await monitoringApi.getPriceHistory()
    assert.equal(Array.isArray(res.data), true)
    assert.equal(res.data.length, 1)
    assert.equal(res.data[0].source_label, 'Branch price edit')
    assert.equal(res.data[0].pharmacy_name, 'Al-Amin Pharmacy')
    assert.equal(res.data[0].medicine_name, 'Amoxil')
    assert.equal(res.data[0].barcode, '6250')
    assert.equal(res.data[0].previous_price_minor, 400)
    assert.equal(res.data[0].new_price_minor, 500)
    assert.equal(res.data[0].change_pct, 0.25)
    assert.equal(res.data[0].status, 'high_price')
  } finally {
    globalThis.fetch = originalFetch
  }
})

test('getSettingsData normalizes enriched admin console payload with render-safe fallbacks', async () => {
  const originalFetch = globalThis.fetch

  globalThis.fetch = async () => ({
    ok: true,
    status: 200,
    statusText: 'OK',
    text: async () => JSON.stringify({
      status: 'success',
      data: {
        terminals: [{
          id: 3,
          name: 'Al-Amin Pharmacy',
          hwid: 'HW-00423',
          license_number: 'LIC-BEY-0041',
          region: 'Beirut',
          status: 'online',
          last_seen: '2026-04-08T09:05:00.000Z',
          last_sync_up: '2026-04-08T09:04:00.000Z',
          pending_outbox: '2',
        }],
        terminal_summary: { total_terminals: '1', online_count: '1', never_synced_count: '0' },
        pricing_policy: { regulated_medicine_count: '120', high_price_violations: '2' },
        recent_price_events: [{ item_name: 'Paracetamol', registry_price: '2.1', charged_price: '2.7' }],
        adjustment_reasons: ['Damaged', 'Expired'],
        recent_adjustments: [{ item_name: 'Paracetamol', unit_count: '-3', reason: 'Damaged' }],
        adjustment_summary: { total_adjustments: '12', adjustments_last_30d: '3' },
        top_adjustment_reasons: [{ reason: 'Damaged', usage_count: '5' }],
      },
    }),
  })

  try {
    const res = await monitoringApi.getSettingsData()
    assert.equal(Array.isArray(res.data.terminals), true)
    assert.equal(res.data.terminals[0].pending_outbox, 2)
    assert.equal(res.data.terminal_summary.total_terminals, 1)
    assert.equal(res.data.pricing_policy.regulated_medicine_count, 120)
    assert.equal(res.data.recent_price_events[0].item_name, 'Paracetamol')
    assert.equal(res.data.recent_adjustments[0].unit_count, -3)
    assert.equal(res.data.adjustment_summary.total_adjustments, 12)
    assert.equal(res.data.top_adjustment_reasons[0].usage_count, 5)

    // Backward-compatible aliases remain available for older views.
    assert.equal(Array.isArray(res.data.nodes), true)
    assert.equal(Array.isArray(res.data.price_alerts), true)
  } finally {
    globalThis.fetch = originalFetch
  }
})
