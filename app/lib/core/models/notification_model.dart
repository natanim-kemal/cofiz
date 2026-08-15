enum NotificationType {
  ping,
  info,
  alert,
  dailyReportRequest,
  // New types for automatic notifications
  lowBalance, // Worker balance below threshold
  moneyDistributed, // Worker received money from admin
  purchaseRecorded, // Admin notified of worker purchase
  commissionEarned; // Worker earned commission

  String get displayName {
    switch (this) {
      case NotificationType.ping:
        return 'Message';
      case NotificationType.info:
        return 'Info';
      case NotificationType.alert:
        return 'Alert';
      case NotificationType.dailyReportRequest:
        return 'Report Request';
      case NotificationType.lowBalance:
        return 'Low Balance';
      case NotificationType.moneyDistributed:
        return 'Money Received';
      case NotificationType.purchaseRecorded:
        return 'Purchase Recorded';
      case NotificationType.commissionEarned:
        return 'Commission Earned';
    }
  }
}

class AppNotification {
  final String id;
  final String targetUserId;
  final String title;
  final String body;
  final NotificationType type;
  final bool isRead;
  final DateTime createdAt;
  final String? senderName;
  final String? senderId;
  final Map<String, dynamic>? metadata;

  AppNotification({
    required this.id,
    required this.targetUserId,
    required this.title,
    required this.body,
    this.type = NotificationType.info,
    this.isRead = false,
    required this.createdAt,
    this.senderName,
    this.senderId,
    this.metadata,
  });

  factory AppNotification.fromFirestore(Map<String, dynamic> data, String id) {
    return AppNotification(
      id: id,
      targetUserId: data['targetUserId'] ?? '',
      title: data['title'] ?? '',
      body: data['body'] ?? '',
      type: NotificationType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => NotificationType.info,
      ),
      isRead: data['isRead'] ?? false,
      createdAt: data['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['createdAt'])
          : DateTime.now(),
      senderName: data['senderName'],
      senderId: data['senderId'],
      metadata: data['metadata'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'targetUserId': targetUserId,
      'title': title,
      'body': body,
      'type': type.name,
      'isRead': isRead,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'senderName': senderName,
      'senderId': senderId,
      'metadata': metadata,
    };
  }

  AppNotification copyWith({
    String? id,
    String? targetUserId,
    String? title,
    String? body,
    NotificationType? type,
    bool? isRead,
    DateTime? createdAt,
    String? senderName,
    String? senderId,
    Map<String, dynamic>? metadata,
  }) {
    return AppNotification(
      id: id ?? this.id,
      targetUserId: targetUserId ?? this.targetUserId,
      title: title ?? this.title,
      body: body ?? this.body,
      type: type ?? this.type,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
      senderName: senderName ?? this.senderName,
      senderId: senderId ?? this.senderId,
      metadata: metadata ?? this.metadata,
    );
  }
}
