import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  MedTrack 360 — Mobile App Local Database
//  SQLite via sqflite — one DB per device install
//  Stores: user profile, search history, watchlist, reviews, price reports
// ═════════════════════════════════════════════════════════════════════════════

// ── Models ────────────────────────────────────────────────────────────────────

class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.fullName,
    this.phone = '',
    required this.createdAt,
    this.isGuest = false,
  });

  final int id;
  final String email;
  final String fullName;
  final String phone;
  final DateTime createdAt;
  final bool isGuest;

  factory AppUser.fromMap(Map<String, dynamic> m) => AppUser(
    id: m['id'] as int,
    email: m['email'] as String,
    fullName: m['full_name'] as String,
    phone: (m['phone'] as String?) ?? '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
    isGuest: (m['is_guest'] as int? ?? 0) == 1,
  );

  Map<String, dynamic> toMap() => {
    'email': email,
    'full_name': fullName,
    'phone': phone,
    'created_at': createdAt.millisecondsSinceEpoch,
    'is_guest': isGuest ? 1 : 0,
  };
}

class SearchHistoryEntry {
  const SearchHistoryEntry({
    required this.id,
    required this.userId,
    required this.query,
    required this.searchedAt,
  });

  final int id;
  final int userId;
  final String query;
  final DateTime searchedAt;

  factory SearchHistoryEntry.fromMap(Map<String, dynamic> m) =>
      SearchHistoryEntry(
        id: m['id'] as int,
        userId: m['user_id'] as int,
        query: m['query'] as String,
        searchedAt: DateTime.fromMillisecondsSinceEpoch(
          m['searched_at'] as int,
        ),
      );

  Map<String, dynamic> toMap() => {
    'user_id': userId,
    'query': query,
    'searched_at': searchedAt.millisecondsSinceEpoch,
  };
}

class WatchlistEntry {
  const WatchlistEntry({
    required this.id,
    required this.userId,
    required this.drugBarcode,
    required this.drugName,
    required this.notifyAvailable,
    required this.addedAt,
  });

  final int id;
  final int userId;
  final String drugBarcode;
  final String drugName;
  final bool notifyAvailable;
  final DateTime addedAt;

  factory WatchlistEntry.fromMap(Map<String, dynamic> m) => WatchlistEntry(
    id: m['id'] as int,
    userId: m['user_id'] as int,
    drugBarcode: m['drug_barcode'] as String,
    drugName: m['drug_name'] as String,
    notifyAvailable: (m['notify_available'] as int? ?? 0) == 1,
    addedAt: DateTime.fromMillisecondsSinceEpoch(m['added_at'] as int),
  );

  Map<String, dynamic> toMap() => {
    'user_id': userId,
    'drug_barcode': drugBarcode,
    'drug_name': drugName,
    'notify_available': notifyAvailable ? 1 : 0,
    'added_at': addedAt.millisecondsSinceEpoch,
  };
}

class PharmacyReview {
  const PharmacyReview({
    required this.id,
    required this.userId,
    required this.pharmacyHwid,
    required this.rating,
    this.comment = '',
    required this.createdAt,
  });

  final int id;
  final int userId;
  final String pharmacyHwid;
  final int rating; // 1–5
  final String comment;
  final DateTime createdAt;

  factory PharmacyReview.fromMap(Map<String, dynamic> m) => PharmacyReview(
    id: m['id'] as int,
    userId: m['user_id'] as int,
    pharmacyHwid: m['pharmacy_hwid'] as String,
    rating: m['rating'] as int,
    comment: (m['comment'] as String?) ?? '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
  );

  Map<String, dynamic> toMap() => {
    'user_id': userId,
    'pharmacy_hwid': pharmacyHwid,
    'rating': rating,
    'comment': comment,
    'created_at': createdAt.millisecondsSinceEpoch,
  };
}

