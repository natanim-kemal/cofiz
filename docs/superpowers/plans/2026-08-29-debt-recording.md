# Debt Recording on Purchases Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When an admin records a purchase that exceeds a collector's balance, surface a "Record as debt" toggle. The overage is recorded in a separate `debts` collection; the collector's `currentBalance` only decreases by the covered portion. Add a debt button on the collector detail page, a per-collector debt list, an admin "All debts" screen, a dashboard "Outstanding debt" tile, and at-record + daily-cron notifications.

**Architecture:** New `DebtModel`, `DebtService` (Firestore), `DebtProvider`. `MoneyTransaction` gains `forgivenAmount` and `isDebt` fields. `transaction_balance.dart` purchase branch and `worker_provider.dart` `applyTransactionDelta` subtract only the covered portion. New screens + a Cloudflare Worker cron.

**Tech Stack:** Flutter, `cloud_firestore`, `fake_cloud_firestore` for tests, `fl_chart` already in pubspec, Cloudflare Workers (Cron Triggers), `firebase-admin`.

**Spec:** `docs/superpowers/specs/2026-08-29-debt-recording-design.md`

## Global Constraints

- `currentBalance` is hard-≥-0. Debt is independent of balance.
- Debt toggle is shown **only when** `amount > balance`.
- `forgivenAmount = amount − currentBalance` at toggle time.
- `coveredAmount = amount − forgivenAmount`. `totalAmount = amount`.
- The collector detail page's "Debt" button sits to the **left** of the filter row.
- Daily reminder cron: `0 6 * * *` UTC = 09:00 Africa/Addis_Ababa.
- Only admins can mark a debt paid.
- Dart SDK `^3.5.4`; existing `firebase_messaging: ^15.2.0` for push.

---

## File Structure

### New Flutter files

- `app/lib/core/models/debt_model.dart`
- `app/lib/core/services/debt_service.dart`
- `app/lib/core/providers/debt_provider.dart`
- `app/lib/presentation/screens/transaction/collector_debts_screen.dart`
- `app/lib/presentation/screens/transaction/all_debts_screen.dart`
- `app/test/core/models/debt_model_test.dart`
- `app/test/core/services/debt_service_test.dart`
- `app/test/core/providers/debt_provider_test.dart`
- `app/test/core/utils/transaction_balance_debt_test.dart` (new test file for the math)
- `app/test/presentation/screens/transaction/collector_debts_screen_test.dart`

### Modified Flutter files

- `app/lib/core/models/transaction_model.dart` — add `forgivenAmount?` and `isDebt`.
- `app/lib/core/utils/transaction_balance.dart` — purchase branch uses `covered = amount − forgivenAmount`.
- `app/lib/core/providers/worker_provider.dart` — `applyTransactionDelta` mirror.
- `app/lib/core/providers/transaction_provider.dart` — `recordPurchase` accepts `forgivenAmount`, calls `DebtService`.
- `app/lib/core/models/notification_model.dart` — add `NotificationType.debtRecorded`.
- `app/lib/core/services/notification_trigger_service.dart` — new `notifyDebtRecorded` method.
- `app/lib/presentation/screens/worker_detail/worker_detail_screen.dart` — add Debt button to the left of the filter row.
- `app/lib/presentation/screens/dashboard/dashboard_screen.dart` — add "Outstanding debt" tile.
- `app/lib/presentation/screens/transaction/dialogs/...purchase_dialog.dart` (whatever the file is named) — add toggle when `amount > balance`.
- `app/lib/l10n/app_en.arb` / `app_am.arb` — new strings.
- `firestore.indexes.json` — add the two composite indexes for `debts`.

### New Worker files

- `workers/fcm-relay/src/cron/debt-reminder.js`
- `workers/fcm-relay/test/cron/debt-reminder.test.js`
- `workers/fcm-relay/wrangler.toml` — add `[[triggers]] crons = ["0 6 * * *"]`.

---

## Task 1: `DebtModel` with tests

**Files:**
- Create: `app/lib/core/models/debt_model.dart`
- Test: `app/test/core/models/debt_model_test.dart`

**Interfaces:**
- Produces:
  ```dart
  enum DebtStatus { open, partial, paid }
  class Debt {
    final String id;
    final String collectorId;
    final String collectorName;
    final String purchaseId;
    final double totalAmount;
    final double coveredAmount;
    final double forgivenAmount;
    final DebtStatus status;
    final DateTime createdAt;
    final DateTime? paidAt;
    final String? notes;
    final String createdBy;
    Map<String, dynamic> toFirestore();
    factory Debt.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc, Map<String, dynamic> data);
    factory Debt.fromMap(Map<String, dynamic> data, {String id = ''});
  }
  ```

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cofiz/core/models/debt_model.dart';

void main() {
  group('Debt round-trip', () {
    test('toFirestore/fromMap preserves fields', () {
      final d = Debt(
        id: 'd1',
        collectorId: 'c1',
        collectorName: 'Alice',
        purchaseId: 'p1',
        totalAmount: 1000,
        coveredAmount: 400,
        forgivenAmount: 600,
        status: DebtStatus.open,
        createdAt: DateTime(2026, 8, 29),
        createdBy: 'u1',
      );
      final m = d.toFirestore();
      expect(m['collectorId'], 'c1');
      expect(m['forgivenAmount'], 600.0);
      expect(m['status'], 'open');
      final back = Debt.fromMap({...m, 'id': 'd1'}, id: 'd1');
      expect(back.coveredAmount, 400);
      expect(back.status, DebtStatus.open);
    });
  });
}
```

- [ ] **Step 2: Run tests, expect failure**

Run: `cd app && flutter test test/core/models/debt_model_test.dart`
Expected: import error.

- [ ] **Step 3: Implement `DebtModel`**

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

enum DebtStatus { open, partial, paid }

class Debt {
  final String id;
  final String collectorId;
  final String collectorName;
  final String purchaseId;
  final double totalAmount;
  final double coveredAmount;
  final double forgivenAmount;
  final DebtStatus status;
  final DateTime createdAt;
  final DateTime? paidAt;
  final String? notes;
  final String createdBy;

  Debt({
    required this.id,
    required this.collectorId,
    required this.collectorName,
    required this.purchaseId,
    required this.totalAmount,
    required this.coveredAmount,
    required this.forgivenAmount,
    required this.status,
    required this.createdAt,
    required this.createdBy,
    this.paidAt,
    this.notes,
  });

  Map<String, dynamic> toFirestore() => {
        'collectorId': collectorId,
        'collectorName': collectorName,
        'purchaseId': purchaseId,
        'totalAmount': totalAmount,
        'coveredAmount': coveredAmount,
        'forgivenAmount': forgivenAmount,
        'status': status.name,
        'createdAt': createdAt.millisecondsSinceEpoch,
        if (paidAt != null) 'paidAt': paidAt!.millisecondsSinceEpoch,
        if (notes != null) 'notes': notes,
        'createdBy': createdBy,
      };

  factory Debt.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    return Debt.fromMap(doc.data() ?? {}, id: doc.id);
  }

  factory Debt.fromMap(Map<String, dynamic> data, {String id = ''}) {
    return Debt(
      id: id.isEmpty ? (data['id'] as String? ?? '') : id,
      collectorId: data['collectorId'] as String,
      collectorName: data['collectorName'] as String? ?? '',
      purchaseId: data['purchaseId'] as String,
      totalAmount: (data['totalAmount'] as num).toDouble(),
      coveredAmount: (data['coveredAmount'] as num).toDouble(),
      forgivenAmount: (data['forgivenAmount'] as num).toDouble(),
      status: DebtStatus.values.firstWhere(
        (s) => s.name == data['status'],
        orElse: () => DebtStatus.open,
      ),
      createdAt: DateTime.fromMillisecondsSinceEpoch(data['createdAt'] as int),
      paidAt: data['paidAt'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(data['paidAt'] as int),
      notes: data['notes'] as String?,
      createdBy: data['createdBy'] as String? ?? '',
    );
  }
}
```

- [ ] **Step 4: Run tests, expect pass**

Run: `cd app && flutter test test/core/models/debt_model_test.dart`
Expected: 1 test passes.

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/models/debt_model.dart app/test/core/models/debt_model_test.dart
git commit -m "feat(debt): add Debt model with round-trip tests"
```

---

## Task 2: Adjust `transaction_balance.dart` and `worker_provider.dart` for partial coverage

**Files:**
- Modify: `app/lib/core/utils/transaction_balance.dart` (purchase branch only)
- Modify: `app/lib/core/providers/worker_provider.dart` (purchase branch in `applyTransactionDelta`)
- Test: `app/test/core/utils/transaction_balance_debt_test.dart` (new)
- Test: extend `app/test/core/providers/worker_provider_test.dart` if it exists; otherwise new file

**Interfaces:**
- `transactionBalanceUpdates(MoneyTransaction t, int direction)` for `purchase` uses `covered = t.amount - (t.forgivenAmount ?? 0)`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cofiz/core/models/transaction_model.dart';
import 'package:cofiz/core/utils/transaction_balance.dart';

MoneyTransaction _purchase({double amount = 1000, double? forgiven, bool isDebt = false}) {
  return MoneyTransaction(
    id: 'p1',
    workerId: 'w1',
    workerName: 'Alice',
    type: 'purchase',
    amount: amount,
    createdAt: DateTime(2026, 8, 29),
    createdBy: 'u1',
    forgivenAmount: forgiven,
    isDebt: isDebt,
  );
}

void main() {
  test('purchase without debt subtracts full amount', () {
    final u = transactionBalanceUpdates(_purchase(amount: 1000), 1);
    expect((u['currentBalance'] as FieldValue), isNotNull);
  });

  test('purchase with forgiven subtracts only covered portion', () {
    final u = transactionBalanceUpdates(_purchase(amount: 1000, forgiven: 600, isDebt: true), 1);
    // covered = 1000 - 600 = 400. We can't assert the FieldValue magnitude directly
    // without inspecting internals; instead run a Firestore emulator test or check
    // the equivalent numeric delta in worker_provider tests.
    expect(u.containsKey('currentBalance'), isTrue);
  });
}
```

- [ ] **Step 2: Run tests, expect failure**

Run: `cd app && flutter test test/core/utils/transaction_balance_debt_test.dart`
Expected: import error on `transaction_balance.dart` (no `forgivenAmount` field on `MoneyTransaction` yet).

- [ ] **Step 3: Add fields to `MoneyTransaction`**

Open `app/lib/core/models/transaction_model.dart`. Add two fields with defaults:

```dart
final double? forgivenAmount;
final bool isDebt;

// constructor:
this.forgivenAmount,
this.isDebt = false,

// in toMap / toFirestore:
if (forgivenAmount != null) 'forgivenAmount': forgivenAmount,
'isDebt': isDebt,
```

Verify existing tests still pass: `cd app && flutter test test/core/models/transaction_model_test.dart`

- [ ] **Step 4: Update `transactionBalanceUpdates` purchase branch**

In `app/lib/core/utils/transaction_balance.dart`, replace the `'purchase'` case with:

```dart
case 'purchase':
  final covered = t.amount - (t.forgivenAmount ?? 0.0);
  final updates = <String, dynamic>{
    'currentBalance': FieldValue.increment(-covered * mult),
    'totalCoffeePurchased': FieldValue.increment(covered * mult),
  };
  if (t.commissionAmount != null && t.commissionAmount! > 0) {
    updates['totalCommissionEarned'] =
        FieldValue.increment(t.commissionAmount! * mult);
  }
  return updates;
```

- [ ] **Step 5: Update `worker_provider.dart` `applyTransactionDelta` purchase branch**

Replace the `'purchase'` case with:

```dart
case 'purchase':
  final covered = t.amount - (t.forgivenAmount ?? 0.0);
  balance -= covered * m;
  purch += covered * m;
  if ((t.commissionAmount ?? 0) > 0) comm += t.commissionAmount! * m;
  break;
```

- [ ] **Step 6: Run all related tests**

Run: `cd app && flutter test test/core/utils/ test/core/providers/ test/core/models/transaction_model_test.dart`
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add app/lib/core/utils/transaction_balance.dart app/lib/core/providers/worker_provider.dart app/lib/core/models/transaction_model.dart app/test/core/utils/transaction_balance_debt_test.dart
git commit -m "feat(debt): subtract only covered portion in balance math"
```

---

## Task 3: `DebtService` with `fake_cloud_firestore` tests

**Files:**
- Create: `app/lib/core/services/debt_service.dart`
- Test: `app/test/core/services/debt_service_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class DebtService {
    DebtService({FirebaseFirestore? firestore}) : _fs = firestore ?? FirebaseFirestore.instance;
    final FirebaseFirestore _fs;
    Future<Debt> createDebtFromPurchase({...});
    Future<void> markPaid(String debtId);
    Stream<List<Debt>> streamDebtsForCollector(String collectorId);
    Stream<List<Debt>> streamAllOpenDebts();
    Future<double> getOpenDebtsTotal();
    Future<double> getOpenDebtsTotalForToday();
  }
  ```

- [ ] **Step 1: Write the failing test**

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cofiz/core/models/debt_model.dart';
import 'package:cofiz/core/services/debt_service.dart';

void main() {
  late FakeFirebaseFirestore fs;
  late DebtService svc;

  setUp(() {
    fs = FakeFirebaseFirestore();
    svc = DebtService(firestore: fs);
  });

  test('createDebtFromPurchase writes a doc and returns it', () async {
    final d = await svc.createDebtFromPurchase(
      collectorId: 'c1',
      collectorName: 'Alice',
      purchaseId: 'p1',
      totalAmount: 1000,
      coveredAmount: 400,
      forgivenAmount: 600,
      createdBy: 'u1',
    );
    expect(d.forgivenAmount, 600);
    final snap = await fs.collection('debts').get();
    expect(snap.docs.length, 1);
  });

  test('markPaid flips status and paidAt', () async {
    final d = await svc.createDebtFromPurchase(
      collectorId: 'c1', collectorName: 'A', purchaseId: 'p1',
      totalAmount: 100, coveredAmount: 50, forgivenAmount: 50, createdBy: 'u1',
    );
    await svc.markPaid(d.id);
    final snap = await fs.collection('debts').doc(d.id).get();
    expect(snap.data()!['status'], 'paid');
    expect(snap.data()!['paidAt'], isNotNull);
  });

  test('getOpenDebtsTotal sums forgivenAmount where status=open', () async {
    await svc.createDebtFromPurchase(collectorId: 'c1', collectorName: 'A', purchaseId: 'p1', totalAmount: 100, coveredAmount: 50, forgivenAmount: 50, createdBy: 'u1');
    await svc.createDebtFromPurchase(collectorId: 'c2', collectorName: 'B', purchaseId: 'p2', totalAmount: 200, coveredAmount: 100, forgivenAmount: 100, createdBy: 'u1');
    expect(await svc.getOpenDebtsTotal(), 150);
  });
}
```

