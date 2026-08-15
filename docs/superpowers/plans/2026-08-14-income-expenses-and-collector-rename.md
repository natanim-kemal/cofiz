# Implementation Plan: Income, Expenses & Collector Rename

**Date:** 2026-08-14
**Source spec:** `docs/superpowers/specs/2026-08-14-income-expenses-and-collector-rename-design.md`
**App:** `app/` (Flutter, Material 3, Provider, Firebase Firestore)
**Branch rule:** Do NOT commit any implementation change. The parent agent reviews and commits.

## Goal

Rework the Cofiz admin app so that:

1. All user-visible "Worker/workers" text reads **"Collector/collectors"** (code identifiers, Firestore collection names, enum values, and stored `role` values stay `Worker`).
2. A new **Income** stream exists with two kinds — **Viewer Investment** (recorded by admin against a viewer account) and **Manual Sales** (admin-recorded, categorised).
3. A new **Expenses** stream exists (admin-recorded, categorised).
4. The dashboard top card shows **Investment / Collectors / Expenses / Sales** (Investment replaces Total, Expenses replaces Perf).
5. **Today's Activity** card shows Money In / Money Out + Net using the new formula.
6. The bottom dashboard section becomes a merged **Latest Transactions** feed.
7. The Collectors page drops its two big stat cards and shows a live count beside the filter chips.
8. Green background containers behind money amounts are removed everywhere; low balance stays red text only.
9. All performance indicators (Perf stat, rating stars, Performance Rating slider, avg performance) are wiped from the UI.
10. Light-mode background is lightened slightly.

## Key design decisions (from spec)

- Rename is **display-only**. Storage stays `Worker`.
- `income_records` collection fields: `kind` (`investment`|`sale`), `amount`, `description?`, `createdAt` (ms), `createdBy`, `createdByName`, investment→`viewerId`,`viewerName`; sale→`saleCategory`.
- `expenses` collection fields: `amount`, `expenseCategory`, `description?`, `createdAt` (ms), `createdBy`, `createdByName`.
- Categories live in settings docs: `settings/saleCategories` → `{categories: [...]}`, `settings/expenseCategories` → `{categories: [...]}`. Admin-manageable, defaults seeded at startup.
- Net = `(Returned + Purchased + Investment income + Manual sales) − (Distributed + Expenses)`.
- Investment card value = **all-time** total income (investments + sales). Expenses card value = all-time total expenses.
- Today's Activity two columns: **Money In** = today(Returned + Purchased + Investment income + Manual sales); **Money Out** = today(Distributed + Expenses); Net = In − Out.
- Viewers (role `viewer`) see their own investments on a **My Investments** screen (read-only). Admin sees all records on **Company Income**.
- Green money backgrounds removed; money amounts are plain text. Red text kept only for low balance. Non-money greens (status chips, success icons, buttons, chart legend) stay.
- Perf wipe keeps the `performanceRating` field in Firestore untouched; only UI references are removed.

## Environment / commands

- Working dir root: `C:\Users\Hp\.gemini\antigravity\scratch\reverse`
- Flutter app dir: `app/`
- Analyze: `flutter analyze` (run inside `app/`)
- Format: `dart format lib test`
- Regenerate localizations: `flutter gen-l10n` (inside `app/`)
- Tests: `flutter test test/<file>` (run inside `app/`)
- Device install (after a milestone): `flutter run -d 23046PNC9C --no-resident`
- ADB only at `C:\Users\Hp\AppData\Local\Android\Sdk\platform-tools\adb.exe`
- Preserve existing build fixes: `google_fonts: ^6.3.3` in `app/pubspec.yaml`, `persistAcrossBackgrounding: true, biometricOnly: true` in `app/lib/core/services/biometric_service.dart`, gradle memory settings in `app/android/gradle.properties`.

---

## Task list (execution order)

### Phase A — Data layer

- [ ] **A1** `IncomeRecord` model (+ enum `IncomeKind`) with unit tests
- [ ] **A2** `ExpenseRecord` model with unit tests
- [ ] **A3** `IncomeService` (records CRUD + sale categories)
- [ ] **A4** `ExpenseService` (records CRUD + expense categories)
- [ ] **A5** `IncomeProvider` (+ audit enum + audit screen switch updates) with unit tests
- [ ] **A6** `ExpenseProvider` with unit tests
- [ ] **A7** Wire providers into `main.dart` + seed default categories at startup

### Phase B — Rename (display only)

- [ ] **B1** Update `app_en.arb` + `app_am.arb` worker→collector strings; run `flutter gen-l10n`
- [ ] **B2** Role display mapping (`Worker.roleDisplay`, `UserRole.worker.displayName`, audit strings, hardcoded fallbacks)

### Phase C — Global polish

- [ ] **C1** Remove green money-amount backgrounds
- [ ] **C2** Wipe performance indicators
- [ ] **C3** Lighten light-mode background

### Phase D — Dashboard

- [ ] **D1** Top stats card → Investment / Collectors / Expenses / Sales
- [ ] **D2** Today's Activity card → Money In / Money Out / Net
- [ ] **D3** Latest Transactions feed replaces Active Workers section

### Phase E — Collectors page

- [ ] **E1** Remove stat cards; add filter-row count

### Phase F — New screens

- [ ] **F1** Company Income screen + Add Income dialog
- [ ] **F2** Expenses screen + Add Expense dialog
- [ ] **F3** My Investments screen (viewer)
- [ ] **F4** Sale/Expense category management screens + entries

---

## Task A1 — IncomeRecord model

**Goal:** New model + enum for income records, with pure-Dart unit tests.

**Create** `app/lib/core/models/income_record_model.dart`:

```dart
enum IncomeKind {
  investment,
  sale;

  String get name => this == IncomeKind.sale ? 'sale' : 'investment';

  static IncomeKind fromName(String? name) =>
      name == 'sale' ? IncomeKind.sale : IncomeKind.investment;
}

class IncomeRecord {
  final String id;
  final IncomeKind kind;
  final double amount;
  final String? description;
  final DateTime createdAt;
  final String createdBy;
  final String createdByName;

  // investment kind
  final String? viewerId;
  final String? viewerName;

  // sale kind
  final String? saleCategory;

  const IncomeRecord({
    required this.id,
    required this.kind,
    required this.amount,
    this.description,
    required this.createdAt,
    required this.createdBy,
    required this.createdByName,
    this.viewerId,
    this.viewerName,
    this.saleCategory,
  });

  factory IncomeRecord.fromFirestore(Map<String, dynamic> data, String id) {
    return IncomeRecord(
      id: id,
      kind: IncomeKind.fromName(data['kind']),
      amount: (data['amount'] ?? 0.0).toDouble(),
      description: data['description'],
      createdAt: data['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['createdAt'])
          : DateTime.now(),
      createdBy: data['createdBy'] ?? '',
      createdByName: data['createdByName'] ?? '',
      viewerId: data['viewerId'],
      viewerName: data['viewerName'],
      saleCategory: data['saleCategory'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'kind': kind.name,
      'amount': amount,
      'description': description,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'createdBy': createdBy,
      'createdByName': createdByName,
      'viewerId': viewerId,
      'viewerName': viewerName,
      'saleCategory': saleCategory,
    };
  }

  Map<String, dynamic> toJson() {
    return {'id': id, ...toFirestore()};
  }

  factory IncomeRecord.fromJson(Map<String, dynamic> json) {
    return IncomeRecord(
      id: json['id'] ?? '',
      kind: IncomeKind.fromName(json['kind']),
      amount: (json['amount'] ?? 0.0).toDouble(),
      description: json['description'],
      createdAt: json['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['createdAt'])
          : DateTime.now(),
      createdBy: json['createdBy'] ?? '',
      createdByName: json['createdByName'] ?? '',
      viewerId: json['viewerId'],
      viewerName: json['viewerName'],
      saleCategory: json['saleCategory'],
    );
  }

  IncomeRecord copyWith({
    String? id,
    IncomeKind? kind,
    double? amount,
    String? description,
    DateTime? createdAt,
    String? createdBy,
    String? createdByName,
    String? viewerId,
    String? viewerName,
    String? saleCategory,
  }) {
    return IncomeRecord(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      amount: amount ?? this.amount,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
      viewerId: viewerId ?? this.viewerId,
      viewerName: viewerName ?? this.viewerName,
      saleCategory: saleCategory ?? this.saleCategory,
    );
  }
}
```

**Create** `app/test/income_record_model_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cofiz/core/models/income_record_model.dart';

void main() {
  group('IncomeKind', () {
    test('name/fromName round trip', () {
      expect(IncomeKind.investment.name, 'investment');
      expect(IncomeKind.sale.name, 'sale');
      expect(IncomeKind.fromName('sale'), IncomeKind.sale);
      expect(IncomeKind.fromName('investment'), IncomeKind.investment);
      expect(IncomeKind.fromName(null), IncomeKind.investment);
      expect(IncomeKind.fromName('unknown'), IncomeKind.investment);
    });
  });

  group('IncomeRecord', () {
    final base = IncomeRecord(
      id: 'r1',
      kind: IncomeKind.investment,
      amount: 500.0,
      createdAt: DateTime(2026, 8, 14, 10, 30),
      createdBy: 'u1',
      createdByName: 'Admin',
      viewerId: 'v1',
      viewerName: 'Alem',
    );

    test('fromFirestore/toFirestore round trip (investment)', () {
      final map = base.toFirestore();
      final parsed = IncomeRecord.fromFirestore(map, 'r1');
      expect(parsed.id, 'r1');
      expect(parsed.kind, IncomeKind.investment);
      expect(parsed.amount, 500.0);
      expect(parsed.viewerId, 'v1');
      expect(parsed.viewerName, 'Alem');
      expect(parsed.saleCategory, isNull);
      expect(parsed.createdAt, DateTime(2026, 8, 14, 10, 30));
    });

    test('fromFirestore/toFirestore round trip (sale)', () {
      final sale = base.copyWith(
        id: 'r2',
        kind: IncomeKind.sale,
        viewerId: null,
        viewerName: null,
        saleCategory: 'Coffee Beans',
      );
      final parsed = IncomeRecord.fromFirestore(sale.toFirestore(), 'r2');
      expect(parsed.kind, IncomeKind.sale);
      expect(parsed.saleCategory, 'Coffee Beans');
      expect(parsed.viewerId, isNull);
    });

    test('toJson/fromJson round trip', () {
      final parsed = IncomeRecord.fromJson(base.toJson());
      expect(parsed.id, 'r1');
      expect(parsed.kind, IncomeKind.investment);
      expect(parsed.amount, 500.0);
      expect(parsed.viewerName, 'Alem');
    });
  });
}
```

