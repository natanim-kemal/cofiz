enum UserRole {
  admin,
  worker,
  viewer;

  String get displayName {
    switch (this) {
      case UserRole.admin:
        return 'Admin';
      case UserRole.worker:
        return 'Collector';
      case UserRole.viewer:
        return 'Viewer';
    }
  }

  String get description {
    switch (this) {
      case UserRole.admin:
        return 'Full access - Can manage users, collectors, settings, and all data';
      case UserRole.worker:
        return 'Can view own dashboard, record transactions, and view history';
      case UserRole.viewer:
        return 'Read-only access to reports and data';
    }
  }

  // Permissions
  bool get canManageUsers => this == UserRole.admin;
  bool get canManageSettings => this == UserRole.admin;
  bool get canManageWorkers => this == UserRole.admin;
  bool get canCreateTransactions =>
      this == UserRole.admin || this == UserRole.worker;
  bool get canDeleteWorkers => this == UserRole.admin;
  bool get canEditWorkers => this == UserRole.admin;
  bool get canViewReports => true; // All roles can view
  bool get canExportData => this == UserRole.admin;
  bool get isWorker => this == UserRole.worker;
}

class AppUser {
  final String uid;
  final String email;
  final String displayName;
  final UserRole role;
  final String? photoUrl;
  final DateTime createdAt;
  final DateTime? lastLoginAt;
  final bool isActive;
  final bool emailVerified;
  final String? createdBy; // Admin who created this user
  final String? workerId; // Link to Worker profile (for Manager role)

  AppUser({
    required this.uid,
    required this.email,
    required this.displayName,
    this.role = UserRole.viewer,
    this.photoUrl,
    required this.createdAt,
    this.lastLoginAt,
    this.isActive = true,
    this.emailVerified = false,
    this.createdBy,
    this.workerId,
  });

  /// Create from Firestore
  factory AppUser.fromFirestore(Map<String, dynamic> data, String uid) {
    final roleString = (data['role'] as String?)?.toLowerCase() ?? 'viewer';
    final parsedRole = UserRole.values.firstWhere(
      (r) => r.name.toLowerCase() == roleString,
      orElse: () => UserRole.viewer,
    );

    return AppUser(
      uid: uid,
      email: data['email'] ?? '',
      displayName: data['displayName'] ?? '',
      role: UserRole.values.firstWhere(
        (r) => r.name == data['role'],
        orElse: () {
          if (data['workerId'] != null) return UserRole.worker;
          throw Exception('Invalid user role: ${data['role']}');
        },
      ),
      photoUrl: data['photoUrl'],
      createdAt: data['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['createdAt'])
          : DateTime.now(),
      lastLoginAt: data['lastLoginAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['lastLoginAt'])
          : null,
      isActive: data['isActive'] ?? true,
      emailVerified: data['emailVerified'] ?? false,
      createdBy: data['createdBy'],
      workerId: data['workerId'],
    );
  }

  /// Convert to Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'email': email,
      'displayName': displayName,
      'role': role.name,
      'photoUrl': photoUrl,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'lastLoginAt': lastLoginAt?.millisecondsSinceEpoch,
      'isActive': isActive,
      'emailVerified': emailVerified,
      'createdBy': createdBy,
      'workerId': workerId,
    };
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      ...toFirestore(),
    };
  }

  /// Create from JSON
  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      uid: json['uid'] ?? '',
      email: json['email'] ?? '',
      displayName: json['displayName'] ?? '',
      role: UserRole.values.firstWhere(
        (r) => r.name == json['role'],
        orElse: () => UserRole.viewer,
      ),
      photoUrl: json['photoUrl'],
      createdAt: json['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['createdAt'])
          : DateTime.now(),
      lastLoginAt: json['lastLoginAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['lastLoginAt'])
          : null,
      isActive: json['isActive'] ?? true,
      emailVerified: json['emailVerified'] ?? false,
      createdBy: json['createdBy'],
      workerId: json['workerId'],
    );
  }

  AppUser copyWith({
    String? uid,
    String? email,
    String? displayName,
    UserRole? role,
    String? photoUrl,
    DateTime? createdAt,
    DateTime? lastLoginAt,
    bool? isActive,
    bool? emailVerified,
    String? createdBy,
    String? workerId,
  }) {
    return AppUser(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      photoUrl: photoUrl ?? this.photoUrl,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      isActive: isActive ?? this.isActive,
      emailVerified: emailVerified ?? this.emailVerified,
      createdBy: createdBy ?? this.createdBy,
      workerId: workerId ?? this.workerId,
    );
  }
}
