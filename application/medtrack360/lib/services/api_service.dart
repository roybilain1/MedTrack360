import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/medication.dart';
import '../models/notification_item.dart';
import '../models/pharmacy.dart';
import '../models/review.dart';
import '../models/watchlist_item.dart';

class ApiService {
  static const String baseUrl = 'http://localhost:3001/api';
  // For production, change to: 'https://your-production-url.com/api'

  /// JWT for the currently signed-in user. Set on login/register, cleared on
  /// logout. Attached to every request via [_headers].
  static String? _authToken;

  static void setAuthToken(String? token) {
    _authToken = token;
  }

  static String? get authToken => _authToken;

  static Map<String, String> get _headers {
    final h = {'Content-Type': 'application/json'};
    if (_authToken != null && _authToken!.isNotEmpty) {
      h['Authorization'] = 'Bearer $_authToken';
    }
    return h;
  }

  // ─── Medications ───────────────────────────────────────────

  /// Get all medications from Neon
  static Future<List<Medication>> getMedications() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/medications'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final medications = (data['data'] as List)
            .map((med) => Medication.fromJson(med))
            .toList();
        return medications;
      } else {
        throw Exception('Failed to load medications: ${response.statusCode}');
      }
    } catch (error) {
      print('Error fetching medications: $error');
      rethrow;
    }
  }

  /// Search medications by name
  static Future<List<Medication>> searchMedications(String query) async {
    try {
      if (query.isEmpty) return getMedications();

      final response = await http
          .get(
            Uri.parse('$baseUrl/medications/search?q=$query'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final medications = (data['data'] as List)
            .map((med) => Medication.fromJson(med))
            .toList();
        return medications;
      } else {
        throw Exception('Failed to search medications: ${response.statusCode}');
      }
    } catch (error) {
      print('Error searching medications: $error');
      rethrow;
    }
  }

  /// Get medication by ID
  static Future<Medication> getMedicationById(String id) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/medications/$id'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return Medication.fromJson(data['data']);
      } else {
        throw Exception('Failed to load medication: ${response.statusCode}');
      }
    } catch (error) {
      print('Error fetching medication: $error');
      rethrow;
    }
  }

  // ─── Categories ───────────────────────────────────────────

  /// Get all medication categories
  static Future<List<Map<String, dynamic>>> getCategories() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/categories'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['data']);
      } else {
        throw Exception('Failed to load categories: ${response.statusCode}');
      }
    } catch (error) {
      print('Error fetching categories: $error');
      rethrow;
    }
  }

  // ─── Pharmacies ───────────────────────────────────────────

  /// Get all pharmacies
  static Future<List<Pharmacy>> getPharmacies() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/pharmacies'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final pharmacies = (data['data'] as List)
            .map((pharmacy) => Pharmacy.fromJson(pharmacy))
            .toList();
        return pharmacies;
      } else {
        throw Exception('Failed to load pharmacies: ${response.statusCode}');
      }
    } catch (error) {
      print('Error fetching pharmacies: $error');
      rethrow;
    }
  }

  /// Get pharmacy by ID
  static Future<Pharmacy> getPharmacyById(int id) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/pharmacies/$id'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return Pharmacy.fromJson(data['data']);
      } else {
        throw Exception('Failed to load pharmacy: ${response.statusCode}');
      }
    } catch (error) {
      print('Error fetching pharmacy: $error');
      rethrow;
    }
  }

  /// Get nearby pharmacies by GPS coordinates
  static Future<List<Pharmacy>> getNearbyPharmacies({
    required double latitude,
    required double longitude,
    double radius = 10.0,
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              '$baseUrl/pharmacies/nearby?lat=$latitude&lng=$longitude&radius=$radius',
            ),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final pharmacies = (data['data'] as List)
            .map((pharmacy) => Pharmacy.fromJson(pharmacy))
            .toList();
        return pharmacies;
      } else {
        throw Exception(
          'Failed to load nearby pharmacies: ${response.statusCode}',
        );
      }
    } catch (error) {
      print('Error fetching nearby pharmacies: $error');
      rethrow;
    }
  }

  // ─── Authentication ───────────────────────────────────────

  /// Register new user. Returns `{user_id, full_name, email, phone, token}`.
  static Future<Map<String, dynamic>> register({
    required String fullName,
    required String email,
    required String password,
    String? phone,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/auth/register'),
          headers: _headers,
          body: jsonEncode({
            'full_name': fullName,
            'email': email,
            'password': password,
            'phone': phone,
          }),
        )
        .timeout(const Duration(seconds: 10));

    final body = jsonDecode(response.body);
    if (response.statusCode == 201 && body['success'] == true) {
      return Map<String, dynamic>.from(body['data']);
    }
    throw Exception(body['error'] ?? 'Registration failed');
  }

  /// User login. Returns `{user_id, full_name, email, phone, token}`.
  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/auth/login'),
          headers: _headers,
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(const Duration(seconds: 10));

    final body = jsonDecode(response.body);
    if (response.statusCode == 200 && body['success'] == true) {
      return Map<String, dynamic>.from(body['data']);
    }
    throw Exception(body['error'] ?? 'Login failed');
  }

  /// Resolve the current user from the stored JWT. Returns null if the token
  /// is missing or no longer valid.
  static Future<Map<String, dynamic>?> me() async {
    if (_authToken == null || _authToken!.isEmpty) return null;
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/auth/me'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body)['data']);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ─── Reviews ───────────────────────────────────────────────

  /// Get reviews for a pharmacy as Review objects
  static Future<List<Review>> getPharmacyReviewsAsObjects(
    String pharmacyId,
  ) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/reviews/pharmacy/$pharmacyId'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['data'] as List)
            .map((review) => Review.fromJson(review))
            .toList();
      } else {
        throw Exception('Failed to load reviews: ${response.statusCode}');
      }
    } catch (error) {
      print('Error fetching reviews: $error');
      rethrow;
    }
  }

  /// Get reviews for a pharmacy as raw maps
  static Future<List<Map<String, dynamic>>> getPharmacyReviews(
    String pharmacyId,
  ) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/reviews/pharmacy/$pharmacyId'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['data']);
      } else {
        throw Exception('Failed to load reviews: ${response.statusCode}');
      }
    } catch (error) {
      print('Error fetching reviews: $error');
      rethrow;
    }
  }

  /// Get the current user's watchlist as WatchlistItem objects. The optional
  /// positional parameter is kept for source compatibility with older call
  /// sites and is ignored — the server derives the user from the JWT.
  // ignore: unused_element_parameter
  static Future<List<WatchlistItem>> getUserWatchlistAsObjects([
    String? legacyUserId,
  ]) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/watchlist'), headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['data'] as List)
            .map((item) => WatchlistItem.fromJson(item))
            .toList();
      } else {
        throw Exception('Failed to load watchlist: ${response.statusCode}');
      }
    } catch (error) {
      print('Error fetching watchlist: $error');
      rethrow;
    }
  }

  /// Submit a review for a pharmacy. Requires an authenticated user — the
  /// server derives `user_id` from the JWT.
  static Future<Map<String, dynamic>> submitReview({
    required String pharmacyId,
    String? userId, // legacy; ignored by the server
    required double stockAccuracyRating,
    required double serviceQualityRating,
    String? comment,
    bool hasDiscrepancyReport = false,
    String? discrepancyDetails,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/reviews'),
          headers: _headers,
          body: jsonEncode({
            'pharmacy_id': pharmacyId,
            'stock_accuracy_rating': stockAccuracyRating,
            'service_quality_rating': serviceQualityRating,
            'comment': comment,
            'has_discrepancy_report': hasDiscrepancyReport,
            'discrepancy_details': discrepancyDetails,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 201) {
      return Map<String, dynamic>.from(jsonDecode(response.body)['data']);
    }
    throw Exception('Failed to submit review: ${response.statusCode}');
  }

  // ─── Watchlist ────────────────────────────────────────────

  /// Get the current user's watchlist (authenticated).
  // ignore: unused_element_parameter
  static Future<List<Medication>> getUserWatchlist([String? legacyUserId]) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/watchlist'), headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final medications = (data['data'] as List)
            .map((med) => Medication.fromJson(med))
            .toList();
        return medications;
      } else {
        throw Exception('Failed to load watchlist: ${response.statusCode}');
      }
    } catch (error) {
      print('Error fetching watchlist: $error');
      rethrow;
    }
  }

  /// Add medication to the current user's watchlist (authenticated).
  static Future<Map<String, dynamic>> addToWatchlist({
    String? userId, // legacy; ignored by the server
    required String medicationId,
    bool notifyOnAvailable = true,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/watchlist'),
          headers: _headers,
          body: jsonEncode({
            'medication_id': medicationId,
            'notify_on_available': notifyOnAvailable,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 201) {
      return Map<String, dynamic>.from(jsonDecode(response.body)['data']);
    }
    throw Exception('Failed to add to watchlist: ${response.statusCode}');
  }

  /// Remove medication from the current user's watchlist (authenticated).
  static Future<void> removeFromWatchlist(String watchlistId) async {
    final response = await http
        .delete(
          Uri.parse('$baseUrl/watchlist/$watchlistId'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to remove from watchlist: ${response.statusCode}',
      );
    }
  }

  // ─── Notifications ───────────────────────────────────────

  /// Fetch the signed-in user's notifications, newest first.
  static Future<List<NotificationItem>> getNotifications() async {
    final response = await http
        .get(Uri.parse('$baseUrl/notifications'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Failed to load notifications: ${response.statusCode}');
    }
    final data = jsonDecode(response.body);
    return (data['data'] as List)
        .map((e) => NotificationItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Cheap unread-count lookup for the bell badge.
  static Future<int> getUnreadNotificationCount() async {
    final response = await http
        .get(
          Uri.parse('$baseUrl/notifications/unread-count'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Failed to load unread count: ${response.statusCode}');
    }
    final data = jsonDecode(response.body);
    return (data['data']['count'] as num).toInt();
  }

  static Future<void> markNotificationRead(String notificationId) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/notifications/$notificationId/read'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to mark notification read: ${response.statusCode}',
      );
    }
  }

  static Future<void> markAllNotificationsRead() async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/notifications/read-all'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to mark all read: ${response.statusCode}',
      );
    }
  }

  // ─── Health Check ────────────────────────────────────────

  /// Check if backend is connected
  static Future<bool> checkConnection() async {
    try {
      final response = await http
          .get(
            Uri.parse('${baseUrl.replaceAll('/api', '')}/health'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (error) {
      print('Backend not accessible: $error');
      return false;
    }
  }
}