> Check the package name in `app/pubspec.yaml` — if `name: cofiz` is not correct, replace the test import with the actual package name.

**Verify:** `dart format lib/core/models/income_record_model.dart test/income_record_model_test.dart && flutter analyze && flutter test test/income_record_model_test.dart`

---

## Task A2 — ExpenseRecord model

**Goal:** New model for expense records with pure-Dart unit tests.

**Create** `app/lib/core/models/expense_record_model.dart`:

```dart
class ExpenseRecord {
  final String id;
  final double amount;
  final String expenseCategory;
  final String? description;
  final DateTime createdAt;
  final String createdBy;
  final String createdByName;

  const ExpenseRecord({
    required this.id,
    required this.amount,
    required this.expenseCategory,
    this.description,
    required this.createdAt,
    required this.createdBy,
    required this.createdByName,
  });

  factory ExpenseRecord.fromFirestore(Map<String, dynamic> data, String id) {
    return ExpenseRecord(
      id: id,
      amount: (data['amount'] ?? 0.0).toDouble(),
      expenseCategory: data['expenseCategory'] ?? 'Other',
      description: data['description'],
      createdAt: data['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['createdAt'])
          : DateTime.now(),
      createdBy: data['createdBy'] ?? '',
      createdByName: data['createdByName'] ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'amount': amount,
      'expenseCategory': expenseCategory,
      'description': description,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'createdBy': createdBy,
      'createdByName': createdByName,
    };
  }

  Map<String, dynamic> toJson() {
    return {'id': id, ...toFirestore()};
  }

  factory ExpenseRecord.fromJson(Map<String, dynamic> json) {
    return ExpenseRecord(
      id: json['id'] ?? '',
      amount: (json['amount'] ?? 0.0).toDouble(),
      expenseCategory: json['expenseCategory'] ?? 'Other',
      description: json['description'],
      createdAt: json['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['createdAt'])
          : DateTime.now(),
      createdBy: json['createdBy'] ?? '',
      createdByName: json['createdByName'] ?? '',
    );
  }

  ExpenseRecord copyWith({
    String? id,
    double? amount,
    String? expenseCategory,
    String? description,
    DateTime? createdAt,
    String? createdBy,
    String? createdByName,
  }) {
    return ExpenseRecord(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      expenseCategory: expenseCategory ?? this.expenseCategory,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
    );
  }
}
```

**Create** `app/test/expense_record_model_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cofiz/core/models/expense_record_model.dart';

void main() {
  group('ExpenseRecord', () {
    final base = ExpenseRecord(
      id: 'e1',
      amount: 1200.0,
      expenseCategory: 'Rent',
      createdAt: DateTime(2026, 8, 14, 9, 0),
      createdBy: 'u1',
      createdByName: 'Admin',
    );

    test('fromFirestore/toFirestore round trip', () {
      final parsed = ExpenseRecord.fromFirestore(base.toFirestore(), 'e1');
      expect(parsed.id, 'e1');
      expect(parsed.amount, 1200.0);
      expect(parsed.expenseCategory, 'Rent');
      expect(parsed.description, isNull);
      expect(parsed.createdAt, DateTime(2026, 8, 14, 9, 0));
    });

    test('defaults description/category when missing', () {
      final parsed = ExpenseRecord.fromFirestore(
          base.copyWith(expenseCategory: 'x').toFirestore()..remove('expenseCategory'),
          'e2');
      expect(parsed.expenseCategory, 'Other');
    });

    test('toJson/fromJson round trip', () {
      final parsed = ExpenseRecord.fromJson(base.toJson());
      expect(parsed.id, 'e1');
      expect(parsed.amount, 1200.0);
      expect(parsed.createdByName, 'Admin');
    });
  });
}
```

**Verify:** `dart format lib/core/models/expense_record_model.dart test/expense_record_model_test.dart && flutter analyze && flutter test test/expense_record_model_test.dart`

---

## Task A3 — IncomeService

**Goal:** Firestore service for income records + sale-category management.

**Create** `app/lib/core/services/income_service.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/income_record_model.dart';

class IncomeService {
  static const String _collectionName = 'income_records';
  static const String _settingsDoc = 'saleCategories';
  static const String _settingsCollection = 'settings';

  static const List<String> defaultSaleCategories = [
    'Coffee Beans',
    'Processed Coffee',
    'Equipment',
    'Byproducts',
    'Other',
  ];

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DocumentReference get _categoriesRef =>
      _firestore.collection(_settingsCollection).doc(_settingsDoc);

  Stream<List<IncomeRecord>> getIncomeStream() {
    return _firestore
        .collection(_collectionName)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => IncomeRecord.fromFirestore(doc.data(), doc.id))
            .toList());
  }

  Stream<List<IncomeRecord>> getIncomeForViewerStream(String viewerId) {
    return _firestore
        .collection(_collectionName)
        .where('viewerId', isEqualTo: viewerId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => IncomeRecord.fromFirestore(doc.data(), doc.id))
            .toList());
  }

  Future<String?> addIncome(IncomeRecord record) async {
    try {
      final docRef =
          await _firestore.collection(_collectionName).add(record.toFirestore());
      return docRef.id;
    } catch (e) {
      print('Error adding income: $e');
      return null;
    }
  }

  // ---- Sale categories ----

  Future<void> initializeDefaultSaleCategories() async {
    try {
      final snap = await _categoriesRef.get();
      final categories = (snap.data()?['categories'] as List?)?.cast<String>();
      if (categories == null || categories.isEmpty) {
        await _categoriesRef.set({'categories': defaultSaleCategories});
      }
    } catch (e) {
      print('Error initializing sale categories: $e');
    }
  }

  Stream<List<String>> getSaleCategoriesStream() {
    return _categoriesRef.snapshots().map((snap) {
      final categories = (snap.data()?['categories'] as List?)?.cast<String>();
      if (categories == null || categories.isEmpty) {
        return defaultSaleCategories;
      }
      return categories;
    });
  }

  Future<List<String>> getSaleCategories() async {
    try {
      final snap = await _categoriesRef.get();
      final categories = (snap.data()?['categories'] as List?)?.cast<String>();
      if (categories == null || categories.isEmpty) {
        return defaultSaleCategories;
      }
      return categories;
    } catch (e) {
      return defaultSaleCategories;
    }
  }

  Future<bool> addSaleCategory(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    try {
      final current = await getSaleCategories();
      if (current.contains(trimmed)) return true;
      await _categoriesRef.update({
        'categories': FieldValue.arrayUnion([trimmed]),
      });
      return true;
    } catch (e) {
      print('Error adding sale category: $e');
      return false;
    }
  }

  Future<bool> removeSaleCategory(String name) async {
    if (defaultSaleCategories.contains(name)) return false;
    try {
      await _categoriesRef.update({
        'categories': FieldValue.arrayRemove([name]),
      });
      return true;
    } catch (e) {
      print('Error removing sale category: $e');
      return false;
    }
  }
}
```

**Verify:** `dart format lib/core/services/income_service.dart && flutter analyze`

---

## Task A4 — ExpenseService

**Goal:** Firestore service for expenses + expense-category management. Mirrors `IncomeService`.

**Create** `app/lib/core/services/expense_service.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/expense_record_model.dart';

class ExpenseService {
  static const String _collectionName = 'expenses';
  static const String _settingsDoc = 'expenseCategories';
  static const String _settingsCollection = 'settings';

  static const List<String> defaultExpenseCategories = [
    'Purchased Goods',
    'Salary',
    'Wages',
    'Maintenance',
    'Food',
    'Transport',
    'Rent',
    'Other',
  ];

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DocumentReference get _categoriesRef =>
      _firestore.collection(_settingsCollection).doc(_settingsDoc);

  Stream<List<ExpenseRecord>> getExpensesStream() {
    return _firestore
        .collection(_collectionName)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => ExpenseRecord.fromFirestore(doc.data(), doc.id))
            .toList());
  }

  Future<String?> addExpense(ExpenseRecord record) async {
    try {
      final docRef = await _firestore.collection(_collectionName).add(record.toFirestore());
      return docRef.id;
    } catch (e) {
      print('Error adding expense: $e');
      return null;
    }
  }

  Future<void> initializeDefaultExpenseCategories() async {
    try {
      final snap = await _categoriesRef.get();
      final categories = (snap.data()?['categories'] as List?)?.cast<String>();
      if (categories == null || categories.isEmpty) {
        await _categoriesRef.set({'categories': defaultExpenseCategories});
      }
    } catch (e) {
      print('Error initializing expense categories: $e');
    }
  }

  Stream<List<String>> getExpenseCategoriesStream() {
    return _categoriesRef.snapshots().map((snap) {
      final categories = (snap.data()?['categories'] as List?)?.cast<String>();
      if (categories == null || categories.isEmpty) {
        return defaultExpenseCategories;
      }
      return categories;
    });
  }

  Future<List<String>> getExpenseCategories() async {
    try {
      final snap = await _categoriesRef.get();
      final categories = (snap.data()?['categories'] as List?)?.cast<String>();
      if (categories == null || categories.isEmpty) {
        return defaultExpenseCategories;
      }
      return categories;
    } catch (e) {
      return defaultExpenseCategories;
    }
  }

  Future<bool> addExpenseCategory(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    try {
      final current = await getExpenseCategories();
      if (current.contains(trimmed)) return true;
      await _categoriesRef.update({
        'categories': FieldValue.arrayUnion([trimmed]),
      });
      return true;
    } catch (e) {
      print('Error adding expense category: $e');
      return false;
    }
  }

  Future<bool> removeExpenseCategory(String name) async {
    if (defaultExpenseCategories.contains(name)) return false;
    try {
      await _categoriesRef.update({
        'categories': FieldValue.arrayRemove([name]),
      });
      return true;
    } catch (e) {
      print('Error removing expense category: $e');
      return false;
    }
  }
}
```

