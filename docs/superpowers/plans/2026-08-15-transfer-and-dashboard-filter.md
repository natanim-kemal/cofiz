# Transfers + Dashboard Activity Filter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add collector-to-collector transfers (two linked records, receiver-confirms-both) and a Money In / Money Out filter on the admin dashboard activity feed.

**Architecture:** A transfer is stored as two `MoneyTransaction` records (`type='transfer'`) linked by a shared `transferId`, with `transferRole` = sender/receiver. Sender record decrements sender balance; receiver record increments receiver balance; neither touches lifetime totals. New `TransferDialog` records transfers. The existing `TransactionService` batch pattern is extended with `addTransfer`, `approveTransfer`, and pair-delete. The dashboard feed gains a direction filter.

**Tech Stack:** Flutter/Dart, Firebase Firestore (batch writes), provider. Pure unit tests (flutter_test) for model serialization only — services/providers hit Firestore and follow existing untested pattern.

## Global Constraints

- Warm orange = `Color(0xFFF0A04B)` — there is no `AppColors.warmOrange` constant; use the literal.
- No code comments unless asked. No commits unless the user asks.
- l10n edited only via `app_en.arb` + `app_am.arb`, then `flutter gen-l10n`.
- `AppToast.show(String message, {bool success = false})` — no context param.
- Money semantics: `distribution` = money-in (worker balance +), `return`/`purchase` = money-out (worker balance −). Transfers are neutral for the admin/company balance.
- Repo is git; modify files in place; never `git checkout`.
- `flutter analyze` must stay at 0 errors; existing test suite must stay green.

---

### Task 1: MoneyTransaction transfer fields + serialization

**Files:**
- Modify: `app/lib/core/models/transaction_model.dart`
- Test: `app/test/transaction_model_test.dart` (new)

**Interfaces:**
- Produces: `MoneyTransaction` fields `fromWorkerId`, `toWorkerId`, `transferId`, `transferRole` (all `String?`); helpers `isTransfer`, `isTransferSender`, `isTransferReceiver` (bool getters); all four factory/`toFirestore`/`toJson` mappings updated.

- [ ] **Step 1: Write the failing test**

Create `app/test/transaction_model_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cofiz/core/models/transaction_model.dart';

MoneyTransaction base({String type = 'distribution'}) {
  return MoneyTransaction(
    id: 'id1',
    workerId: 'w1',
    workerName: 'A',
    type: type,
    amount: 100,
    createdAt: DateTime(2026, 8, 15),
    createdBy: 'admin',
  );
}

void main() {
  test('fromFirestore reads transfer fields', () {
    final t = MoneyTransaction.fromFirestore({
      'workerId': 'w2',
      'workerName': 'B',
      'type': 'transfer',
      'amount': 50.0,
      'createdAt': DateTime(2026, 8, 15).millisecondsSinceEpoch,
      'createdBy': 'admin',
      'fromWorkerId': 'w1',
      'toWorkerId': 'w2',
      'transferId': 't-1',
      'transferRole': 'receiver',
    }, 'id2');
    expect(t.fromWorkerId, 'w1');
    expect(t.toWorkerId, 'w2');
    expect(t.transferId, 't-1');
    expect(t.transferRole, 'receiver');
    expect(t.isTransfer, isTrue);
    expect(t.isTransferReceiver, isTrue);
    expect(t.isTransferSender, isFalse);
  });

  test('toFirestore round-trips transfer fields', () {
    final t = MoneyTransaction(
      id: 'id1',
      workerId: 'w1',
      workerName: 'A',
      type: 'transfer',
      amount: 50,
      createdAt: DateTime(2026, 8, 15),
      createdBy: 'admin',
      fromWorkerId: 'w1',
      toWorkerId: 'w2',
      transferId: 't-1',
      transferRole: 'sender',
    );
    final map = t.toFirestore();
    expect(map['fromWorkerId'], 'w1');
    expect(map['toWorkerId'], 'w2');
    expect(map['transferId'], 't-1');
    expect(map['transferRole'], 'sender');
  });

  test('non-transfer helpers are false', () {
    expect(base().isTransfer, isFalse);
    expect(base().isTransferSender, isFalse);
    expect(base().isTransferReceiver, isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/transaction_model_test.dart`
Expected: FAIL — getters `isTransfer`/`fromWorkerId` don't exist.

- [ ] **Step 3: Add fields + helpers**

In `transaction_model.dart`, add after `commissionAmount`:

```dart
  // Transfer-specific (collector-to-collector)
  final String? fromWorkerId;
  final String? toWorkerId;
  final String? transferId;
  final String? transferRole; // 'sender' or 'receiver'
```

Add to the constructor, after `this.commissionAmount,`:

```dart
    this.fromWorkerId,
    this.toWorkerId,
    this.transferId,
    this.transferRole,
```

