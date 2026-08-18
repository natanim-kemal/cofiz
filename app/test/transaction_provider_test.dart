import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cofiz/core/models/transaction_model.dart';
import 'package:cofiz/core/providers/transaction_provider.dart';
import 'package:cofiz/core/services/connectivity_service.dart';
import 'package:cofiz/core/services/offline_cache_service.dart';
import 'package:cofiz/core/services/transaction_service.dart';

MoneyTransaction tx(String id, {bool approved = false, String? transferId}) {
  return MoneyTransaction(
    id: id,
    workerId: 'w1',
    workerName: 'Alice',
    type: 'distribution',
    amount: 100,
    createdAt: DateTime(2026, 8, 15),
    createdBy: 'u1',
    approved: approved,
    transferId: transferId,
  );
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('tx_provider_test');
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

  test('approveTransaction flips local entry', () async {
    final provider = TransactionProvider(
        transactionService:
            TransactionService(firestore: FakeFirebaseFirestore()));
    provider.debugSetWorkerTransactions([tx('t1', approved: false)]);

    final ok = await provider.approveTransaction('t1');

    expect(ok, isTrue);
    expect(provider.workerTransactions.single.approved, isTrue);
  });

  test('approveTransfer flips both records', () async {
    final provider = TransactionProvider(
        transactionService:
            TransactionService(firestore: FakeFirebaseFirestore()));
    provider.debugSetWorkerTransactions([
      tx('s1', approved: false, transferId: 'tr-1'),
      tx('r1', approved: false, transferId: 'tr-1'),
      tx('other', approved: false),
    ]);

    final ok = await provider.approveTransfer('tr-1');

    expect(ok, isTrue);
    expect(
      provider.workerTransactions.where((t) => t.approved).length,
      2,
    );
    expect(
      provider.workerTransactions.firstWhere((t) => t.id == 'other').approved,
      isFalse,
    );
  });

  test('approveAllForWorker flips all unapproved', () async {
    final provider = TransactionProvider(
        transactionService:
            TransactionService(firestore: FakeFirebaseFirestore()));
    provider.debugSetWorkerTransactions([
      tx('t1', approved: false),
      tx('t2', approved: false),
    ]);

    final ok = await provider.approveAllForWorker('w1');

    expect(ok, isTrue);
    expect(provider.workerTransactions.every((t) => t.approved), isTrue);
  });
}
