import test from 'node:test'
import assert from 'node:assert/strict'
import { renderToStaticMarkup } from 'react-dom/server'

import MonitoringTable from './MonitoringTable.jsx'
import { normalizeCurrencyMinor } from '../../utils/formatters.js'

test('MonitoringTable keeps one-arg renderers stable (no row object fallback leak)', () => {
  const html = renderToStaticMarkup(
    MonitoringTable({
      title: 'Price Compliance',
      columns: [
        { key: 'regulated_price_minor', label: 'Regulated', render: normalizeCurrencyMinor },
      ],
      rows: [{ regulated_price_minor: null, pharmacy_name: 'Al-Amin' }],
      loading: false,
      error: null,
      pagination: { page: 1, totalPages: 1, total: 1 },
      onPageChange() {},
      exportName: 'x.csv',
    }),
  )

  assert.equal(html.includes('[object Object]'), false)
  assert.equal(html.includes('-'), true)
})

test('MonitoringTable supports two-arg renderers for stock row-aware cells', () => {
  const html = renderToStaticMarkup(
    MonitoringTable({
      title: 'Stock Oversight',
      columns: [
        {
          key: 'stock_units',
          label: 'Stock / Threshold',
          render: (_, row) => `${row.stock_units} / ${row.threshold_units}`,
        },
      ],
      rows: [{ stock_units: 12, threshold_units: 20 }],
      loading: false,
      error: null,
      pagination: { page: 1, totalPages: 1, total: 1 },
      onPageChange() {},
      exportName: 'x.csv',
    }),
  )

  assert.equal(html.includes('12 / 20'), true)
})

test('MonitoringTable can render POS-like inventory row hierarchy', () => {
  const html = renderToStaticMarkup(
    MonitoringTable({
      title: 'Selected Pharmacy Inventory',
      columns: [
        {
          key: 'medicine_name',
          label: 'Medicine',
          render: (_, row) => (
            <div>
              <div className="font-semibold">{row.medicine_name}</div>
              <div>{row.dosage}</div>
              <div>{row.barcode}</div>
            </div>
          ),
        },
        {
          key: 'category',
          label: 'Category',
          render: (_, row) => <span>{row.category}</span>,
        },
        {
          key: 'stock_units',
          label: 'Stock',
          render: (_, row) => (
            <div>
              <div>{row.stock_units} units</div>
              <div>{row.stock_state_label}</div>
            </div>
          ),
        },
        {
          key: 'expiry_at',
          label: 'Expiry',
          render: (_, row) => <div>{row.expiry_at}</div>,
        },
        {
          key: 'current_price_minor',
          label: 'Prices',
          render: (_, row) => (
            <div>
              <div>Local: {row.current_price}</div>
              <div>Gov: {row.gov_price}</div>
            </div>
          ),
        },
      ],
      rows: [{
        medicine_name: 'Amoxil',
        dosage: '500 mg',
        barcode: '6250000000010',
        category: 'Antibiotic',
        stock_units: 132,
        stock_state_label: 'In Stock',
        expiry_at: 'Dec 2026',
        current_price: '$12.00',
        gov_price: '$20.00',
      }],
      loading: false,
      error: null,
      pagination: { page: 1, totalPages: 1, total: 1 },
      onPageChange() {},
      exportName: 'x.csv',
    }),
  )

  assert.equal(html.includes('Amoxil'), true)
  assert.equal(html.includes('500 mg'), true)
  assert.equal(html.includes('Antibiotic'), true)
  assert.equal(html.includes('132 units'), true)
  assert.equal(html.includes('In Stock'), true)
  assert.equal(html.includes('Dec 2026'), true)
  assert.equal(html.includes('Local: $12.00'), true)
  assert.equal(html.includes('Gov: $20.00'), true)
})
