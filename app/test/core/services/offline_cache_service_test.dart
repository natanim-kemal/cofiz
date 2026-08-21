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

  group('per-document storage', () {
    test('transactions are stored under per-id keys, not one legacy key',
        () async {
      final tx = MoneyTransaction(
        id: 'perkey-1',
        workerId: 'w1',
        workerName: 'Alice',
        type: 'return',
        amount: 10,
        createdAt: DateTime(2026, 8, 1),
        createdBy: 'u1',
      );
      await OfflineCacheService().cacheTransactions([tx]);

      final box = Hive.box('transactions_cache');
      expect(box.get('perkey-1'), isNotNull);
      expect(box.get('all_transactions'), isNull);
    });

    test('legacy single-key snapshot migrates to per-id keys on read',
        () async {
      final legacyTx = MoneyTransaction(
        id: 'legacy-1',
        workerId: 'w1',
        workerName: 'Alice',
        type: 'distribution',
        amount: 42,
        createdAt: DateTime(2026, 8, 1),
        createdBy: 'u1',
      ).toJson();
      final box = Hive.box('transactions_cache');
      await box.put('all_transactions', {'legacy-1': legacyTx});

      final cached = OfflineCacheService().getCachedTransactions();
      expect(cached!.length, 1);
      expect(cached.first.id, 'legacy-1');
      // Migration write-back removes the legacy key.
      await Future<void>.delayed(Duration.zero);
      expect(box.get('all_transactions'), isNull);
      expect(box.get('legacy-1'), isNotNull);
    });

    test('re-caching a smaller set deletes removed documents', () async {
      MoneyTransaction tx(String id) => MoneyTransaction(
            id: id,
            workerId: 'w1',
            workerName: 'Alice',
            type: 'distribution',
            amount: 5,
            createdAt: DateTime(2026, 8, 1),
            createdBy: 'u1',
          );
      await OfflineCacheService().cacheTransactions([tx('keep'), tx('drop')]);
      await OfflineCacheService().cacheTransactions([tx('keep')]);

      final cached = OfflineCacheService().getCachedTransactions()!;
      expect(cached.length, 1);
      expect(cached.first.id, 'keep');
    });
  });

  group('fetched-at metadata', () {
    test('markFetched records timestamp and isStale reflects it', () async {
      expect(OfflineCacheService().getFetchedAt('test_ds'), isNull);
      expect(
        OfflineCacheService().isStale('test_ds'),
        isTrue,
        reason: 'never-fetched datasets are stale',
      );

      await OfflineCacheService().markFetched('test_ds');

      expect(OfflineCacheService().getFetchedAt('test_ds'), isNotNull);
      expect(
        OfflineCacheService()
            .isStale('test_ds', maxAge: const Duration(hours: 1)),
        isFalse,
      );
      expect(
        OfflineCacheService().isStale('test_ds', maxAge: Duration.zero),
        isTrue,
        reason: 'any elapsed time past a zero max-age counts as stale',
      );
    });

    test('caching a collection marks it fetched', () async {
      await OfflineCacheService().clearAllCache();
      expect(
        OfflineCacheService().isStale(OfflineCacheService.dsTransactions,
            maxAge: const Duration(hours: 1)),
        isTrue,
      );

      await OfflineCacheService().cacheTransactions([
        MoneyTransaction(
          id: 'fresh-1',
          workerId: 'w1',
          workerName: 'Alice',
          type: 'return',
          amount: 3,
          createdAt: DateTime.now(),
          createdBy: 'u1',
        ),
      ]);

      expect(
        OfflineCacheService().isStale(OfflineCacheService.dsTransactions,
            maxAge: const Duration(hours: 1)),
        isFalse,
      );
    });
  });

  group('worker transactions cache', () {
    test('round-trip and replace semantics', () async {
      MoneyTransaction tx(String id, DateTime at) => MoneyTransaction(
            id: id,
            workerId: 'w9',
            workerName: 'Bob',
            type: 'purchase',
            amount: 7,
            createdAt: at,
            createdBy: 'u1',
          );

      await OfflineCacheService().cacheWorkerTransactions('w9', [
        tx('a', DateTime(2026, 8, 2)),
        tx('b', DateTime(2026, 8, 1)),
      ]);
      var cached = OfflineCacheService().getCachedWorkerTransactions('w9');
      expect(cached.length, 2);
      expect(cached.map((t) => t.id), containsAll(['a', 'b']));

      // Replacing with a subset drops the removed doc.
      await OfflineCacheService()
          .cacheWorkerTransactions('w9', [tx('b', DateTime(2026, 8, 1))]);
      cached = OfflineCacheService().getCachedWorkerTransactions('w9');
      expect(cached.length, 1);
      expect(cached.first.id, 'b');
    });

    test('workers are isolated from each other', () async {
      MoneyTransaction txFor(String workerId, String id) => MoneyTransaction(
            id: id,
            workerId: workerId,
            workerName: 'N',
            type: 'distribution',
            amount: 1,
            createdAt: DateTime(2026, 8, 1),
            createdBy: 'u1',
          );
      await OfflineCacheService()
          .cacheWorkerTransactions('wa', [txFor('wa', 'x')]);
      await OfflineCacheService()
          .cacheWorkerTransactions('wb', [txFor('wb', 'y')]);

      expect(OfflineCacheService().getCachedWorkerTransactions('wa').length, 1);
      expect(OfflineCacheService().getCachedWorkerTransactions('wb').length, 1);
      expect(
        OfflineCacheService().getCachedWorkerTransactions('wa').first.id,
        'x',
      );
    });

    test('records older than retention window are evicted', () async {
      await OfflineCacheService().cacheWorkerTransactions('wc', [
        MoneyTransaction(
          id: 'old',
          workerId: 'wc',
          workerName: 'C',
          type: 'return',
          amount: 2,
          createdAt: DateTime.now().subtract(const Duration(days: 400)),
          createdBy: 'u1',
        ),
      ]);
      expect(OfflineCacheService().getCachedWorkerTransactions('wc'), isEmpty);
    });
  });

  group('worker profile cache', () {
    Worker profile(String id) => Worker(
          id: id,
          name: 'Profile $id',
          phone: '09',
          role: 'Worker',
          status: 'active',
          createdAt: DateTime(2026, 8, 1),
          currentBalance: 12,
        );

    test('round-trip by id', () async {
      await OfflineCacheService().cacheWorkerProfile(profile('p1'));

      final cached =
          OfflineCacheService().getCachedWorkerProfile(expectedId: 'p1');
      expect(cached, isNotNull);
      expect(cached!.id, 'p1');
      expect(cached.name, 'Profile p1');
      expect(cached.currentBalance, 12);
    });

    test('mismatched expectedId returns null', () async {
      await OfflineCacheService().cacheWorkerProfile(profile('p2'));
      expect(
        OfflineCacheService().getCachedWorkerProfile(expectedId: 'other'),
        isNull,
      );
    });

    test('null expectedId returns any cached profile', () async {
      await OfflineCacheService().clearAllCache();
      await OfflineCacheService().cacheWorkerProfile(profile('p3'));
      expect(
        OfflineCacheService().getCachedWorkerProfile()?.id,
        'p3',
      );
    });

    test('profile survives workers-collection replacement', () async {
      await OfflineCacheService().clearAllCache();
      await OfflineCacheService().cacheWorkerProfile(profile('keep-me'));

      await OfflineCacheService().cacheWorkers([
        Worker(
          id: 'w1',
          name: 'Alice',
          phone: '09',
          role: 'Worker',
          status: 'active',
          createdAt: DateTime(2026, 8, 1),
          currentBalance: 0,
        ),
      ]);

      expect(
        OfflineCacheService().getCachedWorkerProfile(expectedId: 'keep-me'),
        isNotNull,
        reason: 'collection writes must not delete cached profiles',
      );
      // And the collection read excludes profiles.
      expect(OfflineCacheService().getCachedWorkers()!.length, 1);
    });

    test('profiles-only box reports null (never cached), not empty list',
        () async {
      await OfflineCacheService().clearAllCache();
      await OfflineCacheService().cacheWorkerProfile(profile('solo'));

      // Box is non-empty but holds only profile keys: the collection was
      // never cached, so the contract says null - not a cached-empty [].
      expect(OfflineCacheService().getCachedWorkers(), isNull);
    });

    test('null expectedId returns the single unambiguous profile', () async {
      await OfflineCacheService().clearAllCache();
      await OfflineCacheService().cacheWorkerProfile(profile('only'));
      expect(OfflineCacheService().getCachedWorkerProfile()!.id, 'only');
    });

    test(
        'null expectedId with multiple profiles returns null (ambiguous)',
        () async {
      await OfflineCacheService().clearAllCache();
      await OfflineCacheService().cacheWorkerProfile(profile('a'));
      await OfflineCacheService().cacheWorkerProfile(profile('b'));

      expect(OfflineCacheService().getCachedWorkerProfile(), isNull,
          reason:
              'must never surface another account\'s name/balance on a '
              'multi-account device');
    });

    test('worker transaction fetch times are namespaced per worker',
        () async {
      MoneyTransaction tx(String workerId, String id) => MoneyTransaction(
            id: id,
            workerId: workerId,
            workerName: 'N',
            type: 'distribution',
            amount: 1,
            createdAt: DateTime.now(),
            createdBy: 'u1',
          );

      expect(
        OfflineCacheService()
            .getFetchedAt(OfflineCacheService.workerTxDataset('wa')),
        isNull,
      );

      await OfflineCacheService()
          .cacheWorkerTransactions('wa', [tx('wa', 'x')]);

      final waTime = OfflineCacheService()
          .getFetchedAt(OfflineCacheService.workerTxDataset('wa'));
      expect(waTime, isNotNull);
      // Other workers are untouched by wa's fetch.
      expect(
        OfflineCacheService()
            .getFetchedAt(OfflineCacheService.workerTxDataset('wb')),
        isNull,
      );
    });

    test('newestFetchedAt picks the most recent across datasets', () async {
      await OfflineCacheService().markFetched('ds_old');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await OfflineCacheService().markFetched('ds_new');

      final newest = OfflineCacheService()
          .newestFetchedAt(['ds_old', 'ds_new', 'ds_never']);
      expect(newest, isNotNull);
      expect(
        newest,
        OfflineCacheService().getFetchedAt('ds_new'),
      );
      // All-unknown datasets yield null.
      expect(
        OfflineCacheService().newestFetchedAt(['ds_never']),
        isNull,
      );
    });
  });
}
