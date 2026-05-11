import test from 'node:test'
import assert from 'node:assert/strict'
import { renderToStaticMarkup } from 'react-dom/server'
import PharmacyList from './PharmacyList.js'

test('PharmacyList renders pharmacy with real data', () => {
  const stockRows = [
    {
      pharmacy_id: 1,
      pharmacy_name: 'Central Medical',
      license_number: 'LIC001',
      region: 'North',
      hwid: 'HWID001',
      status: 'critical',
      last_sync_up: '2026-04-30T10:00:00Z',
    },
    {
      pharmacy_id: 1,
      pharmacy_name: 'Central Medical',
      license_number: 'LIC001',
      region: 'North',
      hwid: 'HWID001',
      status: 'safe',
      last_sync_up: '2026-04-30T10:00:00Z',
    },
  ]

  const markup = renderToStaticMarkup(
    PharmacyList({
      stockRows,
      selectedPharmacyId: null,
      onSelectPharmacy() {},
      regionFilter: '',
      loading: false,
    }),
  )

  assert.match(markup, /Central Medical/)
  assert.match(markup, /LIC001/)
  assert.match(markup, /North/)
  assert.match(markup, /2/)
})

test('PharmacyList shows no data message when no pharmacies', () => {
  const markup = renderToStaticMarkup(
    PharmacyList({
      stockRows: [],
      selectedPharmacyId: null,
      onSelectPharmacy() {},
      regionFilter: '',
      loading: false,
    }),
  )

  assert.match(markup, /No pharmacies found/)
})

test('PharmacyList highlights selected pharmacy', () => {
  const stockRows = [
    {
      pharmacy_id: 1,
      pharmacy_name: 'Pharmacy 1',
      license_number: 'LIC001',
      region: 'North',
      hwid: 'HWID001',
      status: 'safe',
      last_sync_up: null,
    },
    {
      pharmacy_id: 2,
      pharmacy_name: 'Pharmacy 2',
      license_number: 'LIC002',
      region: 'South',
      hwid: 'HWID002',
      status: 'critical',
      last_sync_up: null,
    },
  ]

  const markup = renderToStaticMarkup(
    PharmacyList({
      stockRows,
      selectedPharmacyId: 1,
      onSelectPharmacy() {},
      regionFilter: '',
      loading: false,
    }),
  )

  assert.match(markup, /Pharmacy 1/)
  assert.match(markup, /Pharmacy 2/)
  assert.match(markup, /bg-teal-50/)
})

test('PharmacyList filters by region', () => {
  const stockRows = [
    {
      pharmacy_id: 1,
      pharmacy_name: 'North Pharmacy',
      license_number: 'LIC001',
      region: 'North',
      hwid: 'HWID001',
      status: 'safe',
      last_sync_up: null,
    },
    {
      pharmacy_id: 2,
      pharmacy_name: 'South Pharmacy',
      license_number: 'LIC002',
      region: 'South',
      hwid: 'HWID002',
      status: 'safe',
      last_sync_up: null,
    },
  ]

  const markup = renderToStaticMarkup(
    PharmacyList({
      stockRows,
      selectedPharmacyId: null,
      onSelectPharmacy() {},
      regionFilter: 'North',
      loading: false,
    }),
  )

  assert.match(markup, /North Pharmacy/)
  assert.doesNotMatch(markup, /South Pharmacy/)
})

test('PharmacyList shows critical/low counts', () => {
  const stockRows = [
    {
      pharmacy_id: 1,
      pharmacy_name: 'Multi-Status Pharmacy',
      license_number: 'LIC001',
      region: 'Central',
      hwid: 'HWID001',
      status: 'critical',
      last_sync_up: null,
    },
    {
      pharmacy_id: 1,
      pharmacy_name: 'Multi-Status Pharmacy',
      license_number: 'LIC001',
      region: 'Central',
      hwid: 'HWID001',
      status: 'critical',
      last_sync_up: null,
    },
    {
      pharmacy_id: 1,
      pharmacy_name: 'Multi-Status Pharmacy',
      license_number: 'LIC001',
      region: 'Central',
      hwid: 'HWID001',
      status: 'low',
      last_sync_up: null,
    },
    {
      pharmacy_id: 1,
      pharmacy_name: 'Multi-Status Pharmacy',
      license_number: 'LIC001',
      region: 'Central',
      hwid: 'HWID001',
      status: 'safe',
      last_sync_up: null,
    },
  ]

  const markup = renderToStaticMarkup(
    PharmacyList({
      stockRows,
      selectedPharmacyId: null,
      onSelectPharmacy() {},
      regionFilter: '',
      loading: false,
    }),
  )

  assert.match(markup, /2C/)
  assert.match(markup, /1L/)
})
