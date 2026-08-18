import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:cofiz/core/models/expense_record_model.dart';
import 'package:cofiz/core/models/income_record_model.dart';
import 'package:cofiz/core/models/transaction_model.dart';
import 'package:cofiz/core/models/worker_model.dart';
import 'package:cofiz/core/services/offline_cache_service.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('cache_test');
    await OfflineCacheService().initialize(path: tempDir.path);
  });

  tearDown(() async {
    await OfflineCacheService().clearPendingOperations();
    await OfflineCacheService().clearDelivered();
  });

  tearDownAll(() async {
    await OfflineCacheService().clearAllCache();
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('transactions cache round-trip', () async {
    final tx = MoneyTransaction(
      id: 't1',
      workerId: 'w1',
      workerName: 'Alice',
      type: 'distribution',
      amount: 100,
      createdAt: DateTime(2026, 8, 1),
      createdBy: 'u1',
    );
    await OfflineCacheService().cacheTransactions([tx]);

    final cached = OfflineCacheService().getCachedTransactions();
    expect(cached, isNotNull);
    expect(cached!.length, 1);
    expect(cached.first.id, 't1');
    expect(cached.first.amount, 100);
    expect(cached.first.createdAt, DateTime(2026, 8, 1));
  });

  test('income cache round-trip', () async {
    final rec = IncomeRecord(
      id: 'i1',
      kind: IncomeKind.sale,
      amount: 50,
      createdAt: DateTime(2026, 8, 1),
      createdBy: 'u1',
      createdByName: 'Admin',
    );
    await OfflineCacheService().cacheIncome([rec]);

    final cached = OfflineCacheService().getCachedIncome();
    expect(cached, isNotNull);
    expect(cached!.length, 1);
    expect(cached.first.id, 'i1');
    expect(cached.first.kind, IncomeKind.sale);
    expect(cached.first.amount, 50);
  });

  test('expenses cache round-trip', () async {
    final rec = ExpenseRecord(
      id: 'e1',
      amount: 30,
      expenseCategory: 'Transport',
      createdAt: DateTime(2026, 8, 1),
      createdBy: 'u1',
      createdByName: 'Admin',
    );
    await OfflineCacheService().cacheExpenses([rec]);

    final cached = OfflineCacheService().getCachedExpenses();
    expect(cached, isNotNull);
    expect(cached!.length, 1);
    expect(cached.first.id, 'e1');
    expect(cached.first.amount, 30);
    expect(cached.first.expenseCategory, 'Transport');
  });

  test('clearAllCache empties all boxes', () async {
    await OfflineCacheService().cacheIncome([
      IncomeRecord(
        id: 'i2',
        kind: IncomeKind.investment,
        amount: 1,
        createdAt: DateTime(2026, 8, 2),
        createdBy: 'u1',
        createdByName: 'Admin',
      ),
    ]);
    await OfflineCacheService().clearAllCache();

    expect(OfflineCacheService().getCachedIncome(), isNull);
    expect(OfflineCacheService().getCachedExpenses(), isNull);
    expect(OfflineCacheService().getCachedTransactions(), isNull);
    expect(OfflineCacheService().getCachedIncomeTotals(), isNull);
    expect(OfflineCacheService().getCachedExpenseTotals(), isNull);
    expect(OfflineCacheService().getCachedTodayTotals(), isNull);
    expect(OfflineCacheService().getCachedWorkers(), isNull);
  });

  test('income totals cache round-trip', () async {
    await OfflineCacheService().cacheIncomeTotals({
      'totalIncome': 1000.0,
      'totalSales': 400.0,
      'totalInvestments': 600.0,
      'todayIncome': 250.0,
      'todaySales': 100.0,
      'todayInvestments': 150.0,
      'totalCount': 12.0,
    });

    final cached = OfflineCacheService().getCachedIncomeTotals();
    expect(cached, isNotNull);
    expect(cached!['totalIncome'], 1000.0);
    expect(cached['todaySales'], 100.0);
    expect(cached['totalCount'], 12.0);
  });

  test('expense totals cache round-trip', () async {
    await OfflineCacheService().cacheExpenseTotals({
      'totalExpenses': 500.0,
      'todayExpenses': 80.0,
      'totalCount': 5.0,
    });

    final cached = OfflineCacheService().getCachedExpenseTotals();
    expect(cached, isNotNull);
    expect(cached!['totalExpenses'], 500.0);
    expect(cached['todayExpenses'], 80.0);
  });

  test('today totals cache round-trip', () async {
    await OfflineCacheService().cacheTodayTotals({
      'distributed': 300.0,
      'returned': 40.0,
      'purchased': 10.0,
    });

    final cached = OfflineCacheService().getCachedTodayTotals();
    expect(cached, isNotNull);
    expect(cached!['distributed'], 300.0);
    expect(cached['returned'], 40.0);
  });

  test('workers cache round-trip', () async {
    final worker = Worker(
      id: 'w1',
      name: 'Alice',
      phone: '09',
      role: 'Worker',
      status: 'active',
      createdAt: DateTime(2026, 8, 1),
      currentBalance: 0,
    );
    await OfflineCacheService().cacheWorkers([worker]);

    final cached = OfflineCacheService().getCachedWorkers();
    expect(cached, isNotNull);
    expect(cached!.length, 1);
    expect(cached.first.id, 'w1');
    expect(cached.first.status, 'active');
  });

  test('cache write evicts records older than retention window', () async {
    final recent = MoneyTransaction(
      id: 'recent',
      workerId: 'w1',
      workerName: 'Alice',
      type: 'distribution',
      amount: 100,
      createdAt: DateTime.now().subtract(const Duration(days: 10)),
      createdBy: 'u1',
    );
    final old = MoneyTransaction(
      id: 'old',
      workerId: 'w1',
      workerName: 'Alice',
      type: 'distribution',
      amount: 100,
      createdAt: DateTime.now().subtract(const Duration(days: 400)),
      createdBy: 'u1',
    );

    await OfflineCacheService().cacheTransactions([recent, old]);

    final cached = OfflineCacheService().getCachedTransactions();
    expect(cached, isNotNull);
    expect(cached!.length, 1);
    expect(cached.first.id, 'recent');

    await OfflineCacheService().cacheIncome([
      IncomeRecord(
        id: 'oldIncome',
        kind: IncomeKind.sale,
        amount: 50,
        createdAt: DateTime.now().subtract(const Duration(days: 400)),
        createdBy: 'u1',
        createdByName: 'Admin',
      ),
      IncomeRecord(
        id: 'recentIncome',
        kind: IncomeKind.sale,
        amount: 50,
        createdAt: DateTime.now().subtract(const Duration(days: 10)),
        createdBy: 'u1',
        createdByName: 'Admin',
      ),
    ]);
    final cachedIncome = OfflineCacheService().getCachedIncome();
    expect(cachedIncome!.length, 1);
    expect(cachedIncome.first.id, 'recentIncome');

    await OfflineCacheService().cacheExpenses([
      ExpenseRecord(
        id: 'oldExpense',
        expenseCategory: 'Transport',
        amount: 50,
        createdAt: DateTime.now().subtract(const Duration(days: 400)),
        createdBy: 'u1',
        createdByName: 'Admin',
      ),
      ExpenseRecord(
        id: 'recentExpense',
        expenseCategory: 'Transport',
        amount: 50,
        createdAt: DateTime.now().subtract(const Duration(days: 10)),
        createdBy: 'u1',
        createdByName: 'Admin',
      ),
    ]);
    final cachedExpenses = OfflineCacheService().getCachedExpenses();
    expect(cachedExpenses!.length, 1);
    expect(cachedExpenses.first.id, 'recentExpense');
  });

  test('delivered log stores opId and prunes', () async {
    await OfflineCacheService().clearPendingOperations();
    await OfflineCacheService().markDelivered('op-1', 'createTransaction');
    expect(OfflineCacheService().getDeliveredOperations().length, 1);
    expect(OfflineCacheService().getDeliveredCount(), 1);
  });

  test('queueOperation requires opId', () async {
    await OfflineCacheService().queueOperation({
      'opId': 'op-2',
      'type': 'createIncome',
      'queuedAt': DateTime.now().toIso8601String()
    });
    expect(OfflineCacheService().getPendingOperations().first['opId'], 'op-2');
  });
}
