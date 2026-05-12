const crypto = require('crypto');
const {
  normalizeInventoryMovementEvent,
  deterministicVersionWinner,
  deriveStockTotals,
  getServerControlledSnapshot,
  logConflict,
} = require('./reconciliation_service');

const SUPPORTED_EVENT_TYPES = new Set([
  'inventory_movement',
  'price_update',
  'compliance_note',
  'medicine_request_submitted',
]);

function normalized(v) {
  return String(v || '').trim();
}

function normalizedLower(v) {
  return normalized(v).toLowerCase();
}

function toUtcDate(value, fallback = new Date()) {
  const n = Number(value);
  if (Number.isFinite(n) && n > 0) {
    return new Date(n);
  }

  if (typeof value === 'string' && value.trim()) {
    const parsed = new Date(value);
    if (!Number.isNaN(parsed.getTime())) {
      return parsed;
    }
  }

  return fallback;
}

function toIntOrNull(value) {
  if (value == null || value === '') return null;
  const n = Number(value);
  if (!Number.isFinite(n)) return null;
  return Math.trunc(n);
}

function toJsonObject(value, fallback = {}) {
  if (value == null) return fallback;
  if (typeof value === 'string') {
    try {
      const parsed = JSON.parse(value);
      return parsed && typeof parsed === 'object' ? parsed : fallback;
    } catch {
      return fallback;
    }
  }
  if (typeof value === 'object') return value;
  return fallback;
}

function stableUuid(seed) {
  const hash = crypto.createHash('sha1').update(String(seed)).digest('hex').slice(0, 32);
  return `${hash.slice(0, 8)}-${hash.slice(8, 12)}-${hash.slice(12, 16)}-${hash.slice(16, 20)}-${hash.slice(20, 32)}`;
}

function encodeCursor(payload) {
  return Buffer.from(JSON.stringify(payload), 'utf8').toString('base64url');
}

function decodeCursor(cursor) {
  if (!cursor) return null;
  try {
    const json = Buffer.from(String(cursor), 'base64url').toString('utf8');
    const parsed = JSON.parse(json);
    if (!parsed || typeof parsed !== 'object') return null;
    if (!parsed.ts || !parsed.id) return null;
    return parsed;
  } catch {
    return null;
  }
}

function validatePushBody(body) {
  const requestId = normalized(body.request_id || body.requestId);
  const events = Array.isArray(body.events) ? body.events : [];

  if (!requestId) {
    return { error: 'request_id is required' };
  }

  if (events.length === 0) {
    return { error: 'events must be a non-empty array' };
  }

  for (const rawEvent of events) {
    const eventId = normalized(rawEvent.event_id || rawEvent.eventId);
    const eventType = normalizedLower(rawEvent.event_type || rawEvent.eventType);
    if (!eventId) {
      return { error: 'each event must include event_id' };
    }
    if (!SUPPORTED_EVENT_TYPES.has(eventType)) {
      return { error: `unsupported event_type: ${eventType}` };
    }
  }

  return {
    value: {
      requestId,
      events,
    },
  };
}

async function authenticatePharmacyDevice(client, context) {
  const headerPharmacyId = toIntOrNull(context.pharmacyId);
  const headerDeviceId = normalized(context.deviceId);
  const headerLicense = normalized(context.licenseNumber);

  if (!headerDeviceId) {
    throw new Error('x-device-id header is required');
  }

  if (!headerPharmacyId && !headerLicense) {
    throw new Error('x-pharmacy-id or x-license-number header is required');
  }

  let result;
  if (headerPharmacyId) {
    result = await client.query(
      `SELECT *
       FROM pharmacies
       WHERE id = $1
       LIMIT 1`,
      [headerPharmacyId]
    );
  } else {
    result = await client.query(
      `SELECT *
       FROM pharmacies
       WHERE license_number = $1
       LIMIT 1`,
      [headerLicense]
    );
  }

  const pharmacy = result.rows[0];
  if (!pharmacy) {
    throw new Error('pharmacy not found');
  }

  if (normalized(pharmacy.hwid) && normalizedLower(pharmacy.hwid) !== normalizedLower(headerDeviceId)) {
    throw new Error('device is not authorized for this pharmacy');
  }

  if (!normalized(pharmacy.hwid)) {
    const updated = await client.query(
      `UPDATE pharmacies
       SET hwid = $1,
           status = 'online',
           last_seen = 'just now'
       WHERE id = $2
       RETURNING *`,
      [headerDeviceId, pharmacy.id]
    );
    return updated.rows[0] || pharmacy;
  }

  await client.query(
    `UPDATE pharmacies
     SET status = 'online',
         last_seen = 'just now'
     WHERE id = $1`,
    [pharmacy.id]
  );

  return pharmacy;
}

