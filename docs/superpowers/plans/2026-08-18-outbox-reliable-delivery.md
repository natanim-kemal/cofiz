# Outbox Reliable Delivery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire every transaction/income/expense create through a durable Hive outbox so offline writes survive restarts, drain exactly once via deterministic IDs + Firestore transactions, show pending items immediately, and keep a delivered log for positive ack.

**Architecture:** Queue-first always (generate `opId` at call time, persist to Hive `pending_operations`, optimistically write to Hive caches). Drain in `OfflineSyncService` via `runTransaction` conditional creates keyed on `opId`; successes move to `delivered_operations`, failures stay for retry. Retry triggers: connectivity change + app start + 30s timer. No retry cap, 7-day delivered pruning.

**Tech Stack:** Flutter 3.41 / Dart 3.5, Hive/Hive Flutter, Cloud Firestore 5.4 + `FakeFirebaseFirestore` 3.1, `connectivity_plus`, `provider`, `uuid` (or `crypto`-derived random for opId — avoid new dep if already available via `transaction` timestamp; prefer `uuid: ^4.5.0` if not present).

## Global Constraints

- Scope is transactions + income/expense only (not workers/areas/settings/categories) — per approved spec.
- Retry = timer (30s) + reconnect + app start, no cap — retry forever, `debugPrint` on each attempt.
- Confirmation = idempotent conditional create + delivered log (`delivered_operations` box, pruned after 7 days); ground truth is doc existence, queue length is pending count.
- Optimistic visibility: queued creates must appear in lists immediately via Hive caches.
- Follow existing patterns: constructor seams `({FirebaseFirestore? firestore})` for services, `FakeFirebaseFirestore` in tests, `@visibleForTesting` where needed, `print`/`debugPrint` in catch blocks consistent with file style.

---

## File Structure

- `app/lib/core/services/offline_cache_service.dart` — owns `pending_operations` queue + new `delivered_operations` box, op schema `{opId, type, payload/docId, queuedAt, attempts}`.
- `app/lib/core/services/offline_sync_service.dart` — owns drain, timer, `syncNow()`, idempotent `_executeOperation` via `runTransaction`, delivered-log writes.
- `app/lib/core/services/transaction_service.dart` — `addTransaction`/`addTransfer` become queue-first (deterministic IDs), `approve*` become queue-first-always; injectable `firestore` seam already exists.
- `app/lib/core/services/income_service.dart` / `expense_service.dart` — `addIncome`/`addExpense`/`addTransfer`-like paths become queue-first; add firestore seams.
- `app/lib/core/providers/transaction_provider.dart` / `income_provider.dart` / `expense_provider.dart` — call queue-first service methods; no direct Firestore.
- `app/lib/core/services/connectivity_service.dart` — already has `isOnline` + `setOnlineForTest`.
- `app/lib/presentation/widgets/offline_indicator.dart` — already reads `getPendingOperationsCount()`.
- Tests: `app/test/offline_sync_service_test.dart`, `app/test/transaction_service_test.dart`, `app/test/worker_service_test.dart` (existing), new `app/test/income_expense_outbox_test.dart`.

---

### Task 1: OfflineCacheService delivered log + op schema

**Files:**
- Modify: `app/lib/core/services/offline_cache_service.dart`
- Test: `app/test/offline_cache_service_test.dart` (create if missing)

**Interfaces:**
- Consumes: Hive boxes (`pending_operations`, new `delivered_operations`)
- Produces: `Future<void> markDelivered(String opId, String type)`, `List<Map<String,dynamic>> getDeliveredOperations()`, `int getDeliveredCount()`, `Future<void> pruneDelivered()`, `Future<void> queueOperation` now expects `opId` in every op

- [ ] **Step 1: Write the failing test**

