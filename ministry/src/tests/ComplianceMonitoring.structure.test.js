import test from 'node:test'
import assert from 'node:assert/strict'
import { MONITORING_VIEWS } from '../types/monitoring.js'

test('Compliance Monitoring: tab structure is correct', () => {
  assert.equal(MONITORING_VIEWS.length, 7, 'Should have exactly 7 tabs')

  const expectedTabs = [
    { id: 'stock', label: 'Stock Oversight' },
    { id: 'pricing', label: 'Price Compliance' },
    { id: 'hoarding', label: 'Hoarding Alerts' },
    { id: 'sync', label: 'Sync Health' },
    { id: 'medicineHistory', label: 'Medicine History' },
    { id: 'pharmacyAudit', label: 'Pharmacy Audit Trail' },
    { id: 'priceHistory', label: 'Price History' },
  ]

  for (let i = 0; i < expectedTabs.length; i++) {
    assert.equal(MONITORING_VIEWS[i].id, expectedTabs[i].id, `Tab ${i} ID mismatch`)
    assert.equal(MONITORING_VIEWS[i].label, expectedTabs[i].label, `Tab ${i} label mismatch`)
  }
})

test('Compliance Monitoring: tab IDs are unique', () => {
  const ids = MONITORING_VIEWS.map((v) => v.id)
  const uniqueIds = new Set(ids)
  assert.equal(ids.length, uniqueIds.size, 'Tab IDs should be unique')
})

test('Compliance Monitoring: all tabs have label text', () => {
  for (const tab of MONITORING_VIEWS) {
    assert(tab.label && typeof tab.label === 'string' && tab.label.length > 0, `Tab ${tab.id} has invalid label`)
  }
})
