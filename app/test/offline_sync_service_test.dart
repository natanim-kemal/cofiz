import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cofiz/core/services/offline_cache_service.dart';
import 'package:cofiz/core/services/offline_sync_service.dart';

void main() {
  late Directory tempDir;
  late FakeFirebaseFirestore fake;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('sync_test');
    await OfflineCacheService().initialize(path: tempDir.path);
  });

  setUp(() {
    fake = FakeFirebaseFirestore();
    OfflineSyncService().firestore = fake;
  });

  tearDown(() async {
    await OfflineCacheService().clearPendingOperations();
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
      'type': 'approveTransaction',
      'transactionId': 't1',
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
      'type': 'approveTransfer',
      'transferId': 'tr-1',
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
      'type': 'approveAll',
      'workerId': 'w1',
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
      'type': 'approveTransaction',
      'transactionId': 't1',
    });
    await OfflineCacheService().queueOperation({
      'type': 'approveTransfer',
      'transferId': 'tr-1',
    });
    await OfflineCacheService().queueOperation({
      'type': 'approveAll',
      'workerId': 'w1',
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
      'type': 'approveTransaction',
      'transactionId': 'missing',
    });
    await OfflineCacheService().queueOperation({
      'type': 'approveTransaction',
      'transactionId': 't1',
    });
    await OfflineCacheService().queueOperation({
      'type': 'approveTransaction',
      'transactionId': 't2',
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
}
