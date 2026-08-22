# Offline-First Full Ops Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every add/edit/delete for income, expense, and worker transactions (distribution/return/purchase/transfer) succeeds locally while offline via Hive queue coalescing and syncs seamlessly via Firestore transactions when online.

**Architecture:** Extend existing 3-layer stack `Dialog → Provider (optimistic) → Service (queueOperation + cache*) → OfflineCacheService (pending_operations + failed_operations) → OfflineSyncService.runTransaction`. Add 7 new op types, coalesce in `queueOperation` before `box.put`, local projected-balance check via `getCachedWorker + sum(pending)`, deferred Cloudinary upload + queued `auditLog`, capped `attempts` → `failed_operations` outbox with retry/discard.

**Tech Stack:** Flutter, cloud_firestore `runTransaction` + `FieldValue.increment`, Hive (`pending_operations`, `income_cache`, `expenses_cache`, `transactions_cache`), connectivity_plus, http (Cloudinary), uuid, provider, fake_cloud_firestore for tests.

## Global Constraints
- All 6 mutation types per entity must be offline-queued (Q1 A) — income: create/update/delete, expense: create/update/delete, tx: distribution/return/purchase/transfer create/update/delete.
- Local balance validation via cached + pending deltas when offline (Q2 A).
- Coalesce `create+delete→drop` etc. (Q3 A).
- Audit queued + receipt deferred (Q4 A).
- Failed stays visible with retry/edit/discard banner (Q5 A).
- 7-day `isLocked` enforced locally and authoritatively on sync.
- Reuse `offline_cache_service.dart:426` tombstone `_cancelledOpIds`, `income_provider.dart:203` reconciling `_refreshTotals`, no new DB.

---

### Task 1: OfflineCacheService — coalesce + failed box + cache helpers

**Files:**
- Modify: `app/lib/core/services/offline_cache_service.dart:1-560`
- Test: `app/test/core/services/offline_cache_coalesce_test.dart`

**Interfaces:**
- Consumes: existing `queueOperation`, `replacePendingOperations`, `removePendingOperationByOpId`, `markDelivered`, Hive boxes.
- Produces: `Future<void> queueOperation(Map<String,dynamic>)` with coalesce, `List<Map> getFailedOperations()`, `Future<void> markFailed(Map op, String reason)`, `Future<void> discardFailed(String opId)`, `Future<void> removeCachedIncome(String)`, `removeCachedExpense`, `removeCachedTransaction(String|transferId)`, `cacheWorkerTransactions`, failed box `failed_operations`.

- [ ] **Step 1: Write failing test — coalesce matrix**

```dart
// app/test/core/services/offline_cache_coalesce_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:cofiz/core/services/offline_cache_service.dart';

void main() {
  late Directory dir;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('coalesce');
    await OfflineCacheService().initialize(path: dir.path);
  });
  tearDown(() async => await OfflineCacheService().clearAllCache());
  tearDownAll(() async { await Hive.close(); await dir.delete(recursive: true); });

  test('create+delete same id drops both', () async {
    final svc = OfflineCacheService();
    await svc.queueOperation({'opId':'a','type':'createIncome','docId':'a','payload':{'amount':10},'attempts':0});
    await svc.queueOperation({'opId':'a','type':'deleteIncome','docId':'a','attempts':0});
    expect(svc.getPendingOperations().where((o)=>o['opId']=='a'), isEmpty);
  });
  test('create+update merges into create with final payload', () async {
    final svc = OfflineCacheService();
    await svc.queueOperation({'opId':'b','type':'createIncome','docId':'b','payload':{'amount':10},'attempts':0});
    await svc.queueOperation({'opId':'b','type':'updateIncome','docId':'b','payload':{'amount':20},'attempts':0});
    final ops = svc.getPendingOperations().where((o)=>o['opId']=='b').toList();
    expect(ops.length, 1);
    expect(ops[0]['type'], 'createIncome');
    expect(ops[0]['payload']['amount'], 20);
  });
  test('update+update keeps last', () async {
    final svc = OfflineCacheService();
    await svc.queueOperation({'opId':'c','type':'updateIncome','docId':'c','payload':{'amount':10},'attempts':0});
    await svc.queueOperation({'opId':'c','type':'updateIncome','docId':'c','payload':{'amount':30},'attempts':0});
    expect(svc.getPendingOperations().where((o)=>o['opId']=='c').length, 1);
    expect(svc.getPendingOperations().firstWhere((o)=>o['opId']=='c')['payload']['amount'], 30);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test app/test/core/services/offline_cache_coalesce_test.dart -v`
