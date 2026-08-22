import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:cofiz/core/models/transaction_model.dart';
import 'package:cofiz/core/models/worker_model.dart';
import 'package:cofiz/core/services/connectivity_service.dart';
import 'package:cofiz/core/services/offline_cache_service.dart';
import 'package:cofiz/core/services/offline_sync_service.dart';
import 'package:cofiz/core/services/transaction_service.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('transaction_offline_mutation');
    await OfflineCacheService().initialize(path: dir.path);
  });

  setUp(() async {
    await OfflineCacheService().clearAllCache();
    ConnectivityService().setOnlineForTest(false);
  });

  tearDown(() async {
    await OfflineCacheService().clearAllCache();
    ConnectivityService().setOnlineForTest(true);
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('deleteTransaction offline queues and removes from cache', () async {
    final fake = FakeFirebaseFirestore();
    OfflineSyncService().firestore = fake;
    final svc = TransactionService(firestore: fake);
    final now = DateTime.now();
    await OfflineCacheService().cacheWorkers([
      Worker(
          id: 'w1',
          name: 'n',
          phone: '0',
          role: 'Worker',
          currentBalance: 1000,
          createdAt: now),
    ]);
    await OfflineCacheService().cacheWorkerProfile(
      Worker(
          id: 'w1',
          name: 'n',
          phone: '0',
          role: 'Worker',
          currentBalance: 1000,
          createdAt: now),
    );
    await OfflineCacheService().cacheTransactions([
      MoneyTransaction(
        id: 't1',
        workerId: 'w1',
        workerName: 'n',
        type: 'distribution',
        amount: 100,
        createdAt: now,
        createdBy: 'u',
      ),
      MoneyTransaction(
        id: 't2',
        workerId: 'w1',
        workerName: 'n',
        type: 'purchase',
        amount: 50,
        createdAt: now,
        createdBy: 'u',
      ),
    ]);
    await svc.deleteTransaction('t1');
    expect(
      OfflineCacheService()
          .getPendingOperations()
          .any((o) => o['type'] == 'deleteTransaction' && o['opId'] == 't1'),
      isTrue,
    );
    final cached = OfflineCacheService().getCachedTransactions()!;
    expect(cached.any((t) => t.id == 't1'), isFalse);
    expect(cached.any((t) => t.id == 't2'), isTrue);
    // not written to firestore
    expect((await fake.collection('transactions').get()).docs, isEmpty);
  });

  test('offline insufficient balance throws before queue', () async {
    final fake = FakeFirebaseFirestore();
    OfflineSyncService().firestore = fake;
    final svc = TransactionService(firestore: fake);
    // seed worker with low balance
    await OfflineCacheService().cacheWorkers([
      Worker(
          id: 'w1',
          name: 'n',
          phone: '0',
          role: 'Worker',
          currentBalance: 50,
          createdAt: DateTime.now()),
    ]);
    // also cache worker profile for _projectedBalance fallback
    await OfflineCacheService().cacheWorkerProfile(
      Worker(
          id: 'w1',
          name: 'n',
          phone: '0',
          role: 'Worker',
          currentBalance: 50,
          createdAt: DateTime.now()),
    );
    // attempt update to a purchase requiring 100 while projected is 50
    final tx = MoneyTransaction(
      id: 't_new',
      workerId: 'w1',
      workerName: 'n',
      type: 'purchase',
      amount: 100,
      createdAt: DateTime.now(),
      createdBy: 'u',
    );
    // using updateTransaction offline with insufficient should throw
    expect(() => svc.updateTransaction(tx), throwsA(contains('Insufficient')));
    expect(
        OfflineCacheService()
            .getPendingOperations()
            .any((o) => o['opId'] == 't_new'),
        isFalse);
  });

  test('updateTransaction offline queues and updates cache', () async {
    final fake = FakeFirebaseFirestore();
    OfflineSyncService().firestore = fake;
    final svc = TransactionService(firestore: fake);
    final now = DateTime.now();
    await OfflineCacheService().cacheWorkers([
      Worker(
          id: 'w1',
          name: 'n',
          phone: '0',
          role: 'Worker',
          currentBalance: 1000,
          createdAt: now),
    ]);
    await OfflineCacheService().cacheWorkerProfile(
      Worker(
          id: 'w1',
          name: 'n',
          phone: '0',
          role: 'Worker',
          currentBalance: 1000,
          createdAt: now),
    );
    await OfflineCacheService().cacheTransactions([
      MoneyTransaction(
          id: 't1',
          workerId: 'w1',
          workerName: 'n',
          type: 'distribution',
          amount: 100,
          createdAt: now,
          createdBy: 'u'),
    ]);
    final updated = MoneyTransaction(
        id: 't1',
        workerId: 'w1',
        workerName: 'n',
        type: 'distribution',
        amount: 200,
        createdAt: now,
        createdBy: 'u');
    await svc.updateTransaction(updated);
    expect(
        OfflineCacheService()
            .getPendingOperations()
            .any((o) => o['type'] == 'updateTransaction' && o['opId'] == 't1'),
        isTrue);
    expect(
        OfflineCacheService()
            .getCachedTransactions()!
            .firstWhere((t) => t.id == 't1')
            .amount,
        200);
  });

  test('deleteTransfer offline queues and removes from cache', () async {
    final fake = FakeFirebaseFirestore();
    OfflineSyncService().firestore = fake;
    final svc = TransactionService(firestore: fake);
    final now = DateTime.now();
    const transferId = 'tr1';
    await OfflineCacheService().cacheTransactions([
      MoneyTransaction(
          id: 's1',
          workerId: 'w1',
          workerName: 'A',
          type: 'transfer',
          amount: 100,
          createdAt: now,
          createdBy: 'u',
          transferId: transferId,
          transferRole: 'sender',
          fromWorkerId: 'w1',
          toWorkerId: 'w2'),
      MoneyTransaction(
          id: 'r1',
          workerId: 'w2',
          workerName: 'B',
          type: 'transfer',
          amount: 100,
          createdAt: now,
          createdBy: 'u',
          transferId: transferId,
          transferRole: 'receiver',
          fromWorkerId: 'w1',
          toWorkerId: 'w2'),
      MoneyTransaction(
          id: 'other',
          workerId: 'w1',
          workerName: 'A',
          type: 'distribution',
          amount: 50,
          createdAt: now,
          createdBy: 'u'),
    ]);
    await svc.deleteTransfer(transferId);
    expect(
        OfflineCacheService().getPendingOperations().any((o) =>
            o['type'] == 'deleteTransfer' && o['transferId'] == transferId),
        isTrue);
    final cached = OfflineCacheService().getCachedTransactions()!;
    expect(cached.any((t) => t.transferId == transferId), isFalse);
    expect(cached.any((t) => t.id == 'other'), isTrue);
  });

  test('offline locked transaction throws before queue without override',
      () async {
    final fake = FakeFirebaseFirestore();
    OfflineSyncService().firestore = fake;
    final svc = TransactionService(firestore: fake);
    final oldDate = DateTime.now().subtract(const Duration(days: 10));
    await OfflineCacheService().cacheWorkers([
      Worker(
          id: 'w1',
          name: 'n',
          phone: '0',
          role: 'Worker',
          currentBalance: 500,
          createdAt: oldDate),
    ]);
    await OfflineCacheService().cacheWorkerProfile(
      Worker(
          id: 'w1',
          name: 'n',
          phone: '0',
          role: 'Worker',
          currentBalance: 500,
          createdAt: oldDate),
    );
    await OfflineCacheService().cacheTransactions([
      MoneyTransaction(
          id: 't_locked',
          workerId: 'w1',
          workerName: 'n',
          type: 'distribution',
          amount: 100,
          createdAt: oldDate,
          createdBy: 'u'),
    ]);
    expect(() => svc.deleteTransaction('t_locked'),
        throwsA(isA<TransactionLockedException>()));
    expect(
        () => svc.updateTransaction(MoneyTransaction(
            id: 't_locked',
            workerId: 'w1',
            workerName: 'n',
            type: 'distribution',
            amount: 200,
            createdAt: oldDate,
            createdBy: 'u')),
        throwsA(isA<TransactionLockedException>()));
    // with override should queue
    await svc.deleteTransaction('t_locked', overrideReason: 'admin fix');
    expect(
        OfflineCacheService()
            .getPendingOperations()
            .any((o) => o['opId'] == 't_locked'),
        isTrue);
  });
}
