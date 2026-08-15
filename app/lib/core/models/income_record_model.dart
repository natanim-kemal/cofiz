enum IncomeKind {
  investment,
  sale;

  String get name => this == IncomeKind.sale ? 'sale' : 'investment';

  static IncomeKind fromName(String? name) =>
      name == 'sale' ? IncomeKind.sale : IncomeKind.investment;
}

class IncomeRecord {
  final String id;
  final IncomeKind kind;
  final double amount;
  final String? description;
  final DateTime createdAt;
  final String createdBy;
  final String createdByName;

  // investment kind
  final String? viewerId;
  final String? viewerName;

  // sale kind
  final String? saleCategory;

  const IncomeRecord({
    required this.id,
    required this.kind,
    required this.amount,
    this.description,
    required this.createdAt,
    required this.createdBy,
    required this.createdByName,
    this.viewerId,
    this.viewerName,
    this.saleCategory,
  });

  factory IncomeRecord.fromFirestore(Map<String, dynamic> data, String id) {
    return IncomeRecord(
      id: id,
      kind: IncomeKind.fromName(data['kind']),
      amount: (data['amount'] ?? 0.0).toDouble(),
      description: data['description'],
      createdAt: data['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['createdAt'])
          : DateTime.now(),
      createdBy: data['createdBy'] ?? '',
      createdByName: data['createdByName'] ?? '',
      viewerId: data['viewerId'],
      viewerName: data['viewerName'],
      saleCategory: data['saleCategory'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'kind': kind.name,
      'amount': amount,
      'description': description,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'createdBy': createdBy,
      'createdByName': createdByName,
      'viewerId': viewerId,
      'viewerName': viewerName,
      'saleCategory': saleCategory,
    };
  }

  Map<String, dynamic> toJson() {
    return {'id': id, ...toFirestore()};
  }

  factory IncomeRecord.fromJson(Map<String, dynamic> json) {
    return IncomeRecord(
      id: json['id'] ?? '',
      kind: IncomeKind.fromName(json['kind']),
      amount: (json['amount'] ?? 0.0).toDouble(),
      description: json['description'],
      createdAt: json['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['createdAt'])
          : DateTime.now(),
      createdBy: json['createdBy'] ?? '',
      createdByName: json['createdByName'] ?? '',
      viewerId: json['viewerId'],
      viewerName: json['viewerName'],
      saleCategory: json['saleCategory'],
    );
  }

  IncomeRecord copyWith({
    String? id,
    IncomeKind? kind,
    double? amount,
    String? description,
    DateTime? createdAt,
    String? createdBy,
    String? createdByName,
    String? viewerId,
    String? viewerName,
    String? saleCategory,
  }) {
    return IncomeRecord(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      amount: amount ?? this.amount,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
      viewerId: viewerId ?? this.viewerId,
      viewerName: viewerName ?? this.viewerName,
      saleCategory: saleCategory ?? this.saleCategory,
    );
  }
}
