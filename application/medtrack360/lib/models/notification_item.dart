enum NotificationType { priceChange, outOfStock, news, other }

NotificationType _typeFromString(String? raw) {
  switch (raw) {
    case 'price_change':
      return NotificationType.priceChange;
    case 'out_of_stock':
      return NotificationType.outOfStock;
    case 'news':
      return NotificationType.news;
    default:
      return NotificationType.other;
  }
}

class NotificationItem {
  final String id;
  final NotificationType type;
  final String title;
  final String body;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.payload,
    required this.createdAt,
    this.readAt,
  });

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: json['notification_id'] as String,
      type: _typeFromString(json['type'] as String?),
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      payload: (json['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      readAt: json['read_at'] != null
          ? DateTime.parse(json['read_at'] as String).toLocal()
          : null,
    );
  }

  NotificationItem copyWith({DateTime? readAt}) => NotificationItem(
    id: id,
    type: type,
    title: title,
    body: body,
    payload: payload,
    createdAt: createdAt,
    readAt: readAt ?? this.readAt,
  );
}