**Verify:** `dart format lib/core/services/expense_service.dart && flutter analyze`

---

## Task A5 — IncomeProvider (+ audit support)

**Goal:** Provider that streams all income records and exposes totals; testable statics. Also extends `AuditAction` with `incomeRecorded`/`expenseRecorded` and updates the two exhaustive switches in `audit_log_screen.dart` so the app keeps compiling.

**Step 1 — Create** `app/lib/core/providers/income_provider.dart`:

```dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/income_record_model.dart';
import '../services/income_service.dart';

class IncomeProvider extends ChangeNotifier {
  IncomeProvider({IncomeService? service}) : _service = service ?? IncomeService();

  final IncomeService _service;

  List<IncomeRecord> _records = [];
  bool _isLoading = false;
  String? _errorMessage;
  StreamSubscription<List<IncomeRecord>>? _subscription;

  List<IncomeRecord> get records => List.unmodifiable(_records);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  List<IncomeRecord> get investments =>
      _records.where((r) => r.kind == IncomeKind.investment).toList();

  List<IncomeRecord> get sales =>
      _records.where((r) => r.kind == IncomeKind.sale).toList();

  double get totalIncome => sum(_records);
  double get totalInvestments => sum(investments);
  double get totalSales => sum(sales);

  double get todayInvestmentIncome => sumToday(investments);
  double get todayManualSales => sumToday(sales);
  double get todayIncome => todayInvestmentIncome + todayManualSales;

  void initialize() {
    _subscription ??= _service.getIncomeStream().listen(
      (records) {
        _records = records;
        _isLoading = false;
        _errorMessage = null;
        notifyListeners();
      },
      onError: (Object error) {
        _errorMessage = error.toString();
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  Future<bool> addIncome(IncomeRecord record) async {
    final id = await _service.addIncome(record);
    if (id == null) {
      _errorMessage = 'Failed to record income';
      notifyListeners();
      return false;
    }
    return true;
  }

  static double sum(Iterable<IncomeRecord> records) =>
      records.fold(0.0, (total, r) => total + r.amount);

  static double sumToday(Iterable<IncomeRecord> records, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final start = DateTime(reference.year, reference.month, reference.day);
    final end = start.add(const Duration(days: 1));
    return records
        .where((r) => r.createdAt.isAfter(start) && r.createdAt.isBefore(end))
        .fold(0.0, (total, r) => total + r.amount);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
```

**Step 2 — Extend `AuditAction`** in `app/lib/core/models/audit_log_model.dart`:
- Add `incomeRecorded,` and `expenseRecorded,` to the enum (after `transactionCreated`).
- Add cases to `displayName`:
  ```dart
  case AuditAction.incomeRecorded:
    return 'Income Recorded';
  case AuditAction.expenseRecorded:
    return 'Expense Recorded';
  ```
- Rename worker strings in `displayName`: `'Worker Created'` → `'Collector Created'`, `'Worker Updated'` → `'Collector Updated'`, `'Worker Deleted'` → `'Collector Deleted'`.

**Step 3 — Update the two exhaustive switches** in `app/lib/presentation/screens/audit/audit_log_screen.dart`:

- `_getActionIcon` (around line 339): add
  ```dart
  case AuditAction.incomeRecorded:
    return Icons.trending_up;
  case AuditAction.expenseRecorded:
    return Icons.receipt_long;
  ```
- `_getActionColor` (around line 370): add
  ```dart
  case AuditAction.incomeRecorded:
    return Colors.green;
  case AuditAction.expenseRecorded:
    return Colors.red;
  ```

**Create** `app/test/income_provider_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cofiz/core/models/income_record_model.dart';
import 'package:cofiz/core/providers/income_provider.dart';

void main() {
  IncomeRecord rec(IncomeKind kind, double amount, DateTime createdAt) {
    return IncomeRecord(
      id: '',
      kind: kind,
      amount: amount,
      createdAt: createdAt,
      createdBy: 'u',
      createdByName: 'Admin',
    );
  }

  group('IncomeProvider statics', () {
    test('sum totals amounts', () {
      final records = [
        rec(IncomeKind.investment, 100, DateTime(2026, 8, 1)),
        rec(IncomeKind.sale, 50, DateTime(2026, 8, 2)),
      ];
      expect(IncomeProvider.sum(records), 150.0);
    });

    test('sumToday only counts today', () {
      final now = DateTime(2026, 8, 14, 12, 0);
      final records = [
        rec(IncomeKind.investment, 100, DateTime(2026, 8, 14, 8, 0)),
        rec(IncomeKind.investment, 40, DateTime(2026, 8, 13, 23, 0)),
        rec(IncomeKind.sale, 60, DateTime(2026, 8, 14, 23, 30)),
      ];
      expect(IncomeProvider.sumToday(records, now: now), 160.0);
    });
  });
}
```

**Verify:** `dart format lib/core/providers/income_provider.dart lib/core/models/audit_log_model.dart lib/presentation/screens/audit/audit_log_screen.dart test/income_provider_test.dart && flutter analyze && flutter test test/income_provider_test.dart`

---

## Task A6 — ExpenseProvider

**Goal:** Provider that streams all expenses; testable statics.

**Create** `app/lib/core/providers/expense_provider.dart`:

```dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/expense_record_model.dart';
import '../services/expense_service.dart';

class ExpenseProvider extends ChangeNotifier {
  ExpenseProvider({ExpenseService? service})
      : _service = service ?? ExpenseService();

  final ExpenseService _service;

  List<ExpenseRecord> _records = [];
  bool _isLoading = false;
  String? _errorMessage;
  StreamSubscription<List<ExpenseRecord>>? _subscription;

  List<ExpenseRecord> get records => List.unmodifiable(_records);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  double get totalExpenses => sum(_records);
  double get todayExpenses => sumToday(_records);

  void initialize() {
    _subscription ??= _service.getExpensesStream().listen(
      (records) {
        _records = records;
        _isLoading = false;
        _errorMessage = null;
        notifyListeners();
      },
      onError: (Object error) {
        _errorMessage = error.toString();
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  Future<bool> addExpense(ExpenseRecord record) async {
    final id = await _service.addExpense(record);
    if (id == null) {
      _errorMessage = 'Failed to record expense';
      notifyListeners();
      return false;
    }
    return true;
  }

  static double sum(Iterable<ExpenseRecord> records) =>
      records.fold(0.0, (total, r) => total + r.amount);

  static double sumToday(Iterable<ExpenseRecord> records, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final start = DateTime(reference.year, reference.month, reference.day);
    final end = start.add(const Duration(days: 1));
    return records
        .where((r) => r.createdAt.isAfter(start) && r.createdAt.isBefore(end))
        .fold(0.0, (total, r) => total + r.amount);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
```

**Create** `app/test/expense_provider_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cofiz/core/models/expense_record_model.dart';
import 'package:cofiz/core/providers/expense_provider.dart';

void main() {
  ExpenseRecord rec(double amount, DateTime createdAt) {
    return ExpenseRecord(
      id: '',
      amount: amount,
      expenseCategory: 'Rent',
      createdAt: createdAt,
      createdBy: 'u',
      createdByName: 'Admin',
    );
  }

  group('ExpenseProvider statics', () {
    test('sum totals amounts', () {
      final records = [rec(100, DateTime(2026, 8, 1)), rec(50, DateTime(2026, 8, 2))];
      expect(ExpenseProvider.sum(records), 150.0);
    });

    test('sumToday only counts today', () {
      final now = DateTime(2026, 8, 14, 12, 0);
      final records = [
        rec(100, DateTime(2026, 8, 14, 8, 0)),
        rec(40, DateTime(2026, 8, 13, 23, 0)),
      ];
      expect(ExpenseProvider.sumToday(records, now: now), 100.0);
    });
  });
}
```

**Verify:** `dart format lib/core/providers/expense_provider.dart test/expense_provider_test.dart && flutter analyze && flutter test test/expense_provider_test.dart`

---

## Task A7 — Wire providers into main.dart + seed categories

**Goal:** Register the new providers and seed default categories at startup.

**Edit** `app/lib/main.dart`:

1. Add imports after `import 'core/providers/transaction_provider.dart';`:
   ```dart
   import 'core/providers/income_provider.dart';
   import 'core/providers/expense_provider.dart';
   import 'core/services/income_service.dart';
   import 'core/services/expense_service.dart';
   ```
2. In `main()`, right after `await AreaService().initializeDefaultAreas();` add:
   ```dart
   // Initialize default sale & expense categories if none exist
   await IncomeService().initializeDefaultSaleCategories();
   await ExpenseService().initializeDefaultExpenseCategories();
   ```
3. In `MultiProvider`, after `ChangeNotifierProvider(create: (_) => TransactionProvider()),` add:
   ```dart
   ChangeNotifierProvider(create: (_) => IncomeProvider()..initialize()),
   ChangeNotifierProvider(create: (_) => ExpenseProvider()..initialize()),
   ```

**Verify:** `dart format lib/main.dart && flutter analyze && flutter test`

---

## Task B1 — l10n rename (worker → collector)