class PriceDiscrepancyReport {
  const PriceDiscrepancyReport({
    required this.id,
    required this.userId,
    required this.pharmacyHwid,
    required this.drugBarcode,
    required this.drugName,
    required this.reportedPrice,
    this.mohCeiling,
    required this.status,
    required this.reportedAt,
  });

  final int id;
  final int userId;
  final String pharmacyHwid;
  final String drugBarcode;
  final String drugName;
  final double reportedPrice;
  final double? mohCeiling;
  final String status; // pending | reviewed | escalated | dismissed
  final DateTime reportedAt;

  factory PriceDiscrepancyReport.fromMap(Map<String, dynamic> m) =>
      PriceDiscrepancyReport(
        id: m['id'] as int,
        userId: m['user_id'] as int,
        pharmacyHwid: m['pharmacy_hwid'] as String,
        drugBarcode: m['drug_barcode'] as String,
        drugName: m['drug_name'] as String,
        reportedPrice: (m['reported_price'] as num).toDouble(),
        mohCeiling: m['moh_ceiling'] == null
            ? null
            : (m['moh_ceiling'] as num).toDouble(),
        status: m['status'] as String,
        reportedAt: DateTime.fromMillisecondsSinceEpoch(
          m['reported_at'] as int,
        ),
      );

  Map<String, dynamic> toMap() => {
    'user_id': userId,
    'pharmacy_hwid': pharmacyHwid,
    'drug_barcode': drugBarcode,
    'drug_name': drugName,
    'reported_price': reportedPrice,
    'moh_ceiling': mohCeiling,
    'status': status,
    'reported_at': reportedAt.millisecondsSinceEpoch,
  };
}

// ═════════════════════════════════════════════════════════════════════════════
//  Database Singleton
// ═════════════════════════════════════════════════════════════════════════════

class MobileDatabase {
  MobileDatabase._();
  static final MobileDatabase instance = MobileDatabase._();

