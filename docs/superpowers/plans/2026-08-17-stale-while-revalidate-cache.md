# Stale-While-Revalidate Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the existing Hive `OfflineCacheService` as a stale-while-revalidate layer so the reports/dashboard "main transactions" lists paint instantly from last-known data, then refresh from the live Firestore stream.

**Architecture:** Three providers (`TransactionProvider`, `IncomeProvider`, `ExpenseProvider`) seed their in-memory lists from Hive cache before hitting the network; on each fresh data emission they update state and write the list back to Hive. Cache is cleared on sign-out to prevent cross-user leakage.

**Tech Stack:** Flutter, Hive (`hive: ^2.2.3`, `hive_flutter: ^1.1.0`), cloud_firestore `^5.4.4`, Provider.

## Global Constraints

- App root: `C:\Users\Hp\.gemini\antigravity\scratch\reverse\app`
- **Do NOT commit** — standing repo rule. Skip all commit steps.
- Verify gate after each task: `dart format`, `flutter analyze --no-pub` (0 errors), `flutter test` (all pass, currently 15).
- Do not add code comments unless a line already had one.
- Models already expose `toJson()`/`fromJson()` with round-trip tests — reuse them, do not modify models.
- `Hive.initFlutter()` requires the platform channel; `OfflineCacheService.initialize()` gains an optional `path` param so unit tests can call `Hive.init(path)` instead.

---
### Task 1: Extend OfflineCacheService with income/expense caching

**Files:**
- Modify: `app/lib/core/services/offline_cache_service.dart`
- Test: `app/test/offline_cache_service_test.dart` (create)

**Interfaces:**
- Consumes: `IncomeRecord.toJson()`/`IncomeRecord.fromJson()`, `ExpenseRecord.toJson()`/`ExpenseRecord.fromJson()`, `MoneyTransaction.toJson()`/`fromJson()` (all verified present).
- Produces: `OfflineCacheService.initialize({String? path})`; `Future<void> cacheIncome(List<IncomeRecord>)`; `List<IncomeRecord>? getCachedIncome()`; `Future<void> cacheExpenses(List<ExpenseRecord>)`; `List<ExpenseRecord>? getCachedExpenses()`. Box names `income_cache`, `expenses_cache`.

- [ ] **Step 1: Write the failing test** — create `app/test/offline_cache_service_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:cofiz/core/models/expense_record_model.dart';
import 'package:cofiz/core/models/income_record_model.dart';
import 'package:cofiz/core/models/transaction_model.dart';
import 'package:cofiz/core/services/offline_cache_service.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('cache_test');
    await OfflineCacheService().initialize(path: tempDir.path);
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
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/offline_cache_service_test.dart`
Expected: FAIL — compile error, `cacheIncome` / `cacheExpenses` / `getCachedIncome` / `getCachedExpenses` not defined, and `initialize({String? path})` doesn't accept `path`.

- [ ] **Step 3: Implement** — in `offline_cache_service.dart`:

Add imports (already imports `transaction_model.dart` and `worker_model.dart`):
```dart
import '../models/income_record_model.dart';
import '../models/expense_record_model.dart';
```

Add box constants:
```dart
static const String _incomeBox = 'income_cache';
static const String _expensesBox = 'expenses_cache';
```

Change `initialize()` to accept an optional path (production callers pass nothing):
```dart
Future<void> initialize({String? path}) async {
  if (path != null) {
    Hive.init(path);
  } else {
    await Hive.initFlutter();
  }

  await Hive.openBox(_workersBox);
  await Hive.openBox(_transactionsBox);
  await Hive.openBox(_pendingBox);
  await Hive.openBox(_incomeBox);
  await Hive.openBox(_expensesBox);
}
```

Add income cache methods (after the transactions cache section):
```dart
// Income cache
Future<void> cacheIncome(List<IncomeRecord> records) async {
  final box = Hive.box(_incomeBox);
  final recordsMap = {for (var r in records) r.id: r.toJson()};
  await box.put('all_income', recordsMap);
}

List<IncomeRecord>? getCachedIncome() {
  final box = Hive.box(_incomeBox);
  final cached = box.get('all_income') as Map<dynamic, dynamic>?;
  if (cached == null) return null;

  return cached.values
      .map((json) =>
          IncomeRecord.fromJson(Map<String, dynamic>.from(json as Map)))
      .toList();
}

// Expenses cache
Future<void> cacheExpenses(List<ExpenseRecord> records) async {
  final box = Hive.box(_expensesBox);
  final recordsMap = {for (var r in records) r.id: r.toJson()};
  await box.put('all_expenses', recordsMap);
}

List<ExpenseRecord>? getCachedExpenses() {
  final box = Hive.box(_expensesBox);
  final cached = box.get('all_expenses') as Map<dynamic, dynamic>?;
  if (cached == null) return null;

  return cached.values
      .map((json) =>
          ExpenseRecord.fromJson(Map<String, dynamic>.from(json as Map)))
      .toList();
}
```

Update `clearAllCache()`:
```dart
Future<void> clearAllCache() async {
  await Hive.box(_workersBox).clear();
  await Hive.box(_transactionsBox).clear();
  await Hive.box(_incomeBox).clear();
  await Hive.box(_expensesBox).clear();
  await Hive.box(_pendingBox).clear();
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/offline_cache_service_test.dart`
Expected: PASS — 4 tests.