async function assertAndStoreSyncRequest(client, args) {
  const inserted = await client.query(
    `INSERT INTO sync_requests (
       request_id,
       pharmacy_id,
       device_id,
       endpoint,
       payload,
       request_status,
       created_at,
       updated_at
     )
     VALUES ($1, $2, $3, $4, $5::jsonb, 'processing', NOW(), NOW())
     ON CONFLICT (request_id) DO NOTHING
     RETURNING id`,
    [
      args.requestId,
      args.pharmacyId,
      args.deviceId,
      args.endpoint,
      JSON.stringify(args.payload || {}),
    ]
  );

  if (inserted.rowCount > 0) {
    return { isDuplicate: false, syncRequestId: inserted.rows[0].id };
  }

  const existing = await client.query(
    `SELECT id, response_payload, request_status
     FROM sync_requests
     WHERE request_id = $1
     LIMIT 1`,
    [args.requestId]
  );

  const row = existing.rows[0];
  return {
    isDuplicate: true,
    syncRequestId: row?.id || null,
    requestStatus: row?.request_status || 'completed',
    responsePayload: row?.response_payload || null,
  };
}

async function markSyncRequestResult(client, args) {
  if (!args.syncRequestId) return;
  await client.query(
    `UPDATE sync_requests
     SET request_status = $2,
         response_payload = $3::jsonb,
         updated_at = NOW()
     WHERE id = $1`,
    [args.syncRequestId, args.status, JSON.stringify(args.response || {})]
  );
}

function validateInventoryMovementPayload(payload) {
  const barcode = normalized(payload.barcode);
  const movementType = normalizedLower(payload.movement_type || payload.movementType);
  const quantityDelta = toIntOrNull(payload.quantity_delta ?? payload.quantityDelta);

  if (!barcode) {
    return { error: 'inventory_movement payload.barcode is required' };
  }

  if (!movementType) {
    return { error: 'inventory_movement payload.movement_type is required' };
  }

  if (!Number.isFinite(quantityDelta)) {
    return { error: 'inventory_movement payload.quantity_delta must be an integer' };
  }

  return {
    value: {
      barcode,
      movementType,
      quantityDelta,
      unitPriceMinor: toIntOrNull(payload.unit_price_minor ?? payload.unitPriceMinor),
      currencyCode: normalized(payload.currency_code || payload.currencyCode || 'USD') || 'USD',
      referenceType: normalized(payload.reference_type || payload.referenceType || ''),
      referenceId: normalized(payload.reference_id || payload.referenceId || ''),
      metadata: toJsonObject(payload.metadata, {}),
      happenedAt: toUtcDate(payload.happened_at || payload.happenedAt).toISOString(),
      version: Math.max(1, toIntOrNull(payload.version) || 1),
    },
  };
}

function validateMedicineRequestPayload(payload) {
  const barcode = normalized(payload.barcode);
  const requestedName = normalized(payload.requested_name || payload.trade_name || payload.name);
  if (!barcode) {
    return { error: 'medicine_request_submitted payload.barcode is required' };
  }
  if (!requestedName) {
    return { error: 'medicine_request_submitted payload.requested_name is required' };
  }
  return {
    value: {
      barcode,
      requestedName,
      genericName: normalized(payload.generic_name || payload.genericName || requestedName),
      dosage: normalized(payload.dosage),
      category: normalized(payload.category),
      proposedPriceMinor: toIntOrNull(payload.proposed_price_minor ?? payload.proposedPriceMinor ?? Math.round(Number(payload.proposed_price || payload.proposedPrice || 0) * 100)),
      stockUnits: toIntOrNull(payload.stock ?? payload.stock_units ?? payload.stockUnits) ?? 0,
      expiry: normalized(payload.expiry),
      requestStatus: normalizedLower(payload.request_status || payload.requestStatus || 'pending_review') || 'pending_review',
      metadata: toJsonObject(payload.metadata, {}),
      requestUuid: normalized(payload.request_uuid || payload.requestUuid),
    },
  };
}