  Database? _db;

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'medtrack_mobile.db');

    return openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        // ── users ──────────────────────────────────────────────────────────
        await db.execute('''
          CREATE TABLE IF NOT EXISTS users (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            email        TEXT    NOT NULL UNIQUE,
            password_hash TEXT   NOT NULL DEFAULT '',
            full_name    TEXT    NOT NULL DEFAULT '',
            phone        TEXT    NOT NULL DEFAULT '',
            created_at   INTEGER NOT NULL,
            is_guest     INTEGER NOT NULL DEFAULT 0
          )
        ''');

        // ── search_history ─────────────────────────────────────────────────
        await db.execute('''
          CREATE TABLE IF NOT EXISTS search_history (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            query       TEXT    NOT NULL,
            searched_at INTEGER NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_sh_user ON search_history (user_id)',
        );

        // ── watchlist ──────────────────────────────────────────────────────
        await db.execute('''
          CREATE TABLE IF NOT EXISTS watchlist (
            id                INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id           INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            drug_barcode      TEXT    NOT NULL,
            drug_name         TEXT    NOT NULL DEFAULT '',
            notify_available  INTEGER NOT NULL DEFAULT 0,
            added_at          INTEGER NOT NULL,
            UNIQUE (user_id, drug_barcode)
          )
        ''');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_wl_user ON watchlist (user_id)',
        );

        // ── pharmacy_reviews ───────────────────────────────────────────────
        await db.execute('''
          CREATE TABLE IF NOT EXISTS pharmacy_reviews (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id       INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            pharmacy_hwid TEXT    NOT NULL,
            rating        INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
            comment       TEXT    NOT NULL DEFAULT '',
            created_at    INTEGER NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_pr_pharmacy ON pharmacy_reviews (pharmacy_hwid)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_pr_user ON pharmacy_reviews (user_id)',
        );

        // ── price_discrepancy_reports ──────────────────────────────────────
        await db.execute('''
          CREATE TABLE IF NOT EXISTS price_discrepancy_reports (
            id             INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id        INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            pharmacy_hwid  TEXT    NOT NULL,
            drug_barcode   TEXT    NOT NULL,
            drug_name      TEXT    NOT NULL DEFAULT '',
            reported_price REAL    NOT NULL,
            moh_ceiling    REAL,
            status         TEXT    NOT NULL DEFAULT 'pending',
            reported_at    INTEGER NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_pdr_pharmacy ON price_discrepancy_reports (pharmacy_hwid)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_pdr_user ON price_discrepancy_reports (user_id)',
        );
      },
    );
  }

  // ── User CRUD ──────────────────────────────────────────────────────────────

  Future<int> insertUser(AppUser user) async {
    final database = await db;
    return database.insert(
      'users',
      user.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<AppUser?> getUserByEmail(String email) async {
    final database = await db;
    final rows = await database.query(
      'users',
      where: 'email = ?',
      whereArgs: [email],
      limit: 1,
    );
    return rows.isEmpty ? null : AppUser.fromMap(rows.first);
  }

  // ── Search History ─────────────────────────────────────────────────────────

  Future<void> addSearchHistory(int userId, String query) async {
    final database = await db;
    await database.insert('search_history', {
      'user_id': userId,
      'query': query.trim(),
      'searched_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<SearchHistoryEntry>> getSearchHistory(
    int userId, {
    int limit = 30,
  }) async {
    final database = await db;
    final rows = await database.query(
      'search_history',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'searched_at DESC',
      limit: limit,
    );
    return rows.map(SearchHistoryEntry.fromMap).toList();
  }

  Future<void> clearSearchHistory(int userId) async {
    final database = await db;
    await database.delete(
      'search_history',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }

  // ── Watchlist ──────────────────────────────────────────────────────────────

  Future<bool> addToWatchlist(WatchlistEntry entry) async {
    final database = await db;
    final id = await database.insert(
      'watchlist',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return id != 0;
  }

  Future<void> removeFromWatchlist(int userId, String drugBarcode) async {
    final database = await db;
    await database.delete(
      'watchlist',
      where: 'user_id = ? AND drug_barcode = ?',
      whereArgs: [userId, drugBarcode],
    );
  }

  Future<List<WatchlistEntry>> getWatchlist(int userId) async {
    final database = await db;
    final rows = await database.query(
      'watchlist',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'added_at DESC',
    );
    return rows.map(WatchlistEntry.fromMap).toList();
  }

  Future<void> toggleNotification(
    int userId,
    String drugBarcode,
    bool enabled,
  ) async {
    final database = await db;
    await database.update(
      'watchlist',
      {'notify_available': enabled ? 1 : 0},
      where: 'user_id = ? AND drug_barcode = ?',
      whereArgs: [userId, drugBarcode],
    );
  }

  // ── Pharmacy Reviews ───────────────────────────────────────────────────────

  Future<int> submitReview(PharmacyReview review) async {
    final database = await db;
    return database.insert('pharmacy_reviews', review.toMap());
  }

  Future<List<PharmacyReview>> getReviewsForPharmacy(
    String pharmacyHwid,
  ) async {
    final database = await db;
    final rows = await database.query(
      'pharmacy_reviews',
      where: 'pharmacy_hwid = ?',
      whereArgs: [pharmacyHwid],
      orderBy: 'created_at DESC',
    );
    return rows.map(PharmacyReview.fromMap).toList();
  }

  // ── Price Discrepancy Reports ──────────────────────────────────────────────

  Future<int> submitPriceReport(PriceDiscrepancyReport report) async {
    final database = await db;
    return database.insert('price_discrepancy_reports', report.toMap());
  }

  Future<List<PriceDiscrepancyReport>> getMyReports(int userId) async {
    final database = await db;
    final rows = await database.query(
      'price_discrepancy_reports',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'reported_at DESC',
    );
    return rows.map(PriceDiscrepancyReport.fromMap).toList();
  }
}
