enum AuditAction {
  userCreated,
  userUpdated,
  userDeleted,
  userRoleChanged,
  workerCreated,
  workerUpdated,
  workerDeleted,
  transactionCreated,
  transactionDeleted,
  incomeRecorded,
  expenseRecorded,
  settingsChanged,
  dataExported,
  dataImported,
  login,
  logout;

  String get displayName {
    switch (this) {
      case AuditAction.userCreated:
        return 'User Created';
      case AuditAction.userUpdated:
        return 'User Updated';
      case AuditAction.userDeleted:
        return 'User Deleted';
      case AuditAction.userRoleChanged:
        return 'User Role Changed';
      case AuditAction.workerCreated:
        return 'Collector Created';
      case AuditAction.workerUpdated:
        return 'Collector Updated';
      case AuditAction.workerDeleted:
        return 'Collector Deleted';
      case AuditAction.transactionCreated:
        return 'Transaction Created';
      case AuditAction.transactionDeleted:
        return 'Transaction Deleted';
      case AuditAction.incomeRecorded:
        return 'Income Recorded';
      case AuditAction.expenseRecorded:
        return 'Expense Recorded';
      case AuditAction.settingsChanged:
        return 'Settings Changed';
      case AuditAction.dataExported:
        return 'Data Exported';
      case AuditAction.dataImported:
        return 'Data Imported';
      case AuditAction.login:
        return 'User Login';
      case AuditAction.logout:
        return 'User Logout';
    }
  }
}

class AuditLog {
  final String id;
  final String userId;
  final String userName;
  final AuditAction action;
  final String? targetId; // ID of affected resource (worker, user, etc.)
  final String? targetName; // Name of affected resource
  final Map<String, dynamic>? metadata; // Additional context
  final DateTime timestamp;
  final String? ipAddress;
  final String? deviceInfo;

  AuditLog({
    required this.id,
    required this.userId,
    required this.userName,
    required this.action,
    this.targetId,
    this.targetName,
    this.metadata,
    required this.timestamp,
    this.ipAddress,
    this.deviceInfo,
  });

  /// Create from Firestore
  factory AuditLog.fromFirestore(Map<String, dynamic> data, String id) {
    return AuditLog(
      id: id,
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? '',
      action: AuditAction.values.firstWhere(
        (a) => a.name == data['action'],
        orElse: () => AuditAction.login,
      ),
      targetId: data['targetId'],
      targetName: data['targetName'],
      metadata: data['metadata'] != null
          ? Map<String, dynamic>.from(data['metadata'])
          : null,
      timestamp: data['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['timestamp'])
          : DateTime.now(),
      ipAddress: data['ipAddress'],
      deviceInfo: data['deviceInfo'],
    );
  }

  /// Convert to Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'userName': userName,
      'action': action.name,
      'targetId': targetId,
      'targetName': targetName,
      'metadata': metadata,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'ipAddress': ipAddress,
      'deviceInfo': deviceInfo,
    };
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      ...toFirestore(),
    };
  }

  /// Create from JSON
  factory AuditLog.fromJson(Map<String, dynamic> json) {
    return AuditLog(
      id: json['id'] ?? '',
      userId: json['userId'] ?? '',
      userName: json['userName'] ?? '',
      action: AuditAction.values.firstWhere(
        (a) => a.name == json['action'],
        orElse: () => AuditAction.login,
      ),
      targetId: json['targetId'],
      targetName: json['targetName'],
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'])
          : null,
      timestamp: json['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['timestamp'])
          : DateTime.now(),
      ipAddress: json['ipAddress'],
      deviceInfo: json['deviceInfo'],
    );
  }

  /// Format for display
  String get formattedMessage {
    final base = '$userName ${action.displayName}';
    if (targetName != null) {
      return '$base: $targetName';
    }
    return base;
  }
}
