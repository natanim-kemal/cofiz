class MoneyTransaction {
  /// Transactions older than this window are locked against edit/delete
  /// unless an admin provides a reason (override).
  static const Duration immutabilityWindow = Duration(days: 7);

  final String id;
  final String workerId;
  final String workerName;
  final String type; // 'distribution', 'return', 'purchase'
  final double amount;
  final String? notes;
  final String? receiptUrl;
  final DateTime createdAt;
  final String createdBy;
  final bool approved;

  // Specific to Coffee Purchase
  final String? coffeeType; // 'jenfel', 'yetatebe', 'special'
  final double? coffeeWeight; // in Kg
  final double? pricePerKg;
  final double? commissionAmount;

  // Transfer-specific (collector-to-collector)
  final String? fromWorkerId;
  final String? toWorkerId;
  final String? fromWorkerName;
  final String? toWorkerName;
  final String? transferId;
  final String? transferRole; // 'sender' or 'receiver'

  // Debt-related (purchase only): when amount > balance and debt toggle is on,
  // only the covered portion hits the balance; the rest is stored as a Debt doc.
  final double? forgivenAmount;
  final bool isDebt;

  MoneyTransaction({
    required this.id,
    required this.workerId,
    required this.workerName,
    required this.type,
    required this.amount,
    this.notes,
    this.receiptUrl,
    required this.createdAt,
    required this.createdBy,
    this.approved = true,
    this.coffeeType,
    this.coffeeWeight,
    this.pricePerKg,
    this.commissionAmount,
    this.fromWorkerId,
    this.toWorkerId,
    this.fromWorkerName,
    this.toWorkerName,
    this.transferId,
    this.transferRole,
    this.forgivenAmount,
    this.isDebt = false,
  });

  factory MoneyTransaction.fromFirestore(Map<String, dynamic> data, String id) {
    return MoneyTransaction(
      id: id,
      workerId: data['workerId'] ?? '',
      workerName: data['workerName'] ?? '',
      type: data['type'] ?? '',
      amount: (data['amount'] ?? 0.0).toDouble(),
      notes: data['notes'],
      receiptUrl: data['receiptUrl'],
      createdAt: data['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['createdAt'])
          : DateTime.now(),
      createdBy: data['createdBy'] ?? '',
      approved: data['approved'] ?? true,
      coffeeType: data['coffeeType'],
      coffeeWeight: (data['coffeeWeight'] ?? 0.0).toDouble() == 0.0
          ? null
          : (data['coffeeWeight'] ?? 0.0).toDouble(),
      pricePerKg: (data['pricePerKg'] ?? 0.0).toDouble() == 0.0
          ? null
          : (data['pricePerKg'] ?? 0.0).toDouble(),
      commissionAmount: (data['commissionAmount'] ?? 0.0).toDouble() == 0.0
          ? null
          : (data['commissionAmount'] ?? 0.0).toDouble(),
      fromWorkerId: data['fromWorkerId'],
      toWorkerId: data['toWorkerId'],
      fromWorkerName: data['fromWorkerName'],
      toWorkerName: data['toWorkerName'],
      transferId: data['transferId'],
      transferRole: data['transferRole'],
      forgivenAmount: (data['forgivenAmount'] ?? 0.0).toDouble() == 0.0 ? null : (data['forgivenAmount'] as num).toDouble(),
      isDebt: data['isDebt'] == true,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'workerId': workerId,
      'workerName': workerName,
      'type': type,
      'amount': amount,
      'notes': notes,
      'receiptUrl': receiptUrl,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'createdBy': createdBy,
      'approved': approved,
      'coffeeType': coffeeType,
      'coffeeWeight': coffeeWeight,
      'pricePerKg': pricePerKg,
      'commissionAmount': commissionAmount,
      'fromWorkerId': fromWorkerId,
      'toWorkerId': toWorkerId,
      'fromWorkerName': fromWorkerName,
      'toWorkerName': toWorkerName,
      'transferId': transferId,
      'transferRole': transferRole,
      if (forgivenAmount != null) 'forgivenAmount': forgivenAmount,
      'isDebt': isDebt,
    };
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      ...toFirestore(),
    };
  }

  MoneyTransaction copyWith({
    String? type,
    double? amount,
    String? notes,
    String? receiptUrl,
    bool? approved,
    String? coffeeType,
    double? coffeeWeight,
    double? pricePerKg,
    double? commissionAmount,
    double? forgivenAmount,
    bool? isDebt,
  }) {
    return MoneyTransaction(
      id: id,
      workerId: workerId,
      workerName: workerName,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      notes: notes ?? this.notes,
      receiptUrl: receiptUrl ?? this.receiptUrl,
      createdAt: createdAt,
      createdBy: createdBy,
      approved: approved ?? this.approved,
      coffeeType: coffeeType ?? this.coffeeType,
      coffeeWeight: coffeeWeight ?? this.coffeeWeight,
      pricePerKg: pricePerKg ?? this.pricePerKg,
      commissionAmount: commissionAmount ?? this.commissionAmount,
      fromWorkerId: fromWorkerId,
      toWorkerId: toWorkerId,
      fromWorkerName: fromWorkerName,
      toWorkerName: toWorkerName,
      transferId: transferId,
      transferRole: transferRole,
      forgivenAmount: forgivenAmount ?? this.forgivenAmount,
      isDebt: isDebt ?? this.isDebt,
    );
  }

  factory MoneyTransaction.fromJson(Map<String, dynamic> json) {
    return MoneyTransaction(
      id: json['id'] ?? '',
      workerId: json['workerId'] ?? '',
      workerName: json['workerName'] ?? '',
      type: json['type'] ?? '',
      amount: (json['amount'] ?? 0.0).toDouble(),
      notes: json['notes'],
      receiptUrl: json['receiptUrl'],
      createdAt: json['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['createdAt'])
          : DateTime.now(),
      createdBy: json['createdBy'] ?? '',
      approved: json['approved'] ?? true,
      coffeeType: json['coffeeType'],
      coffeeWeight: (json['coffeeWeight'] ?? 0.0).toDouble() == 0.0
          ? null
          : (json['coffeeWeight'] ?? 0.0).toDouble(),
      pricePerKg: (json['pricePerKg'] ?? 0.0).toDouble() == 0.0
          ? null
          : (json['pricePerKg'] ?? 0.0).toDouble(),
      commissionAmount: (json['commissionAmount'] ?? 0.0).toDouble() == 0.0
          ? null
          : (json['commissionAmount'] ?? 0.0).toDouble(),
      fromWorkerId: json['fromWorkerId'],
      toWorkerId: json['toWorkerId'],
      fromWorkerName: json['fromWorkerName'],
      toWorkerName: json['toWorkerName'],
      transferId: json['transferId'],
      transferRole: json['transferRole'],
      forgivenAmount: (json['forgivenAmount'] ?? 0.0).toDouble() == 0.0 ? null : (json['forgivenAmount'] as num).toDouble(),
      isDebt: json['isDebt'] == true,
    );
  }

  /// Get display type
  String get typeDisplay {
    switch (type.toLowerCase()) {
      case 'distribution':
        return 'Money Distributed';
      case 'return':
        return 'Money Returned';
      case 'purchase':
        return 'Coffee Purchase';
      default:
        return type;
    }
  }

  /// Get icon for transaction type
  String get typeIcon {
    switch (type.toLowerCase()) {
      case 'distribution':
        return '💰';
      case 'return':
        return '↩️';
      case 'purchase':
        return '☕';
      default:
        return '📝';
    }
  }

  /// Check if transaction increases balance
  bool get increasesBalance {
    return type.toLowerCase() == 'distribution';
  }

  /// Check if transaction decreases balance
  bool get decreasesBalance {
    return type.toLowerCase() == 'return' || type.toLowerCase() == 'purchase';
  }

  bool get isTransfer => type.toLowerCase() == 'transfer';
  bool get isTransferSender => isTransfer && transferRole == 'sender';
  bool get isTransferReceiver => isTransfer && transferRole == 'receiver';

  /// Whether this transaction is past the immutability window and requires
  /// an admin override reason to be edited or deleted.
  bool get isLocked =>
      DateTime.now().difference(createdAt) > immutabilityWindow;
}