Add to `fromFirestore`, after `commissionAmount: ...`:

```dart
      fromWorkerId: data['fromWorkerId'],
      toWorkerId: data['toWorkerId'],
      transferId: data['transferId'],
      transferRole: data['transferRole'],
```

Add to `toFirestore`, after `'commissionAmount': commissionAmount,`:

```dart
      'fromWorkerId': fromWorkerId,
      'toWorkerId': toWorkerId,
      'transferId': transferId,
      'transferRole': transferRole,
```

Add to `fromJson`, after the `commissionAmount` line:

```dart
      fromWorkerId: json['fromWorkerId'],
      toWorkerId: json['toWorkerId'],
      transferId: json['transferId'],
      transferRole: json['transferRole'],
```

Add to `toJson` map, after `...toFirestore()` (already spread — no change needed; `toFirestore()` covers it).

Add helpers at the end of the class:

```dart
  bool get isTransfer => type.toLowerCase() == 'transfer';
  bool get isTransferSender => isTransfer && transferRole == 'sender';
  bool get isTransferReceiver => isTransfer && transferRole == 'receiver';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/transaction_model_test.dart`
Expected: PASS (3 tests).

---

### Task 2: TransactionService — addTransfer / approveTransfer / pair delete

**Files:**
- Modify: `app/lib/core/services/transaction_service.dart`

**Interfaces:**
- Consumes: `MoneyTransaction` transfer fields from Task 1.
- Produces: `Future<String?> addTransfer({required String fromWorkerId, required String fromWorkerName, required String toWorkerId, required String toWorkerName, required double amount, required String createdBy, String? notes})`; `Future<void> approveTransfer(String transferId)`; `Future<void> deleteTransfer(String transferId)`; transfer cases in `_balanceUpdates`.

- [ ] **Step 1: Add transfer case to `_balanceUpdates`**

In `_balanceUpdates`, after the `'purchase'` case, add:

```dart
      case 'transfer':
        final effect = t.isTransferSender ? -1.0 : 1.0;
        return {
          'currentBalance': FieldValue.increment(t.amount * mult * effect),
        };
```

`mult` is `-1` when reversing a transaction; combined with `effect`, undoing a sender record adds the amount back and undoing a receiver record subtracts it.

- [ ] **Step 2: Add `addTransfer`**

After `addTransaction`, add:

```dart
  /// Record a collector-to-collector transfer: two linked records + balances.
  Future<String?> addTransfer({
    required String fromWorkerId,
    required String fromWorkerName,
    required String toWorkerId,
    required String toWorkerName,
    required double amount,
    required String createdBy,
    String? notes,
  }) async {
    if (amount <= 0) {
      throw 'Amount must be greater than 0';
    }

    // Validate sender balance
    final senderDoc = await _firestore
        .collection('workers')
        .doc(fromWorkerId)
        .get();
    if (!senderDoc.exists) {
      throw 'Collector not found';
    }
    final senderBalance =
        (senderDoc.data()?['currentBalance'] ?? 0.0).toDouble();
    if (amount > senderBalance) {
      throw 'Insufficient balance. Available: ETB ${senderBalance.toStringAsFixed(2)}, Required: ETB ${amount.toStringAsFixed(2)}';
    }

    final now = DateTime.now();
    final transferId =
        '${fromWorkerId}_${toWorkerId}_${now.millisecondsSinceEpoch}';

    final senderTx = MoneyTransaction(
      id: '',
      workerId: fromWorkerId,
      workerName: fromWorkerName,
      type: 'transfer',
      amount: amount,
      notes: notes,
      createdAt: now,
      createdBy: createdBy,
      approved: false,
      fromWorkerId: fromWorkerId,
      toWorkerId: toWorkerId,
      transferId: transferId,
      transferRole: 'sender',
    );

    final receiverTx = MoneyTransaction(
      id: '',
      workerId: toWorkerId,
      workerName: toWorkerName,
      type: 'transfer',
      amount: amount,
      notes: notes,
      createdAt: now,
      createdBy: createdBy,
      approved: false,
      fromWorkerId: fromWorkerId,
      toWorkerId: toWorkerId,
      transferId: transferId,
      transferRole: 'receiver',
    );

    final batch = _firestore.batch();
    final senderRef = _firestore
        .collection(_transactionsCollection)
        .doc();
    final receiverRef = _firestore
        .collection(_transactionsCollection)
        .doc();
    batch.set(senderRef, senderTx.toFirestore());
    batch.set(receiverRef, receiverTx.toFirestore());
    batch.update(
      _firestore.collection('workers').doc(fromWorkerId),
      {'currentBalance': FieldValue.increment(-amount)},
    );
    batch.update(
      _firestore.collection('workers').doc(toWorkerId),
      {'currentBalance': FieldValue.increment(amount)},
    );
    await batch.commit();
    print('Transfer added successfully: $transferId');
    return transferId;
  }
```

