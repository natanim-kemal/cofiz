import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cofiz/core/models/transaction_model.dart';
import 'package:cofiz/core/services/connectivity_service.dart';
import 'package:cofiz/core/services/offline_cache_service.dart';
import 'package:cofiz/core/services/offline_sync_service.dart';
import 'package:cofiz/core/services/transaction_service.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('tx_service_test');
    await OfflineCacheService().initialize(path: tempDir.path);
  });

  setUp(() {
    ConnectivityService().setOnlineForTest(false);
  });

  tearDown(() async {
    await OfflineCacheService().clearPendingOperations();
    ConnectivityService().setOnlineForTest(true);
  });

  tearDownAll(() async {
    await OfflineCacheService().clearAllCache();
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('approveTransaction queues op when offline', () async {
    final service = TransactionService(firestore: FakeFirebaseFirestore());
    await service.approveTransaction('t1');

    final ops = OfflineCacheService().getPendingOperations();
    expect(ops.length, 1);
    expect(ops.first['type'], 'approveTransaction');
    expect(ops.first['transactionId'], 't1');
  });

  test('approveTransfer queues op when offline', () async {
    final service = TransactionService(firestore: FakeFirebaseFirestore());
    await service.approveTransfer('tr-1');

    final ops = OfflineCacheService().getPendingOperations();
    expect(ops.length, 1);
    expect(ops.first['type'], 'approveTransfer');
    expect(ops.first['transferId'], 'tr-1');
  });

  test('approveAllForWorker queues op when offline', () async {
    final service = TransactionService(firestore: FakeFirebaseFirestore());
    await service.approveAllForWorker('w1');

    final ops = OfflineCacheService().getPendingOperations();
    expect(ops.length, 1);
    expect(ops.first['type'], 'approveAll');
    expect(ops.first['workerId'], 'w1');
  });

  test(
      'addTransaction queues and appears in cache, does not directly write while offline',
      () async {
    final fake = FakeFirebaseFirestore();
    final service = TransactionService(firestore: fake);
    // ensure offline cache initialized in setUpAll already
    ConnectivityService().setOnlineForTest(false);
    await service.addTransaction(MoneyTransaction(
      id: '',
      workerId: 'w1',
      workerName: 'W1',
      type: 'distribution',
      amount: 50,
      createdAt: DateTime.now(),
      createdBy: 'tester',
    ));
    expect(
        OfflineCacheService()
            .getPendingOperations()
            .any((o) => o['type'] == 'createTransaction'),
        true);
    expect(
        OfflineCacheService()
            .getCachedTransactions()
            ?.any((t) => t.amount == 50),
        true);
    expect((await fake.collection('transactions').get()).docs.length, 0);
  });

  test(
      'addTransfer queues single op and appears in cache, drain creates two docs atomically',
      () async {
    final fake = FakeFirebaseFirestore();
    await fake.collection('workers').doc('w1').set({'currentBalance': 500});
    await fake.collection('workers').doc('w2').set({'currentBalance': 0});
    final service = TransactionService(firestore: fake);
    OfflineSyncService().firestore = fake;
    ConnectivityService().setOnlineForTest(false);
    final tid = await service.addTransfer(
        fromWorkerId: 'w1',
        fromWorkerName: 'A',
        toWorkerId: 'w2',
        toWorkerName: 'B',
        amount: 100,
        createdBy: 'tester');
    expect(tid, isNotNull);
    expect(
        OfflineCacheService()
            .getPendingOperations()
            .where((o) => o['type'] == 'createTransfer')
            .length,
        1);
    ConnectivityService().setOnlineForTest(true);
    await OfflineSyncService().syncPendingOperations();
    expect(
        (await fake
                .collection('transactions')
                .where('transferId', isEqualTo: tid)
                .get())
            .docs
            .length,
        2);
    expect(
        (await fake.collection('workers').doc('w1').get())
            .data()!['currentBalance'],
        400);
    expect(
        (await fake.collection('workers').doc('w1').get())
            .data()!['totalReturned'],
        100);
    expect(
        (await fake.collection('workers').doc('w2').get())
            .data()!['currentBalance'],
        100);
    expect(
        (await fake.collection('workers').doc('w2').get())
            .data()!['totalDistributed'],
        100);
  });

  MoneyTransaction oldTransaction({
    required String id,
    required String workerId,
    required String type,
    required double amount,
    DateTime? createdAt,
  }) {
    return MoneyTransaction(
      id: id,
      workerId: workerId,
      workerName: 'W',
      type: type,
      amount: amount,
      createdAt: createdAt ?? DateTime.now().subtract(const Duration(days: 10)),
      createdBy: 'tester',
    );
  }

  Future<FakeFirebaseFirestore> seededFirestore() async {
    final fake = FakeFirebaseFirestore();
    await fake.collection('workers').doc('w1').set({'currentBalance': 500});
    await fake.collection('transactions').doc('t1').set(
          oldTransaction(
            id: 't1',
            workerId: 'w1',
            type: 'distribution',
            amount: 100,
          ).toFirestore(),
        );
    await fake.collection('transactions').doc('t2').set(
          oldTransaction(
            id: 't2',
            workerId: 'w1',
            type: 'distribution',
            amount: 50,
            createdAt: DateTime.now(),
          ).toFirestore(),
        );
    return fake;
  }

  test('deleteTransaction throws when locked and no reason given', () async {
    final fake = await seededFirestore();
    final service = TransactionService(firestore: fake);
    ConnectivityService().setOnlineForTest(true);
    await expectLater(
      service.deleteTransaction('t1'),
      throwsA(isA<TransactionLockedException>()),
    );
  });

  test('deleteTransaction succeeds with reason for locked transaction',
      () async {
    final fake = await seededFirestore();
    final service = TransactionService(firestore: fake);
    ConnectivityService().setOnlineForTest(true);
    await service.deleteTransaction('t1', overrideReason: 'Admin correction');
    final remaining = await fake.collection('transactions').doc('t1').get();
    expect(remaining.exists, false);
  });

  test('deleteTransaction succeeds for fresh transaction without reason',
      () async {
    final fake = await seededFirestore();
    final service = TransactionService(firestore: fake);
    ConnectivityService().setOnlineForTest(true);
    await service.deleteTransaction('t2');
    final remaining = await fake.collection('transactions').doc('t2').get();
    expect(remaining.exists, false);
  });

  test('updateTransaction throws when locked and no reason given', () async {
    final fake = await seededFirestore();
    final service = TransactionService(firestore: fake);
    ConnectivityService().setOnlineForTest(true);
    await expectLater(
      service.updateTransaction(
        oldTransaction(
          id: 't1',
          workerId: 'w1',
          type: 'distribution',
          amount: 200,
        ),
      ),
      throwsA(isA<TransactionLockedException>()),
    );
  });

  test('updateTransaction succeeds with reason for locked transaction',
      () async {
    final fake = await seededFirestore();
    final service = TransactionService(firestore: fake);
    ConnectivityService().setOnlineForTest(true);
    await service.updateTransaction(
      oldTransaction(
        id: 't1',
        workerId: 'w1',
        type: 'distribution',
        amount: 200,
      ),
      overrideReason: 'Fix amount',
    );
    final updated = await fake.collection('transactions').doc('t1').get();
    expect(updated.data()!['amount'], 200);
  });

  test('getWorkerTransactionsForDay returns only that day for the worker',
      () async {
    final fake = FakeFirebaseFirestore();
    final day = DateTime(2026, 1, 8);
    final nextDay = day.add(const Duration(days: 1));
    for (var i = 0; i < 3; i++) {
      await fake.collection('transactions').doc('day-$i').set({
        'workerId': 'w1',
        'workerName': 'W',
        'type': 'distribution',
        'amount': 10.0 + i,
        'createdAt':
            day.millisecondsSinceEpoch + Duration(hours: 1 + i).inMilliseconds,
        'createdBy': 'tester',
        'approved': true,
      });
    }
    await fake.collection('transactions').doc('other-worker').set({
      'workerId': 'w2',
      'workerName': 'Other',
      'type': 'distribution',
      'amount': 99.0,
      'createdAt': day.millisecondsSinceEpoch,
      'createdBy': 'tester',
      'approved': true,
    });
    await fake.collection('transactions').doc('next-day').set({
      'workerId': 'w1',
      'workerName': 'W',
      'type': 'distribution',
      'amount': 5.0,
      'createdAt': nextDay.millisecondsSinceEpoch,
      'createdBy': 'tester',
      'approved': true,
    });
    final service = TransactionService(firestore: fake);
    final items = await service.getWorkerTransactionsForDay('w1', day);
    expect(items.length, 3);
    expect(items.map((t) => t.id).toSet(), {'day-0', 'day-1', 'day-2'});
    expect(items.first.createdAt.isAfter(items.last.createdAt), true);
  });

  test('deleteTransfer throws when locked and no reason given', () async {
    final fake = FakeFirebaseFirestore();
    await fake.collection('workers').doc('w1').set({'currentBalance': 500});
    await fake.collection('workers').doc('w2').set({'currentBalance': 0});
    await fake.collection('transactions').doc('tr1-a').set(
          oldTransaction(
            id: 'tr1-a',
            workerId: 'w1',
            type: 'transfer',
            amount: 100,
          ).toFirestore()
            ..['transferId'] = 'tr1'
            ..['transferRole'] = 'sender',
        );
    await fake.collection('transactions').doc('tr1-b').set(
          oldTransaction(
            id: 'tr1-b',
            workerId: 'w2',
            type: 'transfer',
            amount: 100,
          ).toFirestore()
            ..['transferId'] = 'tr1'
            ..['transferRole'] = 'receiver',
        );
    final service = TransactionService(firestore: fake);
    ConnectivityService().setOnlineForTest(true);
    await expectLater(
      service.deleteTransfer('tr1'),
      throwsA(isA<TransactionLockedException>()),
    );
  });

  test('deleteTransfer succeeds with reason for locked transfer', () async {
    final fake = FakeFirebaseFirestore();
    await fake.collection('workers').doc('w1').set({'currentBalance': 500});
    await fake.collection('workers').doc('w2').set({'currentBalance': 0});
    await fake.collection('transactions').doc('tr1-a').set(
          oldTransaction(
            id: 'tr1-a',
            workerId: 'w1',
            type: 'transfer',
            amount: 100,
          ).toFirestore()
            ..['transferId'] = 'tr1'
            ..['transferRole'] = 'sender',
        );
    await fake.collection('transactions').doc('tr1-b').set(
          oldTransaction(
            id: 'tr1-b',
            workerId: 'w2',
            type: 'transfer',
            amount: 100,
          ).toFirestore()
            ..['transferId'] = 'tr1'
            ..['transferRole'] = 'receiver',
        );
    final service = TransactionService(firestore: fake);
    ConnectivityService().setOnlineForTest(true);
    await service.deleteTransfer('tr1', overrideReason: 'Admin correction');
    final remaining = await fake
        .collection('transactions')
        .where('transferId', isEqualTo: 'tr1')
        .get();
    expect(remaining.docs.length, 0);
  });
}