Run: `dart format lib/core/services/offline_cache_service.dart test/offline_cache_service_test.dart && flutter analyze --no-pub && flutter test`
Expected: 0 errors, all 19 tests pass (15 existing + 4 new).

---
### Task 2: Wire TransactionProvider stale-while-revalidate

**Files:**
- Modify: `app/lib/core/providers/transaction_provider.dart:124-137`

**Interfaces:**
- Consumes: `OfflineCacheService().getCachedTransactions()` (returns `List<MoneyTransaction>?`), `OfflineCacheService().cacheTransactions(List<MoneyTransaction>)` from Task 1.
- Produces: no new public API; `loadAllTransactions()` behavior change.

- [ ] **Step 1: Implement** — add import:

```dart
import '../services/offline_cache_service.dart';
```

Replace `loadAllTransactions()`:
```dart
/// Load all transactions - seed from cache instantly, then refresh live.
void loadAllTransactions() {
  final cached = OfflineCacheService().getCachedTransactions();
  if (cached != null) {
    _allTransactions = cached;
    notifyListeners();
  }

  _transactionService.getAllTransactionsStream().listen(
    (transactions) {
      _allTransactions = transactions;
      OfflineCacheService().cacheTransactions(transactions);
      notifyListeners();
    },
    onError: (error) {
      print('Error loading all transactions: $error');
      _errorMessage = _parseError(error);
      notifyListeners();
    },
  );
}
```

- [ ] **Step 2: Verify** — run `dart format lib/core/providers/transaction_provider.dart && flutter analyze --no-pub`
Expected: 0 errors. (Firestore-dependent provider logic is not unit-tested in this repo; the gate is analyze + the Task 1 cache tests.)

---
### Task 3: Wire IncomeProvider + ExpenseProvider stale-while-revalidate

**Files:**
- Modify: `app/lib/core/providers/income_provider.dart:143-146`
- Modify: `app/lib/core/providers/expense_provider.dart:112-115`

**Interfaces:**
- Consumes: `OfflineCacheService().getCachedIncome()`, `cacheIncome(...)`, `getCachedExpenses()`, `cacheExpenses(...)` from Task 1.
- Produces: no new public API; `loadFullRecords()` behavior change in both providers.

- [ ] **Step 1: Implement income** — add import:

```dart
import '../services/offline_cache_service.dart';
```

Replace `loadFullRecords()`:
```dart
/// Load the complete dataset (used by reports/export screens).
Future<void> loadFullRecords() async {
  final cached = OfflineCacheService().getCachedIncome();
  if (cached != null) {
    _fullRecords = cached;
    notifyListeners();
  }

  final records = await _service.getAllIncome();
  _fullRecords = records;
  await OfflineCacheService().cacheIncome(records);
  notifyListeners();
}
```

- [ ] **Step 2: Implement expense** — add import:

```dart
import '../services/offline_cache_service.dart';
```

Replace `loadFullRecords()`:
```dart
/// Load the complete dataset (used by reports/export screens).
Future<void> loadFullRecords() async {
  final cached = OfflineCacheService().getCachedExpenses();
  if (cached != null) {
    _fullRecords = cached;
    notifyListeners();
  }

  final records = await _service.getAllExpenses();
  _fullRecords = records;
  await OfflineCacheService().cacheExpenses(records);
  notifyListeners();
}
```

- [ ] **Step 3: Verify** — run `dart format lib/core/providers/income_provider.dart lib/core/providers/expense_provider.dart && flutter analyze --no-pub && flutter test`
Expected: 0 errors, all 19 tests pass.

---
### Task 4: Clear cache on sign-out

**Files:**
- Modify: `app/lib/core/providers/auth_provider.dart:135-177`

**Interfaces:**
- Consumes: `OfflineCacheService().clearAllCache()` from Task 1.
- Produces: no new public API; `signOut()` clears Hive cache in both success and error paths.

- [ ] **Step 1: Implement** — add import:

```dart
import '../services/offline_cache_service.dart';
```

In `signOut()` success path, after `await _authService.signOut();` add:
```dart
await OfflineCacheService().clearAllCache();
```

In the catch block, after `_status = AuthStatus.unauthenticated;` (the last duplicate lines before `notifyListeners();`), add the same line wrapped so sign-out still succeeds even if cache clearing throws:
```dart
try {
  await OfflineCacheService().clearAllCache();
} catch (_) {}
```

- [ ] **Step 2: Verify** — run `dart format lib/core/providers/auth_provider.dart && flutter analyze --no-pub && flutter test`
Expected: 0 errors, all 19 tests pass.

---
### Task 5: Full verification

- [ ] **Step 1: Run the full verify gate**

Run: `dart format . && flutter analyze --no-pub && flutter test`
Expected: format clean, 0 analyzer errors, all tests pass (19 total).

- [ ] **Step 2: Manual smoke check (on device/emulator)**
- Cold-start the app, open Reports: first paint should show last-known transactions immediately, then refresh within a second or two once the stream emits.
- Sign out, sign in as a different user: Reports should NOT show the previous user's cached transactions.