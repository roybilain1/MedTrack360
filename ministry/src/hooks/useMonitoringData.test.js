import test from 'node:test'
import assert from 'node:assert/strict'

import {
  createRequestState,
  createViewFilterState,
  isCurrentOverviewSeq,
  isCurrentTableSeq,
  nextOverviewSeq,
  nextTableSeq,
  updateViewFilterState,
} from './useMonitoringData.js'

test('overview request token remains valid when table requests advance', () => {
  const state = createRequestState()

  const overviewToken = nextOverviewSeq(state)
  nextTableSeq(state)
  nextTableSeq(state)

  assert.equal(isCurrentOverviewSeq(state, overviewToken), true)
  assert.equal(isCurrentTableSeq(state, 1), false)
  assert.equal(isCurrentTableSeq(state, 2), true)
})

test('view filters are isolated by tab and do not leak', () => {
  const filters = createViewFilterState(['stock', 'pricing'])

  const updatedStock = updateViewFilterState(filters, 'stock', (prev) => ({
    ...prev,
    medicine: 'amoxicillin',
    status: 'low_stock',
    sortBy: 'stock_units',
  }))

  assert.equal(updatedStock.stock.medicine, 'amoxicillin')
  assert.equal(updatedStock.stock.status, 'low_stock')
  assert.equal(updatedStock.stock.sortBy, 'stock_units')

  assert.equal(updatedStock.pricing.medicine, '')
  assert.equal(updatedStock.pricing.status, '')
  assert.equal(updatedStock.pricing.sortBy, '')
})

test('returning to a tab preserves that tab own filter state', () => {
  let filters = createViewFilterState(['stock', 'pricing'])

  filters = updateViewFilterState(filters, 'stock', (prev) => ({
    ...prev,
    medicine: 'ibuprofen',
    page: 3,
  }))

  filters = updateViewFilterState(filters, 'pricing', (prev) => ({
    ...prev,
    status: 'high_price',
    page: 2,
  }))

  assert.equal(filters.stock.medicine, 'ibuprofen')
  assert.equal(filters.stock.page, 3)
  assert.equal(filters.pricing.status, 'high_price')
  assert.equal(filters.pricing.page, 2)
})

