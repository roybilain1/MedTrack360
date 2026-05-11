import test from 'node:test'
import assert from 'node:assert/strict'

import {
  coerceBoolean,
  coerceDate,
  formatDate,
  formatDecimal,
  formatPercent,
  formatTimestamp,
  normalizeCurrencyMinor,
  statusBadgeClass,
  statusLabel,
} from './formatters.js'

test('formatters coerce values predictably', () => {
  assert.equal(coerceBoolean('yes'), true)
  assert.equal(coerceBoolean('0'), false)
  assert.equal(coerceBoolean(null), false)
  assert.equal(coerceDate('not-a-date'), null)
})

test('formatters render stable display values', () => {
  assert.equal(normalizeCurrencyMinor(255), '2.55')
  assert.equal(formatPercent(0.125), '12.5%')
  assert.equal(formatPercent(12.5), '12.5%')
  assert.equal(formatDecimal(12.345, { fractionDigits: 1 }), '12.3')
  assert.equal(formatTimestamp('2026-04-08T10:15:00.000Z').length > 0, true)
  assert.equal(formatDate('2026-04-08T10:15:00.000Z').length > 0, true)
})

test('status helpers normalize labels and badges', () => {
  assert.equal(statusLabel('high_price'), 'High Price')
  assert.equal(statusLabel('unknown_state'), 'unknown_state')
  assert.equal(statusBadgeClass('high_price').includes('red'), true)
})
