import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:cofiz/core/models/transaction_model.dart';
import 'package:cofiz/core/providers/transaction_provider.dart';
import 'package:cofiz/core/services/offline_cache_service.dart';
import 'package:cofiz/core/services/transaction_service.dart';

void main() {
  late Directory tempDir;
  late FakeFirebaseFirestore fake;
  late TransactionProvider provider;

  MoneyTransaction tx(String id, DateTime at, {String workerId = 'w1'}) =>
      MoneyTransaction(
        id: id,
        workerId: workerId,
        workerName: 'Alice',
        type: 'distribution',
        amount: 100,
        createdAt: at,
        createdBy: 'u1',
      );

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('tx_worker_cache');
    await OfflineCacheService().initialize(path: tempDir.path);
  });

  setUp(() async {
    await OfflineCacheService().clearAllCache();
    fake = FakeFirebaseFirestore();
    provider = TransactionProvider(
      transactionService: TransactionService(firestore: fake),
    );
  });

  tearDownAll(() async {
    await OfflineCacheService().clearAllCache();
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('loadWorkerTransactions seeds instantly from cache', () async {
    await OfflineCacheService().cacheWorkerTransactions('w1', [
      tx('t2', DateTime(2026, 8, 1, 10)),
      tx('t1', DateTime(2026, 8, 1, 9)),
    ]);

    // Synchronous call - no awaiting the network stream.
    provider.loadWorkerTransactions('w1');

    expect(provider.workerTransactions.length, 2);
    // Newest first.
    expect(provider.workerTransactions.first.id, 't2');
    expect(provider.workerTransactions.last.id, 't1');
  });

  test('no cached data leaves the list empty until the stream arrives',
      () async {
    provider.loadWorkerTransactions('w1');
    expect(provider.workerTransactions, isEmpty);
  });

  test('cache is scoped per worker', () async {
    await OfflineCacheService().cacheWorkerTransactions('w1', [tx('mine', DateTime(2026, 8, 1))]);

    provider.loadWorkerTransactions('w2');

    expect(provider.workerTransactions, isEmpty);
  });

  test('live stream updates re-persist to the worker cache', () async {
    provider.loadWorkerTransactions('w1');
    expect(provider.workerTransactions, isEmpty);

    final docRef = await fake.collection('transactions').add(
          tx('live-1', DateTime(2026, 8, 2)).toFirestore(),
        );
    // Let the snapshots listener and the fire-and-forget cache write run.
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(provider.errorMessage, isNull);
    expect(
      provider.workerTransactions.any((t) => t.id == docRef.id),
      isTrue,
      reason: 'Firestore assigns its own doc id on add()',
    );
    final cached = OfflineCacheService().getCachedWorkerTransactions('w1');
    expect(cached.any((t) => t.id == docRef.id), isTrue);
  });
}