```dart
// app/test/offline_cache_service_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:cofiz/core/services/offline_cache_service.dart';

void main() {
  late Directory tmp;
  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('offline_cache_delivered_test');
    await OfflineCacheService().initialize(path: tmp.path);
  });
  tearDown(() async => OfflineCacheService().clearPendingOperations());
  tearDownAll(() async { await OfflineCacheService().clearAllCache(); await Hive.close(); await tmp.delete(recursive: true); });

  test('delivered log stores opId and prunes', () async {
    await OfflineCacheService().clearPendingOperations();
    // This will fail until delivered box + methods exist
    await OfflineCacheService().markDelivered('op-1', 'createTransaction');
    expect(OfflineCacheService().getDeliveredOperations().length, 1);
    expect(OfflineCacheService().getDeliveredCount(), 1);
  });

  test('queueOperation requires opId', () async {
    await OfflineCacheService().queueOperation({'opId': 'op-2', 'type': 'createIncome', 'queuedAt': DateTime.now().toIso8601String()});
    expect(OfflineCacheService().getPendingOperations().first['opId'], 'op-2');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/offline_cache_service_test.dart -v`
Expected: FAIL — `markDelivered`/`getDeliveredOperations` not found

- [ ] **Step 3: Implement minimal delivered box + methods**

In `app/lib/core/services/offline_cache_service.dart`:
- Add `static const String _deliveredBox = 'delivered_operations';`
- In `initialize()`, open `Hive.openBox(_deliveredBox)` after pending box.
- Add:
```dart
Future<void> markDelivered(String opId, String type) async {
  final box = Hive.box(_deliveredBox);
  await box.put(opId, {'opId': opId, 'type': type, 'deliveredAt': DateTime.now().millisecondsSinceEpoch});
}

List<Map<String, dynamic>> getDeliveredOperations() {
  final box = Hive.box(_deliveredBox);
  return box.values.map((e) => Map<String, dynamic>.from(e as Map)).toList();
}

int getDeliveredCount() => Hive.box(_deliveredBox).length;

Future<void> pruneDelivered({Duration ttl = const Duration(days: 7)}) async {
  final box = Hive.box(_deliveredBox);
  final cutoff = DateTime.now().subtract(ttl).millisecondsSinceEpoch;
  final toDelete = <dynamic>[];
  for (final k in box.keys) {
    final v = Map<String, dynamic>.from(box.get(k) as Map);
    if ((v['deliveredAt'] as int) < cutoff) toDelete.add(k);
  }
  for (final k in toDelete) await box.delete(k);
}
Future<void> clearDelivered() async => Hive.box(_deliveredBox).clear();
```
Include `clearDelivered` in `clearAllCache()`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/offline_cache_service_test.dart -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/services/offline_cache_service.dart app/test/offline_cache_service_test.dart
git commit -m "feat(outbox): delivered log + opId schema in OfflineCacheService"
```

---

### Task 2: OfflineSyncService — timer, syncNow, idempotent drain with delivered ack

**Files:**
- Modify: `app/lib/core/services/offline_sync_service.dart:25-110`
- Test: `app/test/offline_sync_service_test.dart`

**Interfaces:**
- Consumes: `OfflineCacheService.queueOperation/getPendingOperations/replacePendingOperations/markDelivered/pruneDelivered`, `ConnectivityService.isOnline/connectionStatus`, `FirebaseFirestore` via `firestore` getter/setter seam
- Produces: `Future<void> syncNow()`, `Timer`-based periodic drain, `_executeOperation` that is idempotent for `createTransaction/createTransfer/createIncome/createExpense` via `runTransaction` conditional create

- [ ] **Step 1: Write the failing test — idempotent create + timer + delivered log**

```dart
// app/test/offline_sync_service_test.dart (add to existing file or create)
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cofiz/core/services/offline_cache_service.dart';
import 'package:cofiz/core/services/offline_sync_service.dart';
import 'package:cofiz/core/services/connectivity_service.dart';