**Goal:** User-visible strings say "Collector/collectors" in English and Amharic. Only the `.arb` value strings change — the key names, code identifiers, and Firestore role values stay.

**Step 1 — Edit** `app/lib/l10n/app_en.arb`:

Rename these values (key stays the same, value changes):

| key | old value | new value |
|---|---|---|
| workers | "Workers" | "Collectors" |
| activeWorkers | "Active Workers" | "Collectors" |
| noWorkersYet | "No workers yet" | "No collectors yet" |
| addWorkersToGetStarted | "Add workers to get started" | "Add collectors to get started" |
| searchWorkers | "Search workers..." | "Search collectors..." |
| noWorkersFound | "No workers found" | "No collectors found" |
| workerCommission | "Worker Commission:" | "Collector Commission:" |
| workerDeletedSuccessfully | "Worker deleted successfully" | "Collector deleted successfully" |
| workerSavedSuccessfully | "Worker saved successfully" | "Collector saved successfully" |
| workerNotFound | "Worker not found" | "Collector not found" |
| addWorker | "Add Worker" | "Add Collector" |
| editWorker | "Edit Worker" | "Edit Collector" |
| workerAccountCreated | "Worker account created!" | "Collector account created!" |
| sendCredentialsToWorker | "Send these details to the worker:" | "Send these details to the collector:" |
| pingAllWorkers | "Ping All Workers" | "Ping All Collectors" |
| messageToAllWorkers | "Message to all workers" | "Message to all collectors" |
| failedToDeleteWorker | "Failed to delete worker" | "Failed to delete collector" |
| workerSavedAccountFailed | "Worker saved, but failed to create login account: {error}" | "Collector saved, but failed to create login account: {error}" |
| workerUpdatedSuccessfully | "Worker updated successfully" | "Collector updated successfully" |
| workerAddedSuccessfully | "Worker added successfully" | "Collector added successfully" |
| failedToSaveWorker | "Failed to save worker" | "Failed to save collector" |
| allowWorkerLogin | "Allow this worker to login to the app" | "Allow this collector to login to the app" |
| filterWorkers | "Filter workers" | "Filter collectors" |
| tapToAddWorker | "Tap + to add your first worker" | "Tap + to add your first collector" |
| workerDataNotFound | "Worker data not found" | "Collector data not found" |
| addWorkersToGetStarted | (see above) | "Add collectors to get started" |
| workerNotFound | (see above) | "Collector not found" |

> Grep the file for any remaining occurrences of "worker" (case-insensitive) inside string values after editing and fix any missed ones. Do NOT rename keys.

**Step 2 — Add new keys to** `app/lib/l10n/app_en.arb` (place them alphabetically):

```json
  "addCategory": "Add Category",
  "addExpense": "Add Expense",
  "addIncome": "Add Income",
  "categoryName": "Category Name",
  "collector": "Collector",
  "collectors": "Collectors",
  "companyIncome": "Company Income",
  "defaultCategoriesCannotBeDeleted": "Default categories cannot be deleted",
  "expenseDescription": "Description",
  "expenseRecords": "Expense Records",
  "expenses": "Expenses",
  "incomeBreakdown": "Income Breakdown",
  "incomeDescription": "Description",
  "incomeRecords": "Income Records",
  "investment": "Investment",
  "investmentIncome": "Investment Income",
  "latestTransactions": "Latest Transactions",
  "manageExpenseCategories": "Manage Expense Categories",
  "manageSaleCategories": "Manage Sale Categories",
  "manualSales": "Manual Sales",
  "moneyIn": "Money In",
  "moneyOut": "Money Out",
  "myInvestments": "My Investments",
  "noViewersFound": "No viewers found",
  "recordExpense": "Record Expense",
  "recordInvestment": "Record Investment",
  "recordSale": "Record Sale",
  "recordedBy": "Recorded by",
  "sale": "Sale",
  "salesIncome": "Sales Income",
  "selectExpenseCategory": "Select Expense Category",
  "selectSaleCategory": "Select Category",
  "selectViewer": "Select Viewer",
  "totalExpenses": "Total Expenses",
  "totalIncome": "Total Income",
  "viewer": "Viewer",
  "viewerInvestment": "Viewer Investment"
```

**Step 3 — Edit** `app/lib/l10n/app_am.arb`:

1. Rename worker values ("ሰራተኛ/ሰራተኞች" → "አሰባሳቢ/አሰባሳቢዎች"), e.g.:
   - workers: "አሰባሳቢዎች"
   - activeWorkers: "አሰባሳቢዎች"
   - noWorkersYet: "እስካሁን ምንም አሰባሳቢዎች የሉም"
   - addWorkersToGetStarted: "ለመጀመር አሰባሳቢዎችን ይጨምሩ"
   - searchWorkers: "አሰባሳቢዎችን ይፈልጉ..."
   - noWorkersFound: "ምንም አሰባሳቢዎች አልተገኙም"
   - workerCommission: "የአሰባሳቢ ኮሚሽን"
   - workerDeletedSuccessfully: "አሰባሳቢ በተሳካ ሁኔታ ተሰርዟል"
   - workerSavedSuccessfully: "አሰባሳቢ በተሳካ ሁኔታ ተቀምጧል"
   - workerNotFound: "አሰባሳቢ አልተገኘም"
   - addWorker: "አሰባሳቢ ጨምር"
   - editWorker: "አሰባሳቢ አርትዕ"
   - workerAccountCreated: "የአሰባሳቢ መለያ ተፈጥሯል!"
   - sendCredentialsToWorker: "ይህንን መረጃ ለአሰባሳቢው ይላኩ:"
   - pingAllWorkers: "ለሁሉም አሰባሳቢዎች መልእክት ላክ"
   - messageToAllWorkers: "ለሁሉም አሰባሳቢዎች መልእክት"
   - failedToDeleteWorker: "አሰባሳቢውን መሰረዝ አልተቻለም"
   - workerSavedAccountFailed: "አሰባሳቢ ተቀምጧል፣ ግን የመግቢያ መለያ አልተሳካም: {error}"
   - workerUpdatedSuccessfully: "አሰባሳቢው በተሳካ ሁኔታ ተዘምኗል"
   - workerAddedSuccessfully: "አሰባሳቢው በተሳካ ሁኔታ ታክሏል"
   - failedToSaveWorker: "አሰባሳቢውን ማስቀመጥ አልተቻለም"
   - allowWorkerLogin: "ይህ አሰባሳቢ ወደ መተግበሪያው እንዲገባ ይፍቀዱ"
   - filterWorkers: "አሰባሳቢዎችን አጣራ"
   - tapToAddWorker: "የመጀመሪያውን አሰባሳቢ ለማከል + ይንኩ"
   - workerDataNotFound: "የአሰባሳቢ መረጃ አልተገኘም"
   - workerName / workerPhone / workerRole / pingWorker / pingWorkerTitle: values already non-worker-specific — leave unchanged.

2. Add new Amharic keys (same keys as English):
   ```json
   "addCategory": "ምድብ ጨምር",
   "addExpense": "ወጪ ጨምር",
   "addIncome": "ገቢ ጨምር",
   "categoryName": "የምድብ ስም",
   "collector": "አሰባሳቢ",
   "collectors": "አሰባሳቢዎች",
   "companyIncome": "የኩባንያ ገቢ",
   "defaultCategoriesCannotBeDeleted": "ነባሪ ምድቦችን መሰረዝ አይቻልም",
   "expenseDescription": "መግለጫ",
   "expenseRecords": "የወጪ መዝገቦች",
   "expenses": "ወጪዎች",
   "incomeBreakdown": "የገቢ ብልሽት",
   "incomeDescription": "መግለጫ",
   "incomeRecords": "የገቢ መዝገቦች",
   "investment": "ኢንቨስትመንት",
   "investmentIncome": "የኢንቨስትመንት ገቢ",
   "latestTransactions": "የቅርብ ጊዜ ግብይቶች",
   "manageExpenseCategories": "የወጪ ምድቦችን ያስተዳድሩ",
   "manageSaleCategories": "የሽያጭ ምድቦችን ያስተዳድሩ",
   "manualSales": "የእጅ ሽያጭ",
   "moneyIn": "ገቢ",
   "moneyOut": "ወጪ",
   "myInvestments": "የእኔ ኢንቨስትመንቶች",
   "noViewersFound": "ምንም ተመልካቾች አልተገኙም",
   "recordExpense": "ወጪ መዝግብ",
   "recordInvestment": "ኢንቨስትመንት መዝግብ",
   "recordSale": "ሽያጭ መዝግብ",
   "recordedBy": "የተመዘገበው በ",
   "sale": "ሽያጭ",
   "salesIncome": "የሽያጭ ገቢ",
   "selectExpenseCategory": "የወጪ ምድብ ይምረጡ",
   "selectSaleCategory": "ምድብ ይምረጡ",
   "selectViewer": "ተመልካች ይምረጡ",
   "totalExpenses": "ጠቅላላ ወጪ",
   "totalIncome": "ጠቅላላ ገቢ",
   "viewer": "ተመልካች",
   "viewerInvestment": "የተመልካች ኢንቨስትመንት"
   ```

**Step 4 — Regenerate:** run `flutter gen-l10n` inside `app/`, then `dart format lib/l10n && flutter analyze`.

> The generated files `app_localizations*.dart` must NOT be hand-edited.

**Verify:** `flutter gen-l10n && flutter analyze`

---

## Task B2 — Role display mapping & hardcoded strings

**Goal:** Any remaining user-visible "Worker" text not covered by l10n reads "Collector".

**Step 1 — `Worker.roleDisplay`.** Edit `app/lib/core/models/worker_model.dart` — add a getter after `statusDisplay`:

```dart
  /// Get display role text
  String get roleDisplay =>
      role.toLowerCase() == 'worker' ? 'Collector' : role;
```

