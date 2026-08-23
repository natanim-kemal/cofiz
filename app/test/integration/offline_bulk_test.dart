import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cofiz/core/models/expense_record_model.dart';
import 'package:cofiz/core/models/income_record_model.dart';
import 'package:cofiz/core/providers/expense_provider.dart';
import 'package:cofiz/core/providers/income_provider.dart';
import 'package:cofiz/core/services/connectivity_service.dart';
import 'package:cofiz/core/services/expense_service.dart';
import 'package:cofiz/core/services/income_service.dart';
import 'package:cofiz/core/services/offline_cache_service.dart';
import 'package:cofiz/core/services/offline_sync_service.dart';
import 'package:cofiz/presentation/widgets/sync_outbox_banner.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tempDir;
  late FakeFirebaseFirestore firestore;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('offline_bulk');
    await OfflineCacheService().initialize(path: tempDir.path);
  });

  // Real Hive I/O can stall inside a widget test's FakeAsync zone;
  // route every box write through runAsync.
  Future<void> writeCache(Future<void> Function() action) =>
      TestWidgetsFlutterBinding.instance.runAsync(action);

  setUp(() async {
    await writeCache(() => OfflineCacheService().clearAllCache());
    ConnectivityService().setOnlineForTest(false);
    firestore = FakeFirebaseFirestore();
    OfflineSyncService().firestore = firestore;
  });

  tearDown(() async {
    await writeCache(() => OfflineCacheService().clearAllCache());
    ConnectivityService().setOnlineForTest(true);
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  IncomeRecord income(double amount) => IncomeRecord(
        id: '',
        kind: IncomeKind.sale,
        amount: amount,
        createdAt: DateTime.now(),
        createdBy: 'u1',
        createdByName: 'Tester',
        saleCategory: 'Coffee Beans',
      );

  ExpenseRecord expense(double amount) => ExpenseRecord(
        id: '',
        amount: amount,
        expenseCategory: 'Transport',
        createdAt: DateTime.now(),
        createdBy: 'u1',
        createdByName: 'Tester',
      );

  test('airplane mode: bulk creates + deletes coalesce, reconnect drains all',
      () async {
    final incomes =
        IncomeProvider(service: IncomeService(firestore: firestore));
    final expenses =
        ExpenseProvider(service: ExpenseService(firestore: firestore));

    // Create 3 incomes + 2 expenses while "offline".
    for (var i = 1; i <= 3; i++) {
      await incomes.addIncome(income(10.0 * i));
    }
    await expenses.addExpense(expense(5));
    await expenses.addExpense(expense(7));
    expect(OfflineCacheService().getPendingOperations().length, 5);

    // Delete two of the still-pending incomes before reconnecting.
    final ids = incomes.records.map((r) => r.id).toList();
    await incomes.deleteIncome(ids[0]);
    await incomes.deleteIncome(ids[1]);

    ConnectivityService().setOnlineForTest(true);
    await OfflineSyncService().syncPendingOperations();

    // Coalesce drops create+delete pairs entirely; only the untouched
    // income survives, both expenses land.
    expect(
      (await firestore.collection('income_records').get()).docs.length,
      1,
    );
    expect(
      (await firestore.collection('expenses').get()).docs.length,
      2,
    );
    expect(OfflineCacheService().getPendingOperations(), isEmpty);
    expect(OfflineCacheService().getFailedOperations(), isEmpty);
  });

  testWidgets('SyncOutboxBanner shows pending and failed counts',
      (tester) async {
    await writeCache(() => OfflineCacheService().queueOperation({
          'opId': 'p1',
          'type': 'createIncome',
          'docId': 'd1',
          'attempts': 0,
        }));
    await writeCache(() => OfflineCacheService()
        .markFailed({'opId': 'f1', 'type': 'createExpense'}, 'boom'));

    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: Column(children: [
      SyncOutboxBanner(),
    ]))));
    await tester.pumpAndSettle();

    expect(find.textContaining('1 pending'), findsOneWidget);
    expect(find.textContaining('1 failed'), findsOneWidget);
  });

  testWidgets('SyncOutboxBanner hidden when outbox empty', (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SyncOutboxBanner())));
    await tester.pumpAndSettle();

    expect(find.textContaining('pending'), findsNothing);
    expect(find.textContaining('failed'), findsNothing);
    expect(find.byKey(const Key('outbox_retry')), findsNothing);
  });

  testWidgets('Discard button discards the failed operation', (tester) async {
    await writeCache(() => OfflineCacheService()
        .markFailed({'opId': 'f1', 'type': 'createExpense'}, 'boom'));
    String? discarded;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SyncOutboxBanner(
          onDiscard: (opId) => discarded = opId,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('discard_f1')));
    await tester.pump();

    expect(discarded, 'f1');
  });

  test('discardFailed removes the failed operation from the box', () async {
    await OfflineCacheService()
        .markFailed({'opId': 'f2', 'type': 'createExpense'}, 'boom');
    expect(OfflineCacheService().getFailedOperations().length, 1);
    await OfflineCacheService().discardFailed('f2');
    expect(OfflineCacheService().getFailedOperations(), isEmpty);
  });

  test(
      'discardFailed on a failed createIncome evicts the cache copy '
      'and tombstones the opId', () async {
    final record = IncomeRecord(
      id: 'inc9',
      kind: IncomeKind.sale,
      amount: 12,
      createdAt: DateTime.now(),
      createdBy: 'u1',
      createdByName: 'Tester',
      saleCategory: 'Coffee Beans',
    );
    await OfflineCacheService().cacheIncome([record]);
    await OfflineCacheService().markFailed(
      {'opId': 'f3', 'type': 'createIncome', 'docId': 'inc9'},
      'boom',
    );

    await OfflineCacheService().discardFailed('f3');

    // Optimistic copy gone - it cannot resurface after restart.
    final cached = OfflineCacheService().getCachedIncome() ?? [];
    expect(cached.where((r) => r.id == 'inc9'), isEmpty);
    expect(OfflineCacheService().getFailedOperations(), isEmpty);

    // Tombstoned: a sync merge-back cannot resurrect the discarded op.
    await OfflineCacheService().replacePendingOperations([
      {'opId': 'f3', 'type': 'createIncome', 'docId': 'inc9'}
    ]);
    expect(OfflineCacheService().getPendingOperations(), isEmpty);
  });

  testWidgets('Retry button invokes onRetry callback', (tester) async {
    await writeCache(() => OfflineCacheService().queueOperation({
          'opId': 'p1',
          'type': 'createIncome',
          'docId': 'd1',
          'attempts': 0,
        }));
    var retried = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SyncOutboxBanner(onRetry: () => retried++),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(retried, 1);
  });
}
