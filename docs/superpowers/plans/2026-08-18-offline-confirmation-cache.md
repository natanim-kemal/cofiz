# Offline Confirmation Caching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cache collector confirmations (approvals) locally when offline and reliably replay them to Firestore when connectivity returns, with optimistic UI.

**Architecture:** Reuse the existing Hive pending-ops queue (`OfflineCacheService`). Implement the stub executor in `OfflineSyncService` to replay approval ops to Firestore. Add a connectivity check to the three `TransactionService` approve methods that queues instead of writing when offline. Flip `approved` locally in `TransactionProvider` for immediate UI feedback; the live Firestore stream reconciles later.

**Tech Stack:** Flutter, Firebase Firestore, Hive, connectivity_plus. Tests use `fake_cloud_firestore` + real Hive (temp dir).

## Global Constraints

- Verify gate (every task): `dart format` on changed files, then `flutter analyze --no-pub` (must report **no new errors/warnings** — the ~218 pre-existing analyzer *infos* like `withOpacity` deprecations remain and are fine), then `flutter test` (all existing 27 + new tests must pass). Run from `app/`.
- Do NOT commit unrelated uncommitted work (theme, l10n, worker UI changes from earlier sessions are NOT part of this plan). Stage only the files named in each task.
- Firebase access uses `FirebaseFirestore.instance` unless a test seam is injected. `ConnectivityService()` (factory) returns the shared singleton; it is initialized once in `main.dart` via `OfflineSyncService().initialize()`.
- No new runtime dependencies. The only new dev dependency is `fake_cloud_firestore` (Task 3).
- Existing sync-trigger behavior stays: `OfflineSyncService.syncPendingOperations()` runs on connectivity restore (existing `connectionStatus` listener) and keeps failed ops queued.

---

### Task 1: Add `copyWith` to `MoneyTransaction`

**Files:**
- Modify: `app/lib/core/models/transaction_model.dart` (after `toJson()`, before `typeDisplay`)
- Test: `app/test/transaction_model_test.dart` (append a test)

**Interfaces:**
- Produces: `MoneyTransaction copyWith({bool? approved})` — used by `TransactionProvider` (Task 5) to flip the local `approved` flag.

- [ ] **Step 1: Write the failing test**

Append to `app/test/transaction_model_test.dart`:

```dart
  test('copyWith overrides approved', () {
    final t = base(approved: false);
    final updated = t.copyWith(approved: true);
    expect(updated.approved, isTrue);
    expect(updated.id, t.id);
    expect(updated.amount, t.amount);
  });
```

