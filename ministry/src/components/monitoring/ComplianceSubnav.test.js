import test from 'node:test'
import assert from 'node:assert/strict'
import { renderToStaticMarkup } from 'react-dom/server'

import ComplianceSubnav from './ComplianceSubnav.js'
import { MONITORING_VIEWS } from '../../types/monitoring.js'
import { MONITORING_STATUS_OPTIONS, getMonitoringSortOptions } from '../../views/complianceMonitoringConfig.js'

function collectNodes(node, predicate, results = []) {
  if (!node) return results
  if (Array.isArray(node)) {
    node.forEach((child) => collectNodes(child, predicate, results))
    return results
  }

  if (typeof node === 'object') {
    if (predicate(node)) {
      results.push(node)
    }

    const children = node.props?.children
    if (children) {
      collectNodes(children, predicate, results)
    }
  }

  return results
}

function textContent(node) {
  if (node == null) return ''
  if (typeof node === 'string' || typeof node === 'number') return String(node)
  if (Array.isArray(node)) return node.map(textContent).join('')
  if (typeof node === 'object') return textContent(node.props?.children)
  return ''
}

test('active compliance tab renders correctly after layout move', () => {
  const markup = renderToStaticMarkup(
    ComplianceSubnav({
      activeView: 'stock',
      onSelectView() {},
      onRefresh() {},
    }),
  )

  assert.match(markup, /Compliance Monitoring/)
  assert.match(markup, /Stock Oversight/)
  assert.match(markup, /aria-current="page"/)
  assert.match(markup, /bg-teal-50/)
})

test('clicking left-side compliance nav changes active tab', () => {
  const selected = []
  const tree = ComplianceSubnav({
    activeView: 'pricing',
    onSelectView(viewId) {
      selected.push(viewId)
    },
    onRefresh() {},
  })

  const buttons = collectNodes(tree, (node) => node.type === 'button')
  const stockButton = buttons.find((button) => textContent(button.props.children).includes('Stock Oversight'))

  assert.ok(stockButton)
  stockButton.props.onClick()
  assert.deepEqual(selected, ['stock'])
})

test('refresh action remains available from the relocated left rail', () => {
  let refreshCount = 0
  const tree = ComplianceSubnav({
    activeView: 'stock',
    onSelectView() {},
    onRefresh() {
      refreshCount += 1
    },
  })

  const buttons = collectNodes(tree, (node) => node.type === 'button')
  const refreshButton = buttons.find((button) => textContent(button.props.children).includes('Refresh'))

  assert.ok(refreshButton)
  refreshButton.props.onClick()
  assert.equal(refreshCount, 1)
})

test('relocated compliance tabs and filter options keep the same active-view mapping', () => {
  assert.deepEqual(
    MONITORING_VIEWS.map((view) => view.label),
    [
      'Stock Oversight',
      'Price Compliance',
      'Hoarding Alerts',
      'Sync Health',
      'Medicine History',
      'Pharmacy Audit Trail',
      'Price History',
    ],
  )

  assert.deepEqual(
    getMonitoringSortOptions('pricing').map((option) => option.value),
    ['markup_pct', 'avg_selling_price_minor', 'regulated_price_minor', 'pharmacy_name'],
  )

  assert.equal(MONITORING_STATUS_OPTIONS.some((option) => option.value === 'high_price'), true)
})