double _toDouble(dynamic v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0.0;
  return 0.0;
}

class Pharmacy {
  final int id;
  final String name;
  final String location;
  final String licenseNumber;
  final String hwid;
  final String region;
  final String status;
  final String lastSeen;
  final int latencyMs;
  final String syncVersion;
  final int syncPct;
  final DateTime createdAt;
  final double latitude;
  final double longitude;
  final String phone;
  final double rating;
  final int reviewCount;
  final String openingHours;
  final String closingHours;
  final bool isOpen;
  final double distanceKm;
  final List<PharmacyStock> stock;

  Pharmacy({
    required this.id,
    required this.name,
    required this.location,
    this.licenseNumber = '',
    this.hwid = '',
    this.region = '',
    this.status = 'unknown',
    this.lastSeen = '',
    this.latencyMs = 0,
    this.syncVersion = '',
    this.syncPct = 0,
    DateTime? createdAt,
    required this.latitude,
    required this.longitude,
    this.phone = '',
    this.rating = 0.0,
    this.reviewCount = 0,
    this.openingHours = '09:00',
    this.closingHours = '22:00',
    bool? isOpen,
    this.distanceKm = 0.0,
    this.stock = const [],
  }) : createdAt = createdAt ?? DateTime.now(),
       isOpen = isOpen ?? (status == 'online');

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'location': location,
    'licenseNumber': licenseNumber,
    'hwid': hwid,
    'region': region,
    'status': status,
    'lastSeen': lastSeen,
    'latencyMs': latencyMs,
    'syncVersion': syncVersion,
    'syncPct': syncPct,
    'createdAt': createdAt.toIso8601String(),
    'latitude': latitude,
    'longitude': longitude,
    'phone': phone,
    'rating': rating,
    'reviewCount': reviewCount,
    'openingHours': openingHours,
    'closingHours': closingHours,
    'isOpen': isOpen,
    'distanceKm': distanceKm,
  };

  factory Pharmacy.fromJson(Map<String, dynamic> json) {
    // Handle both int ID (legacy) and string pharmacy_id (Neon UUID)
    final id = json['id'] ?? (json['pharmacy_id'] as String?)?.hashCode ?? 0;
    final numId = id is String ? id.hashCode : (id as int);

    // Get location
    final location = json['location'] as String? ?? '';

    // Use coordinates from API (backend now provides these)
    final latitude = _toDouble(json['latitude']);
    final longitude = _toDouble(json['longitude']);

    return Pharmacy(
      id: numId,
      name: json['name'] as String,
      location: location,
      licenseNumber:
          json['license_number'] as String? ??
          json['licenseNumber'] as String? ??
          '',
      hwid: json['hwid'] as String? ?? '',
      region: json['region'] as String? ?? '',
      status: json['status'] as String? ?? 'unknown',
      lastSeen:
          json['last_seen'] as String? ?? json['lastSeen'] as String? ?? '',
      latencyMs: json['latency_ms'] as int? ?? json['latencyMs'] as int? ?? 0,
      syncVersion:
          json['sync_version'] as String? ??
          json['syncVersion'] as String? ??
          '',
      syncPct: json['sync_pct'] as int? ?? json['syncPct'] as int? ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      latitude: latitude,
      longitude: longitude,
      phone: json['phone'] as String? ?? '',
      rating: _toDouble(json['rating']),
      reviewCount:
          json['review_count'] as int? ?? json['reviewCount'] as int? ?? 0,
      openingHours:
          json['opening_hours'] as String? ??
          json['openingHours'] as String? ??
          '',
      closingHours:
          json['closing_hours'] as String? ??
          json['closingHours'] as String? ??
          '',
      isOpen: json['is_open'] as bool? ?? json['isOpen'] as bool? ?? false,
      distanceKm: _toDouble(json['distance']),
      stock:
          (json['stock'] as List?)
              ?.map((e) => PharmacyStock.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Pharmacy copyWith({double? distanceKm}) => Pharmacy(
    id: id,
    name: name,
    location: location,
    licenseNumber: licenseNumber,
    hwid: hwid,
    region: region,
    status: status,
    lastSeen: lastSeen,
    latencyMs: latencyMs,
    syncVersion: syncVersion,
    syncPct: syncPct,
    createdAt: createdAt,
    latitude: latitude,
    longitude: longitude,
    phone: phone,
    rating: rating,
    reviewCount: reviewCount,
    openingHours: openingHours,
    closingHours: closingHours,
    isOpen: isOpen,
    distanceKm: distanceKm ?? this.distanceKm,
    stock: stock,
  );
}

class PharmacyStock {
  final int medicationId;
  final String medicationUuid;
  final String medicationName;
  final bool inStock;
  final double currentPrice;
  final double ministryLockedPrice;
  final DateTime lastUpdated;

  PharmacyStock({
    required this.medicationId,
    this.medicationUuid = '',
    required this.medicationName,
    required this.inStock,
    required this.currentPrice,
    required this.ministryLockedPrice,
    required this.lastUpdated,
  });

  bool get hasPriceDiscrepancy =>
      (currentPrice - ministryLockedPrice).abs() > 0.01;

  Map<String, dynamic> toJson() => {
    'medicationId': medicationId,
    'medicationName': medicationName,
    'inStock': inStock,
    'currentPrice': currentPrice,
    'ministryLockedPrice': ministryLockedPrice,
    'lastUpdated': lastUpdated.toIso8601String(),
  };

  factory PharmacyStock.fromJson(Map<String, dynamic> json) {
    // Handle both int ID (legacy) and string medication_id (Neon UUID)
    final medId = json['medication_id'] ?? json['medicationId'];
    final numId = medId is String ? medId.hashCode : (medId as int? ?? 0);
    final uuid = medId is String ? medId : '';

    return PharmacyStock(
      medicationId: numId,
      medicationUuid: uuid,
      medicationName:
          json['medication_name'] as String? ??
          json['medicationName'] as String? ??
          '',
      inStock: json['in_stock'] as bool? ?? json['inStock'] as bool? ?? false,
      currentPrice: _toDouble(json['current_price'] ?? json['currentPrice']),
      ministryLockedPrice: _toDouble(
        json['ministry_locked_price'] ?? json['ministryLockedPrice'],
      ),
      lastUpdated: json['last_updated'] != null
          ? DateTime.parse(json['last_updated'] as String)
          : json['lastUpdated'] != null
          ? DateTime.parse(json['lastUpdated'] as String)
          : DateTime.now(),
    );
  }
}