Note: `base()` currently has no `approved` param — add `{bool approved = true}` to the helper signature and pass `approved: approved` in the `MoneyTransaction(...)` constructor.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/transaction_model_test.dart`
Expected: FAIL — `copyWith` is not defined.

- [ ] **Step 3: Implement `copyWith`**

In `app/lib/core/models/transaction_model.dart`, insert after `toJson()` (line ~113):

```dart
  MoneyTransaction copyWith({bool? approved}) {
    return MoneyTransaction(
      id: id,
      workerId: workerId,
      workerName: workerName,
      type: type,
      amount: amount,
      notes: notes,
      receiptUrl: receiptUrl,
      createdAt: createdAt,
      createdBy: createdBy,
      approved: approved ?? this.approved,
      coffeeType: coffeeType,
      coffeeWeight: coffeeWeight,
      pricePerKg: pricePerKg,
      commissionAmount: commissionAmount,
      fromWorkerId: fromWorkerId,
      toWorkerId: toWorkerId,
      fromWorkerName: fromWorkerName,
      toWorkerName: toWorkerName,
      transferId: transferId,
      transferRole: transferRole,
    );
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/transaction_model_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/models/transaction_model.dart app/test/transaction_model_test.dart
git commit -m "feat: add copyWith to MoneyTransaction for optimistic confirmations"
```

---

### Task 2: `ConnectivityService` test seam

**Files:**
- Modify: `app/lib/core/services/connectivity_service.dart`
- Test: `app/test/connectivity_service_test.dart` (new)

**Interfaces:**
- Consumes: nothing.
- Produces: `void setOnlineForTest(bool value)` (`@visibleForTesting`) — used by `TransactionService` (Task 4) and provider tests (Task 5) to force offline.

- [ ] **Step 1: Write the failing test**

Create `app/test/connectivity_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cofiz/core/services/connectivity_service.dart';

void main() {
  test('setOnlineForTest overrides isOnline', () {
    final service = ConnectivityService();
    service.setOnlineForTest(false);
    expect(service.isOnline, isFalse);
    service.setOnlineForTest(true);
    expect(service.isOnline, isTrue);
  });

  test('factory returns the shared singleton', () {
    expect(identical(ConnectivityService(), ConnectivityService()), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/connectivity_service_test.dart`
Expected: FAIL — `setOnlineForTest` is not defined.

- [ ] **Step 3: Implement the seam**

In `app/lib/core/services/connectivity_service.dart`, add the import and method:

```dart
import 'package:flutter/foundation.dart';
```

Add after the `isOnline` getter (line ~16):

```dart
  /// Force connectivity state for tests. Never call from production code.
  @visibleForTesting
  void setOnlineForTest(bool value) {
    _isOnline = value;
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/connectivity_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/services/connectivity_service.dart app/test/connectivity_service_test.dart
git commit -m "feat: add test seam to ConnectivityService"
```

---

### Task 3: Implement `OfflineSyncService._executeOperation`

**Files:**
- Modify: `app/lib/core/services/offline_sync_service.dart`
- Modify: `app/pubspec.yaml` (add dev dependency)
- Test: `app/test/offline_sync_service_test.dart` (new)

**Interfaces:**
- Consumes: `OfflineCacheService.queueOperation` / `getPendingOperations` / `removePendingOperation` (existing); `FirebaseFirestore`.
- Produces: `_executeOperation` handles op types `approveTransaction`, `approveTransfer`, `approveAll`; public `syncPendingOperations()` (existing) drives it. Test seam field `firestore` (a `FirebaseFirestore`) that the executor uses instead of `FirebaseFirestore.instance` when set.

- [ ] **Step 1: Add the dev dependency**

Run: `flutter pub add --dev fake_cloud_firestore`
Expected: prints the resolved version (3.x). Verify with `flutter pub deps --style=compact | Select-String fake_cloud`.

- [ ] **Step 2: Write the failing test**

Create `app/test/offline_sync_service_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cofiz/core/services/offline_cache_service.dart';
import 'package:cofiz/core/services/offline_sync_service.dart';

void main() {
  late Directory tempDir;
  late FakeFirebaseFirestore fake;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('sync_test');
    await OfflineCacheService().initialize(path: tempDir.path);
  });

  setUp(() {
    fake = FakeFirebaseFirestore();
    OfflineSyncService().firestore = fake;
  });

  tearDown(() async {
    await OfflineCacheService().clearPendingOperations();
  });

  tearDownAll(() async {
    await OfflineCacheService().clearAllCache();
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  Future<void> seedTx(String id, {String workerId = 'w1', bool approved = false, String? transferId}) async {
    await fake.collection('transactions').doc(id).set({
      'workerId': workerId,
      'workerName': 'Alice',
      'type': 'distribution',
      'amount': 100.0,
      'createdAt': DateTime(2026, 8, 1).millisecondsSinceEpoch,
      'createdBy': 'u1',
      'approved': approved,
      if (transferId != null) 'transferId': transferId,
    });
  }

  test('replays approveTransaction op', () async {
    await seedTx('t1', approved: false);
    await OfflineCacheService().queueOperation({
      'type': 'approveTransaction',
      'transactionId': 't1',
    });

    await OfflineSyncService().syncPendingOperations();

    final doc = await fake.collection('transactions').doc('t1').get();
    expect(doc.data()?['approved'], isTrue);
    expect(OfflineCacheService().getPendingOperations(), isEmpty);
  });

  test('replays approveTransfer op on both records', () async {
    await seedTx('s1', approved: false, transferId: 'tr-1');
    await seedTx('r1', approved: false, transferId: 'tr-1');
    await OfflineCacheService().queueOperation({
      'type': 'approveTransfer',
      'transferId': 'tr-1',
    });

    await OfflineSyncService().syncPendingOperations();

    final s1 = await fake.collection('transactions').doc('s1').get();
    final r1 = await fake.collection('transactions').doc('r1').get();
    expect(s1.data()?['approved'], isTrue);
    expect(r1.data()?['approved'], isTrue);
    expect(OfflineCacheService().getPendingOperations(), isEmpty);
  });

  test('replays approveAll op for worker', () async {
    await seedTx('t1', workerId: 'w1', approved: false);
    await seedTx('t2', workerId: 'w1', approved: false);
    await seedTx('t3', workerId: 'w2', approved: false);
    await OfflineCacheService().queueOperation({
      'type': 'approveAll',
      'workerId': 'w1',
    });

    await OfflineSyncService().syncPendingOperations();

    final t1 = await fake.collection('transactions').doc('t1').get();
    final t2 = await fake.collection('transactions').doc('t2').get();
    final t3 = await fake.collection('transactions').doc('t3').get();
    expect(t1.data()?['approved'], isTrue);
    expect(t2.data()?['approved'], isTrue);
    expect(t3.data()?['approved'], isFalse); // other worker untouched
    expect(OfflineCacheService().getPendingOperations(), isEmpty);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/offline_sync_service_test.dart`
Expected: FAIL — `firestore` not defined on `OfflineSyncService` (executor still throws `UnimplementedError`).

- [ ] **Step 4: Implement the executor**

In `app/lib/core/services/offline_sync_service.dart`:

Add import:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
```

Add a lazy test-seam getter/setter after `_cache` (line ~11) — lazy so that
constructing the service in unit tests never touches `FirebaseFirestore.instance`
(which is not initialized there):

```dart
  FirebaseFirestore? _firestore;

  /// Production uses FirebaseFirestore.instance; tests inject a fake.
  FirebaseFirestore get firestore => _firestore ??= FirebaseFirestore.instance;

  @visibleForTesting
  set firestore(FirebaseFirestore value) => _firestore = value;
```

Replace the entire `_executeOperation` method (lines ~59-70) with:

```dart
  Future<void> _executeOperation(Map<String, dynamic> operation) async {
    final type = operation['type'] as String;
    switch (type) {
      case 'approveTransaction':
        await firestore
            .collection('transactions')
            .doc(operation['transactionId'] as String)
            .update({'approved': true});
        break;
      case 'approveTransfer':
        final snapshot = await firestore
            .collection('transactions')
            .where('transferId', isEqualTo: operation['transferId'] as String)
            .get();
        final batch = firestore.batch();
        for (final doc in snapshot.docs) {
          batch.update(doc.reference, {'approved': true});
        }
        await batch.commit();
        break;
      case 'approveAll':
        final snapshot = await firestore
            .collection('transactions')
            .where('workerId', isEqualTo: operation['workerId'] as String)
            .where('approved', isEqualTo: false)
            .get();
        final batch = firestore.batch();
        for (final doc in snapshot.docs) {
          batch.update(doc.reference, {'approved': true});
        }
        await batch.commit();
        break;
      default:
        throw UnsupportedError('Unknown operation type: $type');
    }
  }
```

`firestore` field is `@visibleForTesting`, so keep the existing `import 'package:flutter/foundation.dart';` (already present at line 1).

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/offline_sync_service_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add app/lib/core/services/offline_sync_service.dart app/test/offline_sync_service_test.dart app/pubspec.yaml app/pubspec.lock
git commit -m "feat: replay offline confirmation ops to Firestore"
```

---

### Task 4: Queue approvals in `TransactionService` when offline

**Files:**
- Modify: `app/lib/core/services/transaction_service.dart` (three methods)
- Test: `app/test/transaction_service_test.dart` (new)

**Interfaces:**
- Consumes: `ConnectivityService()` (shared singleton), `OfflineCacheService.queueOperation`; `TransactionProvider` (Task 5) calls these methods.
- Produces: `approveTransaction(String)` / `approveAllForWorker(String)` / `approveTransfer(String)` each return normally (queue) when offline, or write directly when online. No signature changes.

- [ ] **Step 1: Write the failing test**

Create `app/test/transaction_service_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cofiz/core/services/connectivity_service.dart';
import 'package:cofiz/core/services/offline_cache_service.dart';
import 'package:cofiz/core/services/transaction_service.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('tx_service_test');
    await OfflineCacheService().initialize(path: tempDir.path);
  });

  setUp(() {
    ConnectivityService().setOnlineForTest(false);
  });

  tearDown(() async {
    await OfflineCacheService().clearPendingOperations();
    ConnectivityService().setOnlineForTest(true);
  });

  tearDownAll(() async {
    await OfflineCacheService().clearAllCache();
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('approveTransaction queues op when offline', () async {
    final service = TransactionService(firestore: FakeFirebaseFirestore());
    await service.approveTransaction('t1');

    final ops = OfflineCacheService().getPendingOperations();
    expect(ops.length, 1);
    expect(ops.first['type'], 'approveTransaction');
    expect(ops.first['transactionId'], 't1');
  });

  test('approveTransfer queues op when offline', () async {
    final service = TransactionService(firestore: FakeFirebaseFirestore());
    await service.approveTransfer('tr-1');

    final ops = OfflineCacheService().getPendingOperations();
    expect(ops.length, 1);
    expect(ops.first['type'], 'approveTransfer');
    expect(ops.first['transferId'], 'tr-1');
  });

  test('approveAllForWorker queues op when offline', () async {
    final service = TransactionService(firestore: FakeFirebaseFirestore());
    await service.approveAllForWorker('w1');

    final ops = OfflineCacheService().getPendingOperations();
    expect(ops.length, 1);
    expect(ops.first['type'], 'approveAll');
    expect(ops.first['workerId'], 'w1');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/transaction_service_test.dart`
Expected: FAIL — `approveTransaction` attempts a Firestore write against the fake (the fake has no `t1` doc, or the write throws) instead of queueing; the queue stays empty.

- [ ] **Step 3: Implement offline queueing**

In `app/lib/core/services/transaction_service.dart`, add imports:

```dart
import 'connectivity_service.dart';
import 'offline_cache_service.dart';
```

Add an injectable Firestore seam so unit tests can pass `FakeFirebaseFirestore()`.
Change the field declaration (line 24) from:

```dart
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
```

to:

```dart
  FirebaseFirestore _firestore;

  TransactionService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;
```

Replace `approveTransaction` (lines ~306-319) with:

```dart
  /// Approve a single transaction entry
  Future<void> approveTransaction(String transactionId) async {
    if (!ConnectivityService().isOnline) {
      await OfflineCacheService().queueOperation({
        'type': 'approveTransaction',
        'transactionId': transactionId,
      });
      return;
    }
    try {
      await _firestore
          .collection(_transactionsCollection)
          .doc(transactionId)
          .update({'approved': true});
    } on FirebaseException catch (e) {
      print('Firestore error approving transaction: ${e.code} - ${e.message}');
      throw _handleFirestoreError(e);
    } catch (e) {
      print('Error approving transaction: $e');
      throw 'Failed to approve transaction. Please try again.';
    }
  }
```

Replace `approveAllForWorker` (lines ~322-342) with:

```dart
  /// Batch approve all pending transactions for a worker
  Future<void> approveAllForWorker(String workerId) async {
    if (!ConnectivityService().isOnline) {
      await OfflineCacheService().queueOperation({
        'type': 'approveAll',
        'workerId': workerId,
      });
      return;
    }
    try {
      final snapshot = await _firestore
          .collection(_transactionsCollection)
          .where('workerId', isEqualTo: workerId)
          .where('approved', isEqualTo: false)
          .get();

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {'approved': true});
      }
      await batch.commit();
    } on FirebaseException catch (e) {
      print('Firestore error batch approving: ${e.code} - ${e.message}');
      throw _handleFirestoreError(e);
    } catch (e) {
      print('Error batch approving: $e');
      throw 'Failed to approve transactions. Please try again.';
    }
  }
```

Replace `approveTransfer` (lines ~345-364) with:

```dart
  /// Approve both records of a transfer by shared transferId.
  Future<void> approveTransfer(String transferId) async {
    if (!ConnectivityService().isOnline) {
      await OfflineCacheService().queueOperation({
        'type': 'approveTransfer',
        'transferId': transferId,
      });
      return;
    }
    try {
      final snapshot = await _firestore
          .collection(_transactionsCollection)
          .where('transferId', isEqualTo: transferId)
          .get();

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {'approved': true});
      }
      await batch.commit();
    } on FirebaseException catch (e) {
      print('Firestore error approving transfer: ${e.code} - ${e.message}');
      throw _handleFirestoreError(e);
    } catch (e) {
      print('Error approving transfer: $e');
      throw 'Failed to approve transfer. Please try again.';
    }
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/transaction_service_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Run the full verify gate**

Run: `flutter analyze --no-pub` (expect 0 issues) and `flutter test` (all tests pass).
Expected: analyze reports 0 issues; all tests (existing 27 + new) pass.

- [ ] **Step 6: Commit**

```bash
git add app/lib/core/services/transaction_service.dart app/test/transaction_service_test.dart
git commit -m "feat: queue confirmation ops when offline"
```

---

### Task 5: Optimistic local confirmations in `TransactionProvider`

**Files:**
- Modify: `app/lib/core/providers/transaction_provider.dart` (three approve methods + helper)
- Test: `app/test/transaction_provider_test.dart` (new)

**Interfaces:**
- Consumes: `MoneyTransaction.copyWith` (Task 1); the `TransactionService` methods from Task 4; `ConnectivityService()` + `OfflineCacheService` for tests.
- Produces: unchanged public signatures; `approveTransaction` / `approveAllForWorker` / `approveTransfer` flip the matching entries in `_workerTransactions` to `approved: true` and `notifyListeners()` on success. Test seam `debugSetWorkerTransactions(List<MoneyTransaction>)` (`@visibleForTesting`).

- [ ] **Step 1: Write the failing test**

Create `app/test/transaction_provider_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cofiz/core/models/transaction_model.dart';
import 'package:cofiz/core/providers/transaction_provider.dart';
import 'package:cofiz/core/services/connectivity_service.dart';
import 'package:cofiz/core/services/offline_cache_service.dart';
import 'package:cofiz/core/services/transaction_service.dart';

MoneyTransaction tx(String id, {bool approved = false, String? transferId}) {
  return MoneyTransaction(
    id: id,
    workerId: 'w1',
    workerName: 'Alice',
    type: 'distribution',
    amount: 100,
    createdAt: DateTime(2026, 8, 15),
    createdBy: 'u1',
    approved: approved,
    transferId: transferId,
  );
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('tx_provider_test');
    await OfflineCacheService().initialize(path: tempDir.path);
  });

  setUp(() {
    ConnectivityService().setOnlineForTest(false);
  });

  tearDown(() async {
    await OfflineCacheService().clearPendingOperations();
    ConnectivityService().setOnlineForTest(true);
  });

  tearDownAll(() async {
    await OfflineCacheService().clearAllCache();
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('approveTransaction flips local entry', () async {
    final provider = TransactionProvider(
        transactionService: TransactionService(firestore: FakeFirebaseFirestore()));
    provider.debugSetWorkerTransactions([tx('t1', approved: false)]);

    final ok = await provider.approveTransaction('t1');

    expect(ok, isTrue);
    expect(provider.workerTransactions.single.approved, isTrue);
  });

  test('approveTransfer flips both records', () async {
    final provider = TransactionProvider(
        transactionService: TransactionService(firestore: FakeFirebaseFirestore()));
    provider.debugSetWorkerTransactions([
      tx('s1', approved: false, transferId: 'tr-1'),
      tx('r1', approved: false, transferId: 'tr-1'),
      tx('other', approved: false),
    ]);

    final ok = await provider.approveTransfer('tr-1');

    expect(ok, isTrue);
    expect(
      provider.workerTransactions.where((t) => t.approved).length,
      2,
    );
    expect(
      provider.workerTransactions.firstWhere((t) => t.id == 'other').approved,
      isFalse,
    );
  });

  test('approveAllForWorker flips all unapproved', () async {
    final provider = TransactionProvider(
        transactionService: TransactionService(firestore: FakeFirebaseFirestore()));
    provider.debugSetWorkerTransactions([
      tx('t1', approved: false),
      tx('t2', approved: false),
    ]);

    final ok = await provider.approveAllForWorker('w1');

    expect(ok, isTrue);
    expect(provider.workerTransactions.every((t) => t.approved), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/transaction_provider_test.dart`
Expected: FAIL — `debugSetWorkerTransactions` is not defined; `approved` stays false.

- [ ] **Step 3: Implement optimistic flips**

In `app/lib/core/providers/transaction_provider.dart`:

Add an injectable TransactionService seam so unit tests can pass a fake. Change
the field declaration (line 9) from:

```dart
  final TransactionService _transactionService = TransactionService();
```

to:

```dart
  final TransactionService _transactionService;

  TransactionProvider({TransactionService? transactionService})
      : _transactionService =
            transactionService ?? TransactionService();
```

Add test seam method (after `loadWorkerTransactions`, line ~70):

```dart
  /// Test seam: seed the in-memory worker transaction list directly.
  @visibleForTesting
  void debugSetWorkerTransactions(List<MoneyTransaction> transactions) {
    _workerTransactions = List.of(transactions);
  }
```

Replace `approveTransaction` (lines ~368-378) with:

```dart
  /// Approve a single transaction entry
  Future<bool> approveTransaction(String transactionId) async {
    try {
      await _transactionService.approveTransaction(transactionId);
      _flipApproved((t) => t.id == transactionId);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }
```

Replace `approveAllForWorker` (lines ~381-390) with:

```dart
  /// Batch approve all pending transactions for a worker
  Future<bool> approveAllForWorker(String workerId) async {
    try {
      await _transactionService.approveAllForWorker(workerId);
      _flipApproved((t) => t.workerId == workerId && !t.approved);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }
```

Replace `approveTransfer` (lines ~392-402) with:

```dart
  /// Approve both sides of a transfer
  Future<bool> approveTransfer(String transferId) async {
    try {
      await _transactionService.approveTransfer(transferId);
      _flipApproved((t) => t.transferId == transferId);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }
```

Add the helper method before `/// Edit an existing transaction` (line ~404):

```dart
  /// Optimistically mark matching in-memory entries as approved so the UI
  /// reflects the confirmation immediately. The live stream reconciles once
  /// back online.
  void _flipApproved(bool Function(MoneyTransaction) matches) {
    var changed = false;
    final updated = <MoneyTransaction>[];
    for (final t in _workerTransactions) {
      if (matches(t) && !t.approved) {
        updated.add(t.copyWith(approved: true));
        changed = true;
      } else {
        updated.add(t);
      }
    }
    _workerTransactions = updated;
    if (changed) notifyListeners();
  }
```

The `MoneyTransaction` type is already imported at line 4.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/transaction_provider_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Run the full verify gate**

Run: `dart format lib/core/providers/transaction_provider.dart`, then `flutter analyze --no-pub`, then `flutter test`.
Expected: analyze reports 0 issues; all tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/lib/core/providers/transaction_provider.dart app/test/transaction_provider_test.dart
git commit -m "feat: optimistic local confirmations in TransactionProvider"
```

---

### Task 6: Final verification

**Files:** none

- [ ] **Step 1: Format all changed files**

Run: `dart format lib/core/services/offline_sync_service.dart lib/core/services/transaction_service.dart lib/core/services/connectivity_service.dart lib/core/providers/transaction_provider.dart lib/core/models/transaction_model.dart`
Expected: "Formatted N files".

- [ ] **Step 2: Analyze**

Run: `flutter analyze --no-pub`
Expected: `0 issues found.`

- [ ] **Step 3: Full test suite**

Run: `flutter test`
Expected: all tests pass (existing 27 + new: 1 copyWith, 2 connectivity, 3 sync executor, 3 transaction service, 3 provider = 39 total).

- [ ] **Step 4: Confirm commits on branch**

Run: `git log --oneline -6`
Expected: 5 new commits (copyWith, connectivity seam, sync executor, offline queueing, optimistic flips) on top of the spec commit `65b923b`.
