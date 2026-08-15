class Worker {
  final String id;
  final String name;
  final String phone;
  final String? email;
  final String role;
  final int yearsOfExperience;
  final String status; // 'active', 'busy', 'offline'
  final double performanceRating; // 0-100
  final String? photoUrl;
  final double currentBalance;
  final double totalDistributed;
  final double totalReturned; // lifetime total
  final double totalCoffeePurchased; // lifetime total
  final double totalCommissionEarned; //
  final DateTime createdAt;
  final DateTime? lastActiveAt;
  final bool isActive;
  final String? userId; // Link to User account (null if no login)
  final bool hasLoginAccess; // Can this worker login?
  final double commissionRate; // Amount given per kg of coffee purchased

  Worker({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    required this.role,
    this.yearsOfExperience = 0,
    this.status = 'active',
    this.performanceRating = 0.0,
    this.photoUrl,
    this.currentBalance = 0.0,
    this.totalDistributed = 0.0,
    this.totalReturned = 0.0,
    this.totalCoffeePurchased = 0.0,
    this.totalCommissionEarned = 0.0,
    required this.createdAt,
    this.lastActiveAt,
    this.isActive = true,
    this.userId,
    this.hasLoginAccess = false,
    this.commissionRate = 0.0,
  });

  /// Create Worker from Firestore document
  factory Worker.fromFirestore(Map<String, dynamic> data, String id) {
    return Worker(
      id: id,
      name: data['name'] ?? '',
      phone: data['phone'] ?? '',
      email: data['email'],
      role: data['role'] ?? 'Worker',
      yearsOfExperience: data['yearsOfExperience'] ?? 0,
      status: data['status'] ?? 'active',
      performanceRating: (data['performanceRating'] ?? 0.0).toDouble(),
      photoUrl: data['photoUrl'],
      currentBalance: (data['currentBalance'] ?? 0.0).toDouble(),
      totalDistributed: (data['totalDistributed'] ?? 0.0).toDouble(),
      totalReturned: (data['totalReturned'] ?? 0.0).toDouble(),
      totalCoffeePurchased: (data['totalCoffeePurchased'] ?? 0.0).toDouble(),
      totalCommissionEarned: (data['totalCommissionEarned'] ?? 0.0).toDouble(),
      createdAt: data['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['createdAt'])
          : DateTime.now(),
      lastActiveAt: data['lastActiveAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['lastActiveAt'])
          : null,
      isActive: data['isActive'] ?? true,
      userId: data['userId'],
      hasLoginAccess: data['hasLoginAccess'] ?? false,
      commissionRate: (data['commissionRate'] ?? 0.0).toDouble(),
    );
  }

  /// Convert Worker to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'phone': phone,
      'email': email,
      'role': role,
      'yearsOfExperience': yearsOfExperience,
      'status': status,
      'performanceRating': performanceRating,
      'photoUrl': photoUrl,
      'currentBalance': currentBalance,
      'totalDistributed': totalDistributed,
      'totalReturned': totalReturned,
      'totalCoffeePurchased': totalCoffeePurchased,
      'totalCommissionEarned': totalCommissionEarned,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'lastActiveAt': lastActiveAt?.millisecondsSinceEpoch,
      'isActive': isActive,
      'userId': userId,
      'hasLoginAccess': hasLoginAccess,
      'commissionRate': commissionRate,
    };
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      ...toFirestore(),
    };
  }

  /// Create Worker from JSON
  factory Worker.fromJson(Map<String, dynamic> json) {
    return Worker(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      phone: json['phone'] ?? '',
      email: json['email'],
      role: json['role'] ?? 'Worker',
      yearsOfExperience: json['yearsOfExperience'] ?? 0,
      status: json['status'] ?? 'active',
      performanceRating: (json['performanceRating'] ?? 0.0).toDouble(),
      photoUrl: json['photoUrl'],
      currentBalance: (json['currentBalance'] ?? 0.0).toDouble(),
      totalDistributed: (json['totalDistributed'] ?? 0.0).toDouble(),
      totalReturned: (json['totalReturned'] ?? 0.0).toDouble(),
      totalCoffeePurchased: (json['totalCoffeePurchased'] ?? 0.0).toDouble(),
      totalCommissionEarned: (json['totalCommissionEarned'] ?? 0.0).toDouble(),
      createdAt: json['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['createdAt'])
          : DateTime.now(),
      lastActiveAt: json['lastActiveAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['lastActiveAt'])
          : null,
      isActive: json['isActive'] ?? true,
      userId: json['userId'],
      hasLoginAccess: json['hasLoginAccess'] ?? false,
      commissionRate: (json['commissionRate'] ?? 0.0).toDouble(),
    );
  }

  /// Create a copy of Worker with updated fields
  Worker copyWith({
    String? id,
    String? name,
    String? phone,
    String? email,
    String? role,
    int? yearsOfExperience,
    String? status,
    double? performanceRating,
    String? photoUrl,
    double? currentBalance,
    double? totalDistributed,
    double? totalReturned,
    double? totalCoffeePurchased,
    double? totalCommissionEarned,
    DateTime? createdAt,
    DateTime? lastActiveAt,
    bool? isActive,
    String? userId,
    bool? hasLoginAccess,
    double? commissionRate,
  }) {
    return Worker(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      role: role ?? this.role,
      yearsOfExperience: yearsOfExperience ?? this.yearsOfExperience,
      status: status ?? this.status,
      performanceRating: performanceRating ?? this.performanceRating,
      photoUrl: photoUrl ?? this.photoUrl,
      currentBalance: currentBalance ?? this.currentBalance,
      totalDistributed: totalDistributed ?? this.totalDistributed,
      totalReturned: totalReturned ?? this.totalReturned,
      totalCoffeePurchased: totalCoffeePurchased ?? this.totalCoffeePurchased,
      totalCommissionEarned:
          totalCommissionEarned ?? this.totalCommissionEarned,
      createdAt: createdAt ?? this.createdAt,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      isActive: isActive ?? this.isActive,
      userId: userId ?? this.userId,
      hasLoginAccess: hasLoginAccess ?? this.hasLoginAccess,
      commissionRate: commissionRate ?? this.commissionRate,
    );
  }

  /// Get display status text
  String get statusDisplay {
    switch (status.toLowerCase()) {
      case 'active':
        return 'Active';
      case 'busy':
        return 'Busy';
      case 'offline':
        return 'Offline';
      default:
        return status;
    }
  }

  /// Get display role text
  String get roleDisplay => role.toLowerCase() == 'worker' ? 'Collector' : role;

  /// Get rating as percentage (0-100)
  int get ratingPercentage => performanceRating.round();

  /// Get rating as stars (0-5)
  double get ratingStars => (performanceRating / 20.0);
}
