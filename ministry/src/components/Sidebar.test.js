import test from 'node:test'
import assert from 'node:assert/strict'

import { PRIMARY_NAV_ITEMS, SYSTEM_NAV_ITEM } from '../sidebarConfig.js'

test('sidebar navigation exposes only the remaining shell pages', () => {
  const ids = PRIMARY_NAV_ITEMS.map((item) => item.id)

  assert.deepEqual(ids, ['registry', 'monitoring'])
  assert.equal(PRIMARY_NAV_ITEMS.some((item) => item.label === 'Master Registry'), true)
  assert.equal(PRIMARY_NAV_ITEMS.some((item) => item.label === 'Compliance Monitoring'), true)
  assert.equal(PRIMARY_NAV_ITEMS.some((item) => item.label === 'Shortage Surveillance'), false)
  assert.equal(PRIMARY_NAV_ITEMS.some((item) => item.label === 'Hoarding Analytics'), false)
  assert.equal(PRIMARY_NAV_ITEMS.some((item) => item.label === 'Audit Trail'), false)
  assert.equal(PRIMARY_NAV_ITEMS.some((item) => item.label === 'System Governance'), false)
  assert.equal(SYSTEM_NAV_ITEM.id, 'settings')
  assert.equal(SYSTEM_NAV_ITEM.label, 'Settings')
})

test('sidebar navigation keeps branding-aligned system access', () => {
  assert.equal(SYSTEM_NAV_ITEM.sublabel, 'Admin Console')
})