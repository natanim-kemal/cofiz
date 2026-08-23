import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:cofiz/core/models/expense_record_model.dart';
import 'package:cofiz/core/models/income_record_model.dart';
import 'package:cofiz/core/providers/expense_provider.dart';
import 'package:cofiz/core/providers/income_provider.dart';
import 'package:cofiz/core/services/connectivity_service.dart';
import 'package:cofiz/core/services/expense_service.dart';
import 'package:cofiz/core/services/income_service.dart';
import 'package:cofiz/core/services/offline_cache_service.dart';
import 'package:cofiz/core/services/offline_sync_service.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp
        .createTemp('income_expense_offline_provider');
    await OfflineCacheService().initialize(path: dir.path);
  });

  setUp(() async {
    await OfflineCacheService().clearAllCache();
    ConnectivityService().setOnlineForTest(false);
    OfflineSyncService().firestore = FakeFirebaseFirestore();
  });

  tearDown(() async {
    await OfflineCacheService().clearAllCache();
    ConnectivityService().setOnlineForTest(true);
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  IncomeRecord investment(double amount) => IncomeRecord(
        id: '',
        kind: IncomeKind.investment,
        amount: amount,
        createdAt: DateTime.now(),
        createdBy: 'u',
        createdByName: 'n',
      );

  IncomeRecord sale(double amount) => IncomeRecord(
        id: '',
        kind: IncomeKind.sale,
        amount: amount,
        createdAt: DateTime.now(),
        createdBy: 'u',
        createdByName: 'n',
        saleCategory: 'Other',
      );

  ExpenseRecord expense(double amount) => ExpenseRecord(
        id: '',
        amount: amount,
        expenseCategory: 'Food',
        createdAt: DateTime.now(),
        createdBy: 'u',
        createdByName: 'n',
      );

  test('deleteIncome offline removes row instantly and queues', () async {
    final p = IncomeProvider(
        service: IncomeService(firestore: FakeFirebaseFirestore()));
    await p.addIncome(investment(100));
    expect(p.totalIncome, 100);
    final id = p.records.first.id;

    final ok = await p.deleteIncome(id);

    expect(ok, isTrue);
    expect(p.records.any((r) => r.id == id), isFalse);
    expect(p.fullRecords.any((r) => r.id == id), isFalse);
    expect(p.totalIncome, 0);
    expect(p.totalInvestments, 0);
    expect(
      OfflineCacheService()
          .getPendingOperations()
          .any((o) => o['type'] == 'deleteIncome' && o['opId'] == id),
      isTrue,
    );
  });

  test('updateIncome offline replaces record in _records', () async {
    final p = IncomeProvider(
        service: IncomeService(firestore: FakeFirebaseFirestore()));
    await p.addIncome(sale(100));
    final id = p.records.first.id;

    final updated =
        p.records.first.copyWith(amount: 250, saleCategory: 'Coffee');
    final ok = await p.updateIncome(updated);

    expect(ok, isTrue);
    final row = p.records.firstWhere((r) => r.id == id);
    expect(row.amount, 250);
    expect(row.saleCategory, 'Coffee');
    expect(
      p.fullRecords.firstWhere((r) => r.id == id).amount,
      250,
    );
    // Coalesce may merge the still-pending create with the update into a
    // single createIncome op carrying the final payload.
    final opsForId = OfflineCacheService()
        .getPendingOperations()
        .where((o) => o['opId'] == id)
        .toList();
    expect(opsForId, isNotEmpty);
    expect(
      opsForId.any((o) =>
          (o['type'] == 'updateIncome' && o['payload']['amount'] == 250) ||
          (o['type'] == 'createIncome' && o['payload']['amount'] == 250)),
      isTrue,
    );
  });

  test('deleteExpense offline removes row instantly and queues', () async {
    final p = ExpenseProvider(
        service: ExpenseService(firestore: FakeFirebaseFirestore()));
    await p.addExpense(expense(80));
    expect(p.totalExpenses, 80);
    final id = p.records.first.id;

    final ok = await p.deleteExpense(id);

    expect(ok, isTrue);
    expect(p.records.any((r) => r.id == id), isFalse);
    expect(p.fullRecords.any((r) => r.id == id), isFalse);
    expect(p.totalExpenses, 0);
    expect(
      OfflineCacheService()
          .getPendingOperations()
          .any((o) => o['type'] == 'deleteExpense' && o['opId'] == id),
      isTrue,
    );
  });

  test('updateExpense offline replaces record in _records', () async {
    final p = ExpenseProvider(
        service: ExpenseService(firestore: FakeFirebaseFirestore()));
    await p.addExpense(expense(80));
    final id = p.records.first.id;

    final updated = p.records.first.copyWith(amount: 120);
    final ok = await p.updateExpense(updated);

    expect(ok, isTrue);
    expect(p.records.firstWhere((r) => r.id == id).amount, 120);
    expect(p.fullRecords.firstWhere((r) => r.id == id).amount, 120);
    // Coalesce may merge the still-pending create with the update into a
    // single createExpense op carrying the final payload.
    final opsForId = OfflineCacheService()
        .getPendingOperations()
        .where((o) => o['opId'] == id)
        .toList();
    expect(opsForId, isNotEmpty);
    expect(
      opsForId.any((o) =>
          (o['type'] == 'updateExpense' && o['payload']['amount'] == 120) ||
          (o['type'] == 'createExpense' && o['payload']['amount'] == 120)),
      isTrue,
    );
  });

  test('deleting yesterday income leaves today totals unchanged', () async {
    final p = IncomeProvider(
        service: IncomeService(firestore: FakeFirebaseFirestore()));
    // Seed an OLD record straight into the cache (created yesterday) so no
    // optimistic today-bump ever happened for it.
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    await OfflineCacheService().cacheIncome([
      IncomeRecord(
        id: 'old1',
        kind: IncomeKind.sale,
        amount: 100,
        createdAt: yesterday,
        createdBy: 'u',
        createdByName: 'n',
        saleCategory: 'Other',
      ),
    ]);
    await p.loadFullRecords();
    final beforeToday = p.todayIncome;

    final okDel = await p.deleteIncome('old1');
    expect(okDel, isTrue);
    expect(p.totalIncome, 0);
    // Today figures must NOT move for an old-record delete.
    expect(p.todayIncome, beforeToday);
    expect(p.todayManualSales, beforeToday);
  });

  test('deleting yesterday expense leaves today totals unchanged', () async {
    final p = ExpenseProvider(
        service: ExpenseService(firestore: FakeFirebaseFirestore()));
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    await OfflineCacheService().cacheExpenses([
      ExpenseRecord(
        id: 'old2',
        amount: 80,
        expenseCategory: 'Food',
        createdAt: yesterday,
        createdBy: 'u',
        createdByName: 'n',
      ),
    ]);
    await p.loadFullRecords();
    final beforeToday = p.todayExpenses;

    final okDel = await p.deleteExpense('old2');
    expect(okDel, isTrue);
    expect(p.totalExpenses, 0);
    expect(p.todayExpenses, beforeToday);
  });
}