async function appendInventoryMovement(client, args) {
  const inserted = await client.query(
    `INSERT INTO inventory_movements (
       event_uuid,
       pharmacy_id,
       device_id,
       source,
       barcode,
       movement_type,
       quantity_delta,
       unit_price_minor,
       currency_code,
       reference_type,
       reference_id,
       metadata,
       happened_at,
       version,
       sync_status,
       updated_at,
       deleted_at
     )
     VALUES (
       $1::uuid, $2, $3, $4, $5, $6, $7, $8, $9,
       $10, $11, $12::jsonb, $13::timestamptz, $14, 'synced', NOW(), NULL
     )
     ON CONFLICT (event_uuid) DO NOTHING
     RETURNING id`,
    [
      args.eventId,
      args.pharmacyId,
      args.deviceId,
      args.source || 'pos',
      args.barcode,
      args.movementType,
      args.quantityDelta,
      args.unitPriceMinor,
      args.currencyCode,
      args.referenceType,
      args.referenceId,
      JSON.stringify(args.metadata || {}),
      args.happenedAt,
      args.version,
    ]
  );

  return inserted.rowCount > 0;
}

async function upsertMedicineRequest(client, args) {
  const inserted = await client.query(
    `INSERT INTO medicine_registration_requests (
       request_uuid,
       pharmacy_id,
       device_id,
       barcode,
       requested_name,
       generic_name,
       dosage,
       category,
       proposed_price_minor,
       stock_units,
       expiry,
       request_status,
       metadata,
       created_at,
       updated_at,
       deleted_at
     )
     VALUES (
       $1::uuid, $2, $3, $4, $5, $6, $7, $8, $9,
       $10, $11, $12, $13::jsonb, NOW(), NOW(), NULL
     )
     ON CONFLICT (request_uuid) DO UPDATE SET
       pharmacy_id = EXCLUDED.pharmacy_id,
       device_id = EXCLUDED.device_id,
       barcode = EXCLUDED.barcode,
       requested_name = EXCLUDED.requested_name,
       generic_name = EXCLUDED.generic_name,
       dosage = EXCLUDED.dosage,
       category = EXCLUDED.category,
       proposed_price_minor = EXCLUDED.proposed_price_minor,
       stock_units = EXCLUDED.stock_units,
       expiry = EXCLUDED.expiry,
       request_status = EXCLUDED.request_status,
       metadata = EXCLUDED.metadata,
       updated_at = NOW(),
       deleted_at = NULL
     RETURNING id`,
    [
      args.requestUuid,
      args.pharmacyId,
      args.deviceId,
      args.barcode,
      args.requestedName,
      args.genericName,
      args.dosage,
      args.category,
      args.proposedPriceMinor,
      args.stockUnits,
      args.expiry,
      args.requestStatus,
      JSON.stringify(args.metadata || {}),
    ]
  );

  return inserted.rowCount > 0;
}

