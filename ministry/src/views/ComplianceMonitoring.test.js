import test from 'node:test'
import assert from 'node:assert/strict'

test('Pharmacy selection logic: filters stock rows by selected pharmacy', () => {
  // Mock data similar to what ComplianceMonitoring would receive
  const allStockRows = [
    { pharmacy_id: 1, pharmacy_name: 'Pharmacy A', medicine_name: 'Med 1', status: 'safe' },
    { pharmacy_id: 1, pharmacy_name: 'Pharmacy A', medicine_name: 'Med 2', status: 'critical' },
    { pharmacy_id: 2, pharmacy_name: 'Pharmacy B', medicine_name: 'Med 1', status: 'low' },
    { pharmacy_id: 2, pharmacy_name: 'Pharmacy B', medicine_name: 'Med 3', status: 'safe' },
  ]

  const selectedPharmacyId = 1

  // Simulate the filteringlogic from ComplianceMonitoring
  const displayData = allStockRows.filter((r) => r.pharmacy_id === selectedPharmacyId)

  assert.equal(displayData.length, 2, 'Should filter to only selected pharmacy rows')
  assert.equal(displayData[0].pharmacy_name, 'Pharmacy A')
  assert.equal(displayData[1].pharmacy_name, 'Pharmacy A')
  assert.deepEqual(displayData.map((r) => r.medicine_name), ['Med 1', 'Med 2'])
})

test('Pharmacy selection logic: returns all rows when no pharmacy selected', () => {
  const allStockRows = [
    { pharmacy_id: 1, pharmacy_name: 'Pharmacy A', medicine_name: 'Med 1', status: 'safe' },
    { pharmacy_id: 2, pharmacy_name: 'Pharmacy B', medicine_name: 'Med 2', status: 'critical' },
  ]

  const selectedPharmacyId = null

  const displayData = selectedPharmacyId ? allStockRows.filter((r) => r.pharmacy_id === selectedPharmacyId) : allStockRows

  assert.equal(displayData.length, 2, 'Should return all rows when no pharmacy selected')
})

test('Pharmacy summary: aggregates statuses for selected pharmacy', () => {
  const allStockRows = [
    { pharmacy_id: 1, pharmacy_name: 'Pharmacy A', status: 'critical' },
    { pharmacy_id: 1, pharmacy_name: 'Pharmacy A', status: 'critical' },
    { pharmacy_id: 1, pharmacy_name: 'Pharmacy A', status: 'low' },
    { pharmacy_id: 1, pharmacy_name: 'Pharmacy A', status: 'safe' },
    { pharmacy_id: 2, pharmacy_name: 'Pharmacy B', status: 'critical' },
  ]

  const selectedPharmacyId = 1

  // Simulate aggregation logic
  const pharmacyRows = allStockRows.filter((r) => r.pharmacy_id === selectedPharmacyId)
  const statuses = { critical: 0, low: 0, safe: 0, watch: 0, unknown: 0 }

  pharmacyRows.forEach((row) => {
    const status = row.status || 'unknown'
    if (statuses[status] !== undefined) {
      statuses[status] += 1
    }
  })

  assert.equal(statuses.critical, 2, 'Should count 2 critical items')
  assert.equal(statuses.low, 1, 'Should count 1 low item')
  assert.equal(statuses.safe, 1, 'Should count 1 safe item')
})

test('Pharmacy list: derives risk badge correctly', () => {
  const getRiskBadge = (criticalCount, lowCount) => {
    if (criticalCount > 0) return 'critical'
    if (lowCount > 0) return 'low'
    return 'safe'
  }

  assert.equal(getRiskBadge(2, 1), 'critical', 'Critical count takes precedence')
  assert.equal(getRiskBadge(0, 3), 'low', 'Low count shows when no critical')
  assert.equal(getRiskBadge(0, 0), 'safe', 'Safe when neither critical nor low')
})

test('Pharmacy selection: switching pharmacies clears detail data', () => {
  let selectedPharmacyId = 1
  let displayData = [
    { pharmacy_id: 1, medicine_name: 'Med A' },
    { pharmacy_id: 1, medicine_name: 'Med B' },
  ]

  // Simulate switching to pharmacy 2
  const allStockRows = [
    { pharmacy_id: 1, medicine_name: 'Med A' },
    { pharmacy_id: 1, medicine_name: 'Med B' },
    { pharmacy_id: 2, medicine_name: 'Med C' },
    { pharmacy_id: 2, medicine_name: 'Med D' },
  ]

  selectedPharmacyId = 2
  displayData = allStockRows.filter((r) => r.pharmacy_id === selectedPharmacyId)

  assert.equal(displayData.length, 2)
  assert.deepEqual(displayData.map((r) => r.medicine_name), ['Med C', 'Med D'])
})

test('Medicine filter: applies within selected pharmacy', () => {
  const allStockRows = [
    { pharmacy_id: 1, barcode: '123', medicine_name: 'Aspirin' },
    { pharmacy_id: 1, barcode: '456', medicine_name: 'Ibuprofen' },
    { pharmacy_id: 2, barcode: '789', medicine_name: 'Aspirin' },
  ]

  const selectedPharmacyId = 1
  const medicineFilter = 'Aspirin'

  let displayData = allStockRows.filter((r) => r.pharmacy_id === selectedPharmacyId)
  displayData = displayData.filter(
    (r) =>
      r.barcode.toLowerCase().includes(medicineFilter.toLowerCase()) ||
      r.medicine_name.toLowerCase().includes(medicineFilter.toLowerCase()),
  )

  assert.equal(displayData.length, 1)
  assert.equal(displayData[0].medicine_name, 'Aspirin')
  assert.equal(displayData[0].pharmacy_id, 1)
})
