import test from 'node:test'
import assert from 'node:assert/strict'

import {
  SETTINGS_TABS,
  computeTerminalSummary,
  freshnessForTerminal,
} from './settings.helpers.js'

test('settings tabs are stable and complete for shell switching', () => {
  assert.deepEqual(
    SETTINGS_TABS.map((t) => t.id),
    ['terminals', 'pricing', 'adjustments']
  )
  assert.equal(new Set(SETTINGS_TABS.map((t) => t.id)).size, SETTINGS_TABS.length)
  assert.equal(SETTINGS_TABS.every((t) => typeof t.label === 'string' && t.label.length > 0), true)
})

test('computeTerminalSummary derives truthful fallback metrics when API summary is missing', () => {
  const rows = [
    { status: 'online', last_sync_up: '2026-04-20T12:00:00.000Z' },
    { status: 'offline', last_sync_up: null, last_sync_down: null },
    { status: 'degraded', last_sync_up: '2026-04-20T12:05:00.000Z' },
  ]

  const summary = computeTerminalSummary(rows, {})
  assert.equal(summary.total_terminals, 3)
  assert.equal(summary.online_count, 1)
  assert.equal(summary.offline_count, 1)
  assert.equal(summary.degraded_count, 1)
  assert.equal(summary.never_synced_count, 1)
})

test('computeTerminalSummary preserves API-provided aggregate truth when present', () => {
  const summary = computeTerminalSummary([], {
    total_terminals: 10,
    online_count: 8,
    offline_count: 1,
    degraded_count: 1,
    version_mismatch_count: 2,
    never_synced_count: 3,
    expected_sync_version: '2.6.1',
  })

  assert.equal(summary.total_terminals, 10)
  assert.equal(summary.version_mismatch_count, 2)
  assert.equal(summary.never_synced_count, 3)
  assert.equal(summary.expected_sync_version, '2.6.1')
})

test('freshnessForTerminal emits truthful freshness badges', () => {
  const now = Date.parse('2026-04-21T12:00:00.000Z')

  assert.deepEqual(freshnessForTerminal({}, now), { label: 'Never synced', color: 'slate' })
  assert.deepEqual(
    freshnessForTerminal({ last_sync_up: '2026-04-21T11:55:00.000Z' }, now),
    { label: 'Fresh', color: 'emerald' }
  )
  assert.deepEqual(
    freshnessForTerminal({ last_sync_up: '2026-04-21T11:20:00.000Z' }, now),
    { label: 'Delayed', color: 'amber' }
  )
  assert.deepEqual(
    freshnessForTerminal({ last_sync_up: '2026-04-21T10:00:00.000Z' }, now),
    { label: 'Stale', color: 'red' }
  )
})