async function upsertPrice(client, args) {
  const historyUuid = stableUuid(`price-history:${args.eventId}`);
  const existingHistory = await client.query(
    `SELECT id
     FROM price_history
     WHERE history_uuid = $1::uuid
     LIMIT 1`,
    [historyUuid]
  );

  if (existingHistory.rowCount > 0) {
    const current = await client.query(
      `SELECT local_price_minor
       FROM prices
       WHERE barcode = $1
       LIMIT 1`,
      [args.barcode]
    );
    return {
      duplicate: true,
      previousPriceMinor: toIntOrNull(current.rows[0]?.local_price_minor),
      newPriceMinor: toIntOrNull(current.rows[0]?.local_price_minor),
      barcode: args.barcode,
      currencyCode: args.currencyCode,
    };
  }

  const previous = await client.query(
    `SELECT local_price_minor
     FROM prices
     WHERE barcode = $1
     LIMIT 1`,
    [args.barcode]
  );
  const previousPriceMinor = toIntOrNull(previous.rows[0]?.local_price_minor);

  await client.query(
    `INSERT INTO prices (
       barcode,
       regulated_price_minor,
       local_price_minor,
       currency_code,
       source,
       version,
       updated_at,
       deleted_at
     )
     VALUES ($1, NULL, $2, $3, 'pos', 1, NOW(), NULL)
     ON CONFLICT (barcode) DO UPDATE SET
       local_price_minor = EXCLUDED.local_price_minor,
       currency_code = EXCLUDED.currency_code,
       source = EXCLUDED.source,
       version = prices.version + 1,
       updated_at = NOW()`,
    [args.barcode, args.newPriceMinor, args.currencyCode]
  );

  await client.query(
    `INSERT INTO price_history (
       history_uuid,
       barcode,
       pharmacy_id,
       previous_price_minor,
       new_price_minor,
       currency_code,
       source,
       changed_by,
       changed_at,
       metadata
     )
     VALUES (
       $1::uuid, $2, $3, $4, $5, $6, 'pos', $7, NOW(), $8::jsonb
     )
     ON CONFLICT (history_uuid) DO NOTHING`,
    [
      historyUuid,
      args.barcode,
      args.pharmacyId,
      previousPriceMinor,
      args.newPriceMinor,
      args.currencyCode,
      args.deviceId,
      JSON.stringify(args.metadata || {}),
    ]
  );

  return {
    duplicate: false,
    previousPriceMinor,
    newPriceMinor: args.newPriceMinor,
    barcode: args.barcode,
    currencyCode: args.currencyCode,
  };
}

async function insertAuditChange(client, args) {
  await client.query(
    `INSERT INTO audit_change_log (
       change_uuid,
       pharmacy_id,
       entity_type,
       entity_id,
       change_type,
       old_value,
       new_value,
       actor_identity,
       actor_role,
       device_id,
       source_ip,
       source,
       request_id,
       created_at,
       updated_at,
       deleted_at
     )
     VALUES (
       $1::uuid, $2, $3, $4, $5,
       $6::jsonb, $7::jsonb, $8, $9, $10, $11, $12, $13,
       NOW(), NOW(), NULL
     )
     ON CONFLICT (change_uuid) DO NOTHING`,
    [
      args.changeUuid,
      args.pharmacyId,
      args.entityType,
      args.entityId,
      args.changeType,
      JSON.stringify(args.oldValue || {}),
      JSON.stringify(args.newValue || {}),
      args.actorIdentity || null,
      args.actorRole || null,
      args.deviceId || null,
      args.sourceIp || null,
      args.source || 'sync',
      args.requestId || null,
    ]
  );
}

