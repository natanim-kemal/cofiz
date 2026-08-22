import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cofiz/core/models/transaction_model.dart';
import 'package:cofiz/core/providers/transaction_provider.dart';
import 'package:cofiz/core/services/connectivity_service.dart';
import 'package:cofiz/core/services/offline_cache_service.dart';
import 'package:cofiz/core/services/transaction_service.dart';

/// Task 7: TransactionDialog must not block on receipt upload while offline.
///
/// Deviation note: the plan asked for a widget test pumping TransactionDialog,
/// but AuthProvider hard-instantiates FirebaseAuth.instance /
/// FirebaseFirestore.instance with no injection seam, so the widget harness
/// cannot be built without Firebase initialization. These tests cover the same
/// behavior one level down: submitting offline queues the operation containing
/// the local receipt path and returns success immediately (dialog pops) instead
/// of blocking/failing on an upload.
void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('offline_dialog_test');
    await OfflineCacheService().initialize(path: tempDir.path);
  });

  setUp(() {
    ConnectivityService().setOnlineForTest(false);
  });

  tearDown(() async {
    await OfflineCacheService().clearAllCache();
    ConnectivityService().setOnlineForTest(true);
  });

  tearDownAll(() async {
    await OfflineCacheService().clearAllCache();
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  MoneyTransaction purchaseTx({double amount = 120}) => MoneyTransaction(
        id: '',
        workerId: 'w1',
        workerName: 'W1',
        type: 'purchase',
        amount: amount,
        createdAt: DateTime.now(),
        createdBy: 'tester',
        coffeeType: 'jenfel',
        coffeeWeight: 3,
        pricePerKg: 40,
        commissionAmount: 15,
      );

  test(
    'addTransaction accepts localReceiptPath and queues it in the op while offline',
    () async {
      final service = TransactionService(firestore: FakeFirebaseFirestore());

      final docId = await service.addTransaction(
        purchaseTx(),
        localReceiptPath: '/tmp/receipt.jpg',
      );

      expect(docId, isNotNull);
      final ops = OfflineCacheService()
          .getPendingOperations()
          .where((o) => o['type'] == 'createTransaction')
          .toList();
      expect(ops.length, 1);
      expect(ops.first['docId'], docId);
      expect(ops.first['localReceiptPath'], '/tmp/receipt.jpg');
      expect(ops.first['receiptUrl'], isNull);
    },
  );

  test(
    'recordCoffeePurchase with localReceiptPath succeeds offline without uploading',
    () async {
      // No network stubs: an upload attempt would throw and make this return
      // false, so returning true proves the dialog path defers the upload.
      final provider = TransactionProvider(
        transactionService:
            TransactionService(firestore: FakeFirebaseFirestore()),
      );

      final success = await provider.recordCoffeePurchase(
        workerId: 'w1',
        workerName: 'W1',
        amount: 120,
        createdBy: 'tester',
        coffeeType: 'jenfel',
        weight: 3,
        pricePerKg: 40,
        commission: 15,
        localReceiptPath: '/tmp/receipt.jpg',
      );

      expect(success, isTrue);
      final ops = OfflineCacheService()
          .getPendingOperations()
          .where((o) => o['type'] == 'createTransaction')
          .toList();
      expect(ops.length, 1);
      expect(ops.first['localReceiptPath'], '/tmp/receipt.jpg');
    },
  );

  test(
    'distributeMoneyToWorker with localReceiptPath succeeds offline without uploading',
    () async {
      final provider = TransactionProvider(
        transactionService:
            TransactionService(firestore: FakeFirebaseFirestore()),
      );

      final success = await provider.distributeMoneyToWorker(
        workerId: 'w1',
        workerName: 'W1',
        amount: 50,
        createdBy: 'tester',
        localReceiptPath: '/tmp/receipt_dist.jpg',
      );

      expect(success, isTrue);
      final ops = OfflineCacheService()
          .getPendingOperations()
          .where((o) => o['type'] == 'createTransaction')
          .toList();
      expect(ops.length, 1);
      expect(ops.first['localReceiptPath'], '/tmp/receipt_dist.jpg');
    },
  );

  test(
    'returnMoneyFromWorker with localReceiptPath succeeds offline without uploading',
    () async {
      final provider = TransactionProvider(
        transactionService:
            TransactionService(firestore: FakeFirebaseFirestore()),
      );
      await OfflineCacheService().cacheTransactions([
        MoneyTransaction(
          id: 'seed-dist',
          workerId: 'w1',
          workerName: 'W1',
          type: 'distribution',
          amount: 500,
          createdAt: DateTime.now(),
          createdBy: 'tester',
        ),
      ]);

      final success = await provider.returnMoneyFromWorker(
        workerId: 'w1',
        workerName: 'W1',
        amount: 100,
        createdBy: 'tester',
        localReceiptPath: '/tmp/receipt_return.jpg',
      );

      expect(success, isTrue);
      final ops = OfflineCacheService()
          .getPendingOperations()
          .where((o) => o['type'] == 'createTransaction')
          .toList();
      expect(ops.length, 1);
      expect(ops.first['localReceiptPath'], '/tmp/receipt_return.jpg');
    },
  );
}
