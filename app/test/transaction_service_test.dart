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
}
