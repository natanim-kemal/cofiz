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
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('income_expense_outbox');
    await OfflineCacheService().initialize(path: tempDir.path);
  });

  setUp(() async {
    await OfflineCacheService().clearPendingOperations();
    await OfflineCacheService().clearDelivered();
    // clear cached collections so each test starts fresh
    await OfflineCacheService().cacheIncome([]);
    await OfflineCacheService().cacheExpenses([]);
    ConnectivityService().setOnlineForTest(false);
  });

  tearDown(() async {
    await OfflineCacheService().clearPendingOperations();
    await OfflineCacheService().clearDelivered();
    ConnectivityService().setOnlineForTest(true);
  });

  tearDownAll(() async {
    await OfflineCacheService().clearAllCache();
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('addIncome queues and shows in cache, drain creates doc', () async {
    final fake = FakeFirebaseFirestore();
    final svc = IncomeService(firestore: fake);
    OfflineSyncService().firestore = fake;
    final record = IncomeRecord(
      id: '',
      kind: IncomeKind.sale,
      amount: 100,
      createdAt: DateTime.now(),
      createdBy: 'u1',
      createdByName: 'Tester',
      saleCategory: 'Coffee Beans',
    );
    final opId = await svc.addIncome(record);
    expect(opId, isNotNull);
    expect(
        OfflineCacheService()
            .getPendingOperations()
            .any((o) => o['type'] == 'createIncome'),
        true);
    expect(
        OfflineCacheService()
            .getPendingOperations()
            .any((o) => o['opId'] == opId),
        true);
    // optimistic cache populated
    expect(OfflineCacheService().getCachedIncome()?.any((r) => r.id == opId),
        true);
    // not yet written to firestore before drain
    expect((await fake.collection('income_records').get()).docs.length, 0);
    ConnectivityService().setOnlineForTest(true);
    await OfflineSyncService().syncPendingOperations();
    expect((await fake.collection('income_records').get()).docs.length, 1);
    final doc = (await fake.collection('income_records').get()).docs.first;
    expect((doc.data()['amount'] as num).toDouble(), 100);
    expect(OfflineCacheService().getPendingOperations(), isEmpty);
  });

  test('addExpense queues and shows in cache, drain creates doc', () async {
    final fake = FakeFirebaseFirestore();
    final svc = ExpenseService(firestore: fake);
    OfflineSyncService().firestore = fake;
    final record = ExpenseRecord(
      id: '',
      amount: 55,
      expenseCategory: 'Transport',
      createdAt: DateTime.now(),
      createdBy: 'u1',
      createdByName: 'Tester',
    );
    final opId = await svc.addExpense(record);
    expect(opId, isNotNull);
    expect(
        OfflineCacheService()
            .getPendingOperations()
            .any((o) => o['type'] == 'createExpense'),
        true);
    expect(
        OfflineCacheService()
            .getPendingOperations()
            .any((o) => o['opId'] == opId),
        true);
    expect(OfflineCacheService().getCachedExpenses()?.any((r) => r.id == opId),
        true);
    expect((await fake.collection('expenses').get()).docs.length, 0);
    ConnectivityService().setOnlineForTest(true);
    await OfflineSyncService().syncPendingOperations();
    expect((await fake.collection('expenses').get()).docs.length, 1);
    final doc = (await fake.collection('expenses').get()).docs.first;
    expect((doc.data()['amount'] as num).toDouble(), 55);
    expect(OfflineCacheService().getPendingOperations(), isEmpty);
  });

  test('addIncome is idempotent across two drains', () async {
    final fake = FakeFirebaseFirestore();
    final svc = IncomeService(firestore: fake);
    OfflineSyncService().firestore = fake;
    final record = IncomeRecord(
      id: '',
      kind: IncomeKind.investment,
      amount: 200,
      createdAt: DateTime.now(),
      createdBy: 'u1',
      createdByName: 'Tester',
      viewerId: 'v1',
      viewerName: 'Viewer',
    );
    final opId = await svc.addIncome(record);
    ConnectivityService().setOnlineForTest(true);
    await OfflineSyncService().syncPendingOperations();
    expect((await fake.collection('income_records').doc(opId!).get()).exists,
        true);
    // re-queue same opId simulating crash between commit and dequeue
    final payload = record.toFirestore();
    await OfflineCacheService().queueOperation({
      'opId': opId,
      'type': 'createIncome',
      'docId': opId,
      'payload': payload,
      'queuedAt': DateTime.now().toIso8601String(),
    });
    await OfflineSyncService().syncPendingOperations();
    expect((await fake.collection('income_records').get()).docs.length, 1);
    expect(OfflineCacheService().getPendingOperations(), isEmpty);
  });

  test('getExpensesForDay returns only records in that calendar day', () async {
    final fake = FakeFirebaseFirestore();
    final svc = ExpenseService(firestore: fake);
    final day = DateTime(2026, 2, 10);
    final nextDay = day.add(const Duration(days: 1));
    for (var i = 0; i < 3; i++) {
      await fake.collection('expenses').doc('exp-$i').set({
        'amount': 10.0 + i,
        'expenseCategory': 'Transport',
        'createdAt':
            day.millisecondsSinceEpoch + Duration(hours: 1 + i).inMilliseconds,
        'createdBy': 'u1',
        'createdByName': 'Tester',
      });
    }
    await fake.collection('expenses').doc('exp-next-day').set({
      'amount': 99.0,
      'expenseCategory': 'Food',
      'createdAt': nextDay.millisecondsSinceEpoch,
      'createdBy': 'u1',
      'createdByName': 'Tester',
    });
    final items = await svc.getExpensesForDay(day);
    expect(items.length, 3);
    expect(items.map((r) => r.id).toSet(), {'exp-0', 'exp-1', 'exp-2'});
    expect(items.first.createdAt.isAfter(items.last.createdAt), true);
  });

  test('getIncomeForDay returns only records in that calendar day', () async {
    final fake = FakeFirebaseFirestore();
    final svc = IncomeService(firestore: fake);
    final day = DateTime(2026, 2, 10);
    final nextDay = day.add(const Duration(days: 1));
    for (var i = 0; i < 2; i++) {
      await fake.collection('income_records').doc('inc-$i').set({
        'kind': 'sale',
        'amount': 20.0 + i,
        'saleCategory': 'Coffee Beans',
        'createdAt':
            day.millisecondsSinceEpoch + Duration(hours: 1 + i).inMilliseconds,
        'createdBy': 'u1',
        'createdByName': 'Tester',
      });
    }
    await fake.collection('income_records').doc('inc-next-day').set({
      'kind': 'sale',
      'amount': 50.0,
      'saleCategory': 'Coffee Beans',
      'createdAt': nextDay.millisecondsSinceEpoch,
      'createdBy': 'u1',
      'createdByName': 'Tester',
    });
    final items = await svc.getIncomeForDay(day);
    expect(items.length, 2);
    expect(items.map((r) => r.id).toSet(), {'inc-0', 'inc-1'});
    expect(items.first.createdAt.isAfter(items.last.createdAt), true);
  });
}
