function movementEvent({
  eventId,
  barcode = '6250000000010',
  movementType = 'sale',
  quantityDelta = -1,
  unitPriceMinor = 300,
  referenceType = 'receipt',
  referenceId = 'R-1',
  happenedAt = Date.now(),
  version = 1,
  metadata = {},
} = {}) {
  return {
    event_id: eventId,
    event_type: 'inventory_movement',
    payload: {
      barcode,
      movement_type: movementType,
      quantity_delta: quantityDelta,
      unit_price_minor: unitPriceMinor,
      currency_code: 'USD',
      reference_type: referenceType,
      reference_id: referenceId,
      happened_at: happenedAt,
      version,
      metadata,
    },
  };
}

function priceUpdateEvent({
  eventId,
  barcode = '6250000000010',
  newPriceMinor = 420,
  happenedAt = Date.now(),
  metadata = {},
} = {}) {
  return {
    event_id: eventId,
    event_type: 'price_update',
    payload: {
      barcode,
      new_price_minor: newPriceMinor,
      currency_code: 'USD',
      happened_at: happenedAt,
      metadata,
    },
  };
}

function pushBody({ requestId, events }) {
  return {
    request_id: requestId,
    events,
  };
}

module.exports = {
  movementEvent,
  priceUpdateEvent,
  pushBody,
};
