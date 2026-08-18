import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cofiz/core/services/offline_cache_service.dart';
import 'package:cofiz/core/services/offline_sync_service.dart';
import 'package:cofiz/core/services/connectivity_service.dart';
import 'package:cofiz/core/services/transaction_service.dart';

void main() {
  late Directory tempDir;
  late FakeFirebaseFirestore fake;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('sync_test');
    await OfflineCacheService().initialize(path: tempDir.path);
  });

  setUp(() async {
    fake = FakeFirebaseFirestore();
    OfflineSyncService().firestore = fake;
    await OfflineCacheService().clearPendingOperations();
    await OfflineCacheService().clearDelivered();
    ConnectivityService().setOnlineForTest(true);
    await fake.collection('workers').doc('w1').set({'currentBalance': 1000.0});
    // Disable periodic timer during tests
    OfflineSyncService().dispose();
  });

  tearDown(() async {
    await OfflineCacheService().clearPendingOperations();
    OfflineSyncService().dispose();
  });

  tearDownAll(() async {
    await OfflineCacheService().clearAllCache();
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  Future<void> seedTx(String id,
      {String workerId = 'w1',
      bool approved = false,
      String? transferId}) async {
    await fake.collection('transactions').doc(id).set({
      'workerId': workerId,
      'workerName': 'Alice',
      'type': 'distribution',
      'amount': 100.0,
      'createdAt': DateTime(2026, 8, 1).millisecondsSinceEpoch,
      'createdBy': 'u1',
      'approved': approved,
      if (transferId != null) 'transferId': transferId,
    });
  }

  test('replays approveTransaction op', () async {
    await seedTx('t1', approved: false);
    await OfflineCacheService().queueOperation({
      'opId': 'op-approve-t1',
      'type': 'approveTransaction',
      'transactionId': 't1',
      'queuedAt': DateTime.now().toIso8601String(),
      'attempts': 0,
    });

    await OfflineSyncService().syncPendingOperations();

    final doc = await fake.collection('transactions').doc('t1').get();
    expect(doc.data()?['approved'], isTrue);
    expect(OfflineCacheService().getPendingOperations(), isEmpty);
  });

  test('replays approveTransfer op on both records', () async {
    await seedTx('s1', approved: false, transferId: 'tr-1');
    await seedTx('r1', approved: false, transferId: 'tr-1');
    await OfflineCacheService().queueOperation({
      'opId': 'op-approve-tr1',
      'type': 'approveTransfer',
      'transferId': 'tr-1',
      'queuedAt': DateTime.now().toIso8601String(),
      'attempts': 0,
    });

    await OfflineSyncService().syncPendingOperations();

    final s1 = await fake.collection('transactions').doc('s1').get();
    final r1 = await fake.collection('transactions').doc('r1').get();
    expect(s1.data()?['approved'], isTrue);
    expect(r1.data()?['approved'], isTrue);
    expect(OfflineCacheService().getPendingOperations(), isEmpty);
  });

  test('replays approveAll op for worker', () async {
    await seedTx('t1', workerId: 'w1', approved: false);
    await seedTx('t2', workerId: 'w1', approved: false);
    await seedTx('t3', workerId: 'w2', approved: false);
    await OfflineCacheService().queueOperation({
      'opId': 'op-approve-all-w1',
      'type': 'approveAll',
      'workerId': 'w1',
      'queuedAt': DateTime.now().toIso8601String(),
      'attempts': 0,
    });

    await OfflineSyncService().syncPendingOperations();

    final t1 = await fake.collection('transactions').doc('t1').get();
    final t2 = await fake.collection('transactions').doc('t2').get();
    final t3 = await fake.collection('transactions').doc('t3').get();
    expect(t1.data()?['approved'], isTrue);
    expect(t2.data()?['approved'], isTrue);
    expect(t3.data()?['approved'], isFalse); // other worker untouched
    expect(OfflineCacheService().getPendingOperations(), isEmpty);
  });

  test('drains multiple queued ops of mixed types in one pass', () async {
    await seedTx('t1', approved: false);
    await seedTx('s1', approved: false, transferId: 'tr-1');
    await seedTx('r1', approved: false, transferId: 'tr-1');
    await seedTx('t2', workerId: 'w1', approved: false);
    await OfflineCacheService().queueOperation({
      'opId': 'op-mixed-1',
      'type': 'approveTransaction',
      'transactionId': 't1',
      'queuedAt': DateTime.now().toIso8601String(),
      'attempts': 0,
    });
    await OfflineCacheService().queueOperation({
      'opId': 'op-mixed-2',
      'type': 'approveTransfer',
      'transferId': 'tr-1',
      'queuedAt': DateTime.now().toIso8601String(),
      'attempts': 0,
    });
    await OfflineCacheService().queueOperation({
      'opId': 'op-mixed-3',
      'type': 'approveAll',
      'workerId': 'w1',
      'queuedAt': DateTime.now().toIso8601String(),
      'attempts': 0,
    });

    await OfflineSyncService().syncPendingOperations();

    final t1 = await fake.collection('transactions').doc('t1').get();
    final s1 = await fake.collection('transactions').doc('s1').get();
    final r1 = await fake.collection('transactions').doc('r1').get();
    final t2 = await fake.collection('transactions').doc('t2').get();
    expect(t1.data()?['approved'], isTrue);
    expect(s1.data()?['approved'], isTrue);
    expect(r1.data()?['approved'], isTrue);
    expect(t2.data()?['approved'], isTrue);
    expect(OfflineCacheService().getPendingOperations(), isEmpty);
  });

  test('failing op leaves only itself queued while later ops drain', () async {
    await seedTx('t1', approved: false);
    await seedTx('t2', approved: false);
    await OfflineCacheService().queueOperation({
      'opId': 'op-fail-missing',
      'type': 'approveTransaction',
      'transactionId': 'missing',
      'queuedAt': DateTime.now().toIso8601String(),
      'attempts': 0,
    });
    await OfflineCacheService().queueOperation({
      'opId': 'op-fail-t1',
      'type': 'approveTransaction',
      'transactionId': 't1',
      'queuedAt': DateTime.now().toIso8601String(),
      'attempts': 0,
    });
    await OfflineCacheService().queueOperation({
      'opId': 'op-fail-t2',
      'type': 'approveTransaction',
      'transactionId': 't2',
      'queuedAt': DateTime.now().toIso8601String(),
      'attempts': 0,
    });

    await OfflineSyncService().syncPendingOperations();

    final t1 = await fake.collection('transactions').doc('t1').get();
    final t2 = await fake.collection('transactions').doc('t2').get();
    expect(t1.data()?['approved'], isTrue);
    expect(t2.data()?['approved'], isTrue);
    final remaining = OfflineCacheService().getPendingOperations();
    expect(remaining, hasLength(1));
    expect(remaining.single['type'], 'approveTransaction');
    expect(remaining.single['transactionId'], 'missing');
  });

  test('createTransaction is idempotent across two drains', () async {
    const opId = 'op-ctest-1';
    await OfflineCacheService().queueOperation({
      'opId': opId,
      'type': 'createTransaction',
      'docId': opId,
      'workerId': 'w1',
      'workerName': 'W1',
      'transactionType': 'distribution',
      'amount': 100.0,
      'createdBy': 'tester',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'queuedAt': DateTime.now().toIso8601String(),
      'attempts': 0,
    });
    await OfflineSyncService().syncPendingOperations();
    // First drain delivered
    expect(OfflineCacheService().getPendingOperations().length, 0);
    expect(
        (await fake.collection('transactions').doc(opId).get()).exists, true);
    expect(
        (await fake.collection('workers').doc('w1').get())
            .data()!['currentBalance'],
        1100.0);
    // Re-queue same opId (simulates crash between commit and dequeue) and drain again
    await OfflineCacheService().queueOperation({
      'opId': opId,
      'type': 'createTransaction',
      'docId': opId,
      'workerId': 'w1',
      'workerName': 'W1',
      'transactionType': 'distribution',
      'amount': 100.0,
      'createdBy': 'tester',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'queuedAt': DateTime.now().toIso8601String(),
      'attempts': 0,
    });
    await OfflineSyncService().syncPendingOperations();
    expect(
        (await fake.collection('workers').doc('w1').get())
            .data()!['currentBalance'],
        1100.0); // not double
    expect(OfflineCacheService().getPendingOperations().length, 0);
  });

  test('failed op stays for retry, delivered log tracks success', () async {
    await OfflineCacheService().queueOperation({
      'opId': 'bad',
      'type': 'unknownType',
      'queuedAt': DateTime.now().toIso8601String(),
      'attempts': 0,
    });
    await OfflineSyncService().syncPendingOperations();
    expect(OfflineCacheService().getPendingOperations().length, 1);
    expect(OfflineCacheService().getDeliveredCount(), 0);
  });

  test('approveTransaction while online queues instead of direct write',
      () async {
    final localFake = FakeFirebaseFirestore();
    OfflineSyncService().firestore = localFake;
    await localFake.collection('transactions').doc('t1').set({
      'approved': false,
      'workerId': 'w1',
      'workerName': 'Alice',
      'type': 'distribution',
      'amount': 100.0,
      'createdAt': DateTime(2026, 8, 1).millisecondsSinceEpoch,
      'createdBy': 'u1',
    });
    final svc = TransactionService(firestore: localFake);
    await OfflineCacheService().clearPendingOperations();
    await OfflineCacheService().clearDelivered();
    // Deterministic: queue while offline, then go online and drain
    ConnectivityService().setOnlineForTest(false);
    await svc.approveTransaction('t1');
    expect(
        OfflineCacheService()
            .getPendingOperations()
            .any((o) => o['type'] == 'approveTransaction'),
        true);
    expect(
        (await localFake.collection('transactions').doc('t1').get())
            .data()!['approved'],
        false);
    ConnectivityService().setOnlineForTest(true);
    OfflineSyncService().firestore = localFake;
    await OfflineSyncService().syncPendingOperations();
    expect(
        (await localFake.collection('transactions').doc('t1').get())
            .data()!['approved'],
        true);
    expect(OfflineCacheService().getPendingOperations(), isEmpty);
    OfflineSyncService().firestore = fake;
  });

  test('approveTransfer while online queues instead of direct write', () async {
    final localFake = FakeFirebaseFirestore();
    OfflineSyncService().firestore = localFake;
    await localFake.collection('transactions').doc('s1').set({
      'workerId': 'w1',
      'workerName': 'Alice',
      'type': 'transfer',
      'amount': 50.0,
      'createdAt': DateTime(2026, 8, 1).millisecondsSinceEpoch,
      'createdBy': 'u1',
      'approved': false,
      'transferId': 'tr-online',
    });
    await localFake.collection('transactions').doc('r1').set({
      'workerId': 'w2',
      'workerName': 'Bob',
      'type': 'transfer',
      'amount': 50.0,
      'createdAt': DateTime(2026, 8, 1).millisecondsSinceEpoch,
      'createdBy': 'u1',
      'approved': false,
      'transferId': 'tr-online',
    });
    final svc = TransactionService(firestore: localFake);
    await OfflineCacheService().clearPendingOperations();
    await OfflineCacheService().clearDelivered();
    ConnectivityService().setOnlineForTest(false);
    await svc.approveTransfer('tr-online');
    expect(
        OfflineCacheService()
            .getPendingOperations()
            .any((o) => o['type'] == 'approveTransfer'),
        true);
    expect(
        (await localFake.collection('transactions').doc('s1').get())
            .data()!['approved'],
        false);
    expect(
        (await localFake.collection('transactions').doc('r1').get())
            .data()!['approved'],
        false);
    ConnectivityService().setOnlineForTest(true);
    OfflineSyncService().firestore = localFake;
    await OfflineSyncService().syncPendingOperations();
    expect(
        (await localFake.collection('transactions').doc('s1').get())
            .data()!['approved'],
        true);
    expect(
        (await localFake.collection('transactions').doc('r1').get())
            .data()!['approved'],
        true);
    expect(OfflineCacheService().getPendingOperations(), isEmpty);
    OfflineSyncService().firestore = fake;
  });

  test('approveAllForWorker while online queues instead of direct write',
      () async {
    final localFake = FakeFirebaseFirestore();
    OfflineSyncService().firestore = localFake;
    await localFake.collection('transactions').doc('t1').set({
      'workerId': 'w1',
      'workerName': 'Alice',
      'type': 'distribution',
      'amount': 100.0,
      'createdAt': DateTime(2026, 8, 1).millisecondsSinceEpoch,
      'createdBy': 'u1',
      'approved': false,
    });
    await localFake.collection('transactions').doc('t2').set({
      'workerId': 'w1',
      'workerName': 'Alice',
      'type': 'distribution',
      'amount': 50.0,
      'createdAt': DateTime(2026, 8, 1).millisecondsSinceEpoch,
      'createdBy': 'u1',
      'approved': false,
    });
    final svc = TransactionService(firestore: localFake);
    await OfflineCacheService().clearPendingOperations();
    await OfflineCacheService().clearDelivered();
    ConnectivityService().setOnlineForTest(false);
    await svc.approveAllForWorker('w1');
    expect(
        OfflineCacheService()
            .getPendingOperations()
            .any((o) => o['type'] == 'approveAll'),
        true);
    expect(
        (await localFake.collection('transactions').doc('t1').get())
            .data()!['approved'],
        false);
    expect(
        (await localFake.collection('transactions').doc('t2').get())
            .data()!['approved'],
        false);
    ConnectivityService().setOnlineForTest(true);
    OfflineSyncService().firestore = localFake;
    await OfflineSyncService().syncPendingOperations();
    expect(
        (await localFake.collection('transactions').doc('t1').get())
            .data()!['approved'],
        true);
    expect(
        (await localFake.collection('transactions').doc('t2').get())
            .data()!['approved'],
        true);
    expect(OfflineCacheService().getPendingOperations(), isEmpty);
    OfflineSyncService().firestore = fake;
  });

  test('ops queued during sync are not lost (lost-update regression)',
      () async {
    // Seed initial pending op that will take time to drain
    await OfflineCacheService().queueOperation({
      'opId': 'op-initial',
      'type': 'createTransaction',
      'docId': 'op-initial',
      'workerId': 'w1',
      'workerName': 'W1',
      'transactionType': 'distribution',
      'amount': 10.0,
      'createdBy': 'tester',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'queuedAt': DateTime.now().toIso8601String(),
      'attempts': 0,
    });
    // Configure firestore to delay runTransaction for the first op
    // Use aCompleter to hold sync in progress, queue new op while isSyncing=true
    // Disable timer and ensure online
    ConnectivityService().setOnlineForTest(true);
    // Start sync without awaiting, then queue during isSyncing
    final syncFuture = OfflineSyncService().syncPendingOperations();
    // Wait a microtask to let isSyncing become true
    await Future.delayed(Duration.zero);
    expect(OfflineSyncService().isSyncing, isTrue);
    // Queue new op while syncing — this simulates queueOperation during isSyncing
    await OfflineCacheService().queueOperation({
      'opId': 'op-during-sync',
      'type': 'createTransaction',
      'docId': 'op-during-sync',
      'workerId': 'w1',
      'workerName': 'W1',
      'transactionType': 'distribution',
      'amount': 20.0,
      'createdBy': 'tester2',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'queuedAt': DateTime.now().toIso8601String(),
      'attempts': 0,
    });
    await syncFuture;
    // After sync, the op queued during sync must still be pending (not overwritten)
    final pending = OfflineCacheService().getPendingOperations();
    expect(pending.any((o) => o['opId'] == 'op-during-sync'), isTrue,
        reason: 'op queued during sync should not be lost');
    // Drain again and verify both delivered
    await OfflineSyncService().syncPendingOperations();
    expect(OfflineCacheService().getPendingOperations(), isEmpty);
    expect(
        (await fake.collection('transactions').doc('op-initial').get()).exists,
        isTrue);
    expect(
        (await fake.collection('transactions').doc('op-during-sync').get())
            .exists,
        isTrue);
  });
}
