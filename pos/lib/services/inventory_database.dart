import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../config/app_config.dart';

const String kSyncProtocolVersion = '2026-04-07';

AppConfig get _appConfig => AppConfig.current;
String get kApiBaseUrl => _appConfig.apiBaseUrl;
String get kSyncApiKey => _appConfig.syncApiKey;
int get kPharmacyId => _appConfig.pharmacyId;
String get kPosHwid => _appConfig.deviceId;
String get kPosAppVersion => _appConfig.appVersion;
String get kPosBranchName => _appConfig.branchName;
String get kPosLicenseNumber => _appConfig.licenseNumber;
String get kPosRegion => _appConfig.region;

double? _asDoubleOrNull(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

int? _asIntOrNull(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

bool _asBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value.toInt() != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }
  return false;
}

String _asString(dynamic value) {
  if (value == null) return '';
  return value.toString();
}

DateTime? _asDateTimeOrNull(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final parsedInt = int.tryParse(trimmed);
    if (parsedInt != null) {
      return DateTime.fromMillisecondsSinceEpoch(parsedInt);
    }
    return DateTime.tryParse(trimmed);
  }
  return null;
}

int _toMinorUnits(dynamic value) {
  final asDouble = _asDoubleOrNull(value) ?? 0.0;
  return (asDouble * 100).round();
}

double? extractOfficialPrice(Map<String, dynamic> row) {
  final directCeiling = _asDoubleOrNull(row['moph_ceiling']);
  if (directCeiling != null) return directCeiling;

  final regulatedMinor = _asIntOrNull(row['regulated_price_minor']);
  if (regulatedMinor == null) return null;
  return regulatedMinor / 100.0;
}

String resolveOfficialName(Map<String, dynamic> row) {
  final preferred = _asString(
    row['official_name'] ??
        row['trade_name'] ??
        row['medication_name'] ??
        row['name'],
  ).trim();
  if (preferred.isNotEmpty) return preferred;
  return _asString(row['barcode']).trim();
}

String resolveOfficialCode(Map<String, dynamic> row) {
  return _asString(row['official_code'] ?? row['reg_number']).trim();
}

int _utcNowMs() => DateTime.now().toUtc().millisecondsSinceEpoch;

String _newUuid() {
  final r = Random.secure();
  String hex(int n) => n.toRadixString(16).padLeft(2, '0');
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final s = bytes.map(hex).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20, 32)}';
}

class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.barcode,
    required this.name,
    required this.dosage,
    required this.category,
    required this.stock,
    required this.expiry,
    required this.price,
    this.mophCeiling,
    this.batchNumber = '',
    this.approvalStatus = 'approved',
    this.officialCode = '',
    this.requestUuid = '',
    this.officialMedicineId,
    this.isBlocked = false,
  });

  final int id;
  final String barcode;
  final String name;
  final String dosage;
  final String category;
  final int stock;
  final String expiry;
  final double price;
  final double? mophCeiling;
  final String batchNumber;
  final String approvalStatus;
  final String officialCode;
  final String requestUuid;
  final int? officialMedicineId;
  final bool isBlocked;

  bool get exceedsCeiling => mophCeiling != null && price > mophCeiling!;
  bool get isPendingApproval => approvalStatus != 'approved';

  factory InventoryItem.fromMap(Map<String, dynamic> m) => InventoryItem(
    id: _asIntOrNull(m['id']) ?? 0,
    barcode: _asString(m['barcode']),
    name: _asString(m['name']),
    dosage: _asString(m['dosage']),
    category: _asString(m['category']),
    stock: _asIntOrNull(m['stock']) ?? 0,
    expiry: _asString(m['expiry']),
    price: _asDoubleOrNull(m['price']) ?? 0,
    mophCeiling: _asDoubleOrNull(m['moph_ceiling']),
    batchNumber: _asString(m['batch_number']),
    approvalStatus: _asString(m['approval_status']).isEmpty
        ? 'approved'
        : _asString(m['approval_status']),
    officialCode: _asString(m['official_code']),
    requestUuid: _asString(m['request_uuid']),
    officialMedicineId: _asIntOrNull(m['official_medicine_id']),
    isBlocked: _asBool(m['is_blocked']),
  );
}

enum MedicineOnboardingOutcome { linked, pending, alreadyPending, rejected }

class MedicineOnboardingResult {
  const MedicineOnboardingResult({
    required this.outcome,
    required this.message,
  });

  final MedicineOnboardingOutcome outcome;
  final String message;
}

class OfflineSaleRecord {
  const OfflineSaleRecord({
    required this.id,
    required this.receiptId,
    required this.saleDataJson,
    required this.createdAt,
    required this.synced,
  });

  final int id;
  final String receiptId;
  final String saleDataJson;
  final DateTime createdAt;
  final bool synced;

  factory OfflineSaleRecord.fromMap(Map<String, dynamic> m) =>
      OfflineSaleRecord(
        id: _asIntOrNull(m['id']) ?? 0,
        receiptId: _asString(m['receipt_id']),
        saleDataJson: _asString(m['sale_data']).isEmpty
            ? '{}'
            : _asString(m['sale_data']),
        createdAt:
            _asDateTimeOrNull(m['created_at']) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        synced: _asBool(m['synced']) || _asString(m['sync_status']) == 'synced',
      );
}

class UnmappedBarcode {
  const UnmappedBarcode({
    required this.id,
    required this.barcode,
    required this.scanCount,
    required this.firstSeen,
  });

  final int id;
  final String barcode;
  final int scanCount;
  final DateTime firstSeen;

  factory UnmappedBarcode.fromMap(Map<String, dynamic> m) => UnmappedBarcode(
    id: _asIntOrNull(m['id']) ?? 0,
    barcode: _asString(m['barcode']),
    scanCount: _asIntOrNull(m['scan_count']) ?? 0,
    firstSeen:
        _asDateTimeOrNull(m['first_seen']) ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );
}

class PurchaseItem {
  const PurchaseItem({
    required this.barcode,
    required this.name,
    required this.dosage,
    required this.qty,
    required this.costPrice,
  });

  final String barcode;
  final String name;
  final String dosage;
  final int qty;
  final double costPrice;

  double get lineTotal => qty * costPrice;

  factory PurchaseItem.fromMap(Map<String, dynamic> m) => PurchaseItem(
    barcode: _asString(m['barcode']),
    name: _asString(m['name']),
    dosage: _asString(m['dosage']),
    qty: _asIntOrNull(m['qty']) ?? 0,
    costPrice: _asDoubleOrNull(m['cost_price']) ?? 0,
  );
}

class PurchaseOrder {
  const PurchaseOrder({
    required this.id,
    required this.receiptId,
    required this.supplierName,
    required this.invoiceNumber,
    required this.createdAt,
    required this.items,
  });

  final int id;
  final String receiptId;
  final String supplierName;
  final String invoiceNumber;
  final DateTime createdAt;
  final List<PurchaseItem> items;

  int get totalUnits => items.fold(0, (s, e) => s + e.qty);
  double get grandTotal => items.fold(0.0, (s, e) => s + e.lineTotal);
}

class MoPhDrug {
  const MoPhDrug({
    required this.regNumber,
    required this.tradeName,
    required this.genericName,
    required this.dosage,
    required this.form,
    required this.category,
    required this.officialPrice,
  });

  final String regNumber;
  final String tradeName;
  final String genericName;
  final String dosage;
  final String form;
  final String category;
  final double officialPrice;
}

// Real-data-only: list is populated from backend sync-down, not hardcoded constants.
const List<MoPhDrug> kMoPhMasterList = [];

class PosSaleItem {
  const PosSaleItem({
    required this.barcode,
    required this.product,
    required this.dosage,
    required this.price,
    required this.qty,
    required this.total,
  });

  final String barcode;
  final String product;
  final String dosage;
  final double price;
  final int qty;
  final double total;

  factory PosSaleItem.fromMap(Map<String, dynamic> m) => PosSaleItem(
    barcode: _asString(m['barcode']),
    product: _asString(m['product']),
    dosage: _asString(m['dosage']),
    price: _asDoubleOrNull(m['price']) ?? 0,
    qty: _asIntOrNull(m['qty']) ?? 0,
    total: _asDoubleOrNull(m['total']) ?? 0,
  );
}

class PosSaleRecord {
  const PosSaleRecord({
    required this.receiptId,
    required this.timestamp,
    required this.method,
    required this.customer,
    required this.subtotal,
    required this.mophTax,
    required this.vat,
    required this.grandTotal,
    required this.items,
    required this.synced,
  });

  final String receiptId;
  final DateTime timestamp;
  final String method;
  final String? customer;
  final double subtotal;
  final double mophTax;
  final double vat;
  final double grandTotal;
  final List<PosSaleItem> items;
  final bool synced;

  factory PosSaleRecord.fromQueueMap(Map<String, dynamic> row) {
    final createdAt = _asDateTimeOrNull(row['created_at']) ?? DateTime.now();

    Map<String, dynamic> payload;
    try {
      final raw = row['sale_data'];
      if (raw is Map) {
        payload = Map<String, dynamic>.from(raw.cast<String, dynamic>());
      } else {
        payload =
            jsonDecode(_asString(raw).isEmpty ? '{}' : _asString(raw))
                as Map<String, dynamic>;
      }
    } catch (_) {
      payload = const {};
    }

    final parsedTimestamp =
        _asDateTimeOrNull(payload['timestamp']) ?? createdAt;
    final itemMaps = (payload['items'] as List?)?.cast<Map>() ?? const [];

    return PosSaleRecord(
      receiptId: _asString(row['receipt_id']),
      timestamp: parsedTimestamp,
      method: _asString(payload['method']).isEmpty
          ? 'CASH'
          : _asString(payload['method']),
      customer: _asString(payload['customer']).trim().isEmpty
          ? null
          : _asString(payload['customer']).trim(),
      subtotal: _asDoubleOrNull(payload['subtotal']) ?? 0,
      mophTax: _asDoubleOrNull(payload['moph_tax']) ?? 0,
      vat: _asDoubleOrNull(payload['vat']) ?? 0,
      grandTotal: _asDoubleOrNull(payload['grand_total']) ?? 0,
      items: itemMaps
          .map((e) => PosSaleItem.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      synced:
          _asBool(row['synced']) || _asString(row['sync_status']) == 'synced',
    );
  }
}

class LoanCustomerSummary {
  const LoanCustomerSummary({
    required this.name,
    required this.phone,
    required this.loanCount,
    required this.totalLoanAmount,
    required this.totalRepaidAmount,
    required this.outstandingAmount,
    required this.lastLoanAt,
    required this.lastRepaymentAt,
  });

  final String name;
  final String phone;
  final int loanCount;
  final double totalLoanAmount;
  final double totalRepaidAmount;
  final double outstandingAmount;
  final DateTime? lastLoanAt;
  final DateTime? lastRepaymentAt;
}

class LoanRepaymentRecord {
  const LoanRepaymentRecord({
    required this.id,
    required this.repaymentUuid,
    required this.customerName,
    required this.amountPaid,
    required this.paymentMethod,
    required this.note,
    required this.createdAt,
    required this.syncStatus,
  });

  final int id;
  final String repaymentUuid;
  final String customerName;
  final double amountPaid;
  final String paymentMethod;
  final String note;
  final DateTime createdAt;
  final String syncStatus;

  factory LoanRepaymentRecord.fromMap(Map<String, Object?> row) {
    final createdAtMs = _asIntOrNull(row['created_at']) ?? _utcNowMs();
    return LoanRepaymentRecord(
      id: _asIntOrNull(row['id']) ?? 0,
      repaymentUuid: _asString(row['repayment_uuid']),
      customerName: _asString(row['customer_name']).trim(),
      amountPaid: _asDoubleOrNull(row['amount_paid']) ?? 0,
      paymentMethod: _asString(row['payment_method']).toUpperCase(),
      note: _asString(row['note']),
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMs),
      syncStatus: _asString(row['sync_status']).isEmpty
          ? 'pending'
          : _asString(row['sync_status']),
    );
  }
}

class SyncOutboxRecord {
  const SyncOutboxRecord({
    required this.id,
    required this.eventUuid,
    required this.stream,
    required this.payload,
    required this.syncStatus,
    required this.retryCount,
    this.lastError,
    required this.createdAt,
    required this.updatedAt,
    this.syncedAt,
  });

  final int id;
  final String eventUuid;
  final String stream;
  final Map<String, dynamic> payload;
  final String syncStatus;
  final int retryCount;
  final String? lastError;
  final int createdAt;
  final int updatedAt;
  final int? syncedAt;

