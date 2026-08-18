import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cofiz/core/services/connectivity_service.dart';
import 'package:cofiz/core/services/offline_cache_service.dart';
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
}
