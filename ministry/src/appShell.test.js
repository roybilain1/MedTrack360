import test from 'node:test'
import assert from 'node:assert/strict'

import { APP_VIEW_IDS, DEFAULT_VIEW_ID, resolveAppViewId } from './appShell.js'
import { PRIMARY_NAV_ITEMS, SYSTEM_NAV_ITEM } from './sidebarConfig.js'

test('app shell default view is registry', () => {
  assert.equal(DEFAULT_VIEW_ID, 'registry')
  assert.equal(resolveAppViewId(undefined), 'registry')
  assert.equal(resolveAppViewId('registry'), 'registry')
})

test('app shell rejects removed or unknown views', () => {
  assert.equal(resolveAppViewId('shortage'), 'registry')
  assert.equal(resolveAppViewId('hoarding'), 'registry')
  assert.equal(resolveAppViewId('audit'), 'registry')
  assert.equal(resolveAppViewId('governance'), 'registry')
  assert.equal(resolveAppViewId('not-a-view'), 'registry')
})

test('app shell exposes only remaining visible shell views', () => {
  assert.deepEqual(APP_VIEW_IDS, ['registry', 'monitoring', 'settings'])
})

test('sidebar config exposes the three remaining destinations', () => {
  assert.deepEqual(
    PRIMARY_NAV_ITEMS.map((item) => item.id),
    ['registry', 'monitoring'],
  )
  assert.equal(SYSTEM_NAV_ITEM.id, 'settings')
  assert.equal(PRIMARY_NAV_ITEMS.some((item) => item.label === 'Shortage Surveillance'), false)
  assert.equal(PRIMARY_NAV_ITEMS.some((item) => item.label === 'Hoarding Analytics'), false)
  assert.equal(PRIMARY_NAV_ITEMS.some((item) => item.label === 'Audit Trail'), false)
  assert.equal(PRIMARY_NAV_ITEMS.some((item) => item.label === 'System Governance'), false)
})