async function processPushEvents(client, args) {
  const conflicts = [];
  const acceptedEventIds = [];
  const duplicateEventIds = [];

  for (const rawEvent of args.events) {
    const eventId = normalized(rawEvent.event_id || rawEvent.eventId);
    const eventType = normalizedLower(rawEvent.event_type || rawEvent.eventType);
    const payload = toJsonObject(rawEvent.payload, {});

    if (eventType === 'inventory_movement') {
      const normalizedEvent = normalizeInventoryMovementEvent(rawEvent, {
        pharmacyId: args.pharmacy.id,
        deviceId: args.deviceId,
      });

      const validated = validateInventoryMovementPayload(payload);
      if (validated.error || !normalizedEvent.barcode || !normalizedEvent.movement_type) {
        conflicts.push({
          event_id: eventId,
          reason: validated.error || 'inventory_movement normalized payload is invalid',
          code: 'invalid_event_payload',
        });
        continue;
      }

      const movement = {
        ...validated.value,
        source: normalizedEvent.source,
        happenedAt: normalizedEvent.happened_at,
        version: normalizedEvent.version,
      };

      const existingMovement = await client.query(
        `SELECT event_uuid, version, updated_at, device_id
         FROM inventory_movements
         WHERE pharmacy_id = $1
           AND barcode = $2
           AND reference_type = $3
           AND reference_id = $4
           AND movement_type = $5
         ORDER BY updated_at DESC
         LIMIT 1`,
        [
          args.pharmacy.id,
          movement.barcode,
          movement.referenceType,
          movement.referenceId,
          movement.movementType,
        ]
      );

      if (existingMovement.rows.length > 0) {
        const winner = deterministicVersionWinner(existingMovement.rows[0], {
          version: movement.version,
          updated_at: new Date().toISOString(),
          device_id: args.deviceId,
          event_uuid: eventId,
        });

        if (winner === 'current') {
          duplicateEventIds.push(eventId);
          await logConflict(client, {
            pharmacyId: args.pharmacy.id,
            deviceId: args.deviceId,
            entityType: 'inventory_movement',
            entityId: movement.barcode,
            field: 'event_order',
            conflictCode: 'out_of_order_or_older_version',
            localValue: {
              existing_event_uuid: existingMovement.rows[0].event_uuid,
              existing_version: existingMovement.rows[0].version,
            },
            serverValue: {
              incoming_event_uuid: eventId,
              incoming_version: movement.version,
            },
            note: 'Older or out-of-order movement ignored deterministically.',
            source: 'server',
          });
          continue;
        }
      }

      const stockBeforeResult = await client.query(
        `SELECT COALESCE(SUM(quantity_delta), 0)::int AS stock_units
         FROM inventory_movements
         WHERE pharmacy_id = $1
           AND barcode = $2
           AND deleted_at IS NULL`,
        [args.pharmacy.id, movement.barcode]
      );
      const stockBefore = toIntOrNull(stockBeforeResult.rows[0]?.stock_units) || 0;

      const inserted = await appendInventoryMovement(client, {
        eventId,
        pharmacyId: args.pharmacy.id,
        deviceId: args.deviceId,
        ...movement,
      });

      if (!inserted) {
        duplicateEventIds.push(eventId);
        await logConflict(client, {
          pharmacyId: args.pharmacy.id,
          deviceId: args.deviceId,
          entityType: 'inventory_movement',
          entityId: movement.barcode,
          field: 'event_uuid',
          conflictCode: 'duplicate_event_uuid',
          localValue: { event_uuid: eventId },
          serverValue: { event_uuid: eventId },
          note: 'Duplicate push detected and ignored.',
          source: 'server',
        });
        continue;
      }

      const stockAfter = stockBefore + Number(movement.quantityDelta || 0);
      await insertAuditChange(client, {
        changeUuid: stableUuid(`audit:stock_change:${eventId}`),
        pharmacyId: args.pharmacy.id,
        entityType: 'inventory',
        entityId: movement.barcode,
        changeType: 'stock_change',
        oldValue: {
          stock_units: stockBefore,
          quantity_delta: 0,
        },
        newValue: {
          stock_units: stockAfter,
          quantity_delta: Number(movement.quantityDelta || 0),
          movement_type: movement.movementType,
          event_uuid: eventId,
        },
        actorIdentity: args.actorIdentity,
        actorRole: args.actorRole,
        deviceId: args.deviceId,
        sourceIp: args.sourceIp,
        source: 'sync_push',
        requestId: args.requestId,
      });

      if (normalizedEvent.clock_skew_flag) {
        await logConflict(client, {
          pharmacyId: args.pharmacy.id,
          deviceId: args.deviceId,
          entityType: 'inventory_movement',
          entityId: movement.barcode,
          field: 'happened_at',
          conflictCode: 'clock_skew_adjusted',
          localValue: payload.happened_at || payload.happenedAt,
          serverValue: movement.happenedAt,
          note: normalizedEvent.clock_skew_note,
          source: 'server',
        });
      }

      acceptedEventIds.push(eventId);

      const registry = await client.query(
        `SELECT moph_ceiling, is_blocked
         FROM moph_registry
         WHERE barcode = $1
         LIMIT 1`,
        [movement.barcode]
      );
      const regRow = registry.rows[0];
      const regulatedPriceMinor = regRow?.moph_ceiling != null
        ? Math.round(Number(regRow.moph_ceiling) * 100)
        : null;

      if (regRow?.is_blocked === true && movement.movementType === 'sale' && movement.quantityDelta < 0) {
        const conflict = {
          event_id: eventId,
          code: 'blocked_sale',
          reason: 'blocked medicine cannot be sold',
          barcode: movement.barcode,
        };
        conflicts.push(conflict);
        await logConflict(client, {
          pharmacyId: args.pharmacy.id,
          deviceId: args.deviceId,
          entityType: 'medicine',
          entityId: movement.barcode,
          field: 'blocked_status',
          conflictCode: 'server_block_override',
          localValue: false,
          serverValue: true,
          note: 'Blocked medicine sale attempted. Server authoritative block applied.',
          source: 'server',
        });

        await client.query(
          `INSERT INTO compliance_alerts (
             alert_uuid,
             pharmacy_id,
             device_id,
             barcode,
             alert_type,
             severity,
             title,
             details,
             status,
             created_at,
             updated_at
           )
           VALUES ($1::uuid, $2, $3, $4, 'blocked_sale', 'critical', $5, $6::jsonb, 'open', NOW(), NOW())
           ON CONFLICT (alert_uuid) DO NOTHING`,
          [
            stableUuid(`blocked-sale:${eventId}`),
            args.pharmacy.id,
            args.deviceId,
            movement.barcode,
            `Blocked medicine sold for barcode ${movement.barcode}`,
            JSON.stringify(conflict),
          ]
        );
      }

      if (
        regulatedPriceMinor != null &&
        Number.isFinite(movement.unitPriceMinor) &&
        movement.unitPriceMinor > regulatedPriceMinor
      ) {
        const conflict = {
          event_id: eventId,
          code: 'price_violation',
          reason: 'charged price exceeds regulated price',
          barcode: movement.barcode,
          regulated_price_minor: regulatedPriceMinor,
          charged_price_minor: movement.unitPriceMinor,
        };
        conflicts.push(conflict);
        await logConflict(client, {
          pharmacyId: args.pharmacy.id,
          deviceId: args.deviceId,
          entityType: 'price',
          entityId: movement.barcode,
          field: 'regulated_price_minor',
          conflictCode: 'regulated_price_override',
          localValue: movement.unitPriceMinor,
          serverValue: regulatedPriceMinor,
          note: 'Selling price exceeded regulated ceiling. Server rule retained.',
          source: 'server',
        });

        await client.query(
          `INSERT INTO compliance_alerts (
             alert_uuid,
             pharmacy_id,
             device_id,
             barcode,
             alert_type,
             severity,
             title,
             details,
             status,
             created_at,
             updated_at
           )
           VALUES ($1::uuid, $2, $3, $4, 'price_violation', 'high', $5, $6::jsonb, 'open', NOW(), NOW())
           ON CONFLICT (alert_uuid) DO NOTHING`,
          [
            stableUuid(`price-violation:${eventId}`),
            args.pharmacy.id,
            args.deviceId,
            movement.barcode,
            `Price violation for barcode ${movement.barcode}`,
            JSON.stringify(conflict),
          ]
        );
      }
    } else if (eventType === 'price_update') {
      const barcode = normalized(payload.barcode);
      const newPriceMinor = toIntOrNull(payload.new_price_minor ?? payload.newPriceMinor);
      const currencyCode = normalized(payload.currency_code || payload.currencyCode || 'USD') || 'USD';
      if (!barcode || !Number.isFinite(newPriceMinor)) {
        conflicts.push({
          event_id: eventId,
          reason: 'price_update requires barcode and new_price_minor integer',
          code: 'invalid_event_payload',
        });
        continue;
      }

      const priceChange = await upsertPrice(client, {
        eventId,
        pharmacyId: args.pharmacy.id,
        deviceId: args.deviceId,
        barcode,
        newPriceMinor,
        currencyCode,
        metadata: toJsonObject(payload.metadata, {}),
      });

      if (priceChange.duplicate) {
        duplicateEventIds.push(eventId);
        continue;
      }

      await insertAuditChange(client, {
        changeUuid: stableUuid(`audit:price_change:${eventId}`),
        pharmacyId: args.pharmacy.id,
        entityType: 'price',
        entityId: barcode,
        changeType: 'price_update',
        oldValue: {
          local_price_minor: priceChange.previousPriceMinor,
          currency_code: currencyCode,
        },
        newValue: {
          local_price_minor: priceChange.newPriceMinor,
          currency_code: currencyCode,
          event_uuid: eventId,
        },
        actorIdentity: args.actorIdentity,
        actorRole: args.actorRole,
        deviceId: args.deviceId,
        sourceIp: args.sourceIp,
        source: 'sync_push',
        requestId: args.requestId,
      });

      acceptedEventIds.push(eventId);
    } else if (eventType === 'compliance_note') {
      await client.query(
        `INSERT INTO audit_logs (
           event_id,
           pharmacy_name,
           hwid,
           license_number,
           region,
           event_type,
           metadata,
           created_at
         )
         VALUES ($1, $2, $3, $4, $5, 'compliance_note', $6::jsonb, NOW())`,
        [
          eventId,
          args.pharmacy.name,
          args.deviceId,
          args.pharmacy.license_number,
          args.pharmacy.region,
          JSON.stringify(toJsonObject(payload, {})),
        ]
      );
      acceptedEventIds.push(eventId);
    } else if (eventType === 'medicine_request_submitted') {
      const validated = validateMedicineRequestPayload(payload);
      if (validated.error) {
        conflicts.push({
          event_id: eventId,
          reason: validated.error,
          code: 'invalid_event_payload',
        });
        continue;
      }

      const requestUuid = validated.value.requestUuid || eventId;
      const inserted = await upsertMedicineRequest(client, {
        requestUuid,
        pharmacyId: args.pharmacy.id,
        deviceId: args.deviceId,
        ...validated.value,
      });

      if (!inserted) {
        duplicateEventIds.push(eventId);
        continue;
      }

      await client.query(
        `INSERT INTO audit_logs (
           event_id,
           pharmacy_name,
           hwid,
           license_number,
           region,
           event_type,
           metadata,
           created_at
         )
         VALUES ($1, $2, $3, $4, $5, 'medicine_request_submitted', $6::jsonb, NOW())`,
        [
          eventId,
          args.pharmacy.name,
          args.deviceId,
          args.pharmacy.license_number,
          args.pharmacy.region,
          JSON.stringify({
            barcode: validated.value.barcode,
            requested_name: validated.value.requestedName,
            request_uuid: requestUuid,
          }),
        ]
      );

      acceptedEventIds.push(eventId);
    }

    await client.query(
      `INSERT INTO audit_logs (
         event_id,
         pharmacy_name,
         hwid,
         license_number,
         region,
         event_type,
         metadata,
         created_at
       )
       VALUES ($1, $2, $3, $4, $5, 'sync_push_event', $6::jsonb, NOW())`,
      [
        eventId,
        args.pharmacy.name,
        args.deviceId,
        args.pharmacy.license_number,
        args.pharmacy.region,
        JSON.stringify({
          event_type: eventType,
          received_at: new Date().toISOString(),
        }),
      ]
    );
  }

  return {
    acceptedEventIds,
    duplicateEventIds,
    conflicts,
  };
}

