import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/debt_model.dart';

class DebtService {
  DebtService({FirebaseFirestore? firestore}) : _fs = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _fs;

  CollectionReference<Map<String, dynamic>> get _col => _fs.collection('debts');

  Future<Debt> createDebtFromPurchase({
    required String collectorId,
    required String collectorName,
    required String purchaseId,
    required double totalAmount,
    required double coveredAmount,
    required double forgivenAmount,
    required String createdBy,
    String? notes,
  }) async {
    final ref = _col.doc();
    final debt = Debt(
      id: ref.id,
      collectorId: collectorId,
      collectorName: collectorName,
      purchaseId: purchaseId,
      totalAmount: totalAmount,
      coveredAmount: coveredAmount,
      forgivenAmount: forgivenAmount,
      status: DebtStatus.open,
      createdAt: DateTime.now(),
      createdBy: createdBy,
      notes: notes,
    );
    await ref.set(debt.toFirestore());
    return debt;
  }

  Future<void> markPaid(String debtId) async {
    await _col.doc(debtId).update({
      'status': DebtStatus.paid.name,
      'paidAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Stream<List<Debt>> streamDebtsForCollector(String collectorId) {
    return _col.where('collectorId', isEqualTo: collectorId).orderBy('createdAt', descending: true).snapshots().map((s) => s.docs.map(Debt.fromFirestore).toList());
  }

  Stream<List<Debt>> streamAllOpenDebts() {
    return _col.where('status', isEqualTo: DebtStatus.open.name).orderBy('createdAt', descending: true).snapshots().map((s) => s.docs.map(Debt.fromFirestore).toList());
  }

  Future<double> getOpenDebtsTotal() async {
    final s = await _col.where('status', isEqualTo: DebtStatus.open.name).get();
    return s.docs.map((d) => (d.data()['forgivenAmount'] as num).toDouble()).fold<double>(0.0, (a, b) => a + b);
  }

  Future<double> getOpenDebtsTotalForToday() async {
    final start = DateTime.now();
    final dayStart = DateTime(start.year, start.month, start.day);
    final s = await _col
        .where('status', isEqualTo: DebtStatus.open.name)
        .where('createdAt', isGreaterThanOrEqualTo: dayStart.millisecondsSinceEpoch)
        .get();
    return s.docs.map((d) => (d.data()['forgivenAmount'] as num).toDouble()).fold<double>(0.0, (a, b) => a + b);
  }

  Future<List<Debt>> getDebtsForCollector(String collectorId) async {
    final s = await _col.where('collectorId', isEqualTo: collectorId).orderBy('createdAt', descending: true).get();
    return s.docs.map(Debt.fromFirestore).toList();
  }
}
