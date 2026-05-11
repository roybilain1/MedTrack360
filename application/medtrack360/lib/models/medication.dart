class Medication {
  final int id;
  final String uuid; // Neon's medication_id UUID — empty for legacy records.
  final String barcode;
  final String regNumber;
  final String tradeName;
  final String genericName;
  final String dosage;
  final String form;
  final String manufacturer;
  final String category;
  final double mophCeiling;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isBlocked;

  /// Stable identifier used for watchlist/review operations. Prefers the
  /// Neon UUID; falls back to the legacy int id as a string.
  String get key => uuid.isNotEmpty ? uuid : id.toString();

  Medication({
    required this.id,
    this.uuid = '',
    required this.barcode,
    required this.regNumber,
    required this.tradeName,
    required this.genericName,
    required this.dosage,
    required this.form,
    required this.manufacturer,
    required this.category,
    required this.mophCeiling,
    required this.createdAt,
    required this.updatedAt,
    required this.isBlocked,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'barcode': barcode,
    'regNumber': regNumber,
    'tradeName': tradeName,
    'genericName': genericName,
    'dosage': dosage,
    'form': form,
    'manufacturer': manufacturer,
    'category': category,
    'mophCeiling': mophCeiling,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'isBlocked': isBlocked,
  };

  factory Medication.fromJson(Map<String, dynamic> json) {
    // Handle both old format (id) and Neon format (medication_id)
    final rawUuid = json['medication_id'] as String? ?? '';
    final id = json['id'] ?? rawUuid.hashCode;

    return Medication(
      id: id is String ? id.hashCode : id,
      uuid: rawUuid,
      barcode: json['barcode'] as String? ?? '',
      regNumber:
          json['reg_number'] as String? ?? json['regNumber'] as String? ?? '',
      tradeName:
          json['brand_name'] as String? ?? json['tradeName'] as String? ?? '',
      genericName:
          json['generic_name'] as String? ??
          json['genericName'] as String? ??
          '',
      dosage: json['strength'] as String? ?? json['dosage'] as String? ?? '',
      form: json['dosage_form'] as String? ?? json['form'] as String? ?? '',
      manufacturer: json['manufacturer'] as String? ?? '',
      category:
          json['category_name'] as String? ?? json['category'] as String? ?? '',
      mophCeiling: _parseDouble(
        json['ministry_locked_price'] ?? json['mophCeiling'],
      ),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : DateTime.now(),
      isBlocked:
          json['is_blocked'] as bool? ?? json['isBlocked'] as bool? ?? false,
    );
  }

  // Helper method to parse double from various types
  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }
    if (value is num) return value.toDouble();
    return 0.0;
  }
}