async function pullSyncData(client, args) {
  const cursorPayload = decodeCursor(args.cursor);
  const pageSize = Math.min(Math.max(toIntOrNull(args.limit) || 200, 1), 500);

  const cursorTime = cursorPayload?.ts ? new Date(cursorPayload.ts) : new Date(0);
  const cursorId = cursorPayload?.id || '00000000-0000-0000-0000-000000000000';

  const movementRows = await client.query(
    `SELECT
       event_uuid,
       barcode,
       movement_type,
       quantity_delta,
      source,
       unit_price_minor,
       currency_code,
       reference_type,
       reference_id,
       metadata,
       happened_at,
       updated_at,
       version
     FROM inventory_movements
     WHERE pharmacy_id = $1
       AND deleted_at IS NULL
       AND (
         updated_at > $2
         OR (updated_at = $2 AND event_uuid::text > $3)
       )
     ORDER BY updated_at ASC, event_uuid ASC
     LIMIT $4`,
    [args.pharmacy.id, cursorTime, cursorId, pageSize]
  );

  const priceRows = await client.query(
    `SELECT
       md5(p.barcode)::uuid AS price_uuid,
       $1::int AS pharmacy_id,
       p.barcode,
       p.regulated_price_minor,
       -- Per-pharmacy price: prefer pharmacy_stock.current_price,
       -- fall back to the global prices.local_price_minor.
       COALESCE(
         ROUND(ps.current_price * 100)::bigint,
         p.local_price_minor
       ) AS local_price_minor,
       p.currency_code,
       p.source,
       p.version,
       p.deleted_at,
       p.updated_at
     FROM prices p
     LEFT JOIN moph_registry mr ON mr.barcode = p.barcode
     LEFT JOIN pharmacy_stock ps
       ON ps.medication_id = mr.medication_id
      AND ps.pharmacy_id = $1
     WHERE p.deleted_at IS NULL
     ORDER BY p.updated_at DESC
     LIMIT 500`,
    [args.pharmacy.id]
  );

  const alertRows = await client.query(
    `SELECT
       alert_uuid,
       COALESCE(pharmacy_id, $1::int) AS pharmacy_id,
       barcode,
       alert_type,
       severity,
       title,
       details,
       status,
       source,
       version,
       deleted_at,
       created_at,
       updated_at
     FROM compliance_alerts
     WHERE deleted_at IS NULL
       AND status = 'open'
       AND (pharmacy_id IS NULL OR pharmacy_id = $1)
     ORDER BY created_at DESC
     LIMIT 500`,
    [args.pharmacy.id]
  );

  let medicineRequestRows = { rows: [] };
  try {
    medicineRequestRows = await client.query(
      `SELECT
         request_uuid,
         pharmacy_id,
         device_id,
         barcode,
         requested_name,
         generic_name,
         dosage,
         category,
         proposed_price_minor,
         stock_units,
         expiry,
         request_status,
         official_medicine_id,
         review_notes,
         metadata,
         reviewed_at,
         created_at,
         updated_at,
         deleted_at
       FROM medicine_registration_requests
       WHERE deleted_at IS NULL
         AND pharmacy_id = $1
       ORDER BY created_at DESC
       LIMIT 500`,
      [args.pharmacy.id]
    );
  } catch (error) {
    if (!String(error?.message || '').includes('medicine_registration_requests')) {
      throw error;
    }
  }

  const stockTotals = await deriveStockTotals(client, args.pharmacy.id);
  const authoritative = await getServerControlledSnapshot(client, args.pharmacy.id);
  const conflictNotes = await client.query(
    `SELECT
       conflict_uuid,
       pharmacy_id,
       device_id,
       entity_type,
       entity_id,
       field,
       conflict_code,
       local_value,
       server_value,
       resolution,
       note,
       source,
       created_at,
       updated_at
     FROM sync_conflict_log
     WHERE deleted_at IS NULL
       AND pharmacy_id = $1
     ORDER BY created_at DESC
     LIMIT 300`,
    [args.pharmacy.id]
  );

  const lastMovement = movementRows.rows[movementRows.rows.length - 1] || null;
  const nextCursor = lastMovement
    ? encodeCursor({
        ts: new Date(lastMovement.updated_at).toISOString(),
        id: String(lastMovement.event_uuid),
      })
    : args.cursor || null;

  return {
    events: movementRows.rows,
    regulated_prices: priceRows.rows,
    compliance_alerts: alertRows.rows,
    stock_totals: stockTotals,
    authoritative_medicines: authoritative.medicines,
    compliance_status: authoritative.complianceAlerts,
    max_markup_settings: authoritative.settings,
    medicine_requests: medicineRequestRows.rows,
    conflict_notes: conflictNotes.rows,
    next_cursor: movementRows.rows.length === pageSize ? nextCursor : null,
  };
}

module.exports = {
  SUPPORTED_EVENT_TYPES,
  normalized,
  normalizedLower,
  stableUuid,
  validatePushBody,
  authenticatePharmacyDevice,
  assertAndStoreSyncRequest,
  markSyncRequestResult,
  processPushEvents,
  pullSyncData,
  decodeCursor,
  encodeCursor,
};
