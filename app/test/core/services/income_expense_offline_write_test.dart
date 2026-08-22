import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:cofiz/core/models/expense_record_model.dart';
import 'package:cofiz/core/models/income_record_model.dart';
import 'package:cofiz/core/services/connectivity_service.dart';
import 'package:cofiz/core/services/expense_service.dart';
import 'package:cofiz/core/services/income_service.dart';
import 'package:cofiz/core/services/offline_cache_service.dart';
import 'package:cofiz/core/services/offline_sync_service.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('income_expense_offline_write');
    await OfflineCacheService().initialize(path: dir.path);
  });

  setUp(() async {
    await OfflineCacheService().clearAllCache();
    // Ensure a fresh OfflineSyncService firestore binding doesn't interfere.
    // Services injected with FakeFirebaseFirestore isolate Firestore.
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

  test('updateIncome offline queues and returns true', () async {
    final fake = FakeFirebaseFirestore();
    OfflineSyncService().firestore = fake;
    final svc = IncomeService(firestore: fake);
    await OfflineCacheService().cacheIncome([
      IncomeRecord(
        id: 'i1',
        kind: IncomeKind.investment,
        amount: 100,
        createdAt: DateTime.now(),
        createdBy: 'u',
        createdByName: 'n',
      ),
    ]);

    final ok = await svc.updateIncome(
      IncomeRecord(
        id: 'i1',
        kind: IncomeKind.sale,
        amount: 200,
        createdAt: DateTime.now(),
        createdBy: 'u',
        createdByName: 'n',
        saleCategory: 'Other',
      ),
    );

    expect(ok, isTrue);
    expect(
      OfflineCacheService()
          .getPendingOperations()
          .any((o) => o['type'] == 'updateIncome' && o['opId'] == 'i1'),
      isTrue,
    );
    expect(
      OfflineCacheService()
          .getCachedIncome()!
          .firstWhere((r) => r.id == 'i1')
          .amount,
      200,
    );
    // Firestore not touched — queued op has payload
    final pending = OfflineCacheService()
        .getPendingOperations()
        .firstWhere((o) => o['type'] == 'updateIncome');
    expect(pending['docId'], 'i1');
    expect((pending['payload'] as Map)['amount'], 200);
  });

  test('deleteIncome offline queues and removes from cache', () async {
    final fake = FakeFirebaseFirestore();
    OfflineSyncService().firestore = fake;
    final svc = IncomeService(firestore: fake);
    await OfflineCacheService().cacheIncome([
      IncomeRecord(
        id: 'i1',
        kind: IncomeKind.investment,
        amount: 100,
        createdAt: DateTime.now(),
        createdBy: 'u',
        createdByName: 'n',
      ),
      IncomeRecord(
        id: 'i2',
        kind: IncomeKind.sale,
        amount: 50,
        createdAt: DateTime.now(),
        createdBy: 'u',
        createdByName: 'n',
        saleCategory: 'Other',
      ),
    ]);

    final ok = await svc.deleteIncome('i1');

    expect(ok, isTrue);
    expect(
      OfflineCacheService()
          .getPendingOperations()
          .any((o) => o['type'] == 'deleteIncome' && o['opId'] == 'i1'),
      isTrue,
    );
    expect(
      OfflineCacheService().getCachedIncome()!.any((r) => r.id == 'i1'),
      isFalse,
    );
    expect(
      OfflineCacheService().getCachedIncome()!.any((r) => r.id == 'i2'),
      isTrue,
    );
  });

  test('updateExpense offline queues and returns true', () async {
    final fake = FakeFirebaseFirestore();
    OfflineSyncService().firestore = fake;
    final svc = ExpenseService(firestore: fake);
    await OfflineCacheService().cacheExpenses([
      ExpenseRecord(
        id: 'e1',
        amount: 80,
        expenseCategory: 'Food',
        createdAt: DateTime.now(),
        createdBy: 'u',
        createdByName: 'n',
      ),
    ]);

    final ok = await svc.updateExpense(
      ExpenseRecord(
        id: 'e1',
        amount: 150,
        expenseCategory: 'Transport',
        createdAt: DateTime.now(),
        createdBy: 'u',
        createdByName: 'n',
      ),
    );

    expect(ok, isTrue);
    expect(
      OfflineCacheService()
          .getPendingOperations()
          .any((o) => o['type'] == 'updateExpense' && o['opId'] == 'e1'),
      isTrue,
    );
    expect(
      OfflineCacheService()
          .getCachedExpenses()!
          .firstWhere((r) => r.id == 'e1')
          .amount,
      150,
    );
  });

  test('deleteExpense offline queues and removes from cache', () async {
    final fake = FakeFirebaseFirestore();
    OfflineSyncService().firestore = fake;
    final svc = ExpenseService(firestore: fake);
    await OfflineCacheService().cacheExpenses([
      ExpenseRecord(
        id: 'e1',
        amount: 80,
        expenseCategory: 'Food',
        createdAt: DateTime.now(),
        createdBy: 'u',
        createdByName: 'n',
      ),
      ExpenseRecord(
        id: 'e2',
        amount: 40,
        expenseCategory: 'Other',
        createdAt: DateTime.now(),
        createdBy: 'u',
        createdByName: 'n',
      ),
    ]);

    final ok = await svc.deleteExpense('e1');

    expect(ok, isTrue);
    expect(
      OfflineCacheService()
          .getPendingOperations()
          .any((o) => o['type'] == 'deleteExpense' && o['opId'] == 'e1'),
      isTrue,
    );
    expect(
      OfflineCacheService().getCachedExpenses()!.any((r) => r.id == 'e1'),
      isFalse,
    );
    expect(
      OfflineCacheService().getCachedExpenses()!.any((r) => r.id == 'e2'),
      isTrue,
    );
  });
}
