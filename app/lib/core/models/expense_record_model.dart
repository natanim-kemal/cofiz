class ExpenseRecord {
  final String id;
  final double amount;
  final String expenseCategory;
  final String? description;
  final DateTime createdAt;
  final String createdBy;
  final String createdByName;

  const ExpenseRecord({
    required this.id,
    required this.amount,
    required this.expenseCategory,
    this.description,
    required this.createdAt,
    required this.createdBy,
    required this.createdByName,
  });

  factory ExpenseRecord.fromFirestore(Map<String, dynamic> data, String id) {
    return ExpenseRecord(
      id: id,
      amount: (data['amount'] ?? 0.0).toDouble(),
      expenseCategory: data['expenseCategory'] ?? 'Other',
      description: data['description'],
      createdAt: data['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['createdAt'])
          : DateTime.now(),
      createdBy: data['createdBy'] ?? '',
      createdByName: data['createdByName'] ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'amount': amount,
      'expenseCategory': expenseCategory,
      'description': description,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'createdBy': createdBy,
      'createdByName': createdByName,
    };
  }

  Map<String, dynamic> toJson() {
    return {'id': id, ...toFirestore()};
  }

  factory ExpenseRecord.fromJson(Map<String, dynamic> json) {
    return ExpenseRecord(
      id: json['id'] ?? '',
      amount: (json['amount'] ?? 0.0).toDouble(),
      expenseCategory: json['expenseCategory'] ?? 'Other',
      description: json['description'],
      createdAt: json['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['createdAt'])
          : DateTime.now(),
      createdBy: json['createdBy'] ?? '',
      createdByName: json['createdByName'] ?? '',
    );
  }

  ExpenseRecord copyWith({
    String? id,
    double? amount,
    String? expenseCategory,
    String? description,
    DateTime? createdAt,
    String? createdBy,
    String? createdByName,
  }) {
    return ExpenseRecord(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      expenseCategory: expenseCategory ?? this.expenseCategory,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
    );
  }
}