**Step 2 — `UserRole.worker.displayName`.** Edit `app/lib/core/models/user_model.dart`: in the `displayName` switch change `case UserRole.worker: return 'Worker';` to `return 'Collector';`.

**Step 3 — Render `roleDisplay` instead of `role` in UI.** Grep `app/lib/presentation` for `worker.role` and `.role` (list tile usage) and replace with `roleDisplay` in these places:
- `app/lib/presentation/screens/worker_list/worker_list_screen.dart` line ~266: `role: worker.role,` → `role: worker.roleDisplay,`
- `app/lib/presentation/screens/dashboard/dashboard_screen.dart` line ~411: `worker.role,` → `worker.roleDisplay,`
- `app/lib/presentation/screens/worker_detail/worker_detail_screen.dart` line ~282: `worker.role,` → `worker.roleDisplay,`

**Step 4 — Audit strings already done in Task A5** (`audit_log_model.dart` displayName). Verify no other exhaustive switches on `AuditAction` exist (grep found only `audit_log_screen.dart`, already updated).

**Step 5 — Hardcoded fallbacks.** Grep `app/lib` (excluding `l10n/`) for string literals containing "worker" (case-insensitive) that are user-visible (fallbacks like `?? 'Worker...'`, notification bodies, report texts) and update them to "collector". Known ones to check:
- `app/lib/presentation/screens/dashboard/dashboard_screen.dart`: `'Ping All Workers'`, `'Message to all workers'`, `'Notification sent to all workers'` fallbacks.
- `app/lib/main.dart`: `'Error: Worker account not properly configured'` (worker-role device, low visibility — rename to "Collector" for consistency).
- `app/lib/core/services/notification_trigger_service.dart` and `worker_service.dart`: inspect for user-visible "worker" text and rename; comments/identifiers stay.

**Verify:** `dart format lib && flutter analyze`

---

## Task C1 — Remove green money-amount backgrounds

**Goal:** Money amounts are plain text (no `color: <green>.withOpacity(...)` background container). Low balance stays red **text only**. Keep green only for non-money elements (status chips, action buttons, success icons, ping/success snackbars, transaction type icons).

Per-file exact edits:

1. **`app/lib/presentation/widgets/worker_item.dart`** — `_buildBalanceDisplay` (lines 132-166): replace the whole method with:
   ```dart
   Widget _buildBalanceDisplay(BuildContext context) {
     final isLowBalance = currentBalance! < 500;
     final balanceColor = isLowBalance ? Colors.red : null;

     return Column(
       crossAxisAlignment: CrossAxisAlignment.end,
       mainAxisSize: MainAxisSize.min,
       children: [
         Text(
           '${AppLocalizations.of(context)?.currency ?? 'ETB'} ${currentBalance!.formatted}',
           style: TextStyle(
             fontSize: 14,
             fontWeight: FontWeight.bold,
             color: balanceColor ??
                 Theme.of(context).textTheme.bodyLarge?.color,
           ),
         ),
         if (isLowBalance)
           Text(
             AppLocalizations.of(context)!.low,
             style: TextStyle(fontSize: 10, color: balanceColor),
           ),
       ],
     );
   }
   ```
   Delete the now-unused `isDark` local in that method. Remove `if (rating > 0) _buildRating(context),` at line 107 and the `_buildRating` method (see Task C2).

2. **`app/lib/presentation/widgets/worker_transactions_list.dart`** — green amount container at ~line 102: replace the balance/amount `Container(color: <green>.withOpacity(...))` block with a plain `Text` using the theme text color; keep any low-balance red text.

3. **`app/lib/presentation/widgets/worker_transaction_tile.dart`** — same pattern; remove the green background container around the amount and render plain text.

4. **`app/lib/presentation/screens/worker_list/worker_list_screen.dart`** line 160: `color: Colors.green` on the Active `StatsCard` — remove the `color:` argument entirely (card keeps default). (Stat cards themselves are removed in Task E1; do E1 instead if sequencing.)

5. **`app/lib/presentation/screens/dashboard/dashboard_screen.dart`** lines 343-453 (Active workers balance badge): replace the `Container` balance badge with:
   ```dart
   Column(
     crossAxisAlignment: CrossAxisAlignment.end,
     mainAxisSize: MainAxisSize.min,
     children: [
       Text(
         'ETB ${worker.currentBalance.formatted}',
         style: TextStyle(
           color: isLowBalance
               ? Colors.red
               : (isDark ? Colors.white : Colors.black87),
           fontSize: 13,
           fontWeight: FontWeight.bold,
         ),
       ),
       if (isLowBalance)
         Text('Low', style: TextStyle(color: Colors.red, fontSize: 10)),
     ],
   ),
   ```
   Delete the `balanceColor` variable (line 343-344) and use only `isLowBalance`.

6. **`app/lib/presentation/screens/worker_detail/worker_detail_screen.dart`** — `_buildStatistics` `_buildStatItem` (lines 733-764) uses colored backgrounds (green/amber for perf). The perf stat is removed in Task C2; the Coffee Purchased stat remains — replace its background container with plain text (no colored bg). Change `_buildStatItem` to render icon+value+label with the theme text color and no `Container(color: ...)` decoration.

7. **`app/lib/presentation/screens/transaction/transaction_dialog.dart`** — Commission preview container (lines 413-436): remove `color: Colors.green.withOpacity(0.1)` and the green border; render as a plain row:
   ```dart
   Row(
     mainAxisAlignment: MainAxisAlignment.spaceBetween,
     children: [
       Text(
         AppLocalizations.of(context)!.workerCommission,
         style: TextStyle(
           color: isDark ? Colors.white : Colors.black87,
           fontWeight: FontWeight.bold,
         ),
       ),
       Text(
         _calculateCommission(),
         style: TextStyle(
           color: isDark ? Colors.white : Colors.black87,
           fontWeight: FontWeight.bold,
           fontSize: 16,
         ),
       ),
     ],
   ),
   ```

8. **`app/lib/presentation/screens/worker/worker_dashboard_screen.dart` + its dialogs** (`record_return_dialog.dart`, `record_purchase_dialog.dart`): remove green amount backgrounds the same way; keep red error text.

