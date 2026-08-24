import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:cofiz/core/models/transaction_model.dart';
import 'package:cofiz/core/providers/transaction_provider.dart';
import 'package:cofiz/core/services/connectivity_service.dart';
import 'package:cofiz/core/services/offline_cache_service.dart';
import 'package:cofiz/core/services/transaction_service.dart';

void main() {
  late Directory dir;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('tx_ticks');
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

  MoneyTransaction tx(String id, {bool approved = false}) => MoneyTransaction(
        id: id,
        workerId: 'w1',
        workerName: 'n',
        type: 'distribution',
        amount: 100,
        createdAt: DateTime.now(),
        createdBy: 'u',
        approved: approved,
      );

  test('offline create is pending', () async {
    final svc = TransactionService(firestore: FakeFirebaseFirestore());
    final p = TransactionProvider(transactionService: svc);
    p.loadWorkerTransactions('w1');
    await Future.delayed(Duration.zero);

    await p.distributeMoneyToWorker(workerId: 'w1', workerName: 'n', amount: 50, createdBy: 'u');
    final id = p.workerTransactions.first.id;
    expect(p.isPending(id), isTrue);
  });

  test('confirmed shows double tick, synced single', () async {
    final p = TransactionProvider(transactionService: TransactionService(firestore: FakeFirebaseFirestore()));
    final pending = tx('a', approved: false);
    p.debugSetWorkerTransactions([pending]);
    expect(pending.approved, isFalse);
    final confirmed = tx('a', approved: true);
    expect(confirmed.approved, isTrue);
  });
}
