import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cofiz/core/services/debt_service.dart';

void main() {
  late FakeFirebaseFirestore fs;
  late DebtService svc;

  setUp(() {
    fs = FakeFirebaseFirestore();
    svc = DebtService(firestore: fs);
  });

  test('createDebtFromPurchase writes a doc and returns it', () async {
    final d = await svc.createDebtFromPurchase(
      collectorId: 'c1',
      collectorName: 'Alice',
      purchaseId: 'p1',
      totalAmount: 1000,
      coveredAmount: 400,
      forgivenAmount: 600,
      createdBy: 'u1',
    );
    expect(d.forgivenAmount, 600);
    final snap = await fs.collection('debts').get();
    expect(snap.docs.length, 1);
  });

  test('markPaid flips status and paidAt', () async {
    final d = await svc.createDebtFromPurchase(
      collectorId: 'c1',
      collectorName: 'A',
      purchaseId: 'p1',
      totalAmount: 100,
      coveredAmount: 50,
      forgivenAmount: 50,
      createdBy: 'u1',
    );
    await svc.markPaid(d.id);
    final snap = await fs.collection('debts').doc(d.id).get();
    expect(snap.data()!['status'], 'paid');
    expect(snap.data()!['paidAt'], isNotNull);
  });

  test('getOpenDebtsTotal sums forgivenAmount where status=open', () async {
    await svc.createDebtFromPurchase(collectorId: 'c1', collectorName: 'A', purchaseId: 'p1', totalAmount: 100, coveredAmount: 50, forgivenAmount: 50, createdBy: 'u1');
    await svc.createDebtFromPurchase(collectorId: 'c2', collectorName: 'B', purchaseId: 'p2', totalAmount: 200, coveredAmount: 100, forgivenAmount: 100, createdBy: 'u1');
    expect(await svc.getOpenDebtsTotal(), 150);
  });
}
