import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:cofiz/core/models/income_record_model.dart';
import 'package:cofiz/core/models/expense_record_model.dart';
import 'package:cofiz/core/providers/income_provider.dart';
import 'package:cofiz/core/providers/expense_provider.dart';
import 'package:cofiz/core/services/income_service.dart';
import 'package:cofiz/core/services/expense_service.dart';
import 'package:cofiz/core/services/offline_cache_service.dart';

/// Aggregate methods backed by a queue of [Completer]s so tests control
/// exactly when each refresh's queries resolve.
class FakeIncomeService extends IncomeService {
  final totalQueue = <Completer<double?>>[];

  FakeIncomeService() : super(firestore: FakeFirebaseFirestore());

  @override
  Future<double?> getIncomeTotal({String? viewerId}) async {
    if (totalQueue.isNotEmpty) return totalQueue.removeAt(0).future;
    return null;
  }

  @override
  Future<double?> getIncomeTotalByKind(IncomeKind kind,
          {String? viewerId}) async =>
      null;

  @override
  Future<double?> getIncomeTodayTotal({String? viewerId}) async => null;

  @override
  Future<double?> getIncomeTodayTotalByKind(IncomeKind kind,
          {String? viewerId}) async =>
      null;

  @override
  Future<int?> getIncomeCount({String? viewerId}) async => 0;

  @override
  Stream<List<IncomeRecord>> getIncomePageStream({int limit = 20}) =>
      const Stream.empty();

  @override
  Future<List<IncomeRecord>> getAllIncome() async => const [];

  @override
  Future<List<IncomeRecord>> getIncomeForDay(DateTime day) async => const [];
}

/// Real queueing behaviour (OfflineCacheService + sync trigger); Firestore
/// handle is a fake so the queued op simply never drains in-test.
class QueueingIncomeService extends IncomeService {
  QueueingIncomeService() : super(firestore: FakeFirebaseFirestore());
}

class FakeExpenseService extends ExpenseService {
  final totalQueue = <Completer<double?>>[];

  FakeExpenseService() : super(firestore: FakeFirebaseFirestore());

  @override
  Future<double?> getExpensesTotal() async {
    if (totalQueue.isNotEmpty) return totalQueue.removeAt(0).future;
    return null;
  }

  @override
  Future<double?> getExpensesTodayTotal() async => null;

  @override
  Future<int?> getExpensesCount() async => 0;

  @override
  Stream<List<ExpenseRecord>> getExpensesPageStream({int limit = 20}) =>
      const Stream.empty();

  @override
  Future<List<ExpenseRecord>> getAllExpenses() async => const [];

  @override
  Future<List<ExpenseRecord>> getExpensesForDay(DateTime day) async =>
      const [];
}

class QueueingExpenseService extends ExpenseService {
  QueueingExpenseService() : super(firestore: FakeFirebaseFirestore());
}

/// Real service except the page stream comes from a test-controlled
/// controller, simulating server snapshots arriving before/after commit.
class StreamControlledIncomeService extends IncomeService {
  final Stream<List<IncomeRecord>> stream;
  StreamControlledIncomeService(this.stream)
      : super(firestore: FakeFirebaseFirestore());

  @override
  Stream<List<IncomeRecord>> getIncomePageStream({int limit = 20}) => stream;

  @override
  Future<double?> getIncomeTotal({String? viewerId}) async => null;

  @override
  Future<double?> getIncomeTotalByKind(IncomeKind kind,
          {String? viewerId}) async =>
      null;

  @override
  Future<double?> getIncomeTodayTotal({String? viewerId}) async => null;

  @override
  Future<double?> getIncomeTodayTotalByKind(IncomeKind kind,
          {String? viewerId}) async =>
      null;

  @override
  Future<int?> getIncomeCount({String? viewerId}) async => null;
}

class StreamControlledExpenseService extends ExpenseService {
  final Stream<List<ExpenseRecord>> stream;
  StreamControlledExpenseService(this.stream)
      : super(firestore: FakeFirebaseFirestore());

