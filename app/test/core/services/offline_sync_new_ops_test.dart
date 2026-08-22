import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:cofiz/core/services/offline_sync_service.dart';
import 'package:cofiz/core/services/offline_cache_service.dart';
import 'package:cofiz/core/models/transaction_model.dart';

void main() {
  late Directory dir;
  late FakeFirebaseFirestore fake;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('sync_new');
    await OfflineCacheService().initialize(path: dir.path);
    fake = FakeFirebaseFirestore();
    OfflineSyncService().firestore = fake;
    // seed base workers
    await fake.collection('workers').doc('w1').set({
      'currentBalance': 1000,
      'totalDistributed': 0,
      'totalReturned': 0,
      'totalCoffeePurchased': 0,
      'totalCommissionEarned': 0,
    });
    await fake.collection('workers').doc('w2').set({
      'currentBalance': 500,
      'totalDistributed': 0,
      'totalReturned': 0,
    });
  });
  tearDown(() async => await OfflineCacheService().clearAllCache());
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('queued deleteIncome syncs via transaction', () async {
    await fake.collection('income_records').doc('inc1').set(
        {'amount': 100, 'createdAt': DateTime.now().millisecondsSinceEpoch});
    await OfflineCacheService().queueOperation({
      'opId': 'inc1',
      'type': 'deleteIncome',
      'docId': 'inc1',
      'attempts': 0
    });
    await OfflineSyncService().syncPendingOperations();
    expect((await fake.collection('income_records').doc('inc1').get()).exists,
        isFalse);
    expect(OfflineCacheService().getPendingOperations(), isEmpty);
  });

  test('attempts cap moves to failed box', () async {
    await OfflineCacheService().queueOperation({
      'opId': 'bad',
      'type': 'deleteIncome',
      'docId': 'nope',
      'attempts': 5
    });
    await OfflineCacheService()
        .queueOperation({'opId': 'x', 'type': 'unknownType', 'attempts': 5});
    await OfflineSyncService().syncPendingOperations();
    expect(
        OfflineCacheService()
            .getFailedOperations()
            .any((o) => o['opId'] == 'x'),
        isTrue);
    // cleanup failed for next tests isolation
    await OfflineCacheService().clearFailed();
  });

  test('queued updateIncome syncs', () async {
    await fake.collection('income_records').doc('inc_upd').set({
      'amount': 100,
      'description': 'old',
      'createdAt': DateTime.now().millisecondsSinceEpoch
    });
    await OfflineCacheService().queueOperation({
      'opId': 'inc_upd',
      'type': 'updateIncome',
      'docId': 'inc_upd',
      'payload': {'amount': 250, 'description': 'new'},
      'attempts': 0
    });
    await OfflineSyncService().syncPendingOperations();
    final snap = await fake.collection('income_records').doc('inc_upd').get();
    expect(snap.exists, isTrue);
    expect(snap.data()!['amount'], 250);
    expect(snap.data()!['description'], 'new');
    expect(OfflineCacheService().getPendingOperations(), isEmpty);
  });

  test('queued deleteExpense syncs', () async {
    await fake.collection('expenses').doc('exp_del').set({
      'amount': 75,
      'description': 'to delete',
      'createdAt': DateTime.now().millisecondsSinceEpoch
    });
    await OfflineCacheService().queueOperation({
      'opId': 'exp_del',
      'type': 'deleteExpense',
      'docId': 'exp_del',
      'attempts': 0
    });
    await OfflineSyncService().syncPendingOperations();
    expect((await fake.collection('expenses').doc('exp_del').get()).exists,
        isFalse);
    expect(OfflineCacheService().getPendingOperations(), isEmpty);
  });

  test('queued updateTransaction with balance reversal', () async {
    // reset worker balance to known state
    await fake.collection('workers').doc('w1').set({
      'currentBalance': 1000,
      'totalDistributed': 1000,
      'totalReturned': 0,
      'totalCoffeePurchased': 0,
    });
    final now = DateTime.now();
    final txId = 'tx_upd_${now.millisecondsSinceEpoch}';
    // seed original transaction: distribution 200
    await fake.collection('transactions').doc(txId).set({
      'workerId': 'w1',
      'workerName': 'Test',
      'type': 'distribution',
      'amount': 200,
      'notes': 'orig',
      'createdAt': now.millisecondsSinceEpoch,
      'createdBy': 'tester',
      'approved': true,
    });
    // payload: same type but amount 300 (increase by 100)
    final payload = {
      'workerId': 'w1',
      'workerName': 'Test',
      'type': 'distribution',
      'amount': 300,
      'notes': 'updated',
      'receiptUrl': null,
      'createdAt': now.millisecondsSinceEpoch,
      'createdBy': 'tester',
      'approved': true,
      'coffeeType': null,
      'coffeeWeight': null,
      'pricePerKg': null,
      'commissionAmount': null,
      'fromWorkerId': null,
      'toWorkerId': null,
      'fromWorkerName': null,
      'toWorkerName': null,
      'transferId': null,
      'transferRole': null,
    };
    await OfflineCacheService().queueOperation({
      'opId': txId,
      'type': 'updateTransaction',
      'docId': txId,
      'payload': payload,
      'attempts': 0,
    });
    await OfflineSyncService().syncPendingOperations();
    final updatedSnap = await fake.collection('transactions').doc(txId).get();
    expect(updatedSnap.exists, isTrue);
    expect((updatedSnap.data()!['amount'] as num).toDouble(), 300);
    // balance: original 1000 + reversal -200 +300 = 1100
    final workerSnap = await fake.collection('workers').doc('w1').get();
    expect((workerSnap.data()!['currentBalance'] as num).toDouble(), 1100);
    expect((workerSnap.data()!['totalDistributed'] as num).toDouble(),
        1100); // 1000 -200 +300
    expect(OfflineCacheService().getPendingOperations(), isEmpty);
  });

  test('deleteTransfer 2-doc atomic via docIds', () async {
    // reset workers
    await fake.collection('workers').doc('w1').set({
      'currentBalance': 1000,
      'totalDistributed': 0,
      'totalReturned': 0,
    });
    await fake.collection('workers').doc('w2').set({
      'currentBalance': 500,
      'totalDistributed': 0,
      'totalReturned': 0,
    });
    final transferId = 'tr_${DateTime.now().millisecondsSinceEpoch}';
    final senderDocId = 'sender_$transferId';
    final receiverDocId = 'receiver_$transferId';
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    // queue createTransfer
    await OfflineCacheService().queueOperation({
      'opId': transferId,
      'type': 'createTransfer',
      'transferId': transferId,
      'senderDocId': senderDocId,
      'receiverDocId': receiverDocId,
      'fromWorkerId': 'w1',
      'fromWorkerName': 'Alice',
      'toWorkerId': 'w2',
      'toWorkerName': 'Bob',
      'amount': 200,
      'createdAt': nowMs,
      'createdBy': 'tester',
      'notes': 'transfer test',
      'attempts': 0,
    });
    await OfflineSyncService().syncPendingOperations();
    final senderSnap =
        await fake.collection('transactions').doc(senderDocId).get();
    final receiverSnap =
        await fake.collection('transactions').doc(receiverDocId).get();
    expect(senderSnap.exists, isTrue);
    expect(receiverSnap.exists, isTrue);
    // verify balances: w1 800, w2 700
    var w1 = await fake.collection('workers').doc('w1').get();
    var w2 = await fake.collection('workers').doc('w2').get();
    expect((w1.data()!['currentBalance'] as num).toDouble(), 800);
    expect((w2.data()!['currentBalance'] as num).toDouble(), 700);

    // now queue deleteTransfer using explicit docIds (tests the docId path)
    await OfflineCacheService().queueOperation({
      'opId': transferId,
      'type': 'deleteTransfer',
      'transferId': transferId,
      'senderDocId': senderDocId,
      'receiverDocId': receiverDocId,
      'attempts': 0,
    });
    await OfflineSyncService().syncPendingOperations();
    expect(
        (await fake.collection('transactions').doc(senderDocId).get()).exists,
        isFalse);
    expect(
        (await fake.collection('transactions').doc(receiverDocId).get()).exists,
        isFalse);
    // balances reverted: w1 1000, w2 500
    w1 = await fake.collection('workers').doc('w1').get();
    w2 = await fake.collection('workers').doc('w2').get();
    expect((w1.data()!['currentBalance'] as num).toDouble(), 1000);
    expect((w2.data()!['currentBalance'] as num).toDouble(), 500);
    expect(OfflineCacheService().getPendingOperations(), isEmpty);
  });

  test('queued auditLog adds to audit_logs', () async {
    final payload = {
      'action': 'test_audit',
      'user': 'tester',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'details': 'audit test'
    };
    await OfflineCacheService().queueOperation({
      'opId': 'audit1',
      'type': 'auditLog',
      'payload': payload,
      'attempts': 0
    });
    await OfflineSyncService().syncPendingOperations();
    final snap = await fake.collection('audit_logs').get();
    final found = snap.docs.any((d) => d.data()['action'] == 'test_audit');
    expect(found, isTrue);
    expect(OfflineCacheService().getPendingOperations(), isEmpty);
  });

  test(
      'receipt defer: createTransaction with missing localReceiptPath no crash',
      () async {
    await fake.collection('workers').doc('w1').set({
      'currentBalance': 2000,
      'totalDistributed': 0,
      'totalReturned': 0,
      'totalCoffeePurchased': 0,
    });
    final docId = 'tx_receipt_${DateTime.now().millisecondsSinceEpoch}';
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await OfflineCacheService().queueOperation({
      'opId': docId,
      'type': 'createTransaction',
      'docId': docId,
      'workerId': 'w1',
      'workerName': 'Test',
      'transactionType': 'distribution',
      'amount': 50,
      'notes': 'receipt test',
      'receiptUrl': null,
      'localReceiptPath': '/tmp/nonexistent_receipt_${nowMs}.jpg',
      'createdAt': nowMs,
      'createdBy': 'tester',
      'attempts': 0,
    });
    // should not throw even though file missing
    await OfflineSyncService().syncPendingOperations();
    final snap = await fake.collection('transactions').doc(docId).get();
    expect(snap.exists, isTrue);
    expect((snap.data()!['amount'] as num).toDouble(), 50);
    expect(OfflineCacheService().getPendingOperations(), isEmpty);
  });
}
