import 'package:cloud_firestore/cloud_firestore.dart';

enum DebtStatus { open, partial, paid }

class Debt {
  final String id;
  final String collectorId;
  final String collectorName;
  final String purchaseId;
  final double totalAmount;
  final double coveredAmount;
  final double forgivenAmount;
  final DebtStatus status;
  final DateTime createdAt;
  final DateTime? paidAt;
  final String? notes;
  final String createdBy;

  const Debt({
    required this.id,
    required this.collectorId,
    required this.collectorName,
    required this.purchaseId,
    required this.totalAmount,
    required this.coveredAmount,
    required this.forgivenAmount,
    required this.status,
    required this.createdAt,
    required this.createdBy,
    this.paidAt,
    this.notes,
  });

  Map<String, dynamic> toFirestore() => {
        'collectorId': collectorId,
        'collectorName': collectorName,
        'purchaseId': purchaseId,
        'totalAmount': totalAmount,
        'coveredAmount': coveredAmount,
        'forgivenAmount': forgivenAmount,
        'status': status.name,
        'createdAt': createdAt.millisecondsSinceEpoch,
        if (paidAt != null) 'paidAt': paidAt!.millisecondsSinceEpoch,
        if (notes != null) 'notes': notes,
        'createdBy': createdBy,
      };

  factory Debt.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    return Debt.fromMap(doc.data() ?? {}, id: doc.id);
  }

  factory Debt.fromMap(Map<String, dynamic> data, {String id = ''}) {
    return Debt(
      id: id.isEmpty ? (data['id'] as String? ?? '') : id,
      collectorId: data['collectorId'] as String,
      collectorName: data['collectorName'] as String? ?? '',
      purchaseId: data['purchaseId'] as String,
      totalAmount: (data['totalAmount'] as num).toDouble(),
      coveredAmount: (data['coveredAmount'] as num).toDouble(),
      forgivenAmount: (data['forgivenAmount'] as num).toDouble(),
      status: DebtStatus.values.firstWhere(
        (s) => s.name == data['status'],
        orElse: () => DebtStatus.open,
      ),
      createdAt: DateTime.fromMillisecondsSinceEpoch(data['createdAt'] as int),
      paidAt: data['paidAt'] == null ? null : DateTime.fromMillisecondsSinceEpoch(data['paidAt'] as int),
      notes: data['notes'] as String?,
      createdBy: data['createdBy'] as String? ?? '',
    );
  }

  Debt copyWith({DebtStatus? status, DateTime? paidAt, String? notes}) {
    return Debt(
      id: id,
      collectorId: collectorId,
      collectorName: collectorName,
      purchaseId: purchaseId,
      totalAmount: totalAmount,
      coveredAmount: coveredAmount,
      forgivenAmount: forgivenAmount,
      status: status ?? this.status,
      createdAt: createdAt,
      paidAt: paidAt ?? this.paidAt,
      notes: notes ?? this.notes,
      createdBy: createdBy,
    );
  }
}