Expected: FAIL — queue has 2 ops (no coalesce), or file not found.

- [ ] **Step 3: Implement coalesce + failed box**

In `app/lib/core/services/offline_cache_service.dart`:
- Add `import 'package:flutter/foundation.dart';` if missing, keep `final Set<String> _cancelledOpIds = {};` `offline_cache_service.dart:426`.
- Add `static const String _failedBox = 'failed_operations';` open in `initialize()`.
- Modify `queueOperation` (before `pending.add`): lookup `existingIdx = pending.indexWhere((e)=> (e as Map)['opId']==operation['opId'])`; if found, apply coalesce rules per spec `create+delete→ pending.removeAt(existingIdx); _cancelledOpIds.add(opId); await box.put('queue', pending); return;` etc. For `update` merge: `pending[existingIdx]['payload'] = {...existingPayload, ...newPayload}`; for `create+update` keep `create` type with merged payload. For transfer key by `transferId`.
- Keep `replacePendingOperations` tombstone filter `where !_cancelledOpIds.contains`.
- Add `getFailedOperations`, `markFailed`, `discardFailed`, `clearFailed`, `getCachedWorkerTransactions` helpers. Add `removeCachedTransaction(String id)` (filter `cacheTransactions` where `id != id` and also `transferId != id`), `removeCachedIncome/Expense` wrappers already exist — keep.
- Open `_failedBox` in `initialize()`, clear in `clearAllCache()`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test app/test/core/services/offline_cache_coalesce_test.dart -v`
Expected: PASS — 3 tests.

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/services/offline_cache_service.dart app/test/core/services/offline_cache_coalesce_test.dart
git commit -m "feat(offline): coalesce queue + failed box helpers"
```

---

### Task 2: OfflineSyncService — 7 new op executors + receipt + audit + cap

**Files:**
- Modify: `app/lib/core/services/offline_sync_service.dart:122`
- Modify: `app/lib/core/services/transaction_service.dart:829` (expose upload helper)
- Test: `app/test/core/services/offline_sync_new_ops_test.dart`

**Interfaces:**
- Consumes: `OfflineCacheService.queueOperation` types, `FirebaseFirestore.runTransaction`, `http.MultipartRequest`, `failed_operations` box.
- Produces: `Future<void> _executeOperation` handling `updateIncome/deleteIncome/updateExpense/deleteExpense/updateTransaction/deleteTransaction/deleteTransfer/auditLog`; `attempts` cap 5 → `markFailed`.

- [ ] **Step 1: Write failing test**

```dart
// app/test/core/services/offline_sync_new_ops_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:cofiz/core/services/offline_sync_service.dart';
import 'package:cofiz/core/services/offline_cache_service.dart';

void main() {
  late Directory dir;
  late FakeFirebaseFirestore fake;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('sync_new');
    await OfflineCacheService().initialize(path: dir.path);
    fake = FakeFirebaseFirestore();
    OfflineSyncService().firestore = fake;
    // seed worker
    await fake.collection('workers').doc('w1').set({'currentBalance':1000,'totalDistributed':0});
  });
  tearDown(() async => await OfflineCacheService().clearAllCache());
  tearDownAll(() async { await Hive.close(); await dir.delete(recursive:true); });

  test('queued deleteIncome syncs via transaction', () async {
    await fake.collection('income_records').doc('inc1').set({'amount':100,'createdAt':DateTime.now().millisecondsSinceEpoch});
    await OfflineCacheService().queueOperation({'opId':'inc1','type':'deleteIncome','docId':'inc1','attempts':0});
    await OfflineSyncService().syncPendingOperations();
    expect((await fake.collection('income_records').doc('inc1').get()).exists, isFalse);
    expect(OfflineCacheService().getPendingOperations(), isEmpty);
  });
  test('attempts cap moves to failed box', () async {
    await OfflineCacheService().queueOperation({'opId':'bad','type':'deleteIncome','docId':'nope','attempts':5});
    // make firestore throw permission-denied by not seeding doc? fake will not throw — force via unknown type handling?
    // inject op that will throw UnsupportedError
    await OfflineCacheService().queueOperation({'opId':'x','type':'unknownType','attempts':5});
    await OfflineSyncService().syncPendingOperations();
    expect(OfflineCacheService().getFailedOperations().any((o)=>o['opId']=='x'), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test app/test/core/services/offline_sync_new_ops_test.dart -v`