9. **`app/lib/presentation/screens/audit/audit_log_screen.dart`** lines ~374/390: those are `_getActionColor` returns (icon colors), NOT money backgrounds — **do not change** (they're non-money action colors).

10. **`app/lib/presentation/screens/reports/reports_screen.dart`** line ~549 and any money-amount container with `Colors.green.withOpacity`: remove the background, keep plain text.

11. **`app/lib/presentation/screens/auth/login_screen.dart`** line ~120: if a money/balance amount is styled with a green container, remove the background. (Login screen likely shows a hint; verify visually — it may not be a money amount; leave if it is a non-money green.)

**Verify:** `flutter analyze`, then `flutter build apk --debug` and install on device to visually confirm no green boxes remain behind amounts.

---

## Task C2 — Wipe performance indicators

**Goal:** Remove all UI references to performance/rating. Keep the Firestore `performanceRating` field and model getters.

1. **`app/lib/presentation/widgets/worker_item.dart`** — remove the `rating` field, the `if (rating > 0) _buildRating(context),` line, and the whole `_buildRating` method. Remove the now-unused `rating` constructor param and the call-site argument.
2. **`app/lib/presentation/screens/worker_list/worker_list_screen.dart`** line 269: remove `rating: worker.ratingStars,`.
3. **`app/lib/presentation/screens/worker_detail/worker_detail_screen.dart`** `_buildStatistics` (lines 679-731): remove the performance `_buildStatItem`; keep the Coffee Purchased stat. Update `_buildStatItem` to have no background container (from Task C1).
4. **`app/lib/presentation/screens/worker_form/worker_form_screen.dart`** — remove the `_performanceRating` field, its init (`line 51`), the save assignment (`line 94`), and the whole "Performance Rating" slider block (lines ~509-560). Do NOT add it back; `performanceRating` stays `70.0`-default on save.
5. **`app/lib/presentation/screens/dashboard/dashboard_screen.dart`** — the `Perf` compact stat (lines 184-189) is removed/replaced in Task D1. Remove `localizations?.perf` reference.
6. **`app/lib/core/providers/worker_provider.dart`** — remove `_avgPerformance`, its getter (`line 33`), and the computation in the update method (`lines 98-100`). Leave `_totalRevenue` untouched.
7. **`app/lib/core/services/worker_service.dart`** — leave as-is (writes `avgPerformance` to Firestore; not UI).
8. Grep `app/lib/presentation` for `rating`, `performance`, `ratingStars`, `ratingPercentage`, `avgPerformance`, `.perf` and remove any remaining UI usages.

**Verify:** `dart format lib && flutter analyze`

---

## Task C3 — Lighten light-mode background

**Edit** `app/lib/core/theme/app_theme.dart`:
- In `AppColors`, change `backgroundLight` from `#F5F5F7` (or current) to `Color(0xFFFAFAFB)` — lighter than cards but not pure white.

**Verify:** `flutter analyze`; visual check on device in light mode.

---

## Task D1 — Dashboard top stats card

**Edit** `app/lib/presentation/screens/dashboard/dashboard_screen.dart`:

1. Add imports:
   ```dart
   import '../../core/providers/income_provider.dart';
   import '../../core/providers/expense_provider.dart';
   import '../income/company_income_screen.dart';
   import '../income/my_investments_screen.dart';
   import '../expense/expenses_screen.dart';
   ```
2. Add to build() locals:
   ```dart
   final incomeProvider = Provider.of<IncomeProvider>(context);
   final expenseProvider = Provider.of<ExpenseProvider>(context);
   ```
3. Replace the four `_buildCompactStat` calls (lines 170-196) with the new slot set:
   ```dart
   _buildCompactStat(
     context,
     Icons.trending_up,
     '${localizations?.currency ?? 'ETB'} ${incomeProvider.totalIncome.formatted}',
     localizations?.investment ?? 'Investment',
     AppColors.primary,
     onTap: () {
       Navigator.push(
         context,
         MaterialPageRoute(
           builder: (context) => authProvider.isViewer
               ? const MyInvestmentsScreen()
               : const CompanyIncomeScreen(),
         ),
       );
     },
   ),
   _buildContainerDivider(isDark),
   _buildCompactStat(
     context,
     Icons.people,
     '${workerProvider.activeToday}',
     localizations?.collectors ?? 'Collectors',
     AppColors.primary,
     onTap: () => MainLayout.navigateTo(1),
   ),
   _buildContainerDivider(isDark),
   _buildCompactStat(
     context,
     Icons.receipt_long,
     '${localizations?.currency ?? 'ETB'} ${expenseProvider.totalExpenses.formatted}',
     localizations?.expenses ?? 'Expenses',
     AppColors.primary,
     onTap: () {
       Navigator.push(
         context,
         MaterialPageRoute(builder: (context) => const ExpensesScreen()),
       );
     },
   ),
   _buildContainerDivider(isDark),
   _buildCompactStat(
     context,
     Icons.local_cafe,
     '${transactionProvider.todayPurchased.formatted}',
     localizations?.sales ?? 'Sales',
     AppColors.primary,
   ),
   ```
4. Update `_buildCompactStat` signature to accept `VoidCallback? onTap` and wrap the `Column` in an `InkWell` (or `GestureDetector`) when `onTap != null`:
   ```dart
   Widget _buildCompactStat(BuildContext context, IconData icon, String value,
       String label, Color color, {VoidCallback? onTap}) {
     final content = Column(
       mainAxisSize: MainAxisSize.min,
       children: [
         Icon(icon, color: color, size: 24),
         const SizedBox(height: 8),
         Text(
           value,
           style: TextStyle(
             fontSize: 16,
             fontWeight: FontWeight.bold,
             color: Theme.of(context).textTheme.bodyLarge?.color,
           ),
         ),
         Text(
           label,
           style: TextStyle(
             fontSize: 12,
             color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7),
           ),
         ),
       ],
     );
     if (onTap == null) return content;
     return InkWell(
       onTap: onTap,
       borderRadius: BorderRadius.circular(12),
       child: content,
     );
   }
   ```
5. Remove the old "Total"/"Perf" references (the `total` compact stat with `Icons.people` and `avgPerformance` are gone).

**Verify:** `dart format lib/presentation/screens/dashboard/dashboard_screen.dart && flutter analyze`

---

## Task D2 — Today's Activity card (Money In / Money Out / Net)

**Edit** `app/lib/presentation/screens/dashboard/dashboard_screen.dart` — replace the "Today's Overview Card" body (the two rows + net block, lines ~246-294) with:

```dart
const SizedBox(height: 20),
Row(
  children: [
    Expanded(
      child: _buildTodayStatItem(
        localizations?.moneyIn ?? 'Money In',
        '${localizations?.currency ?? "ETB"} ${_todayMoneyIn(transactionProvider, incomeProvider, expenseProvider).formatted}',
        Icons.arrow_downward,
        Colors.white,
      ),
    ),
    Container(width: 1, height: 50, color: Colors.white24),
    Expanded(
      child: _buildTodayStatItem(
        localizations?.moneyOut ?? 'Money Out',
        '${localizations?.currency ?? "ETB"} ${_todayMoneyOut(transactionProvider, expenseProvider).formatted}',
        Icons.arrow_upward,
        Colors.white,
      ),
    ),
  ],
),
const SizedBox(height: 16),
Divider(color: Colors.white24),
const SizedBox(height: 12),
Row(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [
    Text(
      localizations?.netBalance ?? 'Net Balance',
      style: const TextStyle(color: Colors.white70, fontSize: 14),
    ),
    Text(
      '${localizations?.currency ?? "ETB"} ${_todayNet(transactionProvider, incomeProvider, expenseProvider).formatted}',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),
  ],
),
```

Add helper methods to the state class:

```dart
double _todayMoneyIn(TransactionProvider tp, IncomeProvider ip, ExpenseProvider ep) {
  return tp.todayReturned +
      tp.todayPurchased +
      ip.todayInvestmentIncome +
      ip.todayManualSales;
}

double _todayMoneyOut(TransactionProvider tp, ExpenseProvider ep) {
  return tp.todayDistributed + ep.todayExpenses;
}

double _todayNet(TransactionProvider tp, IncomeProvider ip, ExpenseProvider ep) {
  return _todayMoneyIn(tp, ip, ep) - _todayMoneyOut(tp, ep);
}
```

**Verify:** `dart format lib/presentation/screens/dashboard/dashboard_screen.dart && flutter analyze`

---

## Task D3 — Latest Transactions feed

**Goal:** Replace the "Active Workers" bottom section with a merged Latest Transactions feed.

**Step 1 — Create** `app/lib/presentation/widgets/activity_feed_list.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/models/expense_record_model.dart';
import '../../core/models/income_record_model.dart';
import '../../core/models/transaction_model.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/number_formatter.dart';
import '../screens/expense/expenses_screen.dart';
import '../screens/income/company_income_screen.dart';
import '../screens/worker_detail/worker_detail_screen.dart';
import '../../l10n/app_localizations.dart';

enum _FeedKind { transaction, income, expense }

class _FeedItem {
  final DateTime createdAt;
  final _FeedKind kind;
  final Object payload;
  const _FeedItem(this.createdAt, this.kind, this.payload);
}

class ActivityFeedList extends StatelessWidget {
  final List<MoneyTransaction> transactions;
  final List<IncomeRecord> incomeRecords;
  final List<ExpenseRecord> expenseRecords;
  final int limit;
  final VoidCallback? onViewAll;
  final String? emptyText;

  const ActivityFeedList({
    super.key,
    required this.transactions,
    required this.incomeRecords,
    required this.expenseRecords,
    this.limit = 8,
    this.onViewAll,
    this.emptyText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    final entries = <_FeedItem>[
      for (final t in transactions) _FeedItem(t.createdAt, _FeedKind.transaction, t),
      for (final r in incomeRecords) _FeedItem(r.createdAt, _FeedKind.income, r),
      for (final e in expenseRecords) _FeedItem(e.createdAt, _FeedKind.expense, e),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final shown = entries.take(limit).toList();

    if (shown.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                emptyText ?? l10n?.noTransactionsYet ?? 'No transactions yet',
                style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        for (final item in shown) _buildRow(context, item),
        if (onViewAll != null)
          TextButton(
            onPressed: onViewAll,
            child: Text(l10n?.viewAll ?? 'View All'),
          ),
      ],
    );
  }

  Widget _buildRow(BuildContext context, _FeedItem item) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    final textColor = isDark ? Colors.white : Colors.black87;
    final mutedColor = isDark ? AppColors.textMutedDark : AppColors.textMutedLight;

    IconData icon;
    String title;
    String subtitle;
    String amount;
    VoidCallback onTap;

    switch (item.kind) {
      case _FeedKind.transaction:
        final t = item.payload as MoneyTransaction;
        switch (t.type.toLowerCase()) {
          case 'distribution':
            icon = Icons.arrow_downward;
            title = l10n?.distributed ?? 'Distributed';
            break;
          case 'return':
            icon = Icons.arrow_upward;
            title = l10n?.returned ?? 'Returned';
            break;
          default:
            icon = Icons.local_cafe;
            title = l10n?.purchased ?? 'Purchased';
        }
        title = '$title · ${t.workerName}';
        subtitle = DateFormat('MMM d, h:mm a').format(t.createdAt);
        amount = '${l10n?.currency ?? 'ETB'} ${t.amount.formatted}';
        onTap = () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => WorkerDetailScreen(workerId: t.workerId),
            ),
          );
        };
        break;
      case _FeedKind.income:
        final r = item.payload as IncomeRecord;
        icon = Icons.trending_up;
        final kindLabel = r.kind == IncomeKind.sale
            ? (r.saleCategory ?? (l10n?.manualSales ?? 'Manual Sales'))
            : (l10n?.investment ?? 'Investment');
        title = r.kind == IncomeKind.investment
            ? '$kindLabel · ${r.viewerName ?? '-'}'
            : kindLabel;
        subtitle = DateFormat('MMM d, h:mm a').format(r.createdAt);
        amount = '+${l10n?.currency ?? 'ETB'} ${r.amount.formatted}';
        onTap = () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CompanyIncomeScreen()),
          );
        };
        break;
      case _FeedKind.expense:
        final e = item.payload as ExpenseRecord;
        icon = Icons.receipt_long;
        title = e.expenseCategory;
        subtitle = DateFormat('MMM d, h:mm a').format(e.createdAt);
        amount = '-${l10n?.currency ?? 'ETB'} ${e.amount.formatted}';
        onTap = () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ExpensesScreen()),
          );
        };
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withOpacity(0.1),
              ),
              child: Icon(icon, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: mutedColor),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              amount,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

**Step 2 — Edit `dashboard_screen.dart`:** replace the whole "Active Workers Section" block (lines 310-485) with:

```dart
// Latest Transactions Section
Row(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [
    Text(
      localizations?.latestTransactions ?? 'Latest Transactions',
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: theme.textTheme.bodyLarge?.color,
      ),
    ),
    TextButton(
      onPressed: () => MainLayout.navigateTo(1),
      child: Text(
        localizations?.viewAll ?? 'View All',
        style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  ],
),
const SizedBox(height: 12),
ActivityFeedList(
  transactions: transactionProvider.allTransactions,
  incomeRecords: incomeProvider.records,
  expenseRecords: expenseProvider.records,
),
```

Remove the `WorkerDetailScreen`/`worker_item` active-workers rendering. Add import for `ActivityFeedList`. The `workers.isNotEmpty` else-branch (empty state) is replaced by the feed's own empty state.

**Verify:** `dart format lib/presentation/widgets/activity_feed_list.dart lib/presentation/screens/dashboard/dashboard_screen.dart && flutter analyze`

---

## Task E1 — Collectors page (remove stat cards, add filter-row count)

**Edit** `app/lib/presentation/screens/worker_list/worker_list_screen.dart`:

1. Delete the "Statistics Cards" `SliverToBoxAdapter` block (lines 142-166) entirely. Remove the now-unused `import '../../widgets/stats_card.dart';`.
2. In the filter chips row (lines 176-185), wrap the chips and a count in a `Row`:
   ```dart
   child: Row(
     children: [
       Expanded(
         child: SingleChildScrollView(
           scrollDirection: Axis.horizontal,
           child: Row(
             children: [
               _buildFilterChip(AppLocalizations.of(context)!.all, 'all'),
               const SizedBox(width: 8),
               _buildFilterChip(AppLocalizations.of(context)!.active, 'active'),
               const SizedBox(width: 8),
               _buildFilterChip(AppLocalizations.of(context)!.busy, 'busy'),
               const SizedBox(width: 8),
               _buildFilterChip(AppLocalizations.of(context)!.offline, 'offline'),
             ],
           ),
         ),
       ),
       const SizedBox(width: 12),
       _buildCountBadge(context, workerProvider.workers.length),
     ],
   ),
   ```
3. Add the count badge helper (tracks the current filter because `workerProvider.workers` is already filtered by `setStatusFilter`):
   ```dart
   Widget _buildCountBadge(BuildContext context, int count) {
     final theme = Theme.of(context);
     final isDark = theme.brightness == Brightness.dark;
     return Container(
       padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
       decoration: BoxDecoration(
         color: isDark ? theme.cardColor : Colors.white,
         borderRadius: BorderRadius.circular(20),
         border: Border.all(
           color: isDark ? Colors.white12 : Colors.grey.shade300,
         ),
       ),
       child: Text(
         '$count',
         style: TextStyle(
           fontSize: 13,
           fontWeight: FontWeight.bold,
           color: AppColors.primary,
         ),
       ),
     );
   }
   ```
4. Add import for `AppColors` (already imported via `app_theme.dart`).

**Verify:** `dart format lib/presentation/screens/worker_list/worker_list_screen.dart && flutter analyze`

---

## Task F1 — Company Income screen + Add Income dialog

### 1. Create `app/lib/presentation/screens/income/company_income_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/income_record_model.dart';
import '../../../core/providers/income_provider.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/utils/number_formatter.dart';
import '../../widgets/custom_header.dart';
import 'dialogs/add_income_dialog.dart';
import '../settings/sale_categories_screen.dart';
import '../../../l10n/app_localizations.dart';

class CompanyIncomeScreen extends StatelessWidget {
  const CompanyIncomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          CustomHeader(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Row(
                  children: [
                    if (Navigator.canPop(context))
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ),
                    Text(
                      l10n.companyIncome,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.totalIncome,
                  style: const TextStyle(fontSize: 14, color: Colors.white70),
                ),
              ],
            ),
          ),
          Expanded(
            child: Consumer<IncomeProvider>(
              builder: (context, provider, _) {
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                  children: [
                    _buildTotalCard(context, provider),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildBreakdown(
                            context,
                            Icons.trending_up,
                            l10n.investmentIncome,
                            provider.totalInvestments,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildBreakdown(
                            context,
                            Icons.storefront,
                            l10n.salesIncome,
                            provider.totalSales,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const SaleCategoriesScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.category, size: 18),
                        label: Text(l10n.manageSaleCategories),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.incomeRecords,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: theme.textTheme.bodyLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (provider.records.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            l10n.noTransactionsYet,
                            style: TextStyle(
                              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                            ),
                          ),
                        ),
                      )
                    else
                      ...provider.records.map((r) => _buildRecordTile(context, r)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          if (auth.userRole?.canCreateTransactions != true) {
            return const SizedBox.shrink();
          }
          return FloatingActionButton.extended(
            onPressed: () => _showAddIncomeDialog(context),
            backgroundColor: AppColors.primary,
            icon: const Icon(Icons.add),
            label: Text(l10n.addIncome),
          );
        },
      ),
    );
  }

  Widget _buildTotalCard(BuildContext context, IncomeProvider provider) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, Color(0xFF6A8DEE)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.totalIncome,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text(
            '${l10n.currency ?? 'ETB'} ${provider.totalIncome.formatted}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.bold,
              letterSpacing: -1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdown(BuildContext context, IconData icon, String label, double value) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 22),
          const SizedBox(height: 8),
          Text(
            '${l10n.currency ?? 'ETB'} ${value.formatted}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.textMutedDark),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordTile(BuildContext context, IncomeRecord record) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final title = record.kind == IncomeKind.sale
        ? (record.saleCategory ?? l10n.manualSales)
        : (l10n.viewerInvestment);
    final subtitle = record.kind == IncomeKind.investment && record.viewerName != null
        ? '${record.viewerName} · ${DateFormat('MMM d, yyyy h:mm a').format(record.createdAt)}'
        : DateFormat('MMM d, yyyy h:mm a').format(record.createdAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withOpacity(0.1),
            ),
            child: Icon(
              record.kind == IncomeKind.sale ? Icons.storefront : Icons.trending_up,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '+${l10n.currency ?? 'ETB'} ${record.amount.formatted}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddIncomeDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (context) => const AddIncomeDialog(),
    );
  }
}
```

### 2. Create `app/lib/presentation/screens/income/dialogs/add_income_dialog.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/models/income_record_model.dart';
import '../../../../core/providers/income_provider.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/services/income_service.dart';
import '../../../../l10n/app_localizations.dart';

class AddIncomeDialog extends StatefulWidget {
  const AddIncomeDialog({super.key});

  @override
  State<AddIncomeDialog> createState() => _AddIncomeDialogState();
}

class _AddIncomeDialogState extends State<AddIncomeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();

  IncomeKind _kind = IncomeKind.investment;
  String? _selectedViewerId;
  String? _selectedViewerName;
  String? _selectedSaleCategory;
  List<String> _saleCategories = [];
  List<({String id, String name})> _viewers = [];
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadViewers();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final categories = await IncomeService().getSaleCategories();
    if (mounted) {
      setState(() {
        _saleCategories = categories;
        _selectedSaleCategory ??= categories.isNotEmpty ? categories.first : null;
      });
    }
  }

  Future<void> _loadViewers() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'viewer')
          .get();
      if (mounted) {
        setState(() {
          _viewers = snap.docs
              .map((d) => (
                    id: d.id,
                    name: (d.data()['displayName'] ?? 'Viewer') as String,
                  ))
              .toList();
        });
      }
    } catch (_) {
      // Ignore viewer load errors; user can still record a sale.
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final provider = Provider.of<IncomeProvider>(context, listen: false);

    final record = IncomeRecord(
      id: '',
      kind: _kind,
      amount: amount,
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      createdAt: DateTime.now(),
      createdBy: auth.user?.uid ?? 'unknown',
      createdByName: auth.user?.displayName ?? '',
      viewerId: _kind == IncomeKind.investment ? _selectedViewerId : null,
      viewerName: _kind == IncomeKind.investment ? _selectedViewerName : null,
      saleCategory: _kind == IncomeKind.sale ? _selectedSaleCategory : null,
    );

    setState(() => _isSubmitting = true);
    final success = await provider.addIncome(record);
    if (mounted) {
      setState(() => _isSubmitting = false);
      if (success) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.transactionCompleted),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(provider.errorMessage ?? 'Failed to record income'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: theme.dialogBackgroundColor,
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.addIncome,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: theme.textTheme.headlineMedium?.color,
                  ),
                ),
                const SizedBox(height: 16),
                SegmentedButton<IncomeKind>(
                  segments: [
                    ButtonSegment(
                      value: IncomeKind.investment,
                      label: Text(l10n.investment),
                      icon: const Icon(Icons.trending_up),
                    ),
                    ButtonSegment(
                      value: IncomeKind.sale,
                      label: Text(l10n.sale),
                      icon: const Icon(Icons.storefront),
                    ),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (selection) {
                    setState(() => _kind = selection.first);
                  },
                ),
                const SizedBox(height: 16),
                if (_kind == IncomeKind.investment) ...[
                  DropdownButtonFormField<({String id, String name})>(
                    value: _viewers.isEmpty ? null : _selectedViewer,
                    decoration: InputDecoration(
                      labelText: l10n.selectViewer,
                      prefixIcon: const Icon(Icons.person),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: isDark ? Colors.grey.shade800 : Colors.grey.shade50,
                    ),
                    items: _viewers
                        .map((v) => DropdownMenuItem(
                              value: v,
                              child: Text(v.name),
                            ))
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedViewerId = value?.id;
                        _selectedViewerName = value?.name;
                      });
                    },
                    validator: (value) =>
                        value == null ? l10n.selectViewer : null,
                  ),
                  if (_viewers.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        l10n.noViewersFound,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                        ),
                      ),
                    ),
                ] else ...[
                  DropdownButtonFormField<String>(
                    value: _saleCategories.contains(_selectedSaleCategory)
                        ? _selectedSaleCategory
                        : null,
                    decoration: InputDecoration(
                      labelText: l10n.selectSaleCategory,
                      prefixIcon: const Icon(Icons.category),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: isDark ? Colors.grey.shade800 : Colors.grey.shade50,
                    ),
                    items: _saleCategories
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (value) => setState(() => _selectedSaleCategory = value),
                    validator: (value) => value == null ? l10n.selectSaleCategory : null,
                  ),
                ],
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Amount (${l10n.currency ?? 'ETB'})',
                    prefixIcon: const Icon(Icons.attach_money),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: isDark ? Colors.grey.shade800 : Colors.grey.shade50,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return l10n.amountIsRequired;
                    }
                    final val = double.tryParse(value);
                    if (val == null || val <= 0) return l10n.invalidAmount;
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: l10n.incomeDescription,
                    hintText: l10n.notesOptional,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: isDark ? Colors.grey.shade800 : Colors.grey.shade50,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(l10n.cancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Text(l10n.confirm),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  ({String id, String name})? get _selectedViewer {
    for (final v in _viewers) {
      if (v.id == _selectedViewerId) return v;
    }
    return null;
  }
}
```

> Use a plain `'Amount (${l10n.currency ?? 'ETB'})'` label for the amount field.

**Verify:** `dart format lib/presentation/screens/income && flutter analyze`

---

## Task F2 — Expenses screen + Add Expense dialog

### 1. Create `app/lib/presentation/screens/expense/expenses_screen.dart`

Mirror of the Company Income screen but simpler (no kind toggle):

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/expense_record_model.dart';
import '../../../core/providers/expense_provider.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/utils/number_formatter.dart';
import '../../widgets/custom_header.dart';
import 'dialogs/add_expense_dialog.dart';
import '../settings/expense_categories_screen.dart';
import '../../../l10n/app_localizations.dart';

class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          CustomHeader(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Row(
                  children: [
                    if (Navigator.canPop(context))
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ),
                    Text(
                      l10n.expenses,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.totalExpenses,
                  style: const TextStyle(fontSize: 14, color: Colors.white70),
                ),
              ],
            ),
          ),
          Expanded(
            child: Consumer<ExpenseProvider>(
              builder: (context, provider, _) {
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFD9534F), Color(0xFFE8735F)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.totalExpenses,
                            style: const TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${l10n.currency ?? 'ETB'} ${provider.totalExpenses.formatted}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ExpenseCategoriesScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.category, size: 18),
                        label: Text(l10n.manageExpenseCategories),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.expenseRecords,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: theme.textTheme.bodyLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (provider.records.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            l10n.noTransactionsYet,
                            style: TextStyle(
                              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                            ),
                          ),
                        ),
                      )
                    else
                      ...provider.records.map((r) => _buildRecordTile(context, r)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          if (auth.userRole?.canCreateTransactions != true) {
            return const SizedBox.shrink();
          }
          return FloatingActionButton.extended(
            onPressed: () => _showAddExpenseDialog(context),
            backgroundColor: AppColors.primary,
            icon: const Icon(Icons.add),
            label: Text(l10n.addExpense),
          );
        },
      ),
    );
  }

  Widget _buildRecordTile(BuildContext context, ExpenseRecord record) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final subtitle = DateFormat('MMM d, yyyy h:mm a').format(record.createdAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withOpacity(0.1),
            ),
            child: const Icon(Icons.receipt_long, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.expenseCategory,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '-${l10n.currency ?? 'ETB'} ${record.amount.formatted}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddExpenseDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (context) => const AddExpenseDialog(),
    );
  }
}
```

