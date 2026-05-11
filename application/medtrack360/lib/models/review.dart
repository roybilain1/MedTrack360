double _parseDouble(dynamic v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0.0;
  return 0.0;
}

class Review {
  final String id;
  final String pharmacyId;
  final String userId;
  final String userName;
  final double stockAccuracyRating;
  final double serviceQualityRating;
  final String comment;
  final DateTime createdAt;
  final bool hasDiscrepancyReport;
  final String? discrepancyDetails;

  Review({
    required this.id,
    required this.pharmacyId,
    required this.userId,
    required this.userName,
    required this.stockAccuracyRating,
    required this.serviceQualityRating,
    required this.comment,
    required this.createdAt,
    this.hasDiscrepancyReport = false,
    this.discrepancyDetails,
  });

  double get overallRating => (stockAccuracyRating + serviceQualityRating) / 2;

  Map<String, dynamic> toJson() => {
    'id': id,
    'pharmacyId': pharmacyId,
    'userId': userId,
    'userName': userName,
    'stockAccuracyRating': stockAccuracyRating,
    'serviceQualityRating': serviceQualityRating,
    'comment': comment,
    'createdAt': createdAt.toIso8601String(),
    'hasDiscrepancyReport': hasDiscrepancyReport,
    'discrepancyDetails': discrepancyDetails,
  };

  factory Review.fromJson(Map<String, dynamic> json) => Review(
    id: json['review_id'] ?? json['id'] ?? '',
    pharmacyId:
        json['pharmacy_id']?.toString() ??
        json['pharmacyId']?.toString() ??
        '0',
    userId: json['user_id'] ?? json['userId'] ?? '',
    userName: json['full_name'] ?? json['userName'] ?? 'Anonymous',
    stockAccuracyRating: _parseDouble(json['stock_accuracy_rating']),
    serviceQualityRating: _parseDouble(json['service_quality_rating']),
    comment: json['comment'] ?? '',
    createdAt: json['created_at'] != null
        ? DateTime.parse(json['created_at'] as String)
        : json['createdAt'] != null
        ? DateTime.parse(json['createdAt'] as String)
        : DateTime.now(),
    hasDiscrepancyReport: json['has_discrepancy_report'] ?? false,
    discrepancyDetails: json['discrepancy_details'] as String?,
  );
}