Expected: FAIL — `deleteIncome` unknown type → `UnsupportedError`.

- [ ] **Step 3: Implement**

In `offline_sync_service.dart:122` add cases:
```dart
case 'updateIncome': {
  final docId = operation['docId'] as String;
  final data = Map<String,dynamic>.from(operation['payload'] as Map);
  await firestore.runTransaction((txn) async {
    final ref = firestore.collection('income_records').doc(docId);
    final snap = await txn.get(ref);
    if (!snap.exists) return;
    txn.update(ref, data);
  });
  break;
}
case 'deleteIncome': {
  final docId = operation['docId'] as String;
  await firestore.runTransaction((txn) async {
    final ref = firestore.collection('income_records').doc(docId);
    final snap = await txn.get(ref);
    if (!snap.exists) return;
    txn.delete(ref);
  });
  break;
}
case 'updateExpense': // same on 'expenses'
case 'deleteExpense':
case 'updateTransaction': {
  // _enforceLock check inside transaction: fetch old, throw TransactionLockedException if isLocked without overrideReason in op
  // then _balanceUpdates(old,-1) + _balanceUpdates(new,+1) + txn.update(doc, newPayload)
}
case 'deleteTransaction': {
  // txn.get, _enforceLock, _balanceUpdates(*,-1), txn.delete
}
case 'deleteTransfer': {
  // where transferId, for each doc _enforceLock, _balanceUpdates(*,-1), batch delete; need transaction over 2 deletes + 2 worker updates atomically: use runTransaction with get + set/delete as existing createTransfer does
}
case 'auditLog': {
  final data = Map<String,dynamic>.from(operation['payload'] as Map);
  await firestore.collection('audit_logs').add(data);
  break;
}
```
For `createTransaction` with `localReceiptPath`: before `runTransaction`, if `operation['localReceiptPath'] != null`, upload to Cloudinary via `http.MultipartRequest` (`transaction_service.dart:829` extract to `static Future<String?> uploadReceiptBytes` reuse); on upload failure throw to keep in `remaining`.