  @override
  Stream<List<ExpenseRecord>> getExpensesPageStream({int limit = 20}) =>
      stream;

  @override
  Future<double?> getExpensesTotal() async => null;

  @override
  Future<double?> getExpensesTodayTotal() async => null;

  @override
  Future<int?> getExpensesCount() async => null;
}

/// Aggregate queries that SUCCEED with values that predate the pending
/// create (the "write not committed yet" case on a real device). The
/// provider must reconcile these with pending amounts, never revert.
class StaleAggregateIncomeService extends IncomeService {
  StaleAggregateIncomeService() : super(firestore: FakeFirebaseFirestore());

  @override
  Future<double?> getIncomeTotal({String? viewerId}) async => 100.0;

  @override
  Future<double?> getIncomeTotalByKind(IncomeKind kind,
          {String? viewerId}) async =>
      0.0;

  @override
  Future<double?> getIncomeTodayTotal({String? viewerId}) async => 0.0;

  @override
  Future<double?> getIncomeTodayTotalByKind(IncomeKind kind,
          {String? viewerId}) async =>
      0.0;

  @override
  Future<int?> getIncomeCount({String? viewerId}) async => 1;

  @override
  Stream<List<IncomeRecord>> getIncomePageStream({int limit = 20}) =>
      const Stream.empty();

  @override
  Future<List<IncomeRecord>> getAllIncome() async => const [];

  @override
  Future<List<IncomeRecord>> getIncomeForDay(DateTime day) async => const [];
}

class StaleAggregateExpenseService extends ExpenseService {
  StaleAggregateExpenseService() : super(firestore: FakeFirebaseFirestore());

  @override
  Future<double?> getExpensesTotal() async => 40.0;

  @override
  Future<double?> getExpensesTodayTotal() async => 40.0;

  @override
  Future<int?> getExpensesCount() async => 2;

  @override
  Stream<List<ExpenseRecord>> getExpensesPageStream({int limit = 20}) =>
      const Stream.empty();

  @override
  Future<List<ExpenseRecord>> getAllExpenses() async => const [];

  @override
  Future<List<ExpenseRecord>> getExpensesForDay(DateTime day) async =>
      const [];
}

IncomeRecord investment(double amount, {String id = ''}) => IncomeRecord(
      id: id,
      kind: IncomeKind.investment,
      amount: amount,
      createdAt: DateTime.now(),
      createdBy: 'u1',
      createdByName: 'Admin',
    );