### 2. Create `app/lib/presentation/screens/expense/dialogs/add_expense_dialog.dart`

Mirror `AddIncomeDialog` but for expenses:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/models/expense_record_model.dart';
import '../../../../core/providers/expense_provider.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/services/expense_service.dart';
import '../../../../l10n/app_localizations.dart';

class AddExpenseDialog extends StatefulWidget {
  const AddExpenseDialog({super.key});

  @override
  State<AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends State<AddExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();

  List<String> _categories = [];
  String? _selectedCategory;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final categories = await ExpenseService().getExpenseCategories();
    if (mounted) {
      setState(() {
        _categories = categories;
        _selectedCategory ??= categories.isNotEmpty ? categories.first : null;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final provider = Provider.of<ExpenseProvider>(context, listen: false);

    final record = ExpenseRecord(
      id: '',
      amount: amount,
      expenseCategory: _selectedCategory ?? 'Other',
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      createdAt: DateTime.now(),
      createdBy: auth.user?.uid ?? 'unknown',
      createdByName: auth.user?.displayName ?? '',
    );

    setState(() => _isSubmitting = true);
    final success = await provider.addExpense(record);
    if (mounted) {
      setState(() => _isSubmitting = false);
      if (success) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.transactionCompleted),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(provider.errorMessage ?? 'Failed to record expense'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: theme.dialogBackgroundColor,
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.addExpense,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: theme.textTheme.headlineMedium?.color,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _categories.contains(_selectedCategory) ? _selectedCategory : null,
                  decoration: InputDecoration(
                    labelText: l10n.selectExpenseCategory,
                    prefixIcon: const Icon(Icons.category),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: isDark ? Colors.grey.shade800 : Colors.grey.shade50,
                  ),
                  items: _categories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (value) => setState(() => _selectedCategory = value),
                  validator: (value) => value == null ? l10n.selectExpenseCategory : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Amount (${l10n.currency ?? 'ETB'})',
                    prefixIcon: const Icon(Icons.attach_money),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: isDark ? Colors.grey.shade800 : Colors.grey.shade50,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return l10n.amountIsRequired;
                    }
                    final val = double.tryParse(value);
                    if (val == null || val <= 0) return l10n.invalidAmount;
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: l10n.expenseDescription,
                    hintText: l10n.notesOptional,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: isDark ? Colors.grey.shade800 : Colors.grey.shade50,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(l10n.cancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Text(l10n.confirm),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

**Verify:** `dart format lib/presentation/screens/expense && flutter analyze`

---

## Task F3 — My Investments screen (viewer)

**Create** `app/lib/presentation/screens/income/my_investments_screen.dart`:

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/income_record_model.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/income_service.dart';
import '../../../core/utils/number_formatter.dart';
import '../../widgets/custom_header.dart';
import '../../../l10n/app_localizations.dart';

class MyInvestmentsScreen extends StatefulWidget {
  const MyInvestmentsScreen({super.key});

  @override
  State<MyInvestmentsScreen> createState() => _MyInvestmentsScreenState();
}

class _MyInvestmentsScreenState extends State<MyInvestmentsScreen> {
  List<IncomeRecord> _records = [];
  StreamSubscription<List<IncomeRecord>>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final uid = auth.user?.uid;
    if (uid == null) return;
    _subscription = IncomeService()
        .getIncomeForViewerStream(uid)
        .listen((records) {
      if (mounted) setState(() => _records = records);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final total = _records.fold<double>(0.0, (s, r) => s + r.amount);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          CustomHeader(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Row(
                  children: [
                    if (Navigator.canPop(context))
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ),
                    Text(
                      l10n.myInvestments,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.primary, Color(0xFF6A8DEE)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.totalIncome,
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${l10n.currency ?? 'ETB'} ${total.formatted}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -1,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (_records.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        l10n.noTransactionsYet,
                        style: TextStyle(
                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                        ),
                      ),
                    ),
                  )
                else
                  ..._records.map((r) => _buildRecordTile(context, r)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordTile(BuildContext context, IncomeRecord record) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withOpacity(0.1),
            ),
            child: const Icon(Icons.trending_up, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.investment,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('MMM d, yyyy h:mm a').format(record.createdAt),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '+${l10n.currency ?? 'ETB'} ${record.amount.formatted}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
```

**Verify:** `dart format lib/presentation/screens/income/my_investments_screen.dart && flutter analyze`

---

## Task F4 — Category management screens

Mirror the existing `area_management_screen.dart` pattern (read it first for the exact tile/add-dialog style).

### 1. Create `app/lib/presentation/screens/settings/sale_categories_screen.dart`

Stateful; holds a `StreamSubscription<List<String>>` from `IncomeService().getSaleCategoriesStream()`; renders an add field/dialog (`l10n.addCategory`, `l10n.categoryName`) calling `addSaleCategory`, and a delete icon per row calling `removeSaleCategory`. Default categories (`IncomeService.defaultSaleCategories`) cannot be deleted — show `l10n.defaultCategoriesCannotBeDeleted` snackbar. Uses `CustomHeader` with `l10n.manageSaleCategories` title.

### 2. Create `app/lib/presentation/screens/settings/expense_categories_screen.dart`

Same pattern using `ExpenseService()` / `ExpenseService.defaultExpenseCategories` / `l10n.manageExpenseCategories`.

(Full code is generated by the implementer following the `area_management_screen.dart` pattern; both screens are short — ~150 lines each.)

**Verify:** `dart format lib/presentation/screens/settings && flutter analyze`

---

## Global verification (run after all tasks)

```bash
cd app
dart format lib test
flutter analyze
flutter test
flutter build apk --debug
```

Then install on device and manually verify:
1. App labels say Collectors (nav tab, headers, search, empty states, ping dialogs, worker detail role, audit log worker actions).
2. Dashboard top card: Investment / Collectors / Expenses / Sales; taps navigate (Investment → Company Income for admin, My Investments for viewer; Collectors → tab 1; Expenses → Expenses screen).
3. Today's Activity: Money In / Money Out / Net correct after recording a distribution, return, investment, sale, and expense.
4. Collectors page: no big stat cards; count badge right of filter chips updates with the selected filter.
5. No green background behind any money amount anywhere; low balance is red text only.
6. No Perf/rating anywhere; worker form has no performance slider.
7. Company Income screen: record an investment (pick a viewer) and a sale (pick category); totals and records update live; audit log shows "Income Recorded".
8. Expenses screen: record an expense; total updates; audit log shows "Expense Recorded".
9. Viewer login: My Investments shows only that viewer's records (read-only).
10. Sale/Expense category management: add/delete works; defaults can't be deleted.
11. Light-mode background is lighter than before but darker than cards.

## Rollback

- All changes are uncommitted. `git checkout -- app/` reverts code. New files under `app/lib/core/models`, `app/lib/core/services`, `app/lib/core/providers`, `app/lib/presentation/screens/{income,expense}`, `app/lib/presentation/widgets/activity_feed_list.dart`, and `app/test/` must be deleted manually.
- `docs/superpowers/specs/2026-08-14-*.md` and this plan file are committed; leave them.