- [ ] **Step 3: Add `approveTransfer` and `deleteTransfer`**

After `approveAllForWorker`, add:

```dart
  /// Approve both records of a transfer by shared transferId.
  Future<void> approveTransfer(String transferId) async {
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

  /// Delete both records of a transfer by shared transferId, reversing balances.
  Future<void> deleteTransfer(String transferId) async {
    try {
      final snapshot = await _firestore
          .collection(_transactionsCollection)
          .where('transferId', isEqualTo: transferId)
          .get();

      if (snapshot.docs.isEmpty) {
        throw 'Transfer not found';
      }

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        final tx = MoneyTransaction.fromFirestore(doc.data(), doc.id);
        final workerRef =
            _firestore.collection('workers').doc(tx.workerId);
        final updates = _balanceUpdates(tx, -1);
        if (updates.isNotEmpty) {
          batch.update(workerRef, updates);
        }
        batch.delete(doc.reference);
      }
      await batch.commit();
      print('Transfer deleted successfully: $transferId');
    } on FirebaseException catch (e) {
      print('Firestore error deleting transfer: ${e.code} - ${e.message}');
      throw _handleFirestoreError(e);
    } catch (e) {
      print('Error deleting transfer: $e');
      throw 'Failed to delete transfer. Please try again.';
    }
  }
```

- [ ] **Step 4: Guard `deleteTransaction` / `updateTransaction` from transfer records**

In `deleteTransaction`, after loading `transaction`, add a guard before the distribution guard:

```dart
      if (transaction.isTransfer) {
        throw 'Use transfer delete for transfers.';
      }
```

In `updateTransaction`, after loading `old`, add:

```dart
      if (old.isTransfer || transaction.isTransfer) {
        throw 'Transfers cannot be edited.';
      }
```

- [ ] **Step 5: Verify**

Run: `flutter analyze`
Expected: 0 errors.

---

### Task 3: TransactionProvider — transfer methods

**Files:**
- Modify: `app/lib/core/providers/transaction_provider.dart`

**Interfaces:**
- Consumes: `TransactionService.addTransfer`, `approveTransfer`, `deleteTransfer` from Task 2.
- Produces: `Future<bool> transferFromCollectorToCollector({required String fromWorkerId, required String fromWorkerName, required String toWorkerId, required String toWorkerName, required double amount, required String createdBy, String? notes})`; `Future<bool> approveTransfer(String transferId)`; `Future<bool> deleteTransfer(String transferId)`.

- [ ] **Step 1: Add provider methods**

After `recordCoffeePurchase`, add:

```dart
  /// Record a collector-to-collector transfer
  Future<bool> transferFromCollectorToCollector({
    required String fromWorkerId,
    required String fromWorkerName,
    required String toWorkerId,
    required String toWorkerName,
    required double amount,
    required String createdBy,
    String? notes,
  }) async {
    if (amount <= 0) {
      _errorMessage = 'Amount must be greater than 0';
      notifyListeners();
      return false;
    }

    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      await _transactionService.addTransfer(
        fromWorkerId: fromWorkerId,
        fromWorkerName: fromWorkerName,
        toWorkerId: toWorkerId,
        toWorkerName: toWorkerName,
        amount: amount,
        createdBy: createdBy,
        notes: notes,
      );

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
```

After `approveAllForWorker`, add:

```dart
  /// Approve both sides of a transfer
  Future<bool> approveTransfer(String transferId) async {
    try {
      await _transactionService.approveTransfer(transferId);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }
```

After `deleteTransaction`, add:

```dart
  /// Delete both records of a transfer
  Future<bool> deleteTransfer(String transferId) async {
    try {
      await _transactionService.deleteTransfer(transferId);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }
```

- [ ] **Step 2: Verify**

Run: `flutter analyze`
Expected: 0 errors.

---

### Task 4: l10n keys (en + am)

**Files:**
- Modify: `app/lib/l10n/app_en.arb`, `app/lib/l10n/app_am.arb`

**Interfaces:**
- Produces: keys `transfer` ("Transfer"), `returnMoney` stays, `chooseSender` ("Choose Sender"), `chooseReceiver` ("Choose Receiver"), `transferTitle` ("Transfer Money"), `transferredOut` ("Transferred Out"), `receivedFrom` ("Received From"), `transferFailed` ("Failed to record transfer").

- [ ] **Step 1: Add English keys**

Add to `app_en.arb` (anywhere inside the JSON object, e.g. near line 100):

```json
  "transfer": "Transfer",
  "chooseSender": "Choose Sender",
  "chooseReceiver": "Choose Receiver",
  "transferTitle": "Transfer Money",
  "transferredOut": "Transferred Out",
  "receivedFrom": "Received From",
  "transferFailed": "Failed to record transfer",
```