void main() {
  late Directory tmp;
  late FakeFirebaseFirestore fake;
  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('outbox_sync_test');
    await OfflineCacheService().initialize(path: tmp.path);
  });
  setUp(() async {
    fake = FakeFirebaseFirestore();
    OfflineSyncService().firestore = fake;
    await OfflineCacheService().clearPendingOperations();
    await OfflineCacheService().clearDelivered();
    ConnectivityService().setOnlineForTest(true);
    await fake.collection('workers').doc('w1').set({'currentBalance': 1000.0});
  });
  tearDownAll(() async { await OfflineCacheService().clearAllCache(); await Hive.close(); await tmp.delete(recursive: true); });

  test('createTransaction is idempotent across two drains', () async {
    const opId = 'op-ctest-1';
    await OfflineCacheService().queueOperation({
      'opId': opId, 'type': 'createTransaction',
      'docId': opId, 'workerId': 'w1', 'workerName': 'W1',
      'transactionType': 'distribution', 'amount': 100.0,
      'createdBy': 'tester', 'createdAt': DateTime.now().millisecondsSinceEpoch,
      'queuedAt': DateTime.now().toIso8601String(),
    });
    await OfflineSyncService().syncPendingOperations();
    // First drain delivered
    expect(OfflineCacheService().getPendingOperations().length, 0);
    expect((await fake.collection('transactions').doc(opId).get()).exists, true);
    expect((await fake.collection('workers').doc('w1').get()).data()!['currentBalance'], 1100.0);
    // Re-queue same opId (simulates crash between commit and dequeue) and drain again
    await OfflineCacheService().queueOperation({
      'opId': opId, 'type': 'createTransaction',
      'docId': opId, 'workerId': 'w1', 'workerName': 'W1',
      'transactionType': 'distribution', 'amount': 100.0,
      'createdBy': 'tester', 'createdAt': DateTime.now().millisecondsSinceEpoch,
      'queuedAt': DateTime.now().toIso8601String(),
    });
    await OfflineSyncService().syncPendingOperations();
    expect((await fake.collection('workers').doc('w1').get()).data()!['currentBalance'], 1100.0); // not double
    expect(OfflineCacheService().getPendingOperations().length, 0);
  });

  test('failed op stays for retry, delivered log tracks success', () async {
    await OfflineCacheService().queueOperation({'opId': 'bad', 'type': 'unknownType', 'queuedAt': DateTime.now().toIso8601String()});
    await OfflineSyncService().syncPendingOperations();
    expect(OfflineCacheService().getPendingOperations().length, 1);
    expect(OfflineCacheService().getDeliveredCount(), 0);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/offline_sync_service_test.dart -v`
Expected: FAIL — `createTransaction` type not handled / delivered methods missing / second drain double-increments

- [ ] **Step 3: Implement minimal idempotent drain + timer + delivered**

In `app/lib/core/services/offline_sync_service.dart`:
- Add `import 'dart:async';`
- Add field `Timer? _periodicTimer;` and in `initialize()` after connectivity listener:
```dart
_periodicTimer?.cancel();
_periodicTimer = Timer.periodic(const Duration(seconds: 30), (_) {
  if (_connectivity.isOnline && !_isSyncing) syncPendingOperations();
});
```
- Cancel timer in a new `dispose()` or on re-initialize.
- Add `Future<void> syncNow() async { if (_connectivity.isOnline && !_isSyncing) await syncPendingOperations(); }`
- Rewrite `syncPendingOperations` to track `delivered` and call `markDelivered` + `pruneDelivered` on success; `remaining` keeps `attempts` increment.
- Extend `_executeOperation`:
```dart
case 'createTransaction':
  final docId = operation['docId'] as String;
  final workerId = operation['workerId'] as String;
  final type = operation['transactionType'] as String;
  final amount = (operation['amount'] as num).toDouble();
  // ... other fields
  await firestore.runTransaction((txn) async {
    final ref = firestore.collection('transactions').doc(docId);
    final snap = await txn.get(ref);
    if (snap.exists) return;
    txn.set(ref, {
      'workerId': workerId, 'workerName': operation['workerName'],
      'type': type, 'amount': amount, 'notes': operation['notes'],
      'receiptUrl': operation['receiptUrl'], 'createdAt': operation['createdAt'],
      'createdBy': operation['createdBy'], 'approved': false,
      // coffee fields if present
    });
    final workerRef = firestore.collection('workers').doc(workerId);
    // FieldValue.increment inside transaction via txn.update
    // Use txn.update with increment map
    if (type == 'distribution') {
      txn.update(workerRef, {'currentBalance': FieldValue.increment(amount), 'totalDistributed': FieldValue.increment(amount)});
    } else if (type == 'return') {
      txn.update(workerRef, {'currentBalance': FieldValue.increment(-amount), 'totalReturned': FieldValue.increment(amount)});
    } else if (type == 'purchase') {
      txn.update(workerRef, {'currentBalance': FieldValue.increment(-amount), 'totalCoffeePurchased': FieldValue.increment(amount)});
    }
  });
  break;
case 'createTransfer':
  // similar: two docIds derived from opId, two balance updates, marker = sender doc
  break;
case 'createIncome':
case 'createExpense':
  // single doc conditional set via runTransaction
  break;
// keep existing approveTransaction/approveTransfer/approveAll as idempotent updates
```

Keep `default: throw UnsupportedError`.

After each success in the loop: `await _cache.markDelivered(operation['opId'] as String, type);`

Note: `FakeFirebaseFirestore` supports `runTransaction` — verify in tests; if not, fallback to get-then-set with same semantics (tests document expected behavior).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/offline_sync_service_test.dart -v`
Expected: PASS (idempotent, delivered log)

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/services/offline_sync_service.dart app/test/offline_sync_service_test.dart
git commit -m "feat(outbox): idempotent drain with delivered log and periodic retry"
```

---

### Task 3: TransactionService queue-first for addTransaction (deterministic IDs + optimistic cache)

**Files:**
- Modify: `app/lib/core/services/transaction_service.dart:131-230` (addTransaction + addTransfer stubs)
- Test: `app/test/transaction_service_test.dart`

**Interfaces:**
- Consumes: `OfflineCacheService.queueOperation` + `cacheTransactions`, `OfflineSyncService.syncNow`, `ConnectivityService.isOnline` not needed (always queue)
- Produces: `Future<String> addTransaction(MoneyTransaction)` now returns deterministic `opId`; queue payload includes all fields needed for drain

- [ ] **Step 1: Write the failing test**

```dart
// app/test/transaction_service_test.dart
test('addTransaction queues and appears in cache, does not directly write while offline', () async {
  final fake = FakeFirebaseFirestore();
  final service = TransactionService(firestore: fake);
  // ensure offline cache initialized in setUpAll already
  ConnectivityService().setOnlineForTest(false);
  await service.addTransaction(MoneyTransaction(
    id: '', workerId: 'w1', workerName: 'W1', type: 'distribution', amount: 50,
    createdAt: DateTime.now(), createdBy: 'tester',
  ));
  expect(OfflineCacheService().getPendingOperations().any((o) => o['type'] == 'createTransaction'), true);
  expect(OfflineCacheService().getCachedTransactions()?.any((t) => t.amount == 50), true);
  expect((await fake.collection('transactions').get()).docs.length, 0);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/transaction_service_test.dart -v`
Expected: FAIL — still does batch commit directly

- [ ] **Step 3: Implement queue-first addTransaction**

In `app/lib/core/services/transaction_service.dart`:
- Add import `package:uuid/uuid.dart` (or generate via `DateTime.now().millisecondsSinceEpoch` + random if uuid not desired — prefer uuid, add dep if missing).
- Rewrite `addTransaction`:
```dart
Future<String?> addTransaction(MoneyTransaction transaction) async {
  if (transaction.amount <= 0) throw 'Amount must be greater than 0';
  // live balance check only when online (skip offline, matches current behavior caveat)
  if (ConnectivityService().isOnline && (transaction.type == 'purchase' || transaction.type == 'return')) { /* existing check */ }
  final opId = const Uuid().v4();
  final docId = opId;
  await OfflineCacheService().queueOperation({
    'opId': opId, 'type': 'createTransaction', 'docId': docId,
    'workerId': transaction.workerId, 'workerName': transaction.workerName,
    'transactionType': transaction.type, 'amount': transaction.amount,
    'notes': transaction.notes, 'receiptUrl': transaction.receiptUrl,
    'createdAt': transaction.createdAt.millisecondsSinceEpoch,
    'createdBy': transaction.createdBy,
    'coffeeType': transaction.coffeeType, 'coffeeWeight': transaction.coffeeWeight,
    'pricePerKg': transaction.pricePerKg, 'commissionAmount': transaction.commissionAmount,
    'queuedAt': DateTime.now().toIso8601String(), 'attempts': 0,
  });
  // optimistic cache
  final cached = OfflineCacheService().getCachedTransactions() ?? [];
  final optimistic = MoneyTransaction(/* same fields, id: docId */);
  await OfflineCacheService().cacheTransactions([...cached, optimistic]);
  unawaited(OfflineSyncService().syncNow());
  return docId;
}
```
`unawaited` via `Future.sync` + ignore.

Keep old batch logic removed — drain owns the Firestore write now. Preserve error handling: queue failure throws.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/transaction_service_test.dart -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/services/transaction_service.dart app/test/transaction_service_test.dart
git commit -m "feat(outbox): queue-first addTransaction with deterministic IDs"
```

---

### Task 4: TransactionService queue-first for addTransfer

**Files:**
- Modify: `app/lib/core/services/transaction_service.dart:225-310`
- Test: `app/test/transaction_service_test.dart` (extend)

**Interfaces:**
- Consumes: same as Task 3
- Produces: `Future<String?> addTransfer` returns `transferId` derived from `opId`, queues single `createTransfer` op

- [ ] **Step 1: Write the failing test**

```dart
test('addTransfer queues single op and appears in cache, drain creates two docs atomically', () async {
  final fake = FakeFirebaseFirestore();
  await fake.collection('workers').doc('w1').set({'currentBalance': 500});
  await fake.collection('workers').doc('w2').set({'currentBalance': 0});
  final service = TransactionService(firestore: fake);
  OfflineSyncService().firestore = fake;
  ConnectivityService().setOnlineForTest(false);
  final tid = await service.addTransfer(fromWorkerId: 'w1', fromWorkerName: 'A', toWorkerId: 'w2', toWorkerName: 'B', amount: 100, createdBy: 'tester');
  expect(tid, isNotNull);
  expect(OfflineCacheService().getPendingOperations().where((o) => o['type'] == 'createTransfer').length, 1);
  ConnectivityService().setOnlineForTest(true);
  await OfflineSyncService().syncPendingOperations();
  expect((await fake.collection('transactions').where('transferId', isEqualTo: tid).get()).docs.length, 2);
  expect((await fake.collection('workers').doc('w1').get()).data()!['currentBalance'], 400);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/transaction_service_test.dart -v`
Expected: FAIL — still does direct batch

- [ ] **Step 3: Implement queue-first addTransfer**

Rewrite `addTransfer` similarly: validate sender balance only when online, generate `opId`, derive `transferId` as `opId` (or keep `${from}_${to}_${millis}` but keyed by `opId` for idempotency — simplest: `transferId = opId`), `senderDocId = opId`, `receiverDocId = '${opId}_r'`, queue single `createTransfer` op with all fields, optimistic cache two MoneyTransactions, `syncNow()`.

Drain side already handles `createTransfer` via transaction (two sets + two increments).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/transaction_service_test.dart -v`

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/services/transaction_service.dart app/test/transaction_service_test.dart
git commit -m "feat(outbox): queue-first addTransfer with atomic drain"
```

---

### Task 5: Income/Expense queue-first

**Files:**
- Modify: `app/lib/core/services/income_service.dart:257-280`, `app/lib/core/services/expense_service.dart:153-186`
- Modify: `app/lib/core/providers/income_provider.dart`, `app/lib/core/providers/expense_provider.dart` (if they call service directly, no provider change needed beyond error handling)
- Test: `app/test/income_expense_outbox_test.dart` (new)

**Interfaces:**
- Consumes: `OfflineCacheService` cache methods, `OfflineSyncService.syncNow`
- Produces: `Future<String?> addIncome`/`addExpense` queue-first, return deterministic `opId`

- [ ] **Step 1: Write the failing test**

```dart
// app/test/income_expense_outbox_test.dart
test('addIncome queues and shows in cache, drain creates doc', () async {
  final fake = FakeFirebaseFirestore();
  final svc = IncomeService(firestore: fake); // after adding seam
  OfflineSyncService().firestore = fake;
  await svc.addIncome(IncomeRecord(/* ... amount 100 ... */));
  expect(OfflineCacheService().getPendingOperations().any((o) => o['type'] == 'createIncome'), true);
  await OfflineSyncService().syncPendingOperations();
  expect((await fake.collection('income_records').get()).docs.length, 1);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/income_expense_outbox_test.dart -v`
Expected: FAIL — direct `collection.add`

- [ ] **Step 3: Add firestore seams + queue-first**

Add `IncomeService({FirebaseFirestore? firestore})` / `ExpenseService({FirebaseFirestore? firestore})` seams (match TransactionService pattern).

Rewrite `addIncome`/`addExpense`:
```dart
Future<String?> addIncome(IncomeRecord record) async {
  final opId = const Uuid().v4();
  await OfflineCacheService().queueOperation({'opId': opId, 'type': 'createIncome', 'docId': opId, 'payload': record.toFirestore(), 'queuedAt': DateTime.now().toIso8601String()});
  final cached = OfflineCacheService().getCachedIncome() ?? [];
  await OfflineCacheService().cacheIncome([...cached, record.copyWith(id: opId)]);
  unawaited(OfflineSyncService().syncNow());
  return opId;
}
```
Similarly `addExpense`.

Extend drain in `OfflineSyncService._executeOperation` for `createIncome`/`createExpense` via `runTransaction` conditional set.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/income_expense_outbox_test.dart test/offline_sync_service_test.dart -v`

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/services/income_service.dart app/lib/core/services/expense_service.dart app/test/income_expense_outbox_test.dart
git commit -m "feat(outbox): queue-first income/expense with idempotent drain"
```

---

### Task 6: Approve paths queue-first-always + verify gate

**Files:**
- Modify: `app/lib/core/services/transaction_service.dart:308-390` (approve methods)
- Test: `app/test/offline_sync_service_test.dart` (extend existing approve tests to verify queue-first even when online)

**Interfaces:**
- Produces: `approveTransaction`/`approveTransfer`/`approveAllForWorker` always queue, never direct write; drain handles them

- [ ] **Step 1: Write the failing test — approve while online should still queue**

```dart
test('approveTransaction while online queues instead of direct write', () async {
  ConnectivityService().setOnlineForTest(true);
  final fake = FakeFirebaseFirestore();
  await fake.collection('transactions').doc('t1').set({'approved': false, 'workerId': 'w1'});
  final svc = TransactionService(firestore: fake);
  await svc.approveTransaction('t1');
  expect(OfflineCacheService().getPendingOperations().any((o) => o['type'] == 'approveTransaction'), true);
  expect((await fake.collection('transactions').doc('t1').get()).data()!['approved'], false); // not yet applied
  await OfflineSyncService().syncPendingOperations();
  expect((await fake.collection('transactions').doc('t1').get()).data()!['approved'], true);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/offline_sync_service_test.dart -v`

- [ ] **Step 3: Change approve methods to queue-first-always**

Remove `if (!isOnline)` guard, always `queueOperation({'opId': Uuid().v4(), 'type': 'approveTransaction', ...})` + cache optimistic `_flipApproved` stays in provider (no change), then `syncNow()`.

- [ ] **Step 4: Run full verify gate**

Run: `dart format --output=none --set-exit-if-changed . && flutter analyze --no-pub && flutter test`
Expected: format clean, 0 new warnings/errors beyond existing 217 infos, all tests pass

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/services/transaction_service.dart app/test/offline_sync_service_test.dart
git commit -m "feat(outbox): approve ops queue-first-always"
```

---

## Self-Review Checklist

- [ ] Spec §4.1 delivered box + opId schema covered by Task 1
- [ ] Spec §4.2 timer + syncNow + drain with delivered ack covered by Task 2
- [ ] Spec §4.4 idempotency via runTransaction covered by Tasks 2-5
- [ ] Optimistic visibility covered by Tasks 3-5 cache writes
- [ ] No placeholder strings — every step has concrete code/commands
- [ ] Type consistency: `opId`/`docId`/`queuedAt`/`attempts` naming consistent across tasks
- [ ] Verify gate in final task

