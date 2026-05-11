class WatchlistItem {
  final String id;
  final String medicationId; // Neon uses UUID strings
  final String medicationName;
  final String genericName;
  final DateTime addedAt;
  final bool notifyOnAvailable;

  WatchlistItem({
    required this.id,
    required this.medicationId,
    required this.medicationName,
    required this.genericName,
    required this.addedAt,
    this.notifyOnAvailable = true,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'medicationId': medicationId,
    'medicationName': medicationName,
    'genericName': genericName,
    'addedAt': addedAt.toIso8601String(),
    'notifyOnAvailable': notifyOnAvailable,
  };

  factory WatchlistItem.fromJson(Map<String, dynamic> json) => WatchlistItem(
    id: json['watchlist_id'] ?? json['id'] ?? '',
    medicationId:
        json['medication_id']?.toString() ??
        json['medicationId']?.toString() ??
        '',
    medicationName: json['brand_name'] ?? json['medicationName'] ?? '',
    genericName: json['generic_name'] ?? json['genericName'] ?? '',
    addedAt: json['added_at'] != null
        ? DateTime.parse(json['added_at'] as String)
        : json['addedAt'] != null
        ? DateTime.parse(json['addedAt'] as String)
        : DateTime.now(),
    notifyOnAvailable:
        json['notify_on_available'] ?? json['notifyOnAvailable'] ?? true,
  );
}

class SearchHistoryItem {
  final String query;
  final DateTime searchedAt;

  SearchHistoryItem({required this.query, required this.searchedAt});

  Map<String, dynamic> toJson() => {
    'query': query,
    'searchedAt': searchedAt.toIso8601String(),
  };

  factory SearchHistoryItem.fromJson(Map<String, dynamic> json) =>
      SearchHistoryItem(
        query: json['query'],
        searchedAt: DateTime.parse(json['searchedAt']),
      );
}
