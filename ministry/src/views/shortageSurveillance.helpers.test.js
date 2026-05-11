import test from 'node:test'
import assert from 'node:assert/strict'

import {
  buildCoverageSnapshot,
  buildScopedSubtitle,
  buildScopeSubtitle,
  normalizeStatus,
  resolveCoverageLabel,
  resolveLastSyncLabel,
  resolvePharmacyName,
  resolveRegionName,
  resolveThresholdSource,
} from './shortageSurveillance.helpers.js'

test('resolvePharmacyName prefers real names and avoids legacy unknown placeholder', () => {
  assert.equal(resolvePharmacyName({ pharmacy_name: 'Apex Pharmacy' }), 'Apex Pharmacy')
  assert.equal(resolvePharmacyName({ hwid: 'HW-1' }), 'Unassigned source')
  assert.equal(resolvePharmacyName({}), 'No linked pharmacy')
})

test('resolveLastSyncLabel prefers sync timestamps then movement then never synced', () => {
  assert.equal(resolveLastSyncLabel({ last_sync_up: '2026-04-12T11:30:00.000Z' }), '2026-04-12 11:30')
  assert.equal(resolveLastSyncLabel({ last_sync_down: '2026-04-12T11:30:00.000Z' }).includes('(down)'), true)
  assert.equal(resolveLastSyncLabel({ last_movement_at: '2026-04-12T11:30:00.000Z' }).includes('(movement)'), true)
  assert.equal(resolveLastSyncLabel({}), 'Never synced')
})

test('status and region helpers keep operational labels', () => {
  assert.equal(normalizeStatus('critical'), 'critical')
  assert.equal(normalizeStatus('low'), 'low')
  assert.equal(normalizeStatus('safe'), 'safe')
  assert.equal(normalizeStatus('watch'), 'watch')
  assert.equal(normalizeStatus('unknown'), 'unknown')
  assert.equal(normalizeStatus('unexpected'), 'unknown')
  assert.equal(resolveRegionName({ region: 'Beirut' }), 'Beirut')
  assert.equal(resolveRegionName({}), 'Region not reported')
})

test('buildCoverageSnapshot sorts by lowest days-of-stock and trims series', () => {
  const input = [
    { name: 'AAA', daysOfStock: 12.321, threshold: 20, stock: 12 },
    { name: 'BBB', daysOfStock: 4.456, threshold: 10, stock: 4 },
    { name: 'CCC', daysOfStock: 7, threshold: 15, stock: 7 },
  ]

  const trend = buildCoverageSnapshot(input)
  assert.equal(trend.length, 3)
  assert.equal(trend[0].label, 'BBB')
  assert.equal(trend[0].daysOfStock, 4.5)
  assert.equal(trend[0].threshold, 10)
})

test('buildScopeSubtitle truthfully reflects single-pharmacy scope', () => {
  const subtitle = buildScopeSubtitle({
    rows: [
      { pharmacy: 'Al-Amin Pharmacy' },
      { pharmacy: 'Al-Amin Pharmacy' },
    ],
    refreshLabel: '15s ago',
  })

  assert.equal(subtitle.includes('Current visible scope: 1 active pharmacy'), true)
  assert.equal(subtitle.includes('15s ago'), true)
})

test('buildScopedSubtitle uses authoritative scope with node totals', () => {
  const subtitle = buildScopedSubtitle({
    scopeLabel: 'Live branch risk view derived from latest synchronized inventory across 3 active pharmacies',
    activePharmacies: 3,
    registeredNodes: 12,
    refreshLabel: '22s ago',
  })

  assert.equal(subtitle.includes('3 active pharmacies'), true)
  assert.equal(subtitle.includes('12 registered nodes'), true)
  assert.equal(subtitle.includes('22s ago'), true)
})

test('resolveThresholdSource and coverage labels stay truthful', () => {
  assert.equal(resolveThresholdSource({ configured_threshold: 10, threshold_units: 12 }), 'Configured threshold')
  assert.equal(resolveThresholdSource({ configured_threshold: null, threshold_units: 8 }), 'Derived 14-day floor')
  assert.equal(resolveThresholdSource({ configured_threshold: null, threshold_units: null }), 'No threshold baseline')

  assert.equal(resolveCoverageLabel({ coverage_basis: 'out_of_stock', daysOfStock: 0 }), '0 d (out of stock)')
  assert.equal(resolveCoverageLabel({ coverage_basis: 'no_demand_history', daysOfStock: null }), 'No demand history')
  assert.equal(resolveCoverageLabel({ coverage_basis: 'recent_sales_30d', daysOfStock: 6.23 }), '6.2 d')
})