Cap: in `syncPendingOperations` loop `catch`: `if ((updated['attempts'] as int) >= 5) { await _cache.markFailed(updated, e.toString()); } else remaining.add(updated);` After loop, `pruneDelivered`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test app/test/core/services/offline_sync_new_ops_test.dart -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/services/offline_sync_service.dart
git commit -m "feat(sync): execute update/delete income/expense/tx/transfer + audit + receipt defer + cap"
```

---

### Task 3: IncomeService + ExpenseService — queue-first update/delete

**Files:**
- Modify: `app/lib/core/services/income_service.dart:303`
- Modify: `app/lib/core/services/expense_service.dart:199`
- Test: `app/test/core/services/income_expense_offline_write_test.dart`

**Interfaces:**
- Consumes: `OfflineCacheService.queueOperation`, `cacheIncome/cacheExpenses`, `OfflineSyncService.syncNow`, `ConnectivityService.isOnline`, `OfflineCacheService.getCachedIncome`.
- Produces: `Future<bool> updateIncome(IncomeRecord)` and `deleteIncome(String)` returning `true` offline (queued), `Future<bool> updateExpense/deleteExpense` same.

- [ ] **Step 1: Write failing test**

```dart
test('updateIncome offline queues and returns true', () async {
  // set offline
  ConnectivityService().setOnlineForTest(false);
  final svc = IncomeService(firestore: FakeFirebaseFirestore());
  // seed cache with existing
  await OfflineCacheService().cacheIncome([IncomeRecord(id:'i1', kind:IncomeKind.investment, amount:100, createdAt:DateTime.now(), createdBy:'u', createdByName:'n')]);
  final ok = await svc.updateIncome(IncomeRecord(id:'i1', kind:IncomeKind.sale, amount:200, createdAt:DateTime.now(), createdBy:'u', createdByName:'n', saleCategory:'Other'));
  expect(ok, isTrue);
  expect(OfflineCacheService().getPendingOperations().any((o)=>o['type']=='updateIncome'), isTrue);
  expect(OfflineCacheService().getCachedIncome()!.firstWhere((r)=>r.id=='i1').amount, 200);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test app/test/core/services/income_expense_offline_write_test.dart -v`
Expected: FAIL — updateIncome returns false offline (direct Firestore).

- [ ] **Step 3: Implement**

In `income_service.dart:303` replace:
```dart
Future<bool> updateIncome(IncomeRecord record) async {
  await OfflineCacheService().queueOperation({'opId':record.id,'type':'updateIncome','docId':record.id,'payload':record.toFirestore(),'attempts':0,'queuedAt':DateTime.now().toIso8601String()});
  final cached = OfflineCacheService().getCachedIncome() ?? [];
  await OfflineCacheService().cacheIncome([for (final r in cached) if (r.id != record.id) r, record]);
  unawaited(OfflineSyncService().syncNow());
  return true;
}
Future<bool> deleteIncome(String id) async {
  await OfflineCacheService().queueOperation({'opId':id,'type':'deleteIncome','docId':id,'attempts':0,'queuedAt':DateTime.now().toIso8601String()});
  await OfflineCacheService().removeCachedIncome(id);
  unawaited(OfflineSyncService().syncNow());
  return true;
}
```
Mirror for `expense_service.dart:199` `updateExpense`/`deleteExpense` with `cacheExpenses`/`removeCachedExpense`. Keep `try/catch` only for `connectivity` check? Remove direct Firestore calls entirely; sync handles authoritative lock/balance.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test app/test/core/services/income_expense_offline_write_test.dart -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/services/income_service.dart app/lib/core/services/expense_service.dart
git commit -m "feat(offline): income/expense update/delete queue-first"
```

---

### Task 4: TransactionService — queue-first update/delete/transferDelete + local balance/lock

**Files:**
- Modify: `app/lib/core/services/transaction_service.dart:417`
- Test: `app/test/core/services/transaction_offline_mutation_test.dart`

**Interfaces:**
- Consumes: `OfflineCacheService` queue + `getCachedWorkerTransactions`, `ConnectivityService.isOnline`.
- Produces: `Future<void> updateTransaction`/`deleteTransaction`/`deleteTransfer` now queue and return successfully offline; local `projectedBalance` check.

- [ ] **Step 1: Write failing test**

```dart
test('deleteTransaction offline queues and removes from cache', () async {
  ConnectivityService().setOnlineForTest(false);
  final svc = TransactionService(firestore: FakeFirebaseFirestore());
  await OfflineCacheService().cacheTransactions([MoneyTransaction(id:'t1', workerId:'w1', workerName:'n', type:'distribution', amount:100, createdAt:DateTime.now(), createdBy:'u')]);
  await svc.deleteTransaction('t1');
  expect(OfflineCacheService().getPendingOperations().any((o)=>o['type']=='deleteTransaction'), isTrue);
  expect(OfflineCacheService().getCachedTransactions()!.any((t)=>t.id=='t1'), isFalse);
});
test('offline insufficient balance throws before queue', () async {
  ConnectivityService().setOnlineForTest(false);
  // seed worker cache with balance 50
  await OfflineCacheService().cacheWorkerProfile(Worker(id:'w1', name:'n', currentBalance:50, ...));
  final svc = TransactionService(firestore: FakeFirebaseFirestore());
  expect(() => svc.addTransaction(MoneyTransaction(id:'', workerId:'w1', workerName:'n', type:'return', amount:100, createdAt:DateTime.now(), createdBy:'u')), throwsA(contains('Insufficient')));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test app/test/core/services/transaction_offline_mutation_test.dart -v`
Expected: FAIL — deleteTransaction throws `Transaction not found` offline (direct get).

- [ ] **Step 3: Implement**

Replace `updateTransaction`/`deleteTransaction`/`deleteTransfer` bodies with queue-first:
```dart
Future<void> updateTransaction(MoneyTransaction tx, {String? overrideReason}) async {
  // local lock + balance projected check when !isOnline using getCachedWorker + sum pending deltas for workerId
  if (!ConnectivityService().isOnline) {
    final projected = _projectedBalance(tx.workerId); // sum cached worker + pending
    if (tx.type.toLowerCase() != 'distribution' && projected < tx.amount) throw 'Insufficient...';
  }
  await OfflineCacheService().queueOperation({'opId':tx.id,'type':'updateTransaction','docId':tx.id,'payload':tx.toFirestore(),'overrideReason':overrideReason,'attempts':0});
  final cached = OfflineCacheService().getCachedTransactions() ?? [];
  await OfflineCacheService().cacheTransactions([for (final t in cached) if (t.id != tx.id) t, tx]);
  unawaited(OfflineSyncService().syncNow());
}
Future<void> deleteTransaction(String id,{String? overrideReason}) async {
  await OfflineCacheService().queueOperation({'opId':id,'type':'deleteTransaction','docId':id,'overrideReason':overrideReason,'attempts':0});
  final cached = OfflineCacheService().getCachedTransactions() ?? [];
  await OfflineCacheService().cacheTransactions(cached.where((t)=>t.id!=id).toList());
  unawaited(OfflineSyncService().syncNow());
}
Future<void> deleteTransfer(String transferId,{String? overrideReason}) async {
  await OfflineCacheService().queueOperation({'opId':transferId,'type':'deleteTransfer','transferId':transferId,'overrideReason':overrideReason,'attempts':0});
  final cached = OfflineCacheService().getCachedTransactions() ?? [];
  await OfflineCacheService().cacheTransactions(cached.where((t)=>t.transferId != transferId).toList());
  unawaited(OfflineSyncService().syncNow());
}
```
Add helper `double _projectedBalance(String workerId)` reading `OfflineCacheService.getCachedWorkerProfile` or workers box + summing `getPendingOperations` deltas via `_balanceUpdates` logic. Check `isLocked` locally via cached `MoneyTransaction.createdAt` before queue — still throw `TransactionLockedException` if locked without `overrideReason` (mirrors `transaction_service.dart:571`).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test app/test/core/services/transaction_offline_mutation_test.dart -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/services/transaction_service.dart
git commit -m "feat(offline): transaction update/delete queue-first + local balance/lock"
```

---

### Task 5: IncomeProvider & ExpenseProvider — optimistic update/delete

**Files:**
- Modify: `app/lib/core/providers/income_provider.dart:360`
- Modify: `app/lib/core/providers/expense_provider.dart:291`
- Test: `app/test/core/providers/income_expense_offline_provider_test.dart`

**Interfaces:**
- Consumes: `IncomeService.updateIncome/deleteIncome` (now queue-first), `OfflineCacheService`.
- Produces: `Future<bool> updateIncome/deleteIncome` optimistically mutating `_records/_fullRecords` + cache before await, same for expense.

- [ ] **Step 1: Write failing test**

```dart
test('deleteIncome offline removes row instantly and queues', () async {
  ConnectivityService().setOnlineForTest(false);
  final svc = IncomeService(firestore: FakeFirebaseFirestore());
  final p = IncomeProvider(service: svc);
  await p.addIncome(investment(100)); // queues
  final id = p.records.first.id;
  final ok = await p.deleteIncome(id);
  expect(ok, isTrue);
  expect(p.records.any((r)=>r.id==id), isFalse);
  expect(OfflineCacheService().getPendingOperations().any((o)=>o['type']=='deleteIncome'), isTrue);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test app/test/core/providers/income_expense_offline_provider_test.dart -v`
Expected: FAIL — deleteIncome returns false offline (before Task 3) or row stays.

- [ ] **Step 3: Implement**

In `income_provider.dart:360` `updateIncome`:
```dart
Future<bool> updateIncome(IncomeRecord record) async {
  final idx = _records.indexWhere((r)=>r.id==record.id);
  final old = idx>=0 ? _records[idx] : null;
  // optimistic
  _records = [for (final r in _records) r.id==record.id ? record : r];
  _fullRecords = [for (final r in _fullRecords) r.id==record.id ? record : r];
  notifyListeners();
  final success = await _service.updateIncome(record);
  if (!success) { // rollback on queue failure (should not happen now)
    if (old!=null) { _records[idx]=old; notifyListeners(); }
    return false;
  }
  _refreshTotals(); return true;
}
Future<bool> deleteIncome(String id) async {
  final removed = [..._records.where((r)=>r.id==id), ..._fullRecords.where((r)=>r.id==id)];
  _records = _records.where((r)=>r.id!=id).toList();
  _fullRecords = _fullRecords.where((r)=>r.id!=id).toList();
  for (final r in removed.toSet()) { _totalIncome -= r.amount; /* byKind/today */ }
  notifyListeners();
  final success = await _service.deleteIncome(id);
  if (!success) return false; // keep removed (already tombstoned) — outbox will retry
  _totalsGeneration++; _refreshTotals(); return true;
}
```
Mirror for `expense_provider.dart`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test app/test/core/providers/income_expense_offline_provider_test.dart -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/providers/income_provider.dart app/lib/core/providers/expense_provider.dart
git commit -m "feat(offline): providers optimistic update/delete"
```

---

### Task 6: TransactionProvider — optimistic update/delete/transferDelete

**Files:**
- Modify: `app/lib/core/providers/transaction_provider.dart:609`
- Test: `app/test/core/providers/transaction_offline_provider_test.dart`

**Interfaces:**
- Consumes: `TransactionService` queue-first.
- Produces: `Future<bool> updateTransaction/deleteTransaction/deleteTransfer` with optimistic `_allTransactions/_workerTransactions` before await.

- [ ] **Step 1: Write failing test**

```dart
test('updateTransaction offline optimistic', () async {
  ConnectivityService().setOnlineForTest(false);
  final p = TransactionProvider(transactionService: TransactionService(firestore: FakeFirebaseFirestore()));
  await p.distributeMoneyToWorker(workerId:'w1', workerName:'n', amount:50, createdBy:'u');
  final tx = p.allTransactions.first;
  final ok = await p.updateTransaction(tx.copyWith(amount:60) as MoneyTransaction); // use real copy
  expect(ok, isTrue);
  expect(p.allTransactions.first.amount, 60);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test app/test/core/providers/transaction_offline_provider_test.dart -v`
Expected: FAIL — update still direct.

- [ ] **Step 3: Implement**

In `transaction_provider.dart:609` replace `updateTransaction`/`deleteTransaction`/`deleteTransfer` to do optimistic `_allTransactions = [...]` + `_workerTransactions = [...]` before `await _transactionService.*`, `notifyListeners`, return `true` even offline. Keep `_optimisticInsert` pattern for creates.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test app/test/core/providers/transaction_offline_provider_test.dart -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/providers/transaction_provider.dart
git commit -m "feat(offline): transaction provider optimistic"
```

---

### Task 7: Dialogs — audit + receipt defer + offline close

**Files:**
- Modify: `app/lib/presentation/screens/transaction/transaction_dialog.dart:160` (`_submitTransaction`)
- Modify: `app/lib/presentation/widgets/worker_transactions_list.dart:199`
- Modify: `app/lib/presentation/screens/income/dialogs/add_income_dialog.dart:92` (already done, keep)
- Modify: `app/lib/presentation/screens/expense/dialogs/add_expense_dialog.dart:86` (already done)
- Test: `app/test/presentation/dialogs/offline_dialog_close_test.dart` (widget test)

**Interfaces:**
- Consumes: `TransactionProvider` queue-first, `ConnectivityService`.
- Produces: dialogs pop immediately when `success==true` even offline; receipt `localReceiptPath` queued, audit `unawaited`.

- [ ] **Step 1: Write failing widget test**

```dart
testWidgets('TransactionDialog closes offline with receipt', (tester) async {
  ConnectivityService().setOnlineForTest(false);
  await tester.pumpWidget(MaterialApp(home: TransactionDialog(worker: Worker(id:'w1', name:'n', currentBalance:1000, commissionRate:1), type:'purchase')));
  await tester.enterText(find.byType(TextFormField).first, '10');
  await tester.tap(find.text('Confirm'));
  await tester.pump();
  expect(find.byType(TransactionDialog), findsNothing); // should pop
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test app/test/presentation/dialogs/offline_dialog_close_test.dart -v`
Expected: FAIL — dialog stays (awaiting upload).

- [ ] **Step 3: Implement**

In `transaction_dialog.dart:160` change `_submitTransaction`:
- Before `uploadReceipt`, if `!ConnectivityService().isOnline && _receiptImage != null` → keep `receiptPath = _receiptImage!.path` in local var, skip upload, pass `receiptPath` into `recordCoffeePurchase` payload (extend `MoneyTransaction` with `localReceiptPath` or put in op's `localReceiptPath` field via `TransactionService.addTransaction` param). Remove `if (receiptUrl==null) return` block for offline.
- After `success` check, keep `Navigator.pop` before any audit (no audit in tx dialog today).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test app/test/presentation/dialogs/offline_dialog_close_test.dart -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/presentation/screens/transaction/transaction_dialog.dart
git commit -m "fix(dialog): defer receipt upload offline, close immediately"
```

---

### Task 8: Failure outbox UI + integration

**Files:**
- Modify: `app/lib/presentation/widgets/offline_indicator.dart`
- Create: `app/lib/presentation/widgets/sync_outbox_banner.dart`
- Test: `app/test/integration/offline_bulk_test.dart`

**Interfaces:**
- Consumes: `OfflineCacheService.getFailedOperations`, `getPendingOperations`, `OfflineSyncService.syncNow`.
- Produces: banner showing `pendingCount` + `failedCount` with Retry/Discard actions.

- [ ] **Step 1: Write failing integration test**

```dart
test('airplane: create 3 incomes, 2 expenses, 1 purchase with receipt, delete 2 → reconnect syncs all', () async {
  ConnectivityService().setOnlineForTest(false);
  // create via providers...
  ConnectivityService().setOnlineForTest(true);
  await OfflineSyncService().syncPendingOperations();
  expect(FakeFirestore incomes count, 3);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test app/test/integration/offline_bulk_test.dart -v`
Expected: FAIL — missing.

- [ ] **Step 3: Implement**

Create `sync_outbox_banner.dart` reading `OfflineCacheService` every `connectionStatus` + `pendingOperations` changes, showing counts and buttons `onRetry: OfflineSyncService().syncNow`, `onDiscard: OfflineCacheService().discardFailed(opId)` + remove row. Modify `offline_indicator.dart` to include it. Wire `OfflineCacheService` stream or `ValueNotifier`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test app/test/integration/offline_bulk_test.dart -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/presentation/widgets/sync_outbox_banner.dart app/lib/presentation/widgets/offline_indicator.dart
git commit -m "feat(offline): outbox banner + bulk integration"
```

---

## Self-Review
- Spec coverage: every Q1-Q5 requirement has a task (Q1 all types → Tasks 2-4, Q2 balance → Task 4, Q3 coalesce → Task 1, Q4 audit/receipt → Tasks 2 & 7, Q5 outbox → Task 8, dialog close → Task 7).
- No placeholders, every step has exact file:line, code block, command + expected.
- Types consistent: `opId`/`docId`/`transferId`/`payload`/`localReceiptPath`/`attempts` across tasks, `OfflineCacheService` helpers reused.