- [ ] **Step 2: Add Amharic keys**

Add to `app_am.arb`:

```json
  "transfer": "ማስተላለፍ",
  "chooseSender": "ላኪ ይምረጡ",
  "chooseReceiver": "ተቀባይ ይምረጡ",
  "transferTitle": "ገንዘብ ማስተላለፍ",
  "transferredOut": "ተላልፏል",
  "receivedFrom": "የተቀበለው ከ",
  "transferFailed": "ገንዘብ ማስተላለፍ አልተሳካም",
```

- [ ] **Step 3: Regenerate**

Run: `flutter gen-l10n`
Expected: completes with no errors.

- [ ] **Step 4: Verify**

Run: `flutter analyze`
Expected: 0 errors.

---

### Task 5: TransferDialog

**Files:**
- Create: `app/lib/presentation/screens/transaction/transfer_dialog.dart`

**Interfaces:**
- Consumes: `Worker` (sender, receiver), `TransactionProvider.transferFromCollectorToCollector`, l10n keys from Task 4.
- Produces: `TransferDialog({required Worker sender, required Worker receiver})` — `showDialog<bool>` wrapper; pops `true` on success.

- [ ] **Step 1: Create the dialog**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/models/worker_model.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/transaction_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';

class TransferDialog extends StatefulWidget {
  final Worker sender;
  final Worker receiver;

  const TransferDialog({
    super.key,
    required this.sender,
    required this.receiver,
  });

  @override
  State<TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<TransferDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    final notes = _notesController.text.trim();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final transactionProvider =
        Provider.of<TransactionProvider>(context, listen: false);

