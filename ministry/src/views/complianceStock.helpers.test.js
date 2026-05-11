import test from 'node:test'
import assert from 'node:assert/strict'

import {
  buildStockScopeSubtitle,
  coverageTooltip,
  formatDaysOfStock,
  formatExpiryLabel,
  stockStateClasses,
  stockStateLabel,
  statusTooltip,
} from './complianceStock.helpers.js'

test('formatDaysOfStock returns truthful fallback for missing demand history', () => {
  assert.equal(formatDaysOfStock(0, 'out_of_stock'), '0.0 d')
  assert.equal(formatDaysOfStock(null, 'no_demand_history'), 'No demand history')
  assert.equal(formatDaysOfStock(18.24, 'recent_sales_30d'), '18.2 d')
})

test('coverageTooltip explains coverage basis for operators', () => {
  assert.equal(coverageTooltip({ coverage_basis: 'recent_sales_30d' }).includes('average daily units sold'), true)
  assert.equal(coverageTooltip({ coverage_basis: 'no_demand_history' }).includes('not computed as zero'), true)
})

test('statusTooltip exposes status basis when available', () => {
  assert.equal(statusTooltip({ status_basis: 'near_threshold_or_low_coverage' }).includes('near threshold or low coverage'), true)
  assert.equal(statusTooltip({}).includes('Status is derived'), true)
})

test('formatExpiryLabel keeps expiry truthful and human readable', () => {
  assert.equal(formatExpiryLabel('2026-12-01T00:00:00.000Z'), 'Dec 2026')
  assert.equal(formatExpiryLabel(null), 'No expiry')
  assert.equal(formatExpiryLabel('not-a-date'), 'No expiry')
})

test('stockStateLabel maps real stock states without inventing values', () => {
  assert.equal(stockStateLabel({ stock_units: 132, status: 'safe' }), 'In Stock')
  assert.equal(stockStateLabel({ stock_units: 4, status: 'low' }), 'Low')
  assert.equal(stockStateLabel({ stock_units: 0, status: 'critical' }), 'Out of Stock')
  assert.equal(stockStateLabel({ stock_units: 22, status: 'watch', stock_state_label: 'Watch' }), 'Watch')
})

test('stockStateClasses returns readable severity tones', () => {
  assert.equal(stockStateClasses({ stock_units: 0 }).includes('red'), true)
  assert.equal(stockStateClasses({ stock_units: 6, status: 'low' }).includes('amber'), true)
  assert.equal(stockStateClasses({ stock_units: 132, status: 'safe' }).includes('emerald'), true)
})

test('buildStockScopeSubtitle is truthful for single-branch and multi-branch contexts', () => {
  const oneBranch = buildStockScopeSubtitle({
    activeView: 'stock',
    scope: null,
    rows: [{ pharmacy_name: 'Al-Amin' }],
    overview: { total_pharmacies: 4 },
  })
  assert.equal(oneBranch.includes('1 active pharmacy'), true)

  const multiBranch = buildStockScopeSubtitle({
    activeView: 'stock',
    scope: null,
    rows: [{ pharmacy_name: 'A' }, { pharmacy_name: 'B' }],
    overview: { total_pharmacies: 7 },
  })
  assert.equal(multiBranch.includes('across 2 active pharmacies'), true)
  assert.equal(multiBranch.includes('7 registered nodes'), true)
})
