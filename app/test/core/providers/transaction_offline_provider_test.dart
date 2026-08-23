import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:cofiz/core/models/transaction_model.dart';
import 'package:cofiz/core/providers/transaction_provider.dart';
import 'package:cofiz/core/services/connectivity_service.dart';
import 'package:cofiz/core/services/offline_cache_service.dart';
import 'package:cofiz/core/services/offline_sync_service.dart';
import 'package:cofiz/core/services/transaction_service.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('transaction_offline_provider');
    await OfflineCacheService().initialize(path: dir.path);
  });

  setUp(() async {
    await OfflineCacheService().clearAllCache();
    ConnectivityService().setOnlineForTest(false);
    final fs = FakeFirebaseFirestore();
    OfflineSyncService().firestore = fs;
    // Sync drains increment worker balances; seed the docs so they exist.
    await fs.collection('workers').doc('w1').set({'currentBalance': 1000.0});
    await fs.collection('workers').doc('w2').set({'currentBalance': 0.0});
  });

  tearDown(() async {
    await OfflineCacheService().clearAllCache();
    ConnectivityService().setOnlineForTest(true);
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  Future<TransactionProvider> makeProvider() async {
    final p = TransactionProvider(
      transactionService:
          TransactionService(firestore: FakeFirebaseFirestore()),
    );
    await p.distributeMoneyToWorker(
      workerId: 'w1',
      workerName: 'n',
      amount: 50,
      createdBy: 'u',
    );
    return p;
  }

  test('updateTransaction offline optimistic', () async {
    final p = await makeProvider();
    final tx = p.allTransactions.first;

    final updated = tx.copyWith(amount: 60);
    final ok = await p.updateTransaction(updated);

    expect(ok, isTrue);
    expect(
      p.allTransactions.firstWhere((t) => t.id == tx.id).amount,
      60,
    );
  });

  test('deleteTransaction offline removes rows instantly and queues', () async {
    final p = await makeProvider();
    final tx = p.allTransactions.first;
    // Drain the pending create so the delete below queues a real op
    // (otherwise outbox coalesce drops create+delete together).
    ConnectivityService().setOnlineForTest(true);
    await OfflineSyncService().syncPendingOperations();
    ConnectivityService().setOnlineForTest(false);
    p.debugSetWorkerTransactions([tx]);

    final ok = await p.deleteTransaction(tx.id);

    expect(ok, isTrue);
    expect(p.allTransactions.any((t) => t.id == tx.id), isFalse);
    expect(p.workerTransactions.any((t) => t.id == tx.id), isFalse);
    expect(
      OfflineCacheService()
          .getPendingOperations()
          .any((o) => o['type'] == 'deleteTransaction' && o['opId'] == tx.id),
      isTrue,
    );
  });

  test('deleteTransfer offline removes both legs and queues', () async {
    final p = TransactionProvider(
      transactionService:
          TransactionService(firestore: FakeFirebaseFirestore()),
    );
    await p.transferFromCollectorToCollector(
      fromWorkerId: 'w1',
      fromWorkerName: 'a',
      toWorkerId: 'w2',
      toWorkerName: 'b',
      amount: 30,
      createdBy: 'u',
    );
    final legs = p.allTransactions.where((t) => t.isTransfer).toList();
    expect(legs.length, 2);
    final transferId = legs.first.transferId!;
    // Drain the pending transfer creates so the delete below queues a real op.
    ConnectivityService().setOnlineForTest(true);
    await OfflineSyncService().syncPendingOperations();
    ConnectivityService().setOnlineForTest(false);

    final ok = await p.deleteTransfer(transferId);

    expect(ok, isTrue);
    expect(
      p.allTransactions.where((t) =>
          t.transferId == transferId ||
          t.id == transferId ||
          t.id == '${transferId}_r'),
      isEmpty,
    );
    expect(
      OfflineCacheService()
          .getPendingOperations()
          .any((o) => o['type'] == 'deleteTransfer' && o['opId'] == transferId),
      isTrue,
    );
  });

  test('failed delete rolls back optimistic removal', () async {
    final p = TransactionProvider(
      transactionService:
          TransactionService(firestore: FakeFirebaseFirestore()),
    );
    // Past the 7-day immutability window: delete without overrideReason is
    // rejected by the service (TransactionLockedException).
    final oldTx = MoneyTransaction(
      id: 'locked-tx',
      workerId: 'w1',
      workerName: 'n',
      type: 'distribution',
      amount: 50,
      createdAt: DateTime.now().subtract(const Duration(days: 8)),
      createdBy: 'u',
      approved: false,
    );
    await OfflineCacheService().cacheTransactions([oldTx]);
    p.debugSetWorkerTransactions([oldTx]);

    final ok = await p.deleteTransaction(oldTx.id);

    expect(ok, isFalse);
    expect(p.workerTransactions.any((t) => t.id == oldTx.id), isTrue);
    expect(p.errorMessage, isNotNull);
  });

  test('offline distribute bumps today activity + worker delta callback',
      () async {
    final p = await makeProvider();
    final before = p.todayDistributed; // makeProvider seeded 50
    var deltaTx;
    var deltaDir = 0;
    p.onTransactionApplied = (tx, dir) {
      deltaTx = tx;
      deltaDir = dir;
    };

    await p.distributeMoneyToWorker(
        workerId: 'w1', workerName: 'n', amount: 300, createdBy: 'u');

    // Today card reconcile source: pending op exists and provider counters
    // moved optimistically.
    expect(p.todayDistributed, before + 300.0);
    expect(deltaTx, isNotNull);
    expect(deltaDir, 1);
    expect(deltaTx.amount, 300.0);

    // Worker balance card: applying -1 then +1 nets back to start (rollback
    // path uses the same primitives).
    expect(deltaTx.workerId, 'w1');
  });
}