    final success =
        await transactionProvider.transferFromCollectorToCollector(
      fromWorkerId: widget.sender.id,
      fromWorkerName: widget.sender.name,
      toWorkerId: widget.receiver.id,
      toWorkerName: widget.receiver.name,
      amount: amount,
      createdBy: authProvider.user?.uid ?? 'unknown',
      notes: notes.isEmpty ? null : notes,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      Navigator.pop(context, true);
      AppToast.show(
        AppLocalizations.of(context)!.transactionCompleted,
        success: true,
      );
    } else {
      AppToast.show(transactionProvider.errorMessage ??
          AppLocalizations.of(context)!.transferFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const warmOrange = Color(0xFFF0A04B);
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
              children: [
                const Icon(Icons.swap_horiz, color: warmOrange, size: 40),
                const SizedBox(height: 16),
                Text(
                  l10n.transferTitle,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: theme.textTheme.headlineMedium?.color,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${widget.sender.name} → ${widget.receiver.name}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark
                        ? Colors.white70
                        : Colors.black54,
                  ),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d+\.?\d{0,2}')),
                  ],
                  decoration: InputDecoration(
                    labelText: l10n.amountWithCurrency(
                        l10n.currency ?? 'ETB'),
                    prefixIcon: const Icon(Icons.attach_money),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor:
                        isDark ? Colors.grey.shade800 : Colors.grey.shade50,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return l10n.amountIsRequired;
                    }
                    final val = double.tryParse(value);
                    if (val == null || val <= 0) return l10n.invalidAmount;
                    if (val > widget.sender.currentBalance) {
                      return l10n.insufficientBalance;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _notesController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: l10n.notesOptional,
                    hintText: l10n.addNotesHere,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor:
                        isDark ? Colors.grey.shade800 : Colors.grey.shade50,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isLoading
                            ? null
                            : () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(l10n.cancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: warmOrange,
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
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

- [ ] **Step 2: Verify**

Run: `flutter analyze`
Expected: 0 errors.

---

### Task 5B: TransactionDialog icon colors → warm orange

**Files:**
- Modify: `app/lib/presentation/screens/transaction/transaction_dialog.dart:102-113`

**Interfaces:**
- Produces: `TransactionDialog.color` returns warm orange for distribution and return (purchase already orange).

- [ ] **Step 1: Change the color getter**

Replace the `color` getter:

```dart
  Color get color {
    const warmOrange = Color(0xFFF0A04B);
    switch (widget.type) {
      case 'distribution':
        return warmOrange;
      case 'return':
        return warmOrange;
      case 'purchase':
        return Colors.orange;
      default:
        return AppColors.primary;
    }
  }
```

- [ ] **Step 2: Verify**

Run: `flutter analyze`
Expected: 0 errors.

---

### Task 6: Shared worker picker sheet + Transfer/Return segmented toggle

**Files:**
- Create: `app/lib/presentation/widgets/worker_picker_sheet.dart`
- Modify: `app/lib/presentation/screens/dashboard/dashboard_screen.dart`

**Interfaces:**
- Consumes: `Worker` list, l10n, `TransactionDialog`.
- Produces: `WorkerPickerSheet({required List<Worker> workers, required String mode})` where `mode` ∈ `'transfer'`, `'return'`, `'distribution'`, `'purchase'`; `Future<Worker?> showWorkerPicker(BuildContext context, {required List<Worker> workers, required String mode, Worker? exclude})`. For `'transfer'` mode, selecting a sender returns a second sheet to pick the receiver; the receiver sheet resolves by popping with the receiver Worker.

- [ ] **Step 1: Extract the picker into a shared widget**

Create `worker_picker_sheet.dart`. The full class replaces the private `_WorkerPickerSheet` in `dashboard_screen.dart` (move its state, build, search filter, and `ListTile` rendering verbatim), renamed to `WorkerPickerSheet`, with a segmented toggle header when `mode == 'transfer'`. The receiver sheet (`mode == 'transfer_receiver'`) renders the same list minus `exclude`.

Header block inserted above the search field, replacing the `selectCollector` title when `mode` is a transfer mode:

```dart
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'transfer',
                      label: Text('Transfer'),
                      icon: Icon(Icons.swap_horiz),
                    ),
                    ButtonSegment(
                      value: 'return',
                      label: Text('Return'),
                      icon: Icon(Icons.remove_circle),
                    ),
                  ],
                  selected: {widget.mode == 'transfer_receiver' ? 'return' : 'transfer'},
                  onSelectionChanged: widget.mode == 'transfer_receiver'
                      ? null
                      : (selection) {
                          if (selection.first == 'return') {
                            widget.onSwitchToReturn?.call();
                          }
                        },
                  style: ButtonStyle(
                    foregroundColor: WidgetStatePropertyAll(
                        const Color(0xFFF0A04B)),
                    selectedForegroundColor:
                        const WidgetStatePropertyAll(Colors.white),
                    selectedBackgroundColor:
                        const WidgetStatePropertyAll(Color(0xFFF0A04B)),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.mode == 'transfer_receiver'
                      ? (localizations?.chooseReceiver ?? 'Choose Receiver')
                      : (localizations?.selectCollector ?? 'Select Collector'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
```

The picker's `onTap` returns different payloads by mode:
- `transfer` → `Navigator.pop(context, worker)` (sender selected).
- `transfer_receiver` → `Navigator.pop(context, worker)` (receiver selected).
- `return` → pop, then `showDialog` → `TransactionDialog(worker: worker, type: 'return')`.

List filtering: `final filtered = widget.workers.where((w) => (widget.exclude == null || w.id != widget.exclude!.id) && (_query.isEmpty || w.name.toLowerCase().contains(_query.toLowerCase()))).toList();`

- [ ] **Step 2: Wire into dashboard**

In `dashboard_screen.dart`, remove the private `_WorkerPickerSheet` class, change `_pickWorkerForEntry` to route through the shared picker, and add a `_showTransferFlow`:

```dart
  void _pickWorkerForEntry(String type) {
    final workerProvider = Provider.of<WorkerProvider>(context, listen: false);
    final workers = workerProvider.workers.where((w) => w.isActive).toList();

    if (workers.isEmpty) {
      AppToast.show('No collectors available');
      return;
    }

    if (type == 'transfer') {
      _showTransferFlow(workers);
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => WorkerPickerSheet(workers: workers, mode: type),
    );
  }

  Future<void> _showTransferFlow(List<Worker> workers) async {
    final sender = await showModalBottomSheet<Worker>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => WorkerPickerSheet(
        workers: workers,
        mode: 'transfer',
        onSwitchToReturn: () {
          Navigator.pop(context);
          _pickWorkerForEntry('return');
        },
      ),
    );
    if (sender == null || !mounted) return;

    final receiver = await showModalBottomSheet<Worker>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => WorkerPickerSheet(
        workers: workers,
        mode: 'transfer_receiver',
        exclude: sender,
      ),
    );
    if (receiver == null || !mounted) return;

    await showDialog<bool>(
      context: context,
      builder: (context) => TransferDialog(sender: sender, receiver: receiver),
    );
  }
```

Change the middle entry button from `return` to `transfer`:

```dart
              Expanded(
                child: _buildEntryButton(
                  Icons.swap_horiz,
                  localizations?.transfer ?? 'Transfer',
                  () => _pickWorkerForEntry('transfer'),
                ),
              ),
```

Add `import '../transaction/transfer_dialog.dart';` and `import '../../widgets/worker_picker_sheet.dart';` to `dashboard_screen.dart`.

- [ ] **Step 3: Verify**

Run: `flutter analyze`
Expected: 0 errors.

---

### Task 7: ActivityFeedList — transfer rendering + direction filter

**Files:**
- Modify: `app/lib/presentation/widgets/activity_feed_list.dart`

**Interfaces:**
- Consumes: `MoneyTransaction` transfer helpers (Task 1).
- Produces: `ActivityFeedList({..., this.filter = _FeedFilter.none})` — add a public `filter` param (`enum FeedFilter { none, in, out }`), `_FeedItem` gains `FeedDirection` (`in`, `out`, `neutral`).

- [ ] **Step 1: Add filter enum + direction**

Add at top (near `_FeedKind`):

```dart
enum FeedFilter { none, in_, out_ }
enum _FeedDirection { in_, out_, neutral }
```

Add `final FeedFilter filter;` and `this.filter = FeedFilter.none,` to the constructor. In the build, filter `entries` before sorting:

```dart
    final allEntries = <_FeedItem>[
      for (final t in transactions)
        _FeedItem(t.createdAt, _FeedKind.transaction, t),
      for (final r in incomeRecords)
        _FeedItem(r.createdAt, _FeedKind.income, r),
      for (final e in expenseRecords)
        _FeedItem(e.createdAt, _FeedKind.expense, e),
    ];

    final entries = switch (filter) {
      FeedFilter.in_ => allEntries
          .where((e) => _directionOf(e) == _FeedDirection.in_)
          .toList(),
      FeedFilter.out_ => allEntries
          .where((e) => _directionOf(e) == _FeedDirection.out_)
          .toList(),
      FeedFilter.none => allEntries,
    }..sort((a, b) => b.createdAt.compareTo(a.createdAt));
```

- [ ] **Step 2: Add direction helper**

```dart
  _FeedDirection _directionOf(_FeedItem item) {
    switch (item.kind) {
      case _FeedKind.income:
        return _FeedDirection.in_;
      case _FeedKind.expense:
        return _FeedDirection.out_;
      case _FeedKind.transaction:
        final t = item.payload as MoneyTransaction;
        if (t.isTransfer) return _FeedDirection.neutral;
        return t.increasesBalance
            ? _FeedDirection.out_
            : _FeedDirection.in_;
    }
  }
```

Note: `increasesBalance` is true for `distribution` (money-out for admin), false for `return`/`purchase` (money-in). This mapping matches the spec's Money In = return + purchase + income; Money Out = distribution + expense.

- [ ] **Step 3: Add transfer rendering case**

In `_buildRow`, in the `_FeedKind.transaction` switch, add before `default`:

```dart
          case 'transfer':
            icon = Icons.swap_horiz;
            title = t.isTransferSender
                ? '${l10n?.transferredOut ?? 'Transferred Out'} · ${t.workerName}'
                : '${l10n?.receivedFrom ?? 'Received From'} · ${t.fromWorkerId != null ? _lookupName(t) : t.workerName}';
            amountColor = const Color(0xFFF0A04B);
            amount = '${l10n?.currency ?? 'ETB'} ${t.amount.formatted}';
            break;
```

Add a helper for the receiver name. Since receiver records carry `workerName` = receiver name, simplify:

```dart
          case 'transfer':
            icon = Icons.swap_horiz;
            title = t.isTransferSender
                ? '${l10n?.transferredOut ?? 'Transferred Out'} · ${t.workerName}'
                : '${l10n?.receivedFrom ?? 'Received From'} · ${t.workerName}';
            amountColor = const Color(0xFFF0A04B);
            amount = '${l10n?.currency ?? 'ETB'} ${t.amount.formatted}';
            break;
```

- [ ] **Step 4: Verify**

Run: `flutter analyze`
Expected: 0 errors.

---

### Task 8: Dashboard filter UI

**Files:**
- Modify: `app/lib/presentation/screens/dashboard/dashboard_screen.dart`

**Interfaces:**
- Consumes: `ActivityFeedList.filter`, `FeedFilter` from Task 7.

- [ ] **Step 1: Add filter state**

Add to `_DashboardScreenState`:

```dart
  FeedFilter _feedFilter = FeedFilter.none;
```

- [ ] **Step 2: Make Money In / Money Out tappable**

Replace the `Row` containing the two `_buildTodayStatItem` calls with a version where each `Expanded` is wrapped in `GestureDetector`/`InkWell` that toggles state and shows a selected ring. Add a new widget `_buildTappableStat`:

```dart
  Widget _buildTappableStat({
    required String label,
    required String value,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFF0A04B).withOpacity(isDark ? 0.25 : 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? const Color(0xFFF0A04B)
                : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
```

Wire toggles:

```dart
                      Expanded(
                        child: _buildTappableStat(
                          label: localizations?.moneyIn ?? 'Money In',
                          value: _showTotalActivity
                              ? '${localizations?.currency ?? "ETB"} ${_totalMoneyIn(transactionProvider, incomeProvider, expenseProvider).formatted}'
                              : '${localizations?.currency ?? "ETB"} ${_todayMoneyIn(transactionProvider, incomeProvider, expenseProvider).formatted}',
                          icon: Icons.arrow_downward,
                          selected: _feedFilter == FeedFilter.in_,
                          onTap: () => setState(() {
                            _feedFilter = _feedFilter == FeedFilter.in_
                                ? FeedFilter.none
                                : FeedFilter.in_;
                          }),
                        ),
                      ),
```

and the Money Out side analogously with `Icons.arrow_upward`, `FeedFilter.out_`, and the out value.

- [ ] **Step 3: Pass filter to the feed**

```dart
                    ActivityFeedList(
                      transactions: transactionProvider.allTransactions,
                      incomeRecords: incomeProvider.records,
                      expenseRecords: expenseProvider.records,
                      filter: _feedFilter,
                    ),
```

- [ ] **Step 4: Verify**

Run: `flutter analyze`
Expected: 0 errors.

---

### Task 9: Collector detail screen — Transfer button + flow

**Files:**
- Modify: `app/lib/presentation/screens/worker_detail/worker_detail_screen.dart`

**Interfaces:**
- Consumes: `WorkerPickerSheet` (receiver), `TransferDialog`, l10n, `WorkerProvider`.
- Produces: Transfer action that picks a receiver (excluding the viewed worker) then opens `TransferDialog`.

- [ ] **Step 1: Change the third action button**

In `_buildActionButtons`, change the `return` button to transfer:

```dart
            Expanded(
              child: _buildActionButton(
                context,
                AppLocalizations.of(context)!.transfer,
                Icons.swap_horiz,
                () async {
                  final workerProvider =
                      Provider.of<WorkerProvider>(context, listen: false);
                  final workers = workerProvider.workers
                      .where((w) => w.isActive && w.id != worker.id)
                      .toList();
                  if (workers.isEmpty) {
                    AppToast.show('No collectors available');
                    return;
                  }

                  final receiver = await showModalBottomSheet<Worker>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) => WorkerPickerSheet(
                      workers: workers,
                      mode: 'transfer_receiver',
                    ),
                  );
                  if (receiver == null || !mounted) return;

                  await showDialog<bool>(
                    context: context,
                    builder: (context) =>
                        TransferDialog(sender: worker, receiver: receiver),
                  );
                },
              ),
            ),
```

Add imports:

```dart
import '../../widgets/worker_picker_sheet.dart';
import '../transaction/transfer_dialog.dart';
```

- [ ] **Step 2: Verify**

Run: `flutter analyze`
Expected: 0 errors.

---

### Task 10: WorkerTransactionTile — transfer rendering + receiver confirm

**Files:**
- Modify: `app/lib/presentation/screens/worker/widgets/worker_transaction_tile.dart`

**Interfaces:**
- Consumes: `MoneyTransaction.isTransfer` helpers, `TransactionProvider.approveTransfer`.
- Produces: sender → "Transferred Out" orange, outgoing, pending badge no confirm; receiver → "Received From" orange, incoming, pending badge + confirm via `approveTransfer(t.transferId!)`.

- [ ] **Step 1: Add transfer case to the display switch**

In `build`, replace the switch:

```dart
    switch (transaction.type) {
      case 'distribution':
        icon = Icons.arrow_downward;
        color = Colors.orange;
        prefix = '+';
        break;
      case 'return':
        icon = Icons.arrow_upward;
        color = Colors.green;
        prefix = '-';
        break;
      case 'purchase':
        icon = Icons.local_cafe;
        color = Colors.brown;
        prefix = '-';
        break;
      case 'transfer':
        icon = Icons.swap_horiz;
        color = const Color(0xFFF0A04B);
        prefix = transaction.isTransferSender ? '-' : '+';
        break;
      default:
        icon = Icons.swap_horiz;
        color = Colors.grey;
        prefix = '';
    }
```

- [ ] **Step 2: Add title case**

In `_getTransactionTitle`:

```dart
      case 'transfer':
        return transaction.isTransferSender
            ? (AppLocalizations.of(context)?.transferredOut ??
                'Transferred Out')
            : (AppLocalizations.of(context)?.receivedFrom ??
                'Received From');
```

- [ ] **Step 3: Gate confirm to receiver transfers**

The confirm button (`onApprove`) currently renders for any `!transaction.approved && onApprove != null`. In the tab callers (Task 11) pass `onApprove` only when `!t.approved && !(t.isTransferSender)`.

- [ ] **Step 4: Verify**

Run: `flutter analyze`
Expected: 0 errors.

---

### Task 11: Worker tabs — approveTransfer wiring

**Files:**
- Modify: `app/lib/presentation/screens/worker/tabs/worker_home_tab.dart`, `app/lib/presentation/screens/worker/tabs/worker_history_tab.dart`

**Interfaces:**
- Consumes: `TransactionProvider.approveTransfer`.

- [ ] **Step 1: Add approve method in both tabs**

Add next to `_approveTransaction` in each file:

```dart
  Future<void> _approveTransfer(
      TransactionProvider provider, String transferId) async {
    setState(() => _approving = true);
    final success = await provider.approveTransfer(transferId);
    if (mounted) {
      setState(() => _approving = false);
      if (success) {
        AppToast.show(
          AppLocalizations.of(context)!.entryConfirmed,
          success: true,
        );
      } else {
        AppToast.show(provider.errorMessage ??
            AppLocalizations.of(context)!.failedToComplete);
      }
    }
  }
```

- [ ] **Step 2: Pass onApprove only for receiver transfers**

Where the tab builds `WorkerTransactionTile(transaction: tx, onApprove: ...)`, change the expression so it is null for pending sender transfers:

```dart
onApprove: (!tx.approved && tx.isTransferReceiver)
    ? () => _approveTransfer(provider, tx.transferId!)
    : (!tx.approved && onApprove for non-transfer)
```

Concretely, in `worker_history_tab.dart` around line 196–198 and `worker_home_tab.dart` around line 293, replace with:

```dart
                            onApprove: !tx.approved
                                ? (tx.isTransfer
                                    ? (tx.isTransferReceiver
                                        ? () => _approveTransfer(
                                            provider, tx.transferId!)
                                        : null)
                                    : () => _approveTransaction(
                                        provider, tx.id))
                                : null,
```

- [ ] **Step 3: Verify**

Run: `flutter analyze`
Expected: 0 errors.

---

### Task 12: Admin per-collector list — transfer rendering, pair delete, no edit

**Files:**
- Modify: `app/lib/presentation/widgets/worker_transactions_list.dart`

**Interfaces:**
- Consumes: `TransactionProvider.deleteTransfer`, `MoneyTransaction.isTransfer` helpers.

- [ ] **Step 1: Add transfer case to `_buildTransactionItem` switch**

```dart
      case 'transfer':
        typeColor = const Color(0xFFF0A04B);
        typeIcon = Icons.swap_horiz;
        break;
```

Also fix the amount sign: for sender records show `-`, receiver show `+` (currently `isPositive = transaction.increasesBalance`, which is false for transfers → always shows `-`). Change:

```dart
    bool isPositive = transaction.increasesBalance;
    if (transaction.isTransfer) {
      isPositive = transaction.isTransferReceiver;
    }
```

- [ ] **Step 2: Add transfer case to `_getTypeDisplay`**

Change the signature to accept the transaction and update the call site (line 216):

```dart
                      Text(
                        _getTypeDisplay(context, transaction),
                        ...
```

Change the method:

```dart
  String _getTypeDisplay(BuildContext context, MoneyTransaction transaction) {
    switch (transaction.type.toLowerCase()) {
      case 'distribution':
        return AppLocalizations.of(context)?.distributed ?? 'Distributed';
      case 'return':
        return AppLocalizations.of(context)?.returned ?? 'Returned';
      case 'purchase':
        return AppLocalizations.of(context)?.purchased ?? 'Purchased';
      case 'transfer':
        return transaction.isTransferSender
            ? (AppLocalizations.of(context)?.transferredOut ??
                'Transferred Out')
            : (AppLocalizations.of(context)?.receivedFrom ??
                'Received From');
      default:
        return transaction.type;
    }
  }
```

- [ ] **Step 3: Handle edit/delete for transfers**

In `_showActionsModal`, hide the edit chip for transfers (show only delete):

```dart
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!transaction.isTransfer)
                  _buildActionChip(
                    icon: Icons.edit_outlined,
                    label: l10n.edit,
                    color: const Color(0xFFF0A04B),
                    value: 'edit',
                  ),
                if (!transaction.isTransfer) const SizedBox(width: 12),
                _buildActionChip(
                  icon: Icons.delete_outline,
                  label: l10n.delete,
                  color: const Color(0xFFF0A04B),
                  value: 'delete',
                ),
              ],
            ),
```

In `_deleteTransaction`, branch on transfer:

```dart
    final success = transaction.isTransfer
        ? await transactionProvider.deleteTransfer(transaction.transferId!)
        : await transactionProvider.deleteTransaction(transaction.id);
```

- [ ] **Step 4: Verify**

Run: `flutter analyze`
Expected: 0 errors.

---

### Task 13: Full verification

- [ ] **Step 1: Run all tests**

Run: `flutter test`
Expected: all pass (existing 12 + new 3 from Task 1).

- [ ] **Step 2: Analyze**

Run: `flutter analyze`
Expected: 0 errors.

- [ ] **Step 3: gen-l10n sanity**

Run: `flutter gen-l10n`
Expected: completes cleanly.

- [ ] **Step 4: Report**

Summarize: transfer flow (two records, approve both, pair delete), dashboard filter behavior, icon colors changed to warm orange. Ask the user to build the APK to visually verify.