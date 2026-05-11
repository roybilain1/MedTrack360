const crypto = require('crypto');

function normalized(v) {
  return String(v || '').trim();
}

function normalizedLower(v) {
  return normalized(v).toLowerCase();
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

function normalizeEventTimestamp({ happenedAt, now = new Date(), futureToleranceMs = 5 * 60 * 1000 }) {
  const eventTime = toUtcDate(happenedAt, now);
  const latestAllowed = new Date(now.getTime() + futureToleranceMs);
  if (eventTime.getTime() > latestAllowed.getTime()) {
    return {
      timestamp: now,
      skewed: true,
      note: 'future_clock_skew_clamped',
    };
  }
  return {
    timestamp: eventTime,
    skewed: false,
    note: null,
  };
}

function deterministicVersionWinner(current, incoming) {
  const currentVersion = Number(current?.version || 1);
  const incomingVersion = Number(incoming?.version || 1);
  if (incomingVersion !== currentVersion) {
    return incomingVersion > currentVersion ? 'incoming' : 'current';
  }

  const currentUpdatedAt = new Date(current?.updated_at || 0).getTime();
  const incomingUpdatedAt = new Date(incoming?.updated_at || 0).getTime();
  if (incomingUpdatedAt !== currentUpdatedAt) {
    return incomingUpdatedAt > currentUpdatedAt ? 'incoming' : 'current';
  }

  const currentDevice = normalized(current?.device_id);
  const incomingDevice = normalized(incoming?.device_id);
  if (incomingDevice !== currentDevice) {
    return incomingDevice > currentDevice ? 'incoming' : 'current';
  }

  const currentEvent = normalized(current?.event_uuid || current?.event_id);
  const incomingEvent = normalized(incoming?.event_uuid || incoming?.event_id);
  return incomingEvent > currentEvent ? 'incoming' : 'current';
}

async function logConflict(client, args) {
  await client.query(
    `INSERT INTO sync_conflict_log (
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
       updated_at,
       deleted_at
     )
     VALUES (
       $1::uuid, $2, $3, $4, $5, $6, $7,
       $8::jsonb, $9::jsonb, $10, $11, $12,
       NOW(), NOW(), NULL
     )
     ON CONFLICT (conflict_uuid) DO NOTHING`,
    [
      args.conflictUuid || stableUuid(`${args.pharmacyId}:${args.entityType}:${args.entityId}:${args.field}:${args.conflictCode}`),
      args.pharmacyId,
      args.deviceId,
      args.entityType,
      args.entityId,
      args.field,
      args.conflictCode,
      JSON.stringify(args.localValue ?? null),
      JSON.stringify(args.serverValue ?? null),
      args.resolution || 'server_override',
      args.note || '',
      args.source || 'server',
    ]
  );
}

function normalizeInventoryMovementEvent(rawEvent, context) {
  const payload = toJsonObject(rawEvent.payload, {});
  const eventId = normalized(rawEvent.event_id || rawEvent.eventId);
  const movementType = normalizedLower(payload.movement_type || payload.movementType);
  const barcode = normalized(payload.barcode);

  const normalizedTime = normalizeEventTimestamp({
    happenedAt: payload.happened_at || payload.happenedAt,
    now: new Date(),
  });

  return {
    event_uuid: eventId,
    version: Math.max(1, toIntOrNull(payload.version) || 1),
    updated_at: new Date().toISOString(),
    source: normalized(payload.source || 'pos'),
    pharmacy_id: context.pharmacyId,
    device_id: context.deviceId,
    barcode,
    movement_type: movementType,
    quantity_delta: toIntOrNull(payload.quantity_delta ?? payload.quantityDelta) || 0,
    unit_price_minor: toIntOrNull(payload.unit_price_minor ?? payload.unitPriceMinor),
    currency_code: normalized(payload.currency_code || payload.currencyCode || 'USD') || 'USD',
    reference_type: normalized(payload.reference_type || payload.referenceType || ''),
    reference_id: normalized(payload.reference_id || payload.referenceId || ''),
    metadata: toJsonObject(payload.metadata, {}),
    happened_at: normalizedTime.timestamp.toISOString(),
    clock_skew_flag: normalizedTime.skewed,
    clock_skew_note: normalizedTime.note,
    deleted_at: payload.deleted_at || payload.deletedAt || null,
  };
}

async function deriveStockTotals(client, pharmacyId) {
  const result = await client.query(
    `SELECT
       barcode,
       GREATEST(0, SUM(quantity_delta))::int AS stock_units
     FROM inventory_movements
     WHERE pharmacy_id = $1
       AND deleted_at IS NULL
     GROUP BY barcode
     ORDER BY barcode ASC`,
    [pharmacyId]
  );
  return result.rows;
}

async function getServerControlledSnapshot(client, pharmacyId) {
  const [medicines, prices, complianceAlerts, maxMarkup] = await Promise.all([
    client.query(
      `SELECT
         md5(barcode)::uuid AS medicine_uuid,
         barcode,
         reg_number AS official_code,
         trade_name AS official_name,
         dosage,
         form,
         category,
         CAST(ROUND(moph_ceiling * 100) AS BIGINT) AS regulated_price_minor,
         is_blocked,
         updated_at,
         NULL::timestamptz AS deleted_at,
         'moph_registry'::text AS source,
         1::int AS version,
         $1::int AS pharmacy_id
       FROM moph_registry
       ORDER BY updated_at DESC
       LIMIT 2000`,
      [pharmacyId]
    ),
    client.query(
      `SELECT
         md5(barcode)::uuid AS price_uuid,
         barcode,
         regulated_price_minor,
         local_price_minor,
         currency_code,
         source,
         version,
         updated_at,
         deleted_at,
         $1::int AS pharmacy_id
       FROM prices
       WHERE deleted_at IS NULL
       ORDER BY updated_at DESC
       LIMIT 2000`,
      [pharmacyId]
    ),
    client.query(
      `SELECT
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
         updated_at,
         deleted_at,
         'compliance_engine'::text AS source,
         1::int AS version
       FROM compliance_alerts
       WHERE deleted_at IS NULL
         AND (pharmacy_id IS NULL OR pharmacy_id = $1)
       ORDER BY updated_at DESC
       LIMIT 1000`,
      [pharmacyId]
    ),
    client.query(
      `SELECT value
       FROM system_settings
       WHERE key = 'max_markup_pct'
       LIMIT 1`
    ),
  ]);

  const maxMarkupPct = Number(maxMarkup.rows[0]?.value?.value ?? 0.15);

  return {
    medicines: medicines.rows,
    prices: prices.rows,
    complianceAlerts: complianceAlerts.rows,
    settings: {
      max_markup_pct: Number.isFinite(maxMarkupPct) ? maxMarkupPct : 0.15,
    },
  };
}

module.exports = {
  normalized,
  normalizedLower,
  toIntOrNull,
  toJsonObject,
  stableUuid,
  normalizeEventTimestamp,
  deterministicVersionWinner,
  normalizeInventoryMovementEvent,
  deriveStockTotals,
  getServerControlledSnapshot,
  logConflict,
};