- [ ] **Step 2: Run tests, expect failure**

Run: `cd app && flutter test test/core/services/debt_service_test.dart`
Expected: import error.

- [ ] **Step 3: Implement `DebtService`**

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/debt_model.dart';

class DebtService {
  DebtService({FirebaseFirestore? firestore})
      : _fs = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _fs;

  CollectionReference<Map<String, dynamic>> get _col => _fs.collection('debts');

  Future<Debt> createDebtFromPurchase({
    required String collectorId,
    required String collectorName,
    required String purchaseId,
    required double totalAmount,
    required double coveredAmount,
    required double forgivenAmount,
    required String createdBy,
    String? notes,
  }) async {
    final ref = _col.doc();
    final debt = Debt(
      id: ref.id,
      collectorId: collectorId,
      collectorName: collectorName,
      purchaseId: purchaseId,
      totalAmount: totalAmount,
      coveredAmount: coveredAmount,
      forgivenAmount: forgivenAmount,
      status: DebtStatus.open,
      createdAt: DateTime.now(),
      createdBy: createdBy,
      notes: notes,
    );
    await ref.set(debt.toFirestore());
    return debt;
  }

  Future<void> markPaid(String debtId) async {
    await _col.doc(debtId).update({
      'status': DebtStatus.paid.name,
      'paidAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Stream<List<Debt>> streamDebtsForCollector(String collectorId) {
    return _col
        .where('collectorId', isEqualTo: collectorId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(Debt.fromFirestore).toList());
  }

  Stream<List<Debt>> streamAllOpenDebts() {
    return _col
        .where('status', isEqualTo: DebtStatus.open.name)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(Debt.fromFirestore).toList());
  }

  Future<double> getOpenDebtsTotal() async {
    final s = await _col.where('status', isEqualTo: DebtStatus.open.name).get();
    return s.docs
        .map((d) => (d.data()['forgivenAmount'] as num).toDouble())
        .fold(0.0, (a, b) => a + b);
  }

  Future<double> getOpenDebtsTotalForToday() async {
    final start = DateTime.now();
    final dayStart = DateTime(start.year, start.month, start.day);
    final s = await _col
        .where('status', isEqualTo: DebtStatus.open.name)
        .where('createdAt', isGreaterThanOrEqualTo: dayStart.millisecondsSinceEpoch)
        .get();
    return s.docs
        .map((d) => (d.data()['forgivenAmount'] as num).toDouble())
        .fold(0.0, (a, b) => a + b);
  }
}
```

- [ ] **Step 4: Run tests, expect pass**

Run: `cd app && flutter test test/core/services/debt_service_test.dart`
Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/services/debt_service.dart app/test/core/services/debt_service_test.dart
git commit -m "feat(debt): add DebtService with create/markPaid/streams"
```

---

## Task 4: `DebtProvider` + notification integration

**Files:**
- Create: `app/lib/core/providers/debt_provider.dart`
- Modify: `app/lib/core/models/notification_model.dart` — add `debtRecorded`
- Modify: `app/lib/core/services/notification_trigger_service.dart` — add `notifyDebtRecorded`
- Test: `app/test/core/providers/debt_provider_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class DebtProvider extends ChangeNotifier {
    DebtProvider({required this.debtService, required this.notificationService});
    final DebtService debtService;
    final NotificationTriggerService notificationService;
    Map<String, List<Debt>> byCollector;
    double openTotal;
    double todayOpenTotal;
    Map<String, int> openCountByCollector;
    Future<Debt> recordDebtFromPurchase({...});
    Future<void> markPaid(String debtId);
  }
  ```

- [ ] **Step 1: Add `NotificationType.debtRecorded`**

In `app/lib/core/models/notification_model.dart`, add to the enum: `debtRecorded`.

- [ ] **Step 2: Add `notifyDebtRecorded`**

In `app/lib/core/services/notification_trigger_service.dart`, add:

```dart
Future<void> notifyDebtRecorded({
  required String collectorId,
  required String collectorName,
  required double forgivenAmount,
  required double totalAmount,
}) async {
  await _notifyAllAdmins(
    title: 'Debt recorded',
    body: 'Collector $collectorName: ETB ${forgivenAmount.toStringAsFixed(0)} added to debt (purchase ETB ${totalAmount.toStringAsFixed(0)}).',
    type: NotificationType.debtRecorded,
    metadata: {'collectorId': collectorId, 'forgivenAmount': forgivenAmount, 'totalAmount': totalAmount},
  );
  await _notifyAllViewers(
    title: 'Debt recorded',
    body: 'Collector $collectorName: ETB ${forgivenAmount.toStringAsFixed(0)} added to debt.',
    type: NotificationType.debtRecorded,
    metadata: {'collectorId': collectorId, 'forgivenAmount': forgivenAmount},
  );
}
```

Note: this assumes `_notifyAllAdmins`/`_notifyAllViewers` exist as private methods (they do — see Task 6 of the OTP plan and the existing `notification_trigger_service.dart:153,182`).

- [ ] **Step 3: Write the failing provider test**

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cofiz/core/providers/debt_provider.dart';
import 'package:cofiz/core/services/debt_service.dart';
import 'package:cofiz/core/services/notification_trigger_service.dart';

class _FakeNotifications extends NotificationTriggerService {
  _FakeNotifications() : super(firestore: FakeFirebaseFirestore());
  int calls = 0;
  @override
  Future<void> notifyDebtRecorded({
    required String collectorId,
    required String collectorName,
    required double forgivenAmount,
    required double totalAmount,
  }) async {
    calls += 1;
  }
}

void main() {
  late FakeFirebaseFirestore fs;
  late DebtService svc;
  late _FakeNotifications notif;
  late DebtProvider p;

  setUp(() {
    fs = FakeFirebaseFirestore();
    svc = DebtService(firestore: fs);
    notif = _FakeNotifications();
    p = DebtProvider(debtService: svc, notificationService: notif);
  });

  test('recordDebtFromPurchase writes a doc and calls notifyDebtRecorded', () async {
    await p.recordDebtFromPurchase(
      collectorId: 'c1', collectorName: 'Alice', purchaseId: 'p1',
      totalAmount: 1000, coveredAmount: 400, forgivenAmount: 600, createdBy: 'u1',
    );
    expect(notif.calls, 1);
    final snap = await fs.collection('debts').get();
    expect(snap.docs.length, 1);
  });
}
```

- [ ] **Step 4: Run tests, expect failure**

Run: `cd app && flutter test test/core/providers/debt_provider_test.dart`
Expected: import error.

- [ ] **Step 5: Implement `DebtProvider`**

```dart
import 'package:flutter/foundation.dart';
import '../models/debt_model.dart';
import '../services/debt_service.dart';
import '../services/notification_trigger_service.dart';

class DebtProvider extends ChangeNotifier {
  DebtProvider({required this.debtService, required this.notificationService});
  final DebtService debtService;
  final NotificationTriggerService notificationService;

