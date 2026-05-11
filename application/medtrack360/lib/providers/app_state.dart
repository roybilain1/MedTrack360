import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/medication.dart';
import '../models/notification_item.dart';
import '../models/pharmacy.dart';
import '../models/review.dart';
import '../models/watchlist_item.dart';
import '../services/api_service.dart';

class NotAuthenticatedException implements Exception {
  final String message;
  NotAuthenticatedException([this.message = 'Please sign in to continue.']);
  @override
  String toString() => message;
}

class AppState extends ChangeNotifier {
  final Uuid _uuid = const Uuid();

  static const _kAuthTokenKey = 'auth_token';
  static const _kUserIdKey = 'auth_user_id';
  static const _kUserNameKey = 'auth_user_name';
  static const _kUserEmailKey = 'auth_user_email';

  // Auth state
  bool _isLoggedIn = false;
  String _userName = 'Guest';
  String _userEmail = '';
  String _userId = '';

  bool get isLoggedIn => _isLoggedIn;
  String get userName => _userName;
  String get userEmail => _userEmail;
  String get userId => _userId;

  /// Sign up against the backend, persist the token and hydrate per-user data.
  Future<void> signUp({
    required String fullName,
    required String email,
    required String password,
    String? phone,
  }) async {
    final result = await ApiService.register(
      fullName: fullName,
      email: email,
      password: password,
      phone: phone,
    );
    await _applyAuthResult(result);
  }

  /// Sign in against the backend, persist the token and hydrate per-user data.
  Future<void> signIn({required String email, required String password}) async {
    final result = await ApiService.login(email: email, password: password);
    await _applyAuthResult(result);
  }

  Future<void> _applyAuthResult(Map<String, dynamic> r) async {
    final token = r['token'] as String?;
    if (token == null || token.isEmpty) {
      throw Exception('Auth response missing token');
    }
    ApiService.setAuthToken(token);
    _isLoggedIn = true;
    _userId = r['user_id']?.toString() ?? '';
    _userName = (r['full_name'] as String?)?.trim().isNotEmpty == true
        ? r['full_name'] as String
        : 'MedTrack360 User';
    _userEmail = r['email'] as String? ?? '';

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAuthTokenKey, token);
    await prefs.setString(_kUserIdKey, _userId);
    await prefs.setString(_kUserNameKey, _userName);
    await prefs.setString(_kUserEmailKey, _userEmail);

    notifyListeners();

    // Load the user's own watchlist + notifications from Neon (best-effort).
    await loadUserWatchlist();
    await loadNotifications();
  }

  Future<void> logout() async {
    _isLoggedIn = false;
    _userName = 'Guest';
    _userEmail = '';
    _userId = '';
    _watchlist.clear();
    _reviews.clear();
    _notifications = [];
    ApiService.setAuthToken(null);

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAuthTokenKey);
    await prefs.remove(_kUserIdKey);
    await prefs.remove(_kUserNameKey);
    await prefs.remove(_kUserEmailKey);

    notifyListeners();
  }

  /// Restore a previously stored session. If the token is still valid, calls
  /// `/api/auth/me` to refresh user details; otherwise clears stale storage.
  Future<void> _restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_kAuthTokenKey);
    if (token == null || token.isEmpty) return;

    ApiService.setAuthToken(token);
    final me = await ApiService.me();
    if (me == null) {
      // Token expired or server rejected it — clear the local session.
      ApiService.setAuthToken(null);
      await prefs.remove(_kAuthTokenKey);
      await prefs.remove(_kUserIdKey);
      await prefs.remove(_kUserNameKey);
      await prefs.remove(_kUserEmailKey);
      return;
    }

    _isLoggedIn = true;
    _userId = me['user_id']?.toString() ?? '';
    _userName = (me['full_name'] as String?) ?? 'MedTrack360 User';
    _userEmail = me['email'] as String? ?? '';
  }

  // Data
  List<Medication> _medications = [];
  List<Pharmacy> _pharmacies = [];
  List<Review> _reviews = [];
  List<WatchlistItem> _watchlist = [];
  List<SearchHistoryItem> _searchHistory = [];
  List<NotificationItem> _notifications = [];

  // Search state
  String _searchQuery = '';
  String _selectedCategory = 'All';
  String _sortBy = 'name'; // name, proximity, rating, price

  // User location (set by the map screen once GPS is acquired).
  double? _userLat;
  double? _userLng;

  // Getters
  List<Medication> get medications => _medications;
  List<Pharmacy> get pharmacies => _pharmacies;
  List<Review> get reviews => _reviews;
  List<WatchlistItem> get watchlist => _watchlist;
  List<SearchHistoryItem> get searchHistory => _searchHistory;
  List<NotificationItem> get notifications => List.unmodifiable(_notifications);
  int get unreadNotificationCount =>
      _notifications.where((n) => n.isUnread).length;
  String get searchQuery => _searchQuery;
  String get selectedCategory => _selectedCategory;
  String get sortBy => _sortBy;

  List<Medication> get filteredMedications {
    var results = _medications;

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      results = results.where((m) {
        return m.tradeName.toLowerCase().contains(query) ||
            m.genericName.toLowerCase().contains(query) ||
            m.category.toLowerCase().contains(query);
      }).toList();
    }

    if (_selectedCategory != 'All') {
      results = results.where((m) => m.category == _selectedCategory).toList();
    }

    return results;
  }

  double? get userLat => _userLat;
  double? get userLng => _userLng;
  bool get hasUserLocation => _userLat != null && _userLng != null;

  /// Updates the known user location and recomputes pharmacy distances.
  /// Called by the map screen once GPS (or a fallback) has resolved.
  void setUserLocation(double lat, double lng) {
    if (_userLat == lat && _userLng == lng) return;
    _userLat = lat;
    _userLng = lng;
    _pharmacies = _pharmacies
        .map((p) => p.copyWith(distanceKm: _distanceKm(lat, lng, p.latitude, p.longitude)))
        .toList();
    notifyListeners();
  }

  /// Pharmacies sorted by ascending distance from the user. Falls back to
  /// the unsorted list when we don't yet have a location.
  List<Pharmacy> get nearbyPharmacies {
    final list = List<Pharmacy>.from(_pharmacies);
    if (hasUserLocation) {
      list.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    }
    return list;
  }

  static double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
    const earthKm = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLng = _deg2rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) * math.cos(_deg2rad(lat2)) *
            math.sin(dLng / 2) * math.sin(dLng / 2);
    return earthKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _deg2rad(double d) => d * math.pi / 180.0;

  /// Tries to grab the device's current location without prompting the
  /// OS permission dialog. Used at startup so the dashboard has accurate
  /// distances even before the user opens the map tab.
  Future<void> acquireUserLocationIfAllowed() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      setUserLocation(pos.latitude, pos.longitude);
    } catch (_) {
      // Silent: dashboard just falls back to "—" until the map screen
      // runs the full permission flow.
    }
  }

  List<Pharmacy> get sortedPharmacies {
    var results = List<Pharmacy>.from(_pharmacies);
    switch (_sortBy) {
      case 'proximity':
        results.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
        break;
      case 'rating':
        results.sort((a, b) => b.rating.compareTo(a.rating));
        break;
      case 'name':
      default:
        results.sort((a, b) => a.name.compareTo(b.name));
        break;
    }
    return results;
  }

  // ─── Init ────────────────────────────────────────────────────
  Future<void> init() async {
    // Restore a previously signed-in session if one exists.
    await _restoreSession();

    try {
      // Load medications from Neon API
      _medications = await ApiService.getMedications();
      print('✅ Loaded ${_medications.length} medications from Neon');
    } catch (e) {
      print('❌ Error loading medications: $e');
      _medications = [];
    }

    try {
      // Load pharmacies from Neon API
      _pharmacies = await ApiService.getPharmacies();
      print('✅ Loaded ${_pharmacies.length} pharmacies from Neon');
    } catch (e) {
      print('❌ Error loading pharmacies: $e');
      _pharmacies = [];
    }

    // Load reviews from Neon API for all pharmacies
    await _loadReviewsFromNeon();

    // Local search history is device-local. The watchlist is Neon-only and
    // is hydrated when a user is signed in; guests don't have one.
    await _loadSearchHistory();
    if (_isLoggedIn) {
      await loadUserWatchlist();
      await loadNotifications();
    }

    print('✅ AppState initialized with all data from Neon!');
    notifyListeners();

    // Fire-and-forget: if permission is already granted, populate distances
    // now so the dashboard shows real km instead of "—".
    unawaited(acquireUserLocationIfAllowed());

    // Start the 20-second background poll so price/stock/notification
    // changes show up without the user pulling to refresh.
    _startAutoSync();
  }

  // ─── Auto-sync ───────────────────────────────────────────────
  // Re-fetch the live data (pharmacies + stock + notifications) every
  // 20 seconds so trigger-driven updates from Neon land in the UI
  // without manual refresh.
  Timer? _syncTimer;
  bool _syncInFlight = false;
  DateTime? _lastSyncedAt;

  /// True while a 20s auto-sync round-trip is in flight.
  bool get isSyncing => _syncInFlight;

  /// When the most recent successful auto-sync completed.
  DateTime? get lastSyncedAt => _lastSyncedAt;

  void _startAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _runAutoSync(),
    );
  }

  Future<void> _runAutoSync() async {
    if (_syncInFlight) return; // skip overlap if last tick is still going
    _syncInFlight = true;
    notifyListeners(); // flip the appbar chip to "syncing"
    try {
      _pharmacies = await ApiService.getPharmacies();
      // Re-apply cached user location so new pharmacies inherit distance.
      if (hasUserLocation) {
        _pharmacies = _pharmacies
            .map((p) => p.copyWith(
                  distanceKm: _distanceKm(
                    _userLat!,
                    _userLng!,
                    p.latitude,
                    p.longitude,
                  ),
                ))
            .toList();
      }
      if (_isLoggedIn) {
        _notifications = await ApiService.getNotifications();
      }
      _lastSyncedAt = DateTime.now();
    } catch (e) {
      // Silent — transient network errors shouldn't surface every 20s.
      print('⏳ Auto-sync skipped: $e');
    } finally {
      _syncInFlight = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  /// Load reviews from Neon for all pharmacies
  Future<void> _loadReviewsFromNeon() async {
    _reviews.clear();
    for (final pharmacy in _pharmacies) {
      try {
        final reviews = await ApiService.getPharmacyReviewsAsObjects(
          pharmacy.id.toString(),
        );
        _reviews.addAll(reviews);
      } catch (e) {
        print('⚠️  Error loading reviews for pharmacy ${pharmacy.id}: $e');
      }
    }
    print('✅ Loaded ${_reviews.length} reviews from Neon');
  }

  /// Load the signed-in user's watchlist from Neon.
  Future<void> loadUserWatchlist() async {
    if (!_isLoggedIn) {
      print('⚠️  User not logged in, skipping watchlist load');
      return;
    }

    try {
      _watchlist = await ApiService.getUserWatchlistAsObjects();
      print('✅ Loaded ${_watchlist.length} items from Neon watchlist');
      notifyListeners();
    } catch (e) {
      print('❌ Error loading watchlist from Neon: $e');
    }
  }

  // ─── Search ──────────────────────────────────────────────────
  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  /// Record a finished search in history. Call this when the user actually
  /// commits to a query (presses submit, or taps a result) — not on every
  /// keystroke, so history stores "panadol" rather than "p", "pa", "pan", ….
  void commitSearch(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    _addToSearchHistory(trimmed);
    notifyListeners();
  }

  void setCategory(String category) {
    _selectedCategory = category;
    notifyListeners();
  }

  void setSortBy(String sort) {
    _sortBy = sort;
    notifyListeners();
  }

  // ─── Search History ──────────────────────────────────────────
  void _addToSearchHistory(String query) {
    _searchHistory.removeWhere(
      (item) => item.query.toLowerCase() == query.toLowerCase(),
    );
    _searchHistory.insert(
      0,
      SearchHistoryItem(query: query, searchedAt: DateTime.now()),
    );
    if (_searchHistory.length > 20) {
      _searchHistory = _searchHistory.sublist(0, 20);
    }
    _saveSearchHistory();
  }

  void clearSearchHistory() {
    _searchHistory.clear();
    _saveSearchHistory();
    notifyListeners();
  }

  void removeFromSearchHistory(String query) {
    _searchHistory.removeWhere((item) => item.query == query);
    _saveSearchHistory();
    notifyListeners();
  }

  // ─── Watchlist ───────────────────────────────────────────────
  bool isInWatchlist(String medicationId) {
    return _watchlist.any((item) => item.medicationId == medicationId);
  }

  /// Add a medication to the signed-in user's Neon watchlist. Throws
  /// [NotAuthenticatedException] if the user isn't signed in, and rethrows on
  /// network/DB failure. The optimistic add is rolled back on failure so
  /// `isInWatchlist` stays accurate.
  Future<void> addToWatchlist(Medication medication) async {
    if (!_isLoggedIn) {
      throw NotAuthenticatedException('Sign in to add items to your watchlist.');
    }
    if (medication.uuid.isEmpty) {
      throw Exception(
        'This medication has no server ID yet — try again after data loads.',
      );
    }
    if (isInWatchlist(medication.uuid)) return;

    final optimistic = WatchlistItem(
      id: _uuid.v4(),
      medicationId: medication.uuid,
      medicationName: medication.tradeName,
      genericName: medication.genericName,
      addedAt: DateTime.now(),
    );
    _watchlist.add(optimistic);
    notifyListeners();

    try {
      await ApiService.addToWatchlist(medicationId: medication.uuid);
      await loadUserWatchlist();
    } catch (e) {
      _watchlist.removeWhere((i) => i.id == optimistic.id);
      notifyListeners();
      rethrow;
    }
  }

  /// Remove a medication from the signed-in user's Neon watchlist. `key` can
  /// be either the medication's Neon UUID or the local watchlist item id.
  Future<void> removeFromWatchlist(String key) async {
    if (!_isLoggedIn) {
      throw NotAuthenticatedException(
        'Sign in to manage your watchlist.',
      );
    }

    final idx = _watchlist.indexWhere(
      (i) => i.medicationId == key || i.id == key,
    );
    if (idx < 0) return;

    final item = _watchlist.removeAt(idx);
    notifyListeners();

    try {
      await ApiService.removeFromWatchlist(item.id);
    } catch (e) {
      _watchlist.insert(idx, item);
      notifyListeners();
      rethrow;
    }
  }

  void toggleWatchlistNotification(String itemId) {
    final index = _watchlist.indexWhere((item) => item.id == itemId);
    if (index >= 0) {
      final old = _watchlist[index];
      _watchlist[index] = WatchlistItem(
        id: old.id,
        medicationId: old.medicationId,
        medicationName: old.medicationName,
        genericName: old.genericName,
        addedAt: old.addedAt,
        notifyOnAvailable: !old.notifyOnAvailable,
      );
      notifyListeners();
    }
  }

  // ─── Reviews ─────────────────────────────────────────────────
  List<Review> getReviewsForPharmacy(String pharmacyId) {
    return _reviews.where((r) => r.pharmacyId == pharmacyId).toList();
  }

  /// Submit a review. Requires sign-in — the server derives `user_id` from
  /// the JWT. The review is optimistically inserted locally, then persisted
  /// to Neon; on failure it's rolled back.
  Future<void> addReview({
    required String pharmacyId,
    required double stockAccuracy,
    required double serviceQuality,
    required String comment,
    bool hasDiscrepancy = false,
    String? discrepancyDetails,
  }) async {
    if (!_isLoggedIn) {
      throw NotAuthenticatedException('Sign in to post a review.');
    }

    final optimistic = Review(
      id: _uuid.v4(),
      pharmacyId: pharmacyId,
      userId: _userId,
      userName: _userName,
      stockAccuracyRating: stockAccuracy,
      serviceQualityRating: serviceQuality,
      comment: comment,
      createdAt: DateTime.now(),
      hasDiscrepancyReport: hasDiscrepancy,
      discrepancyDetails: discrepancyDetails,
    );
    _reviews.insert(0, optimistic);
    notifyListeners();

    try {
      await ApiService.submitReview(
        pharmacyId: pharmacyId,
        stockAccuracyRating: stockAccuracy,
        serviceQualityRating: serviceQuality,
        comment: comment,
        hasDiscrepancyReport: hasDiscrepancy,
        discrepancyDetails: discrepancyDetails,
      );
    } catch (e) {
      _reviews.removeWhere((r) => r.id == optimistic.id);
      notifyListeners();
      rethrow;
    }
  }

  // ─── Notifications ───────────────────────────────────────────
  /// Pull the latest notifications for the signed-in user. No-op for
  /// guests (the bell just shows zero unread for them).
  Future<void> loadNotifications() async {
    if (!_isLoggedIn) {
      _notifications = [];
      notifyListeners();
      return;
    }
    try {
      _notifications = await ApiService.getNotifications();
      notifyListeners();
    } catch (e) {
      print('⚠️  Failed to load notifications: $e');
    }
  }

  Future<void> markNotificationRead(String notificationId) async {
    final idx = _notifications.indexWhere((n) => n.id == notificationId);
    if (idx == -1 || !_notifications[idx].isUnread) return;
    // Optimistic local update so the badge reacts immediately.
    _notifications[idx] = _notifications[idx].copyWith(readAt: DateTime.now());
    notifyListeners();
    try {
      await ApiService.markNotificationRead(notificationId);
    } catch (_) {
      // Server failed — revert.
      _notifications[idx] = _notifications[idx].copyWith(readAt: null);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> markAllNotificationsRead() async {
    if (_notifications.every((n) => !n.isUnread)) return;
    final snapshot = List<NotificationItem>.from(_notifications);
    final now = DateTime.now();
    _notifications = _notifications
        .map((n) => n.isUnread ? n.copyWith(readAt: now) : n)
        .toList();
    notifyListeners();
    try {
      await ApiService.markAllNotificationsRead();
    } catch (_) {
      _notifications = snapshot;
      notifyListeners();
      rethrow;
    }
  }

  // ─── Pharmacy helpers ────────────────────────────────────────
  /// `medicationId` is the Neon UUID of the medication (i.e. `Medication.key`).
  /// Falls back to the legacy hashed int id for older records.
  List<Pharmacy> getPharmaciesWithMedication(String medicationId) {
    return _pharmacies.where((p) {
      return p.stock.any(
        (s) =>
            s.inStock &&
            (s.medicationUuid == medicationId ||
                s.medicationId.toString() == medicationId),
      );
    }).toList()..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
  }

  PharmacyStock? getStockForMedication(Pharmacy pharmacy, String medicationId) {
    try {
      return pharmacy.stock.firstWhere(
        (s) =>
            s.medicationUuid == medicationId ||
            s.medicationId.toString() == medicationId,
      );
    } catch (_) {
      return null;
    }
  }

  // ─── Persistence ─────────────────────────────────────────────
  // Watchlist is Neon-only — see addToWatchlist / loadUserWatchlist. There
  // is no device-local cache to keep it strictly per-user.

  Future<void> _saveSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final json = _searchHistory.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList('searchHistory', json);
  }

  Future<void> _loadSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getStringList('searchHistory') ?? [];
    _searchHistory = json
        .map((e) => SearchHistoryItem.fromJson(jsonDecode(e)))
        .toList();
  }
}