ExpenseRecord expense(double amount, {String id = ''}) => ExpenseRecord(
      id: id,
      amount: amount,
      expenseCategory: 'Transport',
      createdAt: DateTime.now(),
      createdBy: 'u1',
      createdByName: 'Admin',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('totals_race');
    await OfflineCacheService().initialize(path: tempDir.path);
  });

  tearDown(() async {
    await OfflineCacheService().clearAllCache();
  });

  tearDownAll(() async {
    await OfflineCacheService().clearAllCache();
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('IncomeProvider totals', () {
    test('add optimistically bumps every affected total immediately',
        () async {
      final provider =
          IncomeProvider(service: FakeIncomeService());

      await provider.addIncome(investment(500));

      expect(provider.totalIncome, 500.0);
      expect(provider.totalInvestments, 500.0);
      expect(provider.todayInvestmentIncome, 500.0);
      expect(provider.todayIncome, 500.0);
      expect(provider.totalRecordCount, 1);
      expect(provider.records.first.amount, 500.0);
    });

    test('stale in-flight refresh cannot clobber fresher totals', () async {
      final svc = FakeIncomeService();
      final provider = IncomeProvider(service: svc);

      // Refresh A (from initialize) hangs on its first aggregate query.
      final stale = Completer<double?>();
      svc.totalQueue.add(stale);
      provider.initialize();

      // Add happens while A is in flight: optimistic bump to 500, then
      // refresh B runs (its own queries resolve null -> keep live values).
      await provider.addIncome(investment(500));
      await Future<void>.delayed(Duration.zero);

      // Stale A finally resolves with the OLD server total.
      stale.complete(1000.0);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(provider.totalIncome, 500.0,
          reason: 'a stale refresh must never overwrite newer totals');
    });

    test('seed from cache does not flash stale values over live ones',
        () async {
      await OfflineCacheService().cacheIncomeTotals({
        'totalIncome': 9999.0,
        'totalCount': 99.0,
      });
      final provider =
          IncomeProvider(service: FakeIncomeService());

      await provider.addIncome(investment(300));
      // Any later refresh would seed the cache first; the guard must skip
      // seeding because live values already exist.
      provider.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(provider.totalIncome, 300.0,
          reason: 'cache seed must not clobber live totals mid-session');
    });

    test('delete decrements totals and cancels a pending create', () async {
      final svc = QueueingIncomeService();
      final provider = IncomeProvider(service: svc);

      await provider.addIncome(investment(700));
      final id = provider.records.first.id;
      expect(provider.totalIncome, 700.0);
      expect(
        OfflineCacheService()
            .getPendingOperations()
            .any((op) => op['opId'] == id),
        isTrue,
        reason: 'precondition: create op still queued (not synced)',
      );

      await provider.deleteIncome(id);

      // Without cancelling the queued create, the next sync re-creates the
      // record and total income goes back UP after the delete.
      expect(
        OfflineCacheService()
            .getPendingOperations()
            .any((op) =>
                op['opId'] == id &&
                (op['type'] == 'createIncome' ||
                    op['type'] == 'createExpense')),
        isFalse,
        reason: 'deleting an unsynced record must cancel its queued create',
      );
      expect(
        OfflineCacheService().getPendingOperations().any((op) =>
            op['opId'] == id && op['type'].toString().startsWith('delete')),
        isTrue,
        reason: 'offline delete must be queued for sync',
      );
      // Optimistic decrement lands instantly; let the reconciling refresh
      // (fired fire-and-forget by deleteIncome) finish before asserting.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(provider.totalIncome, 0.0);
    });

    test('optimistic record survives a stream emission that lacks it',
        () async {
      final controller =
          StreamController<List<IncomeRecord>>.broadcast();
      final provider = IncomeProvider(
          service: StreamControlledIncomeService(controller.stream));

      provider.initialize();
      await provider.addIncome(investment(250));
      final id = provider.records.first.id;
      expect(provider.records.any((r) => r.id == id), isTrue);

      // Server snapshot taken BEFORE the sync commit: doc not there yet.
      controller.add(<IncomeRecord>[]);
      await Future<void>.delayed(Duration.zero);
      expect(provider.records.any((r) => r.id == id), isTrue,
          reason: 'pending optimistic row must not be wiped');

      // Server confirms the record.
      controller.add([investment(250, id: id)]);
      await Future<void>.delayed(Duration.zero);
      expect(provider.records.any((r) => r.id == id), isTrue);

      // Confirmed once, a later snapshot without it means real deletion.
      controller.add(<IncomeRecord>[]);
      await Future<void>.delayed(Duration.zero);
      expect(provider.records.any((r) => r.id == id), isFalse);

      await controller.close();
    });

    test('successful-but-stale aggregate cannot revert the optimistic total',
        () async {
      // Server write hasn't committed yet, but the aggregate query succeeds
      // with the pre-write total (100 + 0 pending on the server). Reconcile
      // must keep the UI at server+pending = 800, not flash back to 100.
      final provider =
          IncomeProvider(service: StaleAggregateIncomeService());

      await provider.addIncome(investment(700));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(provider.totalIncome, 800.0,
          reason: 'stale-but-successful aggregate must not revert the total');
      expect(provider.totalRecordCount, 2,
          reason: 'pending count must be added on top of server count');
    });

    test('delete removes the row, cache copy and queued op', () async {
      final svc = QueueingIncomeService();
      final provider = IncomeProvider(service: svc);

      await provider.addIncome(investment(700));
      final id = provider.records.first.id;
      expect(
        OfflineCacheService().getCachedIncome()?.any((r) => r.id == id),
        isTrue,
        reason: 'precondition: optimistic record is in the cache',
      );

      await provider.deleteIncome(id);

      expect(provider.records.any((r) => r.id == id), isFalse,
          reason: 'the row must disappear immediately, no stream emission');
      expect(provider.fullRecords.any((r) => r.id == id), isFalse);
      final cachedAfter = OfflineCacheService().getCachedIncome() ?? [];
      expect(cachedAfter.any((r) => r.id == id), isFalse,
          reason: 'deleted record must not resurface from cache after restart');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(provider.totalIncome, 0.0);
    });
  });

  group('ExpenseProvider totals', () {
    test('add optimistically bumps totals immediately', () async {
      final provider = ExpenseProvider(service: FakeExpenseService());

      await provider.addExpense(expense(120));

      expect(provider.totalExpenses, 120.0);
      expect(provider.todayExpenses, 120.0);
      expect(provider.totalRecordCount, 1);
    });

    test('stale in-flight refresh cannot clobber fresher totals', () async {
      final svc = FakeExpenseService();
      final provider = ExpenseProvider(service: svc);

      final stale = Completer<double?>();
      svc.totalQueue.add(stale);
      provider.initialize();

      await provider.addExpense(expense(80));
      await Future<void>.delayed(Duration.zero);

      stale.complete(5000.0);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(provider.totalExpenses, 80.0);
    });

    test('delete cancels pending op and decrements totals', () async {
      final svc = QueueingExpenseService();
      final provider = ExpenseProvider(service: svc);

      await provider.addExpense(expense(90));
      final id = provider.records.first.id;
      expect(provider.totalExpenses, 90.0);

      await provider.deleteExpense(id);

      expect(
        OfflineCacheService()
            .getPendingOperations()
            .any((op) =>
                op['opId'] == id &&
                (op['type'] == 'createIncome' ||
                    op['type'] == 'createExpense')),
        isFalse,
        reason: 'deleting an unsynced record must cancel its queued create',
      );
      expect(
        OfflineCacheService().getPendingOperations().any((op) =>
            op['opId'] == id && op['type'].toString().startsWith('delete')),
        isTrue,
        reason: 'offline delete must be queued for sync',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(provider.totalExpenses, 0.0);
    });

    test('optimistic record survives a stream emission that lacks it',
        () async {
      final controller =
          StreamController<List<ExpenseRecord>>.broadcast();
      final provider = ExpenseProvider(
          service: StreamControlledExpenseService(controller.stream));

      provider.initialize();
      await provider.addExpense(expense(45));
      final id = provider.records.first.id;

      controller.add(<ExpenseRecord>[]);
      await Future<void>.delayed(Duration.zero);
      expect(provider.records.any((r) => r.id == id), isTrue);

      controller.add([expense(45, id: id)]);
      await Future<void>.delayed(Duration.zero);
      expect(provider.records.any((r) => r.id == id), isTrue);

      await controller.close();
    });

    test('successful-but-stale aggregate cannot revert the optimistic total',
        () async {
      final provider =
          ExpenseProvider(service: StaleAggregateExpenseService());

      await provider.addExpense(expense(90));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(provider.totalExpenses, 130.0,
          reason: 'stale-but-successful aggregate must not revert the total');
      expect(provider.totalRecordCount, 3,
          reason: 'pending count must be added on top of server count');
    });

    test('delete removes the row, cache copy and queued op', () async {
      final svc = QueueingExpenseService();
      final provider = ExpenseProvider(service: svc);

      await provider.addExpense(expense(90));
      final id = provider.records.first.id;
      expect(
        OfflineCacheService().getCachedExpenses()?.any((r) => r.id == id),
        isTrue,
      );

      await provider.deleteExpense(id);

      expect(provider.records.any((r) => r.id == id), isFalse,
          reason: 'the row must disappear immediately, no stream emission');
      final cachedAfter = OfflineCacheService().getCachedExpenses() ?? [];
      expect(cachedAfter.any((r) => r.id == id), isFalse,
          reason: 'deleted record must not resurface from cache after restart');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(provider.totalExpenses, 0.0);
    });
  });
}