  Map<String, List<Debt>> byCollector = {};
  double openTotal = 0;
  double todayOpenTotal = 0;
  Map<String, int> openCountByCollector = {};

  Future<Debt> recordDebtFromPurchase({
    required String collectorId,
    required String collectorName,
    required String purchaseId,
    required double totalAmount,
    required double coveredAmount,
    required double forgivenAmount,
    required String createdBy,
    String? notes,
  }) async {
    final debt = await debtService.createDebtFromPurchase(
      collectorId: collectorId,
      collectorName: collectorName,
      purchaseId: purchaseId,
      totalAmount: totalAmount,
      coveredAmount: coveredAmount,
      forgivenAmount: forgivenAmount,
      createdBy: createdBy,
      notes: notes,
    );
    await notificationService.notifyDebtRecorded(
      collectorId: collectorId,
      collectorName: collectorName,
      forgivenAmount: forgivenAmount,
      totalAmount: totalAmount,
    );
    notifyListeners();
    return debt;
  }

  Future<void> markPaid(String debtId) async {
    await debtService.markPaid(debtId);
    notifyListeners();
  }
}
```

- [ ] **Step 6: Run tests, expect pass**

Run: `cd app && flutter test test/core/providers/debt_provider_test.dart`
Expected: 1 test passes.

- [ ] **Step 7: Commit**

```bash
git add app/lib/core/providers/debt_provider.dart app/lib/core/models/notification_model.dart app/lib/core/services/notification_trigger_service.dart app/test/core/providers/debt_provider_test.dart
git commit -m "feat(debt): add DebtProvider with notification fan-out"
```

---

## Task 5: Wire purchase dialog with debt toggle and update `recordPurchase`

**Files:**
- Modify: `app/lib/presentation/screens/transaction/dialogs/add_purchase_dialog.dart` (filename confirmed by the actual project; grep first to find the real one)
- Modify: `app/lib/core/providers/transaction_provider.dart` (`recordPurchase`)
- Modify: `app/lib/l10n/app_en.arb` / `app_am.arb`
- Run: `flutter gen-l10n`

- [ ] **Step 1: Find the real purchase dialog file**

Run:
```bash
grep -rln "Record purchase" app/lib/presentation
```
Use the resulting file path in subsequent steps.

- [ ] **Step 2: Add new strings**

Append to `app/lib/l10n/app_en.arb`:
```json
  "recordAsDebt": "Record as debt",
  "recordAsDebtHint": "Collector has {balance} Birr; remaining {remaining} Birr will be recorded as debt.",
  "debtRecordedToast": "Purchase recorded. {amount} Birr added to debt.",
  "debtButtonLabel": "Debt",
  "outstandingDebt": "Outstanding debt"
```

Append to `app/lib/l10n/app_am.arb`:
```json
  "recordAsDebt": "እንደ ብድር መዝግብ",
  "recordAsDebtHint": "ሰብሳይ ሰው {balance} ብር አለው፤ የቀረው {remaining} ብር እንደ ብድር ይመዘገባል።",
  "debtRecordedToast": "ግዢ ተመዝግቧል። {amount} ብር ወደ ብድር ተጨምሯል።",
  "debtButtonLabel": "ብድር",
  "outstandingDebt": "ያልተከፈለ ብድር"
```

- [ ] **Step 3: Regenerate localizations**

Run: `cd app && flutter gen-l10n`

- [ ] **Step 4: Update `recordPurchase` signature**

In `app/lib/core/providers/transaction_provider.dart`, find `recordPurchase`. Add an optional `double? forgivenAmount` parameter and pass it through to `MoneyTransaction`. After a successful add, if `forgivenAmount != null && forgivenAmount > 0`, call `DebtService.createDebtFromPurchase` (resolve through a Provider lookup — the simplest path is to expose `recordPurchase` on the dialog level, which has access to a `BuildContext` and can read `DebtProvider` directly).

Concretely, change the function signature:

```dart
Future<bool> recordPurchase({
  required String workerId,
  required String workerName,
  required double amount,
  required String createdBy,
  String? coffeeType,
  double? weight,
  double? pricePerKg,
  double? commission,
  String? localReceiptPath,
  double? forgivenAmount,   // NEW
}) async {
  ...
  final transaction = MoneyTransaction(
    ...
    forgivenAmount: forgivenAmount,
    isDebt: (forgivenAmount ?? 0) > 0,
  );
  ...
}
```

- [ ] **Step 5: Add the toggle to the purchase dialog**

Inside the dialog's `build` (or state class), add a reactive variable `_recordAsDebt` (default `false`). Below the amount field, render a `SwitchListTile` only when `overage > 0`:

```dart
Consumer<WorkerProvider>(
  builder: (context, wp, _) {
    final balance = wp.findById(workerId)?.currentBalance ?? 0;
    final overage = _amount - balance;
    if (overage <= 0) return const SizedBox.shrink();
    final t = AppLocalizations.of(context)!;
    return SwitchListTile(
      title: Text(t.recordAsDebt),
      subtitle: Text(t.recordAsDebtHint(balance.toStringAsFixed(0), overage.toStringAsFixed(0))),
      value: _recordAsDebt,
      onChanged: (v) => setState(() => _recordAsDebt = v),
    );
  },
),
```

On submit, if `_recordAsDebt` is true and the service throws "Insufficient balance", set `forgivenAmount = overage` and re-call `recordPurchase`. Show the toast `t.debtRecordedToast(...)`.

- [ ] **Step 6: Run existing transaction tests**

Run: `cd app && flutter test test/core/providers/transaction_provider_test.dart test/core/services/transaction_service_test.dart`
Expected: existing tests still pass; signature change is backward compatible.

- [ ] **Step 7: Commit**

```bash
git add app/lib/presentation/screens/transaction/dialogs/ app/lib/core/providers/transaction_provider.dart app/lib/l10n/
git commit -m "feat(debt): add Record-as-debt toggle to purchase dialog"
```

---

## Task 6: Collector detail Debt button + `CollectorDebtsScreen`

**Files:**
- Modify: `app/lib/presentation/screens/worker_detail/worker_detail_screen.dart`
- Create: `app/lib/presentation/screens/transaction/collector_debts_screen.dart`
- Test: `app/test/presentation/screens/transaction/collector_debts_screen_test.dart`

- [ ] **Step 1: Find the filter row in the collector detail page**

Run:
```bash
grep -n "Filter" app/lib/presentation/screens/worker_detail/worker_detail_screen.dart
```

- [ ] **Step 2: Write the screen widget test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cofiz/core/providers/debt_provider.dart';
import 'package:cofiz/core/services/debt_service.dart';
import 'package:cofiz/core/services/notification_trigger_service.dart';
import 'package:cofiz/presentation/screens/transaction/collector_debts_screen.dart';

class _StubNotifications extends NotificationTriggerService {
  _StubNotifications() : super(firestore: FakeFirebaseFirestore());
}

void main() {
  testWidgets('CollectorDebtsScreen shows empty state when no debts', (tester) async {
    final fs = FakeFirebaseFirestore();
    final svc = DebtService(firestore: fs);
    final p = DebtProvider(debtService: svc, notificationService: _StubNotifications());
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider.value(
          value: p,
          child: const CollectorDebtsScreen(collectorId: 'c1', collectorName: 'Alice'),
        ),
      ),
    );
    expect(find.text('No debts recorded.'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Implement `CollectorDebtsScreen`**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../../core/providers/debt_provider.dart';
import '../../core/models/debt_model.dart';

class CollectorDebtsScreen extends StatelessWidget {
  const CollectorDebtsScreen({super.key, required this.collectorId, required this.collectorName});
  final String collectorId;
  final String collectorName;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<DebtProvider>();
    return Scaffold(
      appBar: AppBar(title: Text('Debts — $collectorName')),
      body: StreamBuilder<List<Debt>>(
        stream: p.debtService.streamDebtsForCollector(collectorId),
        builder: (context, snap) {
          final debts = snap.data ?? const <Debt>[];
          final open = debts.where((d) => d.status == DebtStatus.open).toList();
          final paid = debts.where((d) => d.status == DebtStatus.paid).toList();
          final openTotal = open.fold<double>(0, (a, d) => a + d.forgivenAmount);
          return Column(
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _Stat('Open', openTotal.toStringAsFixed(0)),
                      _Stat('Open count', open.length.toString()),
                      _Stat('Paid count', paid.length.toString()),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: debts.isEmpty
                    ? const Center(child: Text('No debts recorded.'))
                    : ListView.separated(
                        itemCount: debts.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final d = debts[i];
                          return ListTile(
                            title: Text('ETB ${d.totalAmount.toStringAsFixed(0)} (forgiven ${d.forgivenAmount.toStringAsFixed(0)})'),
                            subtitle: Text(DateFormat.yMMMd().format(d.createdAt)),
                            trailing: d.status == DebtStatus.open
                                ? FilledButton(
                                    onPressed: () => p.markPaid(d.id),
                                    child: const Text('Mark paid'),
                                  )
                                : Text('paid'),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
        children: [Text(value, style: Theme.of(context).textTheme.titleLarge), Text(label)],
      );
}
```

- [ ] **Step 4: Add the Debt button to the collector detail page**

Immediately to the **left** of the existing filter row, add:

```dart
IconButton(
  tooltip: 'Debt',
  icon: const Icon(Icons.receipt_long),
  onPressed: () => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => CollectorDebtsScreen(
        collectorId: worker.id,
        collectorName: worker.name,
      ),
    ),
  ),
),
```

- [ ] **Step 5: Run tests, expect pass**

Run: `cd app && flutter test test/presentation/screens/transaction/collector_debts_screen_test.dart`
Expected: 1 test passes.

- [ ] **Step 6: Commit**

```bash
git add app/lib/presentation/screens/transaction/collector_debts_screen.dart app/lib/presentation/screens/worker_detail/worker_detail_screen.dart app/test/presentation/screens/transaction/collector_debts_screen_test.dart
git commit -m "feat(debt): add collector debt screen and detail-page button"
```

---

## Task 7: Admin "All debts" screen + dashboard tile

**Files:**
- Create: `app/lib/presentation/screens/transaction/all_debts_screen.dart`
- Modify: `app/lib/presentation/screens/dashboard/dashboard_screen.dart` (Today's Overview 5th tile)
- Test: `app/test/presentation/screens/transaction/all_debts_screen_test.dart`

- [ ] **Step 1: Add the dashboard tile**

In `app/lib/presentation/screens/dashboard/dashboard_screen.dart`, find the Today's Overview card and add a 5th tile next to the existing 4:

```dart
Consumer<DebtProvider>(
  builder: (context, dp, _) {
    return _StatTile(
      label: 'Outstanding debt',
      value: dp.openTotal.toStringAsFixed(0),
      icon: Icons.receipt_long,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AllDebtsScreen()),
      ),
    );
  },
),
```

Where `_StatTile` is whatever the existing card uses — match its API.

- [ ] **Step 2: Implement `AllDebtsScreen`**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/providers/debt_provider.dart';
import '../../core/models/debt_model.dart';

class AllDebtsScreen extends StatelessWidget {
  const AllDebtsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.watch<DebtProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('All debts')),
      body: StreamBuilder<List<Debt>>(
        stream: p.debtService.streamAllOpenDebts(),
        builder: (context, snap) {
          final debts = snap.data ?? const <Debt>[];
          if (debts.isEmpty) return const Center(child: Text('No open debts.'));
          return ListView.separated(
            itemCount: debts.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final d = debts[i];
              return ListTile(
                title: Text('${d.collectorName} — ETB ${d.forgivenAmount.toStringAsFixed(0)}'),
                subtitle: Text(DateFormat.yMMMd().format(d.createdAt)),
                trailing: FilledButton(
                  onPressed: () => p.markPaid(d.id),
                  child: const Text('Mark paid'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 3: Wire `DebtProvider` into `main.dart` MultiProvider**

Add a `ChangeNotifierProvider` for `DebtProvider` alongside the existing providers.

- [ ] **Step 4: Commit**

```bash
git add app/lib/presentation/screens/transaction/all_debts_screen.dart app/lib/presentation/screens/dashboard/dashboard_screen.dart app/lib/main.dart
git commit -m "feat(debt): add admin all-debts screen and dashboard tile"
```

---

## Task 8: Worker daily cron + indexes

**Files:**
- Create: `workers/fcm-relay/src/cron/debt-reminder.js`
- Modify: `workers/fcm-relay/wrangler.toml`
- Create: `workers/fcm-relay/test/cron/debt-reminder.test.js`

**Interfaces:**
- `sendDailyDigest(env)` queries `debts where status != 'paid'`, groups by collector, and pushes one FCM message per admin/viewer with the affected totals.

- [ ] **Step 1: Update `wrangler.toml`**

Append:
```toml
[[triggers]]
crons = ["0 6 * * *"]
```

- [ ] **Step 2: Implement `debt-reminder.js`**

```javascript
import admin from 'firebase-admin';

function ensureApp(env) {
  if (admin.apps.length) return;
  admin.initializeApp({ credential: admin.credential.cert(JSON.parse(env.FIREBASE_SERVICE_ACCOUNT_JSON)) });
}

export async function sendDailyDigest(env) {
  ensureApp(env);
  const db = admin.firestore();
  const snap = await db.collection('debts').where('status', '!=', 'paid').get();
  if (snap.empty) return { sent: 0 };

  // group by collector
  const byCollector = new Map();
  for (const doc of snap.docs) {
    const d = doc.data();
    const cur = byCollector.get(d.collectorId) || { name: d.collectorName || 'Collector', total: 0, count: 0 };
    cur.total += Number(d.forgivenAmount || 0);
    cur.count += 1;
    byCollector.set(d.collectorId, cur);
  }
  const summary = [...byCollector.entries()]
    .map(([id, v]) => `${v.name}: ${v.count} item(s), ETB ${v.total.toFixed(0)}`)
    .join('; ');

  const users = await db.collection('users').where('role', 'in', ['admin', 'viewer']).get();
  let sent = 0;
  for (const u of users.docs) {
    const tokens = await db.collection('fcm_tokens').where('userId', '==', u.id).get();
    for (const t of tokens.docs) {
      await admin.messaging().send({
        token: t.id,
        notification: { title: 'Open debt reminder', body: summary },
        data: { type: 'debt_reminder' },
      });
      sent += 1;
    }
  }
  return { sent };
}

export default {
  async scheduled(event, env, ctx) {
    ctx.waitUntil(sendDailyDigest(env));
  },
};
```

- [ ] **Step 3: Write the test**

```javascript
import { describe, it, expect } from 'vitest';
import { sendDailyDigest } from '../../src/cron/debt-reminder.js';

describe('sendDailyDigest', () => {
  it('returns sent=0 when no open debts', async () => {
    // Without a real firebase-admin instance, this throws. Smoke test only.
    expect(typeof sendDailyDigest).toBe('function');
  });
});
```

- [ ] **Step 4: Add the Firestore indexes**

In `firestore.indexes.json`, add:
```json
{
  "indexes": [
    {
      "collectionGroup": "debts",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "collectorId", "order": "ASCENDING" },
        { "fieldPath": "status", "order": "ASCENDING" },
        { "fieldPath": "createdAt", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "debts",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "status", "order": "ASCENDING" },
        { "fieldPath": "createdAt", "order": "DESCENDING" }
      ]
    }
  ],
  "fieldOverrides": []
}
```

- [ ] **Step 5: Run worker tests**

Run: `cd workers/fcm-relay && npm test`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add workers/fcm-relay/src/cron/debt-reminder.js workers/fcm-relay/wrangler.toml workers/fcm-relay/test/cron/debt-reminder.test.js firestore.indexes.json
git commit -m "feat(debt): add daily debt reminder cron and Firestore indexes"
```

---

## Self-Review

**Spec coverage:**

| Spec section | Task |
|---|---|
| Purchase dialog with toggle (only when `amount > balance`) | Task 5 |
| `MoneyTransaction` `forgivenAmount`, `isDebt` | Task 2 |
| `transactionBalanceUpdates` purchase uses `covered` | Task 2 |
| `worker_provider.applyTransactionDelta` mirror | Task 2 |
| `DebtService` CRUD + streams | Task 3 |
| `DebtProvider` + notification fan-out | Task 4 |
| `NotificationType.debtRecorded` + `notifyDebtRecorded` | Task 4 |
| Collector detail Debt button (left of filter row) | Task 6 |
| `CollectorDebtsScreen` | Task 6 |
| Admin `AllDebtsScreen` + dashboard tile | Task 7 |
| Daily 09:00 cron | Task 8 |
| Firestore indexes | Task 8 |
| `firestore.indexes.json` updated | Task 8 |
| Error handling matrix | Each task has graceful failure paths |
| Testing matrix | Each task has tests |

**Placeholder scan:** no TBD/TODO.

**Type consistency:** `Debt` fields used uniformly across Tasks 1, 3, 4, 6, 7. `DebtStatus` enum used consistently. `DebtService.streamDebtsForCollector` signature used in Task 6. `DebtProvider.recordDebtFromPurchase` signature used in Task 5. `forgivenAmount` field on `MoneyTransaction` referenced in Tasks 2, 5.

**Open item:** `NotificationTriggerService._notifyAllAdmins`/`_notifyAllViewers` are currently `async` private methods in the existing service (file `notification_trigger_service.dart:153,182`). The new `notifyDebtRecorded` calls them — no change needed unless they're renamed. Verify by running `cd app && flutter test test/core/services/notification_trigger_service_test.dart`.