  factory SyncOutboxRecord.fromMap(Map<String, dynamic> m) {
    Map<String, dynamic> payload;
    try {
      payload = Map<String, dynamic>.from(
        jsonDecode((m['payload'] as String?) ?? '{}') as Map,
      );
    } catch (_) {
      payload = const {};
    }

    return SyncOutboxRecord(
      id: _asIntOrNull(m['id']) ?? 0,
      eventUuid: _asString(m['event_uuid']),
      stream: _asString(m['stream']),
      payload: payload,
      syncStatus: _asString(m['sync_status']).isEmpty
          ? 'pending'
          : _asString(m['sync_status']),
      retryCount: _asIntOrNull(m['retry_count']) ?? 0,
      lastError: m['last_error'] as String?,
      createdAt: _asIntOrNull(m['created_at']) ?? 0,
      updatedAt: _asIntOrNull(m['updated_at']) ?? 0,
      syncedAt: _asIntOrNull(m['synced_at']),
    );
  }
}

class SyncConflict {
  const SyncConflict({
    required this.entity,
    required this.entityId,
    required this.field,
    required this.localValue,
    required this.serverValue,
  });

  final String entity;
  final String entityId;
  final String field;
  final dynamic localValue;
  final dynamic serverValue;
}

typedef SyncConflictHandler = Future<void> Function(SyncConflict conflict);

enum SyncBackendFamily { central, proxy }

class InventoryDatabase {
  InventoryDatabase._();
  static final InventoryDatabase instance = InventoryDatabase._();

  Database? _db;
  SyncBackendFamily? _backendFamily;
  static const double _loanBalanceEpsilon = 0.000001;
  final StreamController<int> _inventoryChanges =
      StreamController<int>.broadcast();
  int _inventoryChangeTick = 0;

  Stream<int> get inventoryChanges => _inventoryChanges.stream;

  /// Fetch active Ministry announcements targeted at the POS.
  /// Returns a list of {id, title, body, source, url, created_at} maps.
  /// Returns [] on any HTTP error so callers can degrade gracefully.
  Future<List<Map<String, dynamic>>> fetchAnnouncements({int limit = 20}) async {
    try {
      final family = await resolveBackendFamily();
      final uri = _syncUriForFamily(
        family,
        'sync/announcements',
        'sync/announcements',
      ).replace(queryParameters: {'limit': '$limit'});
      final response = await http
          .get(uri, headers: _canonicalSyncHeaders())
          .timeout(_appConfig.requestTimeout);
      if (response.statusCode != 200) return const [];
      final json = jsonDecode(response.body);
      final rows = (json is Map ? json['data'] : null) as List?;
      if (rows == null) return const [];
      return rows
          .whereType<Map>()
          .map((r) => Map<String, dynamic>.from(r))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  void _emitInventoryChanged() {
    if (_inventoryChanges.isClosed) return;
    _inventoryChangeTick += 1;
    _inventoryChanges.add(_inventoryChangeTick);
  }

  Uri _syncUriForFamily(
    SyncBackendFamily family,
    String centralPath,
    String proxyPath,
  ) {
    return _appConfig.syncUriFor(
      family == SyncBackendFamily.central ? centralPath : proxyPath,
    );
  }

  Future<SyncBackendFamily> resolveBackendFamily({bool refresh = false}) async {
    if (!refresh && _backendFamily != null) return _backendFamily!;

    Future<bool> probe(Uri uri) async {
      try {
        final response = await http.get(uri).timeout(_appConfig.healthTimeout);
        return response.statusCode >= 200 && response.statusCode < 300;
      } catch (_) {
        return false;
      }
    }

    if (await probe(_appConfig.centralHealthUri)) {
      _backendFamily = SyncBackendFamily.central;
      return _backendFamily!;
    }
    if (await probe(_appConfig.proxyHealthUri)) {
      _backendFamily = SyncBackendFamily.proxy;
      return _backendFamily!;
    }

    _backendFamily ??= SyncBackendFamily.central;
    return _backendFamily!;
  }

  void _logSyncHttpFailure({
    required String operation,
    required Uri uri,
    required int statusCode,
    required SyncBackendFamily family,
  }) {
    final base = _appConfig.apiBaseUrl;
    final path = uri.path.isEmpty ? '/' : uri.path;
    print(
      '[InventoryDatabase] $operation failed: base=$base path=$path status=$statusCode family=${family.name}',
    );
  }

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'medtrack_inventory.db');
    final database = await openDatabase(
      path,
      version: 9,
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _createSchema(db);
      },
    );
    return database;
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
			CREATE TABLE IF NOT EXISTS inventory (
				id INTEGER PRIMARY KEY AUTOINCREMENT,
				barcode TEXT NOT NULL UNIQUE,
				name TEXT NOT NULL,
				dosage TEXT NOT NULL DEFAULT '',
				category TEXT NOT NULL DEFAULT '',
				stock INTEGER NOT NULL DEFAULT 0,
				expiry TEXT NOT NULL DEFAULT '',
				price REAL NOT NULL DEFAULT 0,
				moph_ceiling REAL,
				batch_number TEXT NOT NULL DEFAULT ''
			)
		''');

    await _safeAddColumn(
      db,
      'inventory',
      'is_blocked INTEGER NOT NULL DEFAULT 0',
    );
    await _safeAddColumn(
      db,
      'inventory',
      "approval_status TEXT NOT NULL DEFAULT 'approved'",
    );
    await _safeAddColumn(
      db,
      'inventory',
      "official_code TEXT NOT NULL DEFAULT ''",
    );
    await _safeAddColumn(
      db,
      'inventory',
      "request_uuid TEXT NOT NULL DEFAULT ''",
    );
    await _safeAddColumn(db, 'inventory', 'official_medicine_id INTEGER');
    await _safeAddColumn(
      db,
      'inventory',
      "pending_reason TEXT NOT NULL DEFAULT ''",
    );
    await _safeAddColumn(db, 'inventory', 'server_updated_at INTEGER');
    await _safeAddColumn(db, 'inventory', 'product_uuid TEXT');
    await _safeAddColumn(db, 'inventory', 'pharmacy_id INTEGER');
    await _safeAddColumn(
      db,
      'inventory',
      "source TEXT NOT NULL DEFAULT 'local'",
    );
    await _safeAddColumn(db, 'inventory', 'version INTEGER NOT NULL DEFAULT 1');
    await _safeAddColumn(db, 'inventory', 'updated_at INTEGER');
    await _safeAddColumn(db, 'inventory', 'deleted_at INTEGER');

    await db.execute('''
			CREATE TABLE IF NOT EXISTS unmapped_barcodes (
				id INTEGER PRIMARY KEY AUTOINCREMENT,
				barcode TEXT NOT NULL UNIQUE,
				scan_count INTEGER NOT NULL DEFAULT 1,
				first_seen INTEGER NOT NULL
			)
		''');

    await db.execute('''
			CREATE TABLE IF NOT EXISTS offline_sale_queue (
				id INTEGER PRIMARY KEY AUTOINCREMENT,
				receipt_id TEXT NOT NULL,
				sale_data TEXT NOT NULL,
				created_at INTEGER NOT NULL,
				synced INTEGER NOT NULL DEFAULT 0
			)
		''');

    await _safeAddColumn(db, 'offline_sale_queue', 'sale_uuid TEXT');
    await _safeAddColumn(db, 'offline_sale_queue', 'pharmacy_id INTEGER');
    await _safeAddColumn(db, 'offline_sale_queue', 'device_id TEXT');
    await _safeAddColumn(
      db,
      'offline_sale_queue',
      "source TEXT NOT NULL DEFAULT 'pos'",
    );
    await _safeAddColumn(
      db,
      'offline_sale_queue',
      'version INTEGER NOT NULL DEFAULT 1',
    );
    await _safeAddColumn(db, 'offline_sale_queue', 'updated_at INTEGER');
    await _safeAddColumn(db, 'offline_sale_queue', 'deleted_at INTEGER');
    await _safeAddColumn(
      db,
      'offline_sale_queue',
      "sync_status TEXT NOT NULL DEFAULT 'pending'",
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS inventory_movement_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        movement_uuid TEXT NOT NULL UNIQUE,
        pharmacy_id INTEGER,
        device_id TEXT NOT NULL,
        source TEXT NOT NULL DEFAULT 'pos',
        version INTEGER NOT NULL DEFAULT 1,
        barcode TEXT NOT NULL,
        movement_type TEXT NOT NULL,
        quantity_delta INTEGER NOT NULL,
        unit_price_minor INTEGER,
        currency_code TEXT NOT NULL DEFAULT 'USD',
        reference_type TEXT NOT NULL DEFAULT '',
        reference_id TEXT NOT NULL DEFAULT '',
        metadata TEXT NOT NULL DEFAULT '{}',
        happened_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        synced_at INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS medicine_onboarding_requests (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_uuid TEXT NOT NULL UNIQUE,
        barcode TEXT NOT NULL,
        requested_name TEXT NOT NULL DEFAULT '',
        generic_name TEXT NOT NULL DEFAULT '',
        dosage TEXT NOT NULL DEFAULT '',
        category TEXT NOT NULL DEFAULT '',
        proposed_price REAL,
        stock INTEGER NOT NULL DEFAULT 0,
        expiry TEXT NOT NULL DEFAULT '',
        request_status TEXT NOT NULL DEFAULT 'pending_review',
        review_notes TEXT NOT NULL DEFAULT '',
        official_medicine_id INTEGER,
        pharmacy_id INTEGER,
        device_id TEXT,
        metadata TEXT NOT NULL DEFAULT '{}',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        reviewed_at INTEGER,
        deleted_at INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_outbox (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_uuid TEXT NOT NULL UNIQUE,
        stream TEXT NOT NULL,
        payload TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        retry_count INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        synced_at INTEGER,
        deleted_at INTEGER
      )
    ''');

    await _safeAddColumn(db, 'sync_outbox', 'synced_at INTEGER');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_checkpoint (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        stream TEXT NOT NULL UNIQUE,
        checkpoint_token TEXT NOT NULL,
        checkpoint_time INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_state (
        state_key TEXT PRIMARY KEY,
        state_value TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
			CREATE TABLE IF NOT EXISTS purchases (
				id INTEGER PRIMARY KEY AUTOINCREMENT,
				receipt_id TEXT NOT NULL,
				supplier_name TEXT NOT NULL DEFAULT '',
				invoice_number TEXT NOT NULL DEFAULT '',
				created_at INTEGER NOT NULL
			)
		''');

    await _safeAddColumn(db, 'purchases', 'purchase_uuid TEXT');
    await _safeAddColumn(db, 'purchases', 'pharmacy_id INTEGER');
    await _safeAddColumn(db, 'purchases', 'device_id TEXT');
    await _safeAddColumn(db, 'purchases', 'version INTEGER NOT NULL DEFAULT 1');
    await _safeAddColumn(db, 'purchases', 'updated_at INTEGER');
    await _safeAddColumn(db, 'purchases', 'deleted_at INTEGER');
    await _safeAddColumn(
      db,
      'purchases',
      "sync_status TEXT NOT NULL DEFAULT 'pending'",
    );

    await db.execute('''
			CREATE TABLE IF NOT EXISTS purchase_items (
				id INTEGER PRIMARY KEY AUTOINCREMENT,
				purchase_id INTEGER NOT NULL REFERENCES purchases(id) ON DELETE CASCADE,
				barcode TEXT NOT NULL,
				name TEXT NOT NULL,
				dosage TEXT NOT NULL DEFAULT '',
				qty INTEGER NOT NULL,
				cost_price REAL NOT NULL DEFAULT 0
			)
		''');

    await _safeAddColumn(db, 'purchase_items', 'line_uuid TEXT');
    await _safeAddColumn(db, 'purchase_items', 'updated_at INTEGER');
    await _safeAddColumn(db, 'purchase_items', 'deleted_at INTEGER');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sale_items_cache (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        line_uuid TEXT NOT NULL UNIQUE,
        sale_uuid TEXT NOT NULL,
        receipt_id TEXT NOT NULL,
        barcode TEXT NOT NULL,
        product_name TEXT NOT NULL,
        dosage TEXT NOT NULL DEFAULT '',
        qty INTEGER NOT NULL,
        unit_price_minor INTEGER NOT NULL,
        line_total_minor INTEGER NOT NULL,
        batch_number TEXT,
        version INTEGER NOT NULL DEFAULT 1,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_batches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        batch_uuid TEXT NOT NULL UNIQUE,
        barcode TEXT NOT NULL,
        batch_number TEXT NOT NULL,
        expiry TEXT NOT NULL DEFAULT '',
        qty_on_hand INTEGER NOT NULL DEFAULT 0,
        unit_cost_minor INTEGER,
        unit_price_minor INTEGER,
        currency_code TEXT NOT NULL DEFAULT 'USD',
        supplier_name TEXT,
        reference_id TEXT,
        version INTEGER NOT NULL DEFAULT 1,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS returns (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        return_uuid TEXT NOT NULL UNIQUE,
        barcode TEXT NOT NULL,
        return_type TEXT NOT NULL,
        qty INTEGER NOT NULL,
        unit_price_minor INTEGER,
        reason TEXT,
        reference_id TEXT,
        version INTEGER NOT NULL DEFAULT 1,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock_adjustments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        adjustment_uuid TEXT NOT NULL UNIQUE,
        barcode TEXT NOT NULL,
        quantity_delta INTEGER NOT NULL,
        reason TEXT NOT NULL DEFAULT '',
        reference_id TEXT,
        version INTEGER NOT NULL DEFAULT 1,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS prices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        price_uuid TEXT NOT NULL UNIQUE,
        pharmacy_id INTEGER,
        barcode TEXT NOT NULL UNIQUE,
        regulated_price_minor INTEGER,
        local_price_minor INTEGER,
        currency_code TEXT NOT NULL DEFAULT 'USD',
        source TEXT NOT NULL DEFAULT 'server',
        version INTEGER NOT NULL DEFAULT 1,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS price_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        history_uuid TEXT NOT NULL UNIQUE,
        barcode TEXT NOT NULL,
        previous_price_minor INTEGER,
        new_price_minor INTEGER,
        currency_code TEXT NOT NULL DEFAULT 'USD',
        source TEXT NOT NULL,
        changed_by TEXT,
        changed_at INTEGER NOT NULL,
        metadata TEXT NOT NULL DEFAULT '{}'
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS compliance_alerts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        alert_uuid TEXT NOT NULL UNIQUE,
        pharmacy_id INTEGER,
        source TEXT NOT NULL DEFAULT 'server',
        version INTEGER NOT NULL DEFAULT 1,
        alert_type TEXT NOT NULL,
        severity TEXT NOT NULL DEFAULT 'medium',
        title TEXT NOT NULL,
        details TEXT NOT NULL DEFAULT '{}',
        status TEXT NOT NULL DEFAULT 'open',
        created_at INTEGER NOT NULL,
        acknowledged_at INTEGER,
        resolved_at INTEGER,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_conflict_notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        note_uuid TEXT NOT NULL UNIQUE,
        pharmacy_id INTEGER,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        field TEXT NOT NULL,
        conflict_code TEXT NOT NULL,
        local_value TEXT,
        server_value TEXT,
        note TEXT NOT NULL DEFAULT '',
        source TEXT NOT NULL DEFAULT 'server',
        resolved INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
      )
    ''');

    await db.execute('''
			CREATE TABLE IF NOT EXISTS loan_customers (
				id INTEGER PRIMARY KEY AUTOINCREMENT,
				name TEXT NOT NULL UNIQUE COLLATE NOCASE,
				phone TEXT NOT NULL DEFAULT '',
				note TEXT NOT NULL DEFAULT '',
				created_at INTEGER NOT NULL
			)
		''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS loan_repayments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        repayment_uuid TEXT NOT NULL UNIQUE,
        customer_name TEXT NOT NULL,
        amount_paid REAL NOT NULL,
        payment_method TEXT NOT NULL DEFAULT 'CASH',
        note TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_osq_sync_status ON offline_sale_queue(sync_status)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_osq_sale_uuid_unique ON offline_sale_queue(sale_uuid) WHERE sale_uuid IS NOT NULL',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_imq_sync_status ON inventory_movement_queue(sync_status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_imq_barcode_happened_at ON inventory_movement_queue(barcode, happened_at)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_inventory_product_uuid_unique ON inventory(product_uuid) WHERE product_uuid IS NOT NULL',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_purchases_uuid_unique ON purchases(purchase_uuid) WHERE purchase_uuid IS NOT NULL',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_purchase_items_line_uuid_unique ON purchase_items(line_uuid) WHERE line_uuid IS NOT NULL',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sale_items_sale_uuid ON sale_items_cache(sale_uuid)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_product_batches_barcode ON product_batches(barcode)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_returns_sync_status ON returns(sync_status, updated_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_stock_adjustments_sync_status ON stock_adjustments(sync_status, updated_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_prices_barcode ON prices(barcode)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_price_history_barcode_changed_at ON price_history(barcode, changed_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_compliance_alerts_status_created_at ON compliance_alerts(status, created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_conflict_notes_created_at ON sync_conflict_notes(created_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_outbox_status ON sync_outbox(sync_status, created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_loan_repayments_customer_created_at ON loan_repayments(customer_name, created_at DESC)',
    );

    final now = _utcNowMs();
    await db.rawUpdate(
      "UPDATE offline_sale_queue SET sync_status = CASE WHEN synced = 1 THEN 'synced' ELSE 'pending' END WHERE sync_status IS NULL OR sync_status = ''",
    );
    await db.rawUpdate(
      'UPDATE offline_sale_queue SET updated_at = COALESCE(updated_at, created_at, ?)',
      [now],
    );
    await db.rawUpdate(
      'UPDATE offline_sale_queue SET device_id = COALESCE(device_id, ?)',
      [kPosHwid],
    );
    await db.rawUpdate(
      '''
      UPDATE inventory
      SET
        product_uuid = lower(
          hex(randomblob(4)) || '-' ||
          hex(randomblob(2)) || '-' ||
          hex(randomblob(2)) || '-' ||
          hex(randomblob(2)) || '-' ||
          hex(randomblob(6))
        ),
        updated_at = COALESCE(updated_at, ?)
      WHERE product_uuid IS NULL OR product_uuid = ''
      ''',
      [now],
    );

    await db.execute('''
      CREATE VIEW IF NOT EXISTS sales AS
      SELECT
        sale_uuid,
        receipt_id,
        sale_data,
        created_at,
        updated_at,
        deleted_at,
        version,
        sync_status
      FROM offline_sale_queue
    ''');

    await db.execute('''
      CREATE VIEW IF NOT EXISTS sale_items AS
      SELECT
        line_uuid,
        sale_uuid,
        receipt_id,
        barcode,
        product_name,
        dosage,
        qty,
        unit_price_minor,
        line_total_minor,
        batch_number,
        version,
        updated_at,
        deleted_at
      FROM sale_items_cache
    ''');

    await db.execute('''
      CREATE VIEW IF NOT EXISTS medicines AS
      SELECT
        product_uuid AS medicine_uuid,
        barcode,
        name AS trade_name,
        dosage,
        category,
        moph_ceiling,
        is_blocked,
        version,
        updated_at,
        deleted_at
      FROM inventory
    ''');
  }

  Future<void> _safeAddColumn(
    DatabaseExecutor db,
    String table,
    String columnDefinition,
  ) async {
    try {
      await db.execute('ALTER TABLE $table ADD COLUMN $columnDefinition');
    } catch (_) {}
  }

  Future<List<InventoryItem>> searchInventory(String query) async {
    final database = await db;
    final q = '%${query.trim()}%';
    final maps = await database.query(
      'inventory',
      where:
          'name LIKE ? OR barcode LIKE ? OR category LIKE ? OR dosage LIKE ? OR batch_number LIKE ?',
      whereArgs: [q, q, q, q, q],
      orderBy: 'name ASC',
    );
    return maps.map(InventoryItem.fromMap).toList();
  }

  Future<List<InventoryItem>> allInventory() async {
    final database = await db;
    final maps = await database.query('inventory', orderBy: 'name ASC');
    return maps.map(InventoryItem.fromMap).toList();
  }

  Future<List<InventoryItem>> lowStockItems({
    int threshold = 15,
    int limit = 10,
  }) async {
    final database = await db;
    final maps = await database.query(
      'inventory',
      where: 'stock <= ?',
      whereArgs: [threshold],
      orderBy: 'stock ASC, name ASC',
      limit: limit,
    );
    return maps.map(InventoryItem.fromMap).toList();
  }

  Future<List<InventoryItem>> pricedAboveCeiling({int limit = 10}) async {
    final database = await db;
    final maps = await database.rawQuery(
      '''
      SELECT
        i.id,
        i.barcode,
        i.name,
        i.dosage,
        i.category,
        i.stock,
        i.expiry,
        i.price,
        COALESCE(i.moph_ceiling, CAST(p.regulated_price_minor AS REAL) / 100.0) AS moph_ceiling,
        i.batch_number
      FROM inventory i
      LEFT JOIN prices p ON p.barcode = i.barcode
      WHERE COALESCE(i.moph_ceiling, CAST(p.regulated_price_minor AS REAL) / 100.0) IS NOT NULL
        AND i.price > COALESCE(i.moph_ceiling, CAST(p.regulated_price_minor AS REAL) / 100.0)
      ORDER BY
        (i.price - COALESCE(i.moph_ceiling, CAST(p.regulated_price_minor AS REAL) / 100.0)) DESC,
        i.name ASC
      LIMIT ?
      ''',
      [limit],
    );
    return maps.map(InventoryItem.fromMap).toList();
  }

  Future<List<UnmappedBarcode>> unmappedBarcodes() async {
    final database = await db;
    final maps = await database.query(
      'unmapped_barcodes',
      orderBy: 'first_seen DESC',
    );
    return maps.map(UnmappedBarcode.fromMap).toList();
  }

  Future<void> dismissUnmapped(String barcode) async {
    final database = await db;
    await database.delete(
      'unmapped_barcodes',
      where: 'barcode = ?',
      whereArgs: [barcode],
    );
    _emitInventoryChanged();
  }

  Future<void> linkBarcodeToMoPH(String barcode, dynamic drug) async {
    final database = await db;
    final name = (drug?.tradeName as String?) ?? barcode;
    final dosage = (drug?.dosage as String?) ?? '';
    final category = (drug?.category as String?) ?? 'Uncategorized';
    final regNumber = (drug?.regNumber as String?) ?? '';
    final ceiling = (drug?.officialPrice as double?) ?? 0.0;

    await database.transaction((txn) async {
      await txn.insert('inventory', {
        'barcode': barcode,
        'name': name,
        'dosage': dosage,
        'category': category,
        'stock': 0,
        'expiry': '',
        'price': ceiling,
        'moph_ceiling': ceiling,
        'batch_number': regNumber,
        'approval_status': 'approved',
        'official_code': regNumber,
        'request_uuid': '',
        'official_medicine_id': null,
        'is_blocked': 0,
        'pending_reason': '',
        'source': 'server',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);

      await txn.update(
        'inventory',
        {
          'name': name,
          'dosage': dosage,
          'category': category,
          'price': ceiling,
          'moph_ceiling': ceiling,
          'batch_number': regNumber,
          'approval_status': 'approved',
          'official_code': regNumber,
          'request_uuid': '',
          'official_medicine_id': null,
          'is_blocked': 0,
          'pending_reason': '',
          'source': 'server',
        },
        where: 'barcode = ?',
        whereArgs: [barcode],
      );

      final eventUuid = _newUuid();
      await _insertOutboxEvent(
        eventUuid: eventUuid,
        stream: 'product_updated',
        payload: {
          'barcode': barcode,
          'trade_name': name,
          'dosage': dosage,
          'category': category,
        },
        executor: txn,
      );
    });

    await dismissUnmapped(barcode);
    _emitInventoryChanged();
  }

  Future<MedicineOnboardingResult> submitMedicineOnboardingRequest({
    required String barcode,
    required String name,
    required String dosage,
    required String category,
    required int stock,
    required String expiry,
    required double price,
  }) async {
    final database = await db;
    final cleanBarcode = barcode.trim();
    if (cleanBarcode.isEmpty) {
      return const MedicineOnboardingResult(
        outcome: MedicineOnboardingOutcome.rejected,
        message: 'Barcode is required',
      );
    }

    final existingRows = await database.query(
      'inventory',
      where: 'barcode = ?',
      whereArgs: [cleanBarcode],
      limit: 1,
    );
    final existing = existingRows.isNotEmpty
        ? InventoryItem.fromMap(existingRows.first)
        : null;
    if (existing != null &&
        existing.approvalStatus == 'approved' &&
        !existing.isBlocked) {
      return const MedicineOnboardingResult(
        outcome: MedicineOnboardingOutcome.linked,
        message: 'This medicine is already linked to the official registry.',
      );
    }

    final requestUuid = _newUuid();
    final now = _utcNowMs();
    await database.transaction((txn) async {
      await txn.insert(
        'medicine_onboarding_requests',
        {
          'request_uuid': requestUuid,
          'barcode': cleanBarcode,
          'requested_name': name,
          'generic_name': name,
          'dosage': dosage,
          'category': category,
          'proposed_price': price,
          'stock': stock,
          'expiry': expiry,
          'request_status': 'pending_review',
          'review_notes': '',
          'official_medicine_id': null,
          'pharmacy_id': kPharmacyId > 0 ? kPharmacyId : null,
          'device_id': kPosHwid,
          'metadata': jsonEncode({
            'requested_name': name,
            'proposed_price': price,
            'stock': stock,
            'expiry': expiry,
          }),
          'created_at': now,
          'updated_at': now,
          'reviewed_at': null,
          'deleted_at': null,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await txn.insert('inventory', {
        'barcode': cleanBarcode,
        'name': name,
        'dosage': dosage,
        'category': category,
        'stock': stock,
        'expiry': expiry,
        'price': price,
        'moph_ceiling': null,
        'batch_number': '',
        'approval_status': 'pending_approval',
        'official_code': '',
        'request_uuid': requestUuid,
        'official_medicine_id': null,
        'is_blocked': 1,
        'pending_reason': 'Awaiting ministry review',
        'source': 'local',
        'version': 1,
        'updated_at': now,
        'deleted_at': null,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);

      await txn.update(
        'inventory',
        {
          'name': name,
          'dosage': dosage,
          'category': category,
          'stock': stock,
          'expiry': expiry,
          'price': price,
          'approval_status': 'pending_approval',
          'request_uuid': requestUuid,
          'official_code': '',
          'official_medicine_id': null,
          'is_blocked': 1,
          'pending_reason': 'Awaiting ministry review',
          'source': 'local',
          'updated_at': now,
        },
        where: 'barcode = ?',
        whereArgs: [cleanBarcode],
      );

      await _insertOutboxEvent(
        eventUuid: requestUuid,
        stream: 'medicine_request_submitted',
        payload: {
          'request_uuid': requestUuid,
          'barcode': cleanBarcode,
          'requested_name': name,
          'generic_name': name,
          'dosage': dosage,
          'category': category,
          'proposed_price': price,
          'stock': stock,
          'expiry': expiry,
          'request_status': 'pending_review',
        },
        executor: txn,
      );
    });

    _emitInventoryChanged();
    return MedicineOnboardingResult(
      outcome: existing == null
          ? MedicineOnboardingOutcome.pending
          : MedicineOnboardingOutcome.alreadyPending,
      message: existing == null
          ? 'Medicine request submitted for ministry review.'
          : 'Medicine request updated and remains pending review.',
    );
  }

  Future<void> syncMedicineRequestStatuses(
    List<Map<String, dynamic>> requests,
  ) async {
    if (requests.isEmpty) return;
    final database = await db;
    await database.transaction((txn) async {
      for (final raw in requests) {
        final row = Map<String, dynamic>.from(raw);
        final barcode = _asString(row['barcode']).trim();
        if (barcode.isEmpty) continue;
        final status = _asString(row['request_status']).isEmpty
            ? 'pending_review'
            : _asString(row['request_status']);
        final requestUuid = _asString(row['request_uuid']);
        final requestedName = _asString(row['requested_name']);
        final dosage = _asString(row['dosage']);
        final category = _asString(row['category']);
        final officialMedicineId = _asIntOrNull(row['official_medicine_id']);
        final reviewNotes = _asString(row['review_notes']);
        final price = _asDoubleOrNull(row['proposed_price']);
        final updatedAt =
            _asDateTimeOrNull(row['updated_at'])?.millisecondsSinceEpoch ??
            _utcNowMs();
        final reviewedAt = _asDateTimeOrNull(
          row['reviewed_at'],
        )?.millisecondsSinceEpoch;

        await txn.insert(
          'medicine_onboarding_requests',
          {
            'request_uuid': requestUuid.isEmpty ? _newUuid() : requestUuid,
            'barcode': barcode,
            'requested_name': requestedName,
            'generic_name': requestedName,
            'dosage': dosage,
            'category': category,
            'proposed_price': price,
            'stock': _asIntOrNull(row['stock']) ?? 0,
            'expiry': _asString(row['expiry']),
            'request_status': status,
            'review_notes': reviewNotes,
            'official_medicine_id': officialMedicineId,
            'pharmacy_id':
                _asIntOrNull(row['pharmacy_id']) ??
                (kPharmacyId > 0 ? kPharmacyId : null),
            'device_id': _asString(row['device_id']),
            'metadata': _asString(row['metadata']).isEmpty
                ? '{}'
                : _asString(row['metadata']),
            'created_at':
                _asDateTimeOrNull(row['created_at'])?.millisecondsSinceEpoch ??
                updatedAt,
            'updated_at': updatedAt,
            'reviewed_at': reviewedAt,
            'deleted_at': null,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        final existingRows = await txn.query(
          'inventory',
          where: 'barcode = ?',
          whereArgs: [barcode],
          limit: 1,
        );
        final approved = status == 'approved';
        final rejected = status == 'rejected';

        if (existingRows.isEmpty && approved) {
          await txn.insert('inventory', {
            'barcode': barcode,
            'name': requestedName.isEmpty ? barcode : requestedName,
            'dosage': dosage,
            'category': category,
            'stock': _asIntOrNull(row['stock']) ?? 0,
            'expiry': _asString(row['expiry']),
            'price': price ?? 0.0,
            'moph_ceiling': price,
            'batch_number': _asString(row['official_code']),
            'approval_status': 'approved',
            'official_code': _asString(row['official_code']),
            'request_uuid': requestUuid,
            'official_medicine_id': officialMedicineId,
            'is_blocked': 0,
            'pending_reason': '',
            'source': 'server',
            'version': 1,
            'updated_at': updatedAt,
            'deleted_at': null,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
          continue;
        }

        await txn.update(
          'inventory',
          {
            'name': approved && requestedName.isNotEmpty
                ? requestedName
                : (requestedName.isNotEmpty ? requestedName : barcode),
            'dosage': dosage,
            'category': category,
            'price': approved && price != null
                ? price
                : (_asDoubleOrNull(
                        existingRows.isNotEmpty
                            ? existingRows.first['price']
                            : null,
                      ) ??
                      0.0),
            'moph_ceiling': approved ? price : null,
            'batch_number': _asString(row['official_code']),
            'approval_status': approved
                ? 'approved'
                : (rejected ? 'rejected' : 'pending_approval'),
            'official_code': approved ? _asString(row['official_code']) : '',
            'request_uuid': requestUuid.isEmpty
                ? _asString(
                    existingRows.isNotEmpty
                        ? existingRows.first['request_uuid']
                        : '',
                  )
                : requestUuid,
            'official_medicine_id': officialMedicineId,
            'is_blocked': approved ? 0 : 1,
            'pending_reason': approved
                ? ''
                : (rejected
                      ? 'Request rejected by ministry'
                      : 'Awaiting ministry review'),
            'source': approved ? 'server' : 'local',
            'updated_at': updatedAt,
          },
          where: 'barcode = ?',
          whereArgs: [barcode],
        );
      }
    });
    _emitInventoryChanged();
  }

  Future<bool> insertInventoryItem({
    required String barcode,
    required String name,
    required String dosage,
    required String category,
    required int stock,
    required String expiry,
    required double price,
  }) async {
    final database = await db;
    try {
      await database.transaction((txn) async {
        await txn.insert('inventory', {
          'barcode': barcode,
          'name': name,
          'dosage': dosage,
          'category': category,
          'stock': stock,
          'expiry': expiry,
          'price': price,
          'approval_status': 'approved',
          'official_code': '',
          'request_uuid': '',
          'official_medicine_id': null,
          'is_blocked': 0,
          'pending_reason': '',
          'source': 'local',
        });

        await _insertOutboxEvent(
          eventUuid: _newUuid(),
          stream: 'product_updated',
          payload: {
            'barcode': barcode,
            'trade_name': name,
            'dosage': dosage,
            'category': category,
          },
          executor: txn,
        );
      });
      _emitInventoryChanged();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> recordReturn({
    required String barcode,
    required int qty,
    required String returnType,
    String reason = '',
    String referenceId = '',
    int? unitPriceMinor,
  }) async {
    if (barcode.trim().isEmpty || qty <= 0) return;

    final database = await db;
    final now = _utcNowMs();
    await database.transaction((txn) async {
      final returnUuid = _newUuid();
      final movementUuid = _newUuid();
      final signedQty = returnType == 'return_out' ? -qty : qty;

      await txn.insert('returns', {
        'return_uuid': returnUuid,
        'barcode': barcode,
        'return_type': returnType,
        'qty': qty,
        'unit_price_minor': unitPriceMinor,
        'reason': reason,
        'reference_id': referenceId,
        'version': 1,
        'updated_at': now,
        'deleted_at': null,
        'sync_status': 'pending',
      });

      await txn.rawUpdate(
        'UPDATE inventory SET stock = MAX(stock + ?, 0) WHERE barcode = ?',
        [signedQty, barcode],
      );

      await txn.insert('inventory_movement_queue', {
        'movement_uuid': movementUuid,
        'pharmacy_id': kPharmacyId > 0 ? kPharmacyId : null,
        'device_id': kPosHwid,
        'version': 1,
        'barcode': barcode,
        'movement_type': returnType,
        'quantity_delta': signedQty,
        'unit_price_minor': unitPriceMinor,
        'currency_code': 'USD',
        'reference_type': 'return',
        'reference_id': referenceId,
        'metadata': jsonEncode({'reason': reason}),
        'happened_at': now,
        'updated_at': now,
        'deleted_at': null,
        'sync_status': 'pending',
        'synced_at': null,
      });

      await _insertOutboxEvent(
        eventUuid: returnUuid,
        stream: 'return_created',
        payload: {
          'return_uuid': returnUuid,
          'movement_uuid': movementUuid,
          'barcode': barcode,
          'return_type': returnType,
          'qty': qty,
        },
        executor: txn,
      );
    });
  }

  Future<bool> deleteInventoryItem(String barcode) async {
    final database = await db;
    final n = await database.delete(
      'inventory',
      where: 'barcode = ?',
      whereArgs: [barcode],
    );
    if (n > 0) {
      _emitInventoryChanged();
    }
    return n > 0;
  }

  Future<bool> setStock(String barcode, int stock) async {
    final database = await db;
    var ok = false;
    await database.transaction((txn) async {
      final existing = await txn.query(
        'inventory',
        columns: ['stock'],
        where: 'barcode = ?',
        whereArgs: [barcode],
        limit: 1,
      );
      if (existing.isEmpty) return;

      final oldStock = (existing.first['stock'] as num?)?.toInt() ?? 0;
      final safeStock = stock < 0 ? 0 : stock;
      final delta = safeStock - oldStock;
      final n = await txn.update(
        'inventory',
        {'stock': safeStock},
        where: 'barcode = ?',
        whereArgs: [barcode],
      );
      ok = n > 0;
      if (!ok || delta == 0) return;

      final now = _utcNowMs();
      final adjustmentUuid = _newUuid();
      await txn.insert('stock_adjustments', {
        'adjustment_uuid': adjustmentUuid,
        'barcode': barcode,
        'quantity_delta': delta,
        'reason': 'manual_adjustment',
        'reference_id': barcode,
        'version': 1,
        'updated_at': now,
        'deleted_at': null,
        'sync_status': 'pending',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);

      final movementUuid = _newUuid();
      await txn.insert('inventory_movement_queue', {
        'movement_uuid': movementUuid,
        'pharmacy_id': kPharmacyId > 0 ? kPharmacyId : null,
        'device_id': kPosHwid,
        'version': 1,
        'barcode': barcode,
        'movement_type': 'adjustment',
        'quantity_delta': delta,
        'unit_price_minor': null,
        'currency_code': 'USD',
        'reference_type': 'manual_adjustment',
        'reference_id': barcode,
        'metadata': jsonEncode({'before': oldStock, 'after': safeStock}),
        'happened_at': now,
        'updated_at': now,
        'deleted_at': null,
        'sync_status': 'pending',
        'synced_at': null,
      });

      await _insertOutboxEvent(
        eventUuid: movementUuid,
        stream: 'stock_adjusted',
        payload: {
          'movement_uuid': movementUuid,
          'barcode': barcode,
          'quantity_delta': delta,
        },
        executor: txn,
      );
    });
    if (ok) {
      _emitInventoryChanged();
    }
    return ok;
  }

  Future<bool> setPrice(String barcode, double price) async {
    final database = await db;
    var ok = false;
    await database.transaction((txn) async {
      final existing = await txn.query(
        'inventory',
        columns: ['price'],
        where: 'barcode = ?',
        whereArgs: [barcode],
        limit: 1,
      );
      final oldPrice = (existing.isNotEmpty ? existing.first['price'] : null);
      final safePrice = price < 0 ? 0 : price;
      final n = await txn.update(
        'inventory',
        {'price': safePrice},
        where: 'barcode = ?',
        whereArgs: [barcode],
      );
      ok = n > 0;
      if (!ok) return;

      final now = _utcNowMs();
      await txn.insert('prices', {
        'price_uuid': _newUuid(),
        'barcode': barcode,
        'regulated_price_minor': null,
        'local_price_minor': _toMinorUnits(safePrice),
        'currency_code': 'USD',
        'source': 'client',
        'version': 1,
        'updated_at': now,
        'deleted_at': null,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await txn.insert('price_history', {
        'history_uuid': _newUuid(),
        'barcode': barcode,
        'previous_price_minor': _toMinorUnits(oldPrice),
        'new_price_minor': _toMinorUnits(safePrice),
        'currency_code': 'USD',
        'source': 'client',
        'changed_by': kPosHwid,
        'changed_at': now,
        'metadata': jsonEncode({'reason': 'manual_price'}),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);

      final movementUuid = _newUuid();
      await txn.insert('inventory_movement_queue', {
        'movement_uuid': movementUuid,
        'pharmacy_id': kPharmacyId > 0 ? kPharmacyId : null,
        'device_id': kPosHwid,
        'version': 1,
        'barcode': barcode,
        'movement_type': 'price_change',
        'quantity_delta': 0,
        'unit_price_minor': _toMinorUnits(safePrice),
        'currency_code': 'USD',
        'reference_type': 'manual_price',
        'reference_id': barcode,
        'metadata': '{}',
        'happened_at': now,
        'updated_at': now,
        'deleted_at': null,
        'sync_status': 'pending',
        'synced_at': null,
      });

      await _insertOutboxEvent(
        eventUuid: movementUuid,
        stream: 'price_change_requested',
        payload: {
          'movement_uuid': movementUuid,
          'barcode': barcode,
          'unit_price_minor': _toMinorUnits(safePrice),
        },
        executor: txn,
      );
    });
    if (ok) {
      _emitInventoryChanged();
    }
    return ok;
  }

  Future<void> applyPriceDecree(String namePattern, double newPrice) async {
    final database = await db;
    await database.update(
      'inventory',
      {'moph_ceiling': newPrice},
      where: 'LOWER(name) LIKE ?',
      whereArgs: ['%${namePattern.toLowerCase()}%'],
    );
    _emitInventoryChanged();
  }

  Future<void> applySaleStockDeductions(
    List<Map<String, dynamic>> saleItems, {
    String referenceId = '',
  }) async {
    final database = await db;
    final now = _utcNowMs();
    await database.transaction((txn) async {
      for (final item in saleItems) {
        final barcode = (item['barcode'] as String?) ?? '';
        final qty = (item['qty'] as num?)?.toInt() ?? 0;
        if (barcode.isEmpty || qty <= 0) continue;

        await txn.rawUpdate(
          'UPDATE inventory SET stock = MAX(stock - ?, 0) WHERE barcode = ?',
          [qty, barcode],
        );

        await txn.insert('inventory_movement_queue', {
          'movement_uuid': _newUuid(),
          'pharmacy_id': kPharmacyId > 0 ? kPharmacyId : null,
          'device_id': kPosHwid,
          'version': 1,
          'barcode': barcode,
          'movement_type': 'sale',
          'quantity_delta': -qty,
          'unit_price_minor': _toMinorUnits(item['price']),
          'currency_code': 'USD',
          'reference_type': 'sale',
          'reference_id': referenceId,
          'metadata': jsonEncode({
            'receipt_id': referenceId,
            'batch_number': item['batch_number'],
          }),
          'happened_at': now,
          'updated_at': now,
          'deleted_at': null,
          'sync_status': 'pending',
          'synced_at': null,
        });

        final lookup = await txn.query(
          'inventory_movement_queue',
          columns: ['movement_uuid'],
          where: 'reference_id = ? AND barcode = ? AND movement_type = ?',
          whereArgs: [referenceId, barcode, 'sale'],
          orderBy: 'id DESC',
          limit: 1,
        );
        final movementUuid = _asString(
          lookup.isEmpty ? null : lookup.first['movement_uuid'],
        );
        if (movementUuid.isNotEmpty) {
          await _insertOutboxEvent(
            eventUuid: movementUuid,
            stream: 'inventory_movement',
            payload: {
              'movement_uuid': movementUuid,
              'barcode': barcode,
              'movement_type': 'sale',
              'reference_id': referenceId,
            },
            executor: txn,
          );
        }
      }
    });
    _emitInventoryChanged();
  }

  Future<void> queueSale(
    String receiptId,
    Map<String, dynamic> saleData,
  ) async {
    final database = await db;
    await database.transaction((txn) async {
      final now = _utcNowMs();
      final saleUuid = _newUuid();
      final enrichedSaleData = Map<String, dynamic>.from(saleData)
        ..['sale_uuid'] = saleUuid
        ..['device_id'] = kPosHwid
        ..['version'] = 1
        ..['updated_at'] = now
        ..['sync_status'] = 'pending';

      await txn.insert('offline_sale_queue', {
        'sale_uuid': saleUuid,
        'receipt_id': receiptId,
        'sale_data': jsonEncode(enrichedSaleData),
        'created_at': now,
        'pharmacy_id': kPharmacyId > 0 ? kPharmacyId : null,
        'device_id': kPosHwid,
        'version': 1,
        'updated_at': now,
        'deleted_at': null,
        'sync_status': 'pending',
        'synced': 0,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);

      final items =
          (enrichedSaleData['items'] as List?)?.cast<Map>() ?? const [];
      for (var i = 0; i < items.length; i += 1) {
        final item = Map<String, dynamic>.from(items[i]);
        final qty = (item['qty'] as num?)?.toInt() ?? 0;
        if (qty <= 0) continue;

        await txn.insert('sale_items_cache', {
          'line_uuid': _newUuid(),
          'sale_uuid': saleUuid,
          'receipt_id': receiptId,
          'barcode': _asString(item['barcode']),
          'product_name': _asString(item['product']).isEmpty
              ? _asString(item['name'])
              : _asString(item['product']),
          'dosage': _asString(item['dosage']),
          'qty': qty,
          'unit_price_minor': _toMinorUnits(item['price']),
          'line_total_minor': _toMinorUnits(item['total']),
          'batch_number': _asString(item['batch_number']),
          'version': 1,
          'updated_at': now,
          'deleted_at': null,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }

      await _insertOutboxEvent(
        eventUuid: saleUuid,
        stream: 'sale_created',
        payload: {'receipt_id': receiptId, 'sale_uuid': saleUuid},
        executor: txn,
      );
    });
    _emitInventoryChanged();
  }

  Future<List<OfflineSaleRecord>> getPendingQueue() async {
    final database = await db;
    final maps = await database.query(
      'offline_sale_queue',
      where: "sync_status = 'pending' OR synced = 0",
      orderBy: 'created_at ASC',
    );
    return maps.map(OfflineSaleRecord.fromMap).toList();
  }

  Future<void> markSynced(int id) async {
    final database = await db;
    await database.update(
      'offline_sale_queue',
      {'synced': 1, 'sync_status': 'synced', 'updated_at': _utcNowMs()},
      where: 'id = ?',
      whereArgs: [id],
    );
    _emitInventoryChanged();
  }

  bool _incomingIsNewer({
    required int? localVersion,
    required int? localUpdatedAt,
    required int incomingVersion,
    required int incomingUpdatedAt,
    required String localSource,
    required String incomingSource,
  }) {
    final lv = localVersion ?? 1;
    final lu = localUpdatedAt ?? 0;
    if (incomingSource == 'server' && localSource != 'server') return true;
    if (incomingVersion != lv) return incomingVersion > lv;
    if (incomingUpdatedAt != lu) return incomingUpdatedAt > lu;
    return incomingSource.compareTo(localSource) >= 0;
  }

  Future<void> _recordConflictNote({
    required DatabaseExecutor txn,
    required String entityType,
    required String entityId,
    required String field,
    required String conflictCode,
    required dynamic localValue,
    required dynamic serverValue,
    required String note,
  }) async {
    final now = _utcNowMs();
    await txn.insert('sync_conflict_notes', {
      'note_uuid': _newUuid(),
      'pharmacy_id': kPharmacyId > 0 ? kPharmacyId : null,
      'entity_type': entityType,
      'entity_id': entityId,
      'field': field,
      'conflict_code': conflictCode,
      'local_value': jsonEncode(localValue),
      'server_value': jsonEncode(serverValue),
      'note': note,
      'source': 'server',
      'resolved': 0,
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<Map<String, dynamic>>> getRecentConflictNotes({
    int limit = 100,
  }) async {
    final database = await db;
    return database.query(
      'sync_conflict_notes',
      where: 'deleted_at IS NULL',
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  Future<void> _insertOutboxEvent({
    required String eventUuid,
    required String stream,
    required Map<String, dynamic> payload,
    DatabaseExecutor? executor,
  }) async {
    final database = executor ?? await db;
    final now = _utcNowMs();
    await database.insert('sync_outbox', {
      'event_uuid': eventUuid,
      'stream': stream,
      'payload': jsonEncode(payload),
      'sync_status': 'pending',
      'retry_count': 0,
      'last_error': null,
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<SyncOutboxRecord>> getPendingOutboxChunk({
    int limit = 100,
  }) async {
    final database = await db;
    final rows = await database.query(
      'sync_outbox',
      where: "sync_status = 'pending'",
      orderBy: 'created_at ASC, id ASC',
      limit: limit,
    );
    return rows.map(SyncOutboxRecord.fromMap).toList();
  }

  Future<void> markOutboxInProgress(List<String> eventUuids) async {
    if (eventUuids.isEmpty) return;
    final database = await db;
    final now = _utcNowMs();
    final placeholders = List.filled(eventUuids.length, '?').join(',');
    await database.rawUpdate(
      "UPDATE sync_outbox SET sync_status = 'in_progress', updated_at = ? WHERE event_uuid IN ($placeholders)",
      [now, ...eventUuids],
    );
  }

  Future<void> markOutboxFailed({
    required String eventUuid,
    required String error,
  }) async {
    final database = await db;
    final now = _utcNowMs();
    await database.rawUpdate(
      "UPDATE sync_outbox SET sync_status = 'pending', retry_count = retry_count + 1, last_error = ?, updated_at = ? WHERE event_uuid = ?",
      [error, now, eventUuid],
    );
  }

  Future<void> recoverInProgressOutbox() async {
    final database = await db;
    final now = _utcNowMs();
    await database.rawUpdate(
      "UPDATE sync_outbox SET sync_status = 'pending', last_error = COALESCE(last_error, 'Recovered after app restart'), updated_at = ? WHERE sync_status = 'in_progress'",
      [now],
    );
  }

  Future<void> _markOutboxSynced(String eventUuid) async {
    final database = await db;
    final now = _utcNowMs();
    await database.update(
      'sync_outbox',
      {'sync_status': 'synced', 'updated_at': now, 'synced_at': now},
      where: 'event_uuid = ?',
      whereArgs: [eventUuid],
    );
  }

  Future<List<Map<String, dynamic>>> _getPendingSalesBySaleUuids(
    List<String> saleUuids,
  ) async {
    if (saleUuids.isEmpty) return const [];
    final database = await db;
    final placeholders = List.filled(saleUuids.length, '?').join(',');
    final rows = await database.rawQuery('''
      SELECT id, receipt_id, sale_data, created_at
      FROM offline_sale_queue
      WHERE sale_uuid IN ($placeholders)
        AND (sync_status = 'pending' OR synced = 0)
      ORDER BY created_at ASC
      ''', saleUuids);
    return rows;
  }

  Future<List<Map<String, dynamic>>> _getPendingMovementsByUuids(
    List<String> movementUuids,
  ) async {
    if (movementUuids.isEmpty) return const [];
    final database = await db;
    final placeholders = List.filled(movementUuids.length, '?').join(',');
    final rows = await database.rawQuery('''
      SELECT movement_uuid, pharmacy_id, device_id, version, barcode, movement_type,
             quantity_delta, unit_price_minor, currency_code, reference_type,
             reference_id, metadata, happened_at, updated_at, deleted_at, sync_status
      FROM inventory_movement_queue
      WHERE movement_uuid IN ($placeholders)
        AND sync_status = 'pending'
      ORDER BY happened_at ASC, id ASC
      ''', movementUuids);
    return rows;
  }

  Map<String, String> _canonicalSyncHeaders({bool includeJson = false}) {
    return {
      if (includeJson) 'Content-Type': 'application/json',
      'x-device-id': kPosHwid,
      if (kPharmacyId > 0)
        'x-pharmacy-id': '$kPharmacyId'
      else if (kPosLicenseNumber.trim().isNotEmpty)
        'x-license-number': kPosLicenseNumber.trim(),
      if (kSyncApiKey.trim().isNotEmpty) 'x-sync-key': kSyncApiKey.trim(),
    };
  }

  Future<int> syncUpChunk({int chunkSize = 100}) async {
    final outbox = await getPendingOutboxChunk(limit: chunkSize);
    if (outbox.isEmpty) return 0;

    final eventUuids = outbox.map((e) => e.eventUuid).toList();
    await markOutboxInProgress(eventUuids);

    try {
      final saleUuids = outbox
          .where((e) => e.stream == 'sale' || e.stream == 'sale_created')
          .map(
            (e) => _asString(e.payload['sale_uuid']).isEmpty
                ? e.eventUuid
                : _asString(e.payload['sale_uuid']),
          )
          .toSet()
          .toList();
      final movementUuids = outbox
          .where(
            (e) =>
                e.stream == 'inventory_movement' ||
                e.stream == 'stock_adjusted' ||
                e.stream == 'purchase_created' ||
                e.stream == 'return_created' ||
                e.stream == 'price_change_requested' ||
                e.stream == 'product_updated' ||
                e.stream == 'medicine_request_submitted',
          )
          .map(
            (e) => _asString(e.payload['movement_uuid']).isEmpty
                ? e.eventUuid
                : _asString(e.payload['movement_uuid']),
          )
          .toSet()
          .toList();

      final saleRows = await _getPendingSalesBySaleUuids(saleUuids);
      final movementRows = await _getPendingMovementsByUuids(movementUuids);
      final salesByUuid = {
        for (final row in saleRows)
          _asString(row['sale_uuid']).isEmpty
                  ? ''
                  : _asString(row['sale_uuid']):
              row,
      };
      final movementsByUuid = {
        for (final row in movementRows)
          _asString(row['movement_uuid']).isEmpty
                  ? ''
                  : _asString(row['movement_uuid']):
              row,
      };

      final events = <Map<String, dynamic>>[];
      for (final entry in outbox) {
        final saleUuid = _asString(entry.payload['sale_uuid']).isEmpty
            ? entry.eventUuid
            : _asString(entry.payload['sale_uuid']);
        final movementUuid = _asString(entry.payload['movement_uuid']).isEmpty
            ? entry.eventUuid
            : _asString(entry.payload['movement_uuid']);

        if (entry.stream == 'medicine_request_submitted') {
          events.add({
            'event_id': entry.eventUuid,
            'event_type': 'medicine_request_submitted',
            'payload': {
              'request_uuid': _asString(entry.payload['request_uuid']).isEmpty
                  ? entry.eventUuid
                  : _asString(entry.payload['request_uuid']),
              'barcode': entry.payload['barcode'],
              'requested_name': entry.payload['requested_name'],
              'generic_name': entry.payload['generic_name'],
              'dosage': entry.payload['dosage'],
              'category': entry.payload['category'],
              'proposed_price': entry.payload['proposed_price'],
              'stock': entry.payload['stock'],
              'expiry': entry.payload['expiry'],
              'request_status':
                  entry.payload['request_status'] ?? 'pending_review',
            },
          });
          continue;
        }

        if (entry.stream == 'sale' || entry.stream == 'sale_created') {
          final sale = salesByUuid[saleUuid];
          events.add({
            'event_id': entry.eventUuid,
            'event_type': 'compliance_note',
            'payload': {
              'note_type': 'sale_record',
              'sale_uuid': saleUuid,
              'receipt_id': sale?['receipt_id'],
              'sale_data': sale?['sale_data'],
              'created_at': sale?['created_at'],
            },
          });
          continue;
        }

        final movement = movementsByUuid[movementUuid];
        if (movement == null) {
          continue;
        }

        Map<String, dynamic> movementMetadata;
        try {
          movementMetadata = Map<String, dynamic>.from(
            jsonDecode(_asString(movement['metadata'])) as Map,
          );
        } catch (_) {
          movementMetadata = const {};
        }

        events.add({
          'event_id': entry.eventUuid,
          'event_type': 'inventory_movement',
          'payload': {
            'barcode': movement['barcode'],
            'movement_type': movement['movement_type'],
            'quantity_delta': movement['quantity_delta'],
            'unit_price_minor': movement['unit_price_minor'],
            'currency_code': movement['currency_code'],
            'reference_type': movement['reference_type'],
            'reference_id': movement['reference_id'],
            'metadata': movementMetadata,
            'happened_at': movement['happened_at'],
            'version': movement['version'],
          },
        });
      }

      if (events.isEmpty) {
        for (final uuid in eventUuids) {
          await markOutboxFailed(
            eventUuid: uuid,
            error: 'event mapping failed before push',
          );
        }
        return 0;
      }

      final requestId = _newUuid();
      final payload = <String, dynamic>{
        'request_id': requestId,
        'events': events,
      };

      Future<http.Response> postSync(SyncBackendFamily family) {
        final uri = _syncUriForFamily(family, 'sync/push', 'sync/push');
        return http
            .post(
              uri,
              headers: _canonicalSyncHeaders(includeJson: true),
              body: jsonEncode(payload),
            )
            .timeout(_appConfig.requestTimeout);
      }

      final family = await resolveBackendFamily();
      var response = await postSync(family);
      if (response.statusCode == 404) {
        final fallbackFamily = family == SyncBackendFamily.central
            ? SyncBackendFamily.proxy
            : SyncBackendFamily.central;
        _logSyncHttpFailure(
          operation: 'sync-up chunk',
          uri: _syncUriForFamily(family, 'sync/push', 'sync/push'),
          statusCode: response.statusCode,
          family: family,
        );
        _backendFamily = fallbackFamily;
        response = await postSync(fallbackFamily);
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        for (final uuid in eventUuids) {
          await markOutboxFailed(
            eventUuid: uuid,
            error: 'sync-up unauthorized',
          );
        }
        throw StateError('sync-up unauthorized');
      }

      if (response.statusCode != 200) {
        final message = 'sync-up chunk http ${response.statusCode}';
        _logSyncHttpFailure(
          operation: 'sync-up chunk',
          uri: _syncUriForFamily(
            _backendFamily ?? SyncBackendFamily.central,
            'sync/push',
            'sync/push',
          ),
          statusCode: response.statusCode,
          family: _backendFamily ?? SyncBackendFamily.central,
        );
        for (final uuid in eventUuids) {
          await markOutboxFailed(eventUuid: uuid, error: message);
        }
        throw StateError(message);
      }

      final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;
      if (jsonResponse['status'] != 'success') {
        const message = 'sync-up chunk failed';
        for (final uuid in eventUuids) {
          await markOutboxFailed(eventUuid: uuid, error: message);
        }
        return 0;
      }

      final acceptedEventIds =
          (jsonResponse['accepted_event_ids'] as List?)
              ?.map((e) => e.toString())
              .toSet() ??
          <String>{};
      final duplicateEventIds =
          (jsonResponse['duplicate_event_ids'] as List?)
              ?.map((e) => e.toString())
              .toSet() ??
          <String>{};
      final rejectedEventIds =
          (jsonResponse['rejected_event_ids'] as List?)
              ?.map((e) => e.toString())
              .toSet() ??
          <String>{};
      final processedIds = <String>{...acceptedEventIds, ...duplicateEventIds};

      for (final entry in outbox) {
        final eventId = entry.eventUuid;
        final saleUuid = _asString(entry.payload['sale_uuid']).isEmpty
            ? eventId
            : _asString(entry.payload['sale_uuid']);
        final movementUuid = _asString(entry.payload['movement_uuid']).isEmpty
            ? eventId
            : _asString(entry.payload['movement_uuid']);

        if (processedIds.contains(eventId)) {
          if (entry.stream == 'sale' || entry.stream == 'sale_created') {
            final sale = salesByUuid[saleUuid];
            final queueId = (sale?['id'] as num?)?.toInt() ?? 0;
            if (queueId > 0) {
              await markSynced(queueId);
              await _markSaleOutboxSyncedByQueueId(queueId);
            } else {
              await _markOutboxSynced(eventId);
            }
          } else {
            if (movementsByUuid.containsKey(movementUuid)) {
              await _markMovementSynced(movementUuid);
            }
            await _markOutboxSynced(eventId);
          }
          continue;
        }

        if (rejectedEventIds.contains(eventId)) {
          await markOutboxFailed(
            eventUuid: eventId,
            error: 'event rejected by canonical sync contract',
          );
        }
      }

      await _setSyncState(
        'last_successful_push_time',
        DateTime.now().toUtc().toIso8601String(),
      );
      return processedIds.length;
    } catch (e) {
      for (final uuid in eventUuids) {
        await markOutboxFailed(eventUuid: uuid, error: e.toString());
      }
      rethrow;
    }
  }

  Future<void> _markSaleOutboxSyncedByQueueId(int queueId) async {
    final database = await db;
    final rows = await database.query(
      'offline_sale_queue',
      columns: ['sale_uuid'],
      where: 'id = ?',
      whereArgs: [queueId],
      limit: 1,
    );
    final saleUuid = _asString(
      rows.isEmpty ? null : rows.first['sale_uuid'],
    ).trim();
    if (saleUuid.isEmpty) return;
    await _markOutboxSynced(saleUuid);
  }

  Future<String?> _getCheckpointToken(String stream) async {
    final database = await db;
    final rows = await database.query(
      'sync_checkpoint',
      columns: ['checkpoint_token'],
      where: 'stream = ?',
      whereArgs: [stream],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['checkpoint_token'] as String?;
  }

  Future<void> _setCheckpoint(String stream, String token) async {
    final database = await db;
    final now = _utcNowMs();
    await database.insert('sync_checkpoint', {
      'stream': stream,
      'checkpoint_token': token,
      'checkpoint_time': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _setSyncState(String key, String value) async {
    final database = await db;
    final now = _utcNowMs();
    await database.insert('sync_state', {
      'state_key': key,
      'state_value': value,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _markMovementSynced(String movementUuid) async {
    final database = await db;
    final now = _utcNowMs();
    await database.update(
      'inventory_movement_queue',
      {'sync_status': 'synced', 'updated_at': now, 'synced_at': now},
      where: 'movement_uuid = ?',
      whereArgs: [movementUuid],
    );
  }

  Future<int> pendingQueueCount() async {
    final database = await db;
    final rows = await database.rawQuery(
      "SELECT COUNT(*) AS c FROM offline_sale_queue WHERE COALESCE(sync_status, CASE WHEN synced = 1 THEN 'synced' ELSE 'pending' END) = 'pending'",
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<int> syncedSalesCount() async {
    final database = await db;
    final rows = await database.rawQuery(
      "SELECT COUNT(*) AS c FROM offline_sale_queue WHERE COALESCE(sync_status, CASE WHEN synced = 1 THEN 'synced' ELSE 'pending' END) = 'synced'",
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<List<PosSaleRecord>> getSalesHistory({int limit = 400}) async {
    final database = await db;
    final maps = await database.query(
      'offline_sale_queue',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return maps.map(PosSaleRecord.fromQueueMap).toList();
  }

  Future<void> createLoanCustomer({
    required String name,
    String phone = '',
    String note = '',
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final database = await db;
    await database.insert('loan_customers', {
      'name': trimmed,
      'phone': phone.trim(),
      'note': note.trim(),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<LoanCustomerSummary>> getLoanCustomerSummaries() async {
    final sales = await getSalesHistory(limit: 5000);
    final byName = <String, LoanCustomerSummary>{};

    final database = await db;
    final customerRows = await database.query('loan_customers');
    final phoneByName = {
      for (final row in customerRows)
        ((row['name'] as String?) ?? '').trim().toLowerCase():
            ((row['phone'] as String?) ?? ''),
    };

    for (final s in sales.where((e) => e.method.toUpperCase() == 'LOAN')) {
      final name = (s.customer ?? '').trim();
      if (name.isEmpty) continue;
      final key = name.toLowerCase();
      final existing = byName[key];
      if (existing == null) {
        byName[key] = LoanCustomerSummary(
          name: name,
          phone: phoneByName[key] ?? '',
          loanCount: 1,
          totalLoanAmount: s.grandTotal,
          totalRepaidAmount: 0,
          outstandingAmount: s.grandTotal,
          lastLoanAt: s.timestamp,
          lastRepaymentAt: null,
        );
      } else {
        byName[key] = LoanCustomerSummary(
          name: existing.name,
          phone: existing.phone,
          loanCount: existing.loanCount + 1,
          totalLoanAmount: existing.totalLoanAmount + s.grandTotal,
          totalRepaidAmount: existing.totalRepaidAmount,
          outstandingAmount: existing.outstandingAmount + s.grandTotal,
          lastLoanAt:
              s.timestamp.isAfter(
                existing.lastLoanAt ?? DateTime.fromMillisecondsSinceEpoch(0),
              )
              ? s.timestamp
              : existing.lastLoanAt,
          lastRepaymentAt: existing.lastRepaymentAt,
        );
      }
    }

    final repaymentRows = await database.query('loan_repayments');
    final repaidByName = <String, double>{};
    final lastRepaymentByName = <String, DateTime?>{};
    for (final row in repaymentRows) {
      final key = _asString(row['customer_name']).trim().toLowerCase();
      if (key.isEmpty) continue;
      final amount = _asDoubleOrNull(row['amount_paid']) ?? 0;
      if (amount <= 0) continue;
      repaidByName[key] = (repaidByName[key] ?? 0) + amount;
      final createdAt = _asDateTimeOrNull(row['created_at']);
      if (createdAt == null) continue;
      final existing = lastRepaymentByName[key];
      if (existing == null || createdAt.isAfter(existing)) {
        lastRepaymentByName[key] = createdAt;
      }
    }

    final rows = byName.entries
        .map((entry) {
          final repaid = repaidByName[entry.key] ?? 0;
          final outstanding = max<double>(
            entry.value.totalLoanAmount - repaid,
            0.0,
          );
          return LoanCustomerSummary(
            name: entry.value.name,
            phone: entry.value.phone,
            loanCount: entry.value.loanCount,
            totalLoanAmount: entry.value.totalLoanAmount,
            totalRepaidAmount: repaid,
            outstandingAmount: outstanding,
            lastLoanAt: entry.value.lastLoanAt,
            lastRepaymentAt: lastRepaymentByName[entry.key],
          );
        })
        .where((row) => row.outstandingAmount > _loanBalanceEpsilon)
        .toList();

    rows.sort((a, b) => b.outstandingAmount.compareTo(a.outstandingAmount));
    return rows;
  }

  Future<List<LoanRepaymentRecord>> getLoanRepaymentsForCustomer(
    String customerName, {
    int limit = 20,
  }) async {
    final trimmed = customerName.trim();
    if (trimmed.isEmpty) return const [];
    final database = await db;
    final rows = await database.query(
      'loan_repayments',
      where: 'customer_name = ? COLLATE NOCASE',
      whereArgs: [trimmed],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows
        .map(
          (row) => LoanRepaymentRecord.fromMap(Map<String, Object?>.from(row)),
        )
        .toList();
  }

  Future<double> getOutstandingDebtTotal() async {
    final rows = await getLoanCustomerSummaries();
    return rows.fold<double>(0, (sum, row) => sum + row.outstandingAmount);
  }

  Future<void> recordLoanRepayment({
    required String customerName,
    required double amountPaid,
    String paymentMethod = 'CASH',
    String note = '',
  }) async {
    final trimmedName = customerName.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Customer name is required.');
    }
    if (!amountPaid.isFinite || amountPaid <= 0) {
      throw ArgumentError('Repayment amount must be greater than 0.');
    }

    final summaries = await getLoanCustomerSummaries();
    final summary = summaries
        .where((row) => row.name.toLowerCase() == trimmedName.toLowerCase())
        .cast<LoanCustomerSummary?>()
        .firstWhere((row) => row != null, orElse: () => null);
    if (summary == null) {
      throw StateError('No outstanding loan account found for this customer.');
    }
    final outstanding = summary.outstandingAmount;
    if (outstanding <= _loanBalanceEpsilon) {
      throw StateError('This account has no outstanding balance.');
    }
    if (amountPaid - outstanding > _loanBalanceEpsilon) {
      throw StateError('Repayment exceeds outstanding balance.');
    }

    final database = await db;
    final now = _utcNowMs();
    await database.transaction((txn) async {
      await txn.insert('loan_customers', {
        'name': summary.name,
        'phone': summary.phone,
        'note': '',
        'created_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);

      await txn.insert('loan_repayments', {
        'repayment_uuid': _newUuid(),
        'customer_name': summary.name,
        'amount_paid': amountPaid,
        'payment_method': paymentMethod.trim().isEmpty
            ? 'CASH'
            : paymentMethod.trim().toUpperCase(),
        'note': note.trim(),
        'created_at': now,
        'updated_at': now,
        'sync_status': 'pending',
        'synced': 0,
      });
    });
    _emitInventoryChanged();
  }

  Future<String> recordPurchase({
    required String supplierName,
    required String invoiceNumber,
    required List<PurchaseItem> items,
  }) async {
    final database = await db;
    final receiptId = 'PO-${DateTime.now().millisecondsSinceEpoch}';
    final now = _utcNowMs();
    final purchaseUuid = _newUuid();

    await database.transaction((txn) async {
      final purchaseId = await txn.insert('purchases', {
        'purchase_uuid': purchaseUuid,
        'receipt_id': receiptId,
        'supplier_name': supplierName,
        'invoice_number': invoiceNumber,
        'pharmacy_id': kPharmacyId > 0 ? kPharmacyId : null,
        'device_id': kPosHwid,
        'version': 1,
        'updated_at': now,
        'deleted_at': null,
        'sync_status': 'pending',
        'created_at': now,
      });

      for (final item in items) {
        await txn.insert('purchase_items', {
          'line_uuid': _newUuid(),
          'purchase_id': purchaseId,
          'barcode': item.barcode,
          'name': item.name,
          'dosage': item.dosage,
          'qty': item.qty,
          'cost_price': item.costPrice,
          'updated_at': now,
          'deleted_at': null,
        });

        await txn.insert('product_batches', {
          'batch_uuid': _newUuid(),
          'barcode': item.barcode,
          'batch_number': receiptId,
          'expiry': '',
          'qty_on_hand': item.qty,
          'unit_cost_minor': _toMinorUnits(item.costPrice),
          'unit_price_minor': _toMinorUnits(item.costPrice),
          'currency_code': 'USD',
          'supplier_name': supplierName,
          'reference_id': receiptId,
          'version': 1,
          'updated_at': now,
          'deleted_at': null,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);

        await txn.rawUpdate(
          'UPDATE inventory SET stock = stock + ?, price = ? WHERE barcode = ?',
          [item.qty, item.costPrice, item.barcode],
        );

        final movementUuid = _newUuid();
        await txn.insert('inventory_movement_queue', {
          'movement_uuid': movementUuid,
          'pharmacy_id': kPharmacyId > 0 ? kPharmacyId : null,
          'device_id': kPosHwid,
          'version': 1,
          'barcode': item.barcode,
          'movement_type': 'purchase',
          'quantity_delta': item.qty,
          'unit_price_minor': _toMinorUnits(item.costPrice),
          'currency_code': 'USD',
          'reference_type': 'purchase',
          'reference_id': receiptId,
          'metadata': jsonEncode({
            'supplier_name': supplierName,
            'invoice_number': invoiceNumber,
          }),
          'happened_at': now,
          'updated_at': now,
          'deleted_at': null,
          'sync_status': 'pending',
          'synced_at': null,
        });

        await _insertOutboxEvent(
          eventUuid: movementUuid,
          stream: 'purchase_created',
          payload: {
            'movement_uuid': movementUuid,
            'barcode': item.barcode,
            'movement_type': 'purchase',
            'reference_id': receiptId,
          },
          executor: txn,
        );
      }
    });

    _emitInventoryChanged();
    return receiptId;
  }

  Future<List<PurchaseOrder>> getPurchaseHistory() async {
    final database = await db;
    final headers = await database.query(
      'purchases',
      orderBy: 'created_at DESC',
    );
    final orders = <PurchaseOrder>[];

    for (final h in headers) {
      final purchaseId = (h['id'] as num?)?.toInt() ?? 0;
      final itemMaps = await database.query(
        'purchase_items',
        where: 'purchase_id = ?',
        whereArgs: [purchaseId],
        orderBy: 'id ASC',
      );

      orders.add(
        PurchaseOrder(
          id: purchaseId,
          receiptId: (h['receipt_id'] as String?) ?? '',
          supplierName: (h['supplier_name'] as String?) ?? '',
          invoiceNumber: (h['invoice_number'] as String?) ?? '',
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            (h['created_at'] as num?)?.toInt() ?? 0,
          ),
          items: itemMaps.map(PurchaseItem.fromMap).toList(),
        ),
      );
    }

    return orders;
  }

  Future<void> syncDown({
    int limit = 500,
    SyncConflictHandler? onConflict,
  }) async {
    try {
      final lastCheckpoint = await _getCheckpointToken('server_to_pos');
      final params = <String, String>{
        'limit': '$limit',
        if ((lastCheckpoint ?? '').isNotEmpty) 'cursor': lastCheckpoint!,
      };
      final family = await resolveBackendFamily();
      final syncDownUri = _syncUriForFamily(
        family,
        'sync/pull',
        'sync/pull',
      ).replace(queryParameters: params);
      var response = await http
          .get(syncDownUri, headers: _canonicalSyncHeaders())
          .timeout(_appConfig.requestTimeout);
      if (response.statusCode == 404) {
        final fallbackFamily = family == SyncBackendFamily.central
            ? SyncBackendFamily.proxy
            : SyncBackendFamily.central;
        _logSyncHttpFailure(
          operation: 'sync-down',
          uri: syncDownUri,
          statusCode: response.statusCode,
          family: family,
        );
        _backendFamily = fallbackFamily;
        response = await http
            .get(
              _syncUriForFamily(
                fallbackFamily,
                'sync/pull',
                'sync/pull',
              ).replace(queryParameters: params),
              headers: _canonicalSyncHeaders(),
            )
            .timeout(_appConfig.requestTimeout);
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw StateError('sync-down unauthorized');
      }
      if (response.statusCode != 200) return;

      final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;
      final pullData = Map<String, dynamic>.from(
        (jsonResponse['data'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      );
      final rows =
          ((pullData['authoritative_medicines'] ??
                      jsonResponse['authoritative_medicines'] ??
                      jsonResponse['medicines'] ??
                      jsonResponse['data'])
                  as List?)
              ?.cast<Map>() ??
          const [];
      final regulatedPrices =
          ((pullData['regulated_prices'] ?? jsonResponse['regulated_prices'])
                  as List?)
              ?.cast<Map>() ??
          const [];
      final complianceAlerts =
          ((pullData['compliance_status'] ??
                      pullData['compliance_alerts'] ??
                      jsonResponse['compliance_status'] ??
                      jsonResponse['compliance_alerts'])
                  as List?)
              ?.cast<Map>() ??
          const [];
      final medicineRequests =
          ((pullData['medicine_requests'] ?? jsonResponse['medicine_requests'])
                  as List?)
              ?.cast<Map>() ??
          const [];
      final conflictNotes =
          ((pullData['conflict_notes'] ?? jsonResponse['conflict_notes'])
                  as List?)
              ?.cast<Map>() ??
          const [];
      if (rows.isEmpty &&
          regulatedPrices.isEmpty &&
          complianceAlerts.isEmpty &&
          medicineRequests.isEmpty) {
        return;
      }
      final appliedData =
          rows.isNotEmpty ||
          regulatedPrices.isNotEmpty ||
          complianceAlerts.isNotEmpty ||
          medicineRequests.isNotEmpty ||
          conflictNotes.isNotEmpty;

      final checkpointToken = _asString(
        jsonResponse['checkpoint_token'] ??
            jsonResponse['next_cursor'] ??
            pullData['next_cursor'] ??
            jsonResponse['server_checkpoint'],
      ).trim();

      if (medicineRequests.isNotEmpty) {
        final requestRows = medicineRequests
            .map((raw) => Map<String, dynamic>.from(raw))
            .toList();
        await syncMedicineRequestStatuses(requestRows);
      }

      final database = await db;
      await database.transaction((txn) async {
        for (final raw in rows) {
          final row = Map<String, dynamic>.from(raw);
          final barcode = _asString(row['barcode']).trim();
          if (barcode.isEmpty) continue;

          final existingRows = await txn.query(
            'inventory',
            columns: [
              'moph_ceiling',
              'is_blocked',
              'name',
              'batch_number',
              'version',
              'updated_at',
              'source',
            ],
            where: 'barcode = ?',
            whereArgs: [barcode],
            limit: 1,
          );

          final officialName = resolveOfficialName(row);
          final dosage = _asString(row['dosage']);
          final category = _asString(row['category']);
          final ceiling = extractOfficialPrice(row);
          final blocked = _asBool(row['is_blocked']);
          final serverUpdatedAtMs =
              DateTime.tryParse(
                _asString(row['updated_at']),
              )?.toUtc().millisecondsSinceEpoch ??
              _utcNowMs();
          final medicineUuid = _asString(row['medicine_uuid']).trim().isEmpty
              ? _newUuid()
              : _asString(row['medicine_uuid']).trim();
          final incomingVersion = _asIntOrNull(row['version']) ?? 1;
          final incomingSource = _asString(row['source']).isEmpty
              ? 'server'
              : _asString(row['source']);
          final incomingDeletedAt =
              DateTime.tryParse(
                _asString(row['deleted_at']),
              )?.toUtc().millisecondsSinceEpoch ??
              _asIntOrNull(row['deleted_at']);
          final incomingOfficialName = officialName;
          final incomingOfficialCode = resolveOfficialCode(row);

          if (onConflict != null && existingRows.isNotEmpty) {
            final existing = existingRows.first;
            final localCeiling = _asDoubleOrNull(existing['moph_ceiling']);
            if (localCeiling != ceiling) {
              await onConflict(
                SyncConflict(
                  entity: 'medicine',
                  entityId: barcode,
                  field: 'moph_ceiling',
                  localValue: localCeiling,
                  serverValue: ceiling,
                ),
              );
            }

            final localBlocked = _asBool(existing['is_blocked']);
            if (localBlocked != blocked) {
              await onConflict(
                SyncConflict(
                  entity: 'medicine',
                  entityId: barcode,
                  field: 'is_blocked',
                  localValue: localBlocked,
                  serverValue: blocked,
                ),
              );
            }

            final localName = _asString(existing['name']);
            if (localName != incomingOfficialName) {
              await onConflict(
                SyncConflict(
                  entity: 'medicine',
                  entityId: barcode,
                  field: 'official_name',
                  localValue: localName,
                  serverValue: incomingOfficialName,
                ),
              );
            }
          }

          final existing = existingRows.isNotEmpty ? existingRows.first : null;
          final shouldApply = existing == null
              ? true
              : _incomingIsNewer(
                  localVersion: _asIntOrNull(existing['version']),
                  localUpdatedAt: _asIntOrNull(existing['updated_at']),
                  incomingVersion: incomingVersion,
                  incomingUpdatedAt: serverUpdatedAtMs,
                  localSource: _asString(existing['source']).isEmpty
                      ? 'local'
                      : _asString(existing['source']),
                  incomingSource: incomingSource,
                );

          if (!shouldApply) {
            await _recordConflictNote(
              txn: txn,
              entityType: 'medicine',
              entityId: barcode,
              field: 'version',
              conflictCode: 'out_of_order_server_update_ignored',
              localValue: {
                'version': existing['version'],
                'updated_at': existing['updated_at'],
              },
              serverValue: {
                'version': incomingVersion,
                'updated_at': serverUpdatedAtMs,
              },
              note:
                  'Received out-of-order medicine update. Deterministic ordering kept local latest row.',
            );
            continue;
          }

          if (existing != null) {
            if (_asDoubleOrNull(existing['moph_ceiling']) != ceiling) {
              await _recordConflictNote(
                txn: txn,
                entityType: 'medicine',
                entityId: barcode,
                field: 'regulated_price',
                conflictCode: 'server_authoritative_override',
                localValue: existing['moph_ceiling'],
                serverValue: ceiling,
                note:
                    'Regulated price overridden by government source while syncing.',
              );
            }
            if (_asBool(existing['is_blocked']) != blocked) {
              await _recordConflictNote(
                txn: txn,
                entityType: 'medicine',
                entityId: barcode,
                field: 'blocked_status',
                conflictCode: 'server_authoritative_override',
                localValue: existing['is_blocked'],
                serverValue: blocked,
                note:
                    'Blocked or suspended status overridden by server policy.',
              );
            }
          }

          await txn.rawInsert(
            '''
						INSERT INTO inventory (barcode, name, dosage, category, stock, expiry, price, moph_ceiling, batch_number)
						VALUES (?, ?, ?, ?, 0, '', 0.0, ?, '')
						ON CONFLICT(barcode) DO UPDATE SET
							name = excluded.name,
							dosage = excluded.dosage,
							category = excluded.category,
							moph_ceiling = excluded.moph_ceiling
						''',
            [barcode, incomingOfficialName, dosage, category, ceiling],
          );

          await txn.update(
            'inventory',
            {
              'is_blocked': blocked ? 1 : 0,
              'server_updated_at': serverUpdatedAtMs,
              'product_uuid': medicineUuid,
              'pharmacy_id': kPharmacyId > 0 ? kPharmacyId : null,
              'source': incomingSource,
              'version': incomingVersion,
              'updated_at': serverUpdatedAtMs,
              'deleted_at': incomingDeletedAt,
              'batch_number': incomingOfficialCode,
            },
            where: 'barcode = ?',
            whereArgs: [barcode],
          );
        }

        for (final raw in regulatedPrices) {
          final row = Map<String, dynamic>.from(raw);
          final barcode = _asString(row['barcode']).trim();
          if (barcode.isEmpty) continue;
          final updatedAt =
              DateTime.tryParse(
                _asString(row['updated_at']),
              )?.toUtc().millisecondsSinceEpoch ??
              _utcNowMs();
          final localPriceRows = await txn.query(
            'prices',
            columns: [
              'regulated_price_minor',
              'version',
              'updated_at',
              'source',
            ],
            where: 'barcode = ?',
            whereArgs: [barcode],
            limit: 1,
          );
          final localPrice = localPriceRows.isEmpty
              ? null
              : localPriceRows.first;
          final incomingVersion = _asIntOrNull(row['version']) ?? 1;
          final incomingSource = _asString(row['source']).isEmpty
              ? 'server'
              : _asString(row['source']);
          final incomingDeletedAt =
              DateTime.tryParse(
                _asString(row['deleted_at']),
              )?.toUtc().millisecondsSinceEpoch ??
              _asIntOrNull(row['deleted_at']);

          if (localPrice != null &&
              !_incomingIsNewer(
                localVersion: _asIntOrNull(localPrice['version']),
                localUpdatedAt: _asIntOrNull(localPrice['updated_at']),
                incomingVersion: incomingVersion,
                incomingUpdatedAt: updatedAt,
                localSource: _asString(localPrice['source']).isEmpty
                    ? 'local'
                    : _asString(localPrice['source']),
                incomingSource: incomingSource,
              )) {
            await _recordConflictNote(
              txn: txn,
              entityType: 'price',
              entityId: barcode,
              field: 'regulated_price',
              conflictCode: 'out_of_order_price_update_ignored',
              localValue: localPrice['regulated_price_minor'],
              serverValue: row['regulated_price_minor'],
              note:
                  'Out-of-order regulated price update ignored by deterministic rule.',
            );
            continue;
          }

          if (localPrice != null &&
              localPrice['regulated_price_minor'] !=
                  row['regulated_price_minor']) {
            await _recordConflictNote(
              txn: txn,
              entityType: 'price',
              entityId: barcode,
              field: 'regulated_price',
              conflictCode: 'server_authoritative_override',
              localValue: localPrice['regulated_price_minor'],
              serverValue: row['regulated_price_minor'],
              note: 'Government regulated price superseded local value.',
            );
          }

          final incomingLocalMinor = _asIntOrNull(row['local_price_minor']);
          final incomingRegulatedMinor = _asIntOrNull(row['regulated_price_minor']);

          await txn.insert('prices', {
            'price_uuid': _asString(row['price_uuid']).isEmpty
                ? _newUuid()
                : _asString(row['price_uuid']),
            'pharmacy_id':
                _asIntOrNull(row['pharmacy_id']) ??
                (kPharmacyId > 0 ? kPharmacyId : null),
            'barcode': barcode,
            'regulated_price_minor': incomingRegulatedMinor,
            'local_price_minor': incomingLocalMinor,
            'currency_code': _asString(row['currency_code']).isEmpty
                ? 'USD'
                : _asString(row['currency_code']),
            'source': incomingSource,
            'version': incomingVersion,
            'updated_at': updatedAt,
            'deleted_at': incomingDeletedAt,
          }, conflictAlgorithm: ConflictAlgorithm.replace);

          // Keep inventory price + ceiling aligned with canonical pricing.
          // Local price comes from the pharmacy's own sales / approved price.
          // Ministry ceiling (moph_ceiling) is the regulated price.
          final inventoryUpdate = <String, dynamic>{
            'moph_ceiling': incomingRegulatedMinor == null
                ? null
                : incomingRegulatedMinor / 100.0,
          };
          if (incomingLocalMinor != null) {
            inventoryUpdate['price'] = incomingLocalMinor / 100.0;
          }
          await txn.update(
            'inventory',
            inventoryUpdate,
            where: 'barcode = ?',
            whereArgs: [barcode],
          );
        }

        // Apply per-pharmacy stock totals so the inventory reflects what the
        // server says this pharmacy has on hand. Without this, after a local
        // wipe / fresh sync every medicine would show 0 units even when the
        // backend's pharmacy_stock has real numbers.
        final stockTotals =
            ((pullData['stock_totals'] ?? jsonResponse['stock_totals'])
                    as List?)
                ?.cast<Map>() ??
            const [];
        for (final raw in stockTotals) {
          final row = Map<String, dynamic>.from(raw);
          final barcode = _asString(row['barcode']).trim();
          if (barcode.isEmpty) continue;
          final stock = _asIntOrNull(row['stock_units']);
          if (stock == null) continue;
          await txn.update(
            'inventory',
            {'stock': stock.clamp(0, 999999)},
            where: 'barcode = ?',
            whereArgs: [barcode],
          );
        }

        for (final raw in complianceAlerts) {
          final row = Map<String, dynamic>.from(raw);
          final alertUuid = _asString(row['alert_uuid']).trim();
          if (alertUuid.isEmpty) continue;
          final createdAt =
              DateTime.tryParse(
                _asString(row['created_at']),
              )?.toUtc().millisecondsSinceEpoch ??
              _utcNowMs();
          final updatedAt =
              DateTime.tryParse(
                _asString(row['updated_at']),
              )?.toUtc().millisecondsSinceEpoch ??
              createdAt;
          final incomingDeletedAt =
              DateTime.tryParse(
                _asString(row['deleted_at']),
              )?.toUtc().millisecondsSinceEpoch ??
              _asIntOrNull(row['deleted_at']);
          await txn.insert('compliance_alerts', {
            'alert_uuid': alertUuid,
            'pharmacy_id':
                _asIntOrNull(row['pharmacy_id']) ??
                (kPharmacyId > 0 ? kPharmacyId : null),
            'source': _asString(row['source']).isEmpty
                ? 'server'
                : _asString(row['source']),
            'version': _asIntOrNull(row['version']) ?? 1,
            'alert_type': _asString(row['alert_type']),
            'severity': _asString(row['severity']).isEmpty
                ? 'medium'
                : _asString(row['severity']),
            'title': _asString(row['title']),
            'details': jsonEncode(row['details'] ?? const {}),
            'status': _asString(row['status']).isEmpty
                ? 'open'
                : _asString(row['status']),
            'created_at': createdAt,
            'acknowledged_at': null,
            'resolved_at': null,
            'updated_at': updatedAt,
            'deleted_at': incomingDeletedAt,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }

        for (final raw in conflictNotes) {
          final row = Map<String, dynamic>.from(raw);
          final incomingDeletedAt =
              DateTime.tryParse(
                _asString(row['deleted_at']),
              )?.toUtc().millisecondsSinceEpoch ??
              _asIntOrNull(row['deleted_at']);
          await txn.insert('sync_conflict_notes', {
            'note_uuid': _asString(row['conflict_uuid']).isEmpty
                ? _newUuid()
                : _asString(row['conflict_uuid']),
            'pharmacy_id':
                _asIntOrNull(row['pharmacy_id']) ??
                (kPharmacyId > 0 ? kPharmacyId : null),
            'entity_type': _asString(row['entity_type']),
            'entity_id': _asString(row['entity_id']),
            'field': _asString(row['field']),
            'conflict_code': _asString(row['conflict_code']),
            'local_value': jsonEncode(row['local_value']),
            'server_value': jsonEncode(row['server_value']),
            'note': _asString(row['note']),
            'source': _asString(row['source']).isEmpty
                ? 'server'
                : _asString(row['source']),
            'resolved': 0,
            'created_at':
                DateTime.tryParse(
                  _asString(row['created_at']),
                )?.toUtc().millisecondsSinceEpoch ??
                _utcNowMs(),
            'updated_at':
                DateTime.tryParse(
                  _asString(row['updated_at']),
                )?.toUtc().millisecondsSinceEpoch ??
                _utcNowMs(),
            'deleted_at': incomingDeletedAt,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      });

      if (checkpointToken.isNotEmpty) {
        await _setCheckpoint('server_to_pos', checkpointToken);
        await _setSyncState('last_pulled_checkpoint', checkpointToken);

        final ackPayload = jsonEncode({
          'request_id': _newUuid(),
          'batch_id': _asString(jsonResponse['batch_id']).isEmpty
              ? _newUuid()
              : _asString(jsonResponse['batch_id']),
          'checkpoint_token': checkpointToken,
        });
        final ackUri = _syncUriForFamily(
          _backendFamily ?? SyncBackendFamily.central,
          'sync/ack',
          'sync/ack',
        );
        var ackResponse = await http
            .post(
              ackUri,
              headers: _canonicalSyncHeaders(includeJson: true),
              body: ackPayload,
            )
            .timeout(_appConfig.requestTimeout);
        if (ackResponse.statusCode == 404) {
          final fallbackFamily =
              (_backendFamily ?? SyncBackendFamily.central) ==
                  SyncBackendFamily.central
              ? SyncBackendFamily.proxy
              : SyncBackendFamily.central;
          _logSyncHttpFailure(
            operation: 'sync-ack',
            uri: ackUri,
            statusCode: ackResponse.statusCode,
            family: _backendFamily ?? SyncBackendFamily.central,
          );
          _backendFamily = fallbackFamily;
          ackResponse = await http
              .post(
                _syncUriForFamily(fallbackFamily, 'sync/ack', 'sync/ack'),
                headers: _canonicalSyncHeaders(includeJson: true),
                body: ackPayload,
              )
              .timeout(_appConfig.requestTimeout);
        }

        if (ackResponse.statusCode == 200) {
          await _setSyncState('last_acknowledged_checkpoint', checkpointToken);
        }
      }
      if (appliedData) {
        _emitInventoryChanged();
      }
    } catch (e) {
      print('Sync Down Error: $e');
      rethrow;
    }
  }

  Future<void> syncUp() async {
    try {
      if (kPharmacyId <= 0 && kPosHwid.trim().isEmpty) {
        print(
          'Sync Up skipped: configure MEDTRACK_PHARMACY_ID or MEDTRACK_POS_HWID.',
        );
        return;
      }

      for (var i = 0; i < 20; i += 1) {
        final pushed = await syncUpChunk(chunkSize: 100);
        if (pushed == 0) break;
      }
    } catch (e) {
      print('Sync Up Error: $e');
      rethrow;
    }
  }

  Future<void> runFullSync() async {
    await syncDown();
    await syncUp();
  }
}
