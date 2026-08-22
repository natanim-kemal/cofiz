# Offline-First Ops Design — Cofiz (2026-08-22)

## Overview
Make Cofiz fully offline-operational: every add/edit/delete for **income** (investment/sale), **expense**, **transactions** (distribution, return, purchase) and **transfers** (sender+receiver) must succeed locally with instant UI feedback and sync seamlessly when online. Audit logs and receipt images must not block the UX. Completed with Approach A — surgical extension of the existing Hive queue + `runTransaction` sync.

Current queue already handles `createIncome`, `createExpense`, `createTransaction`, `createTransfer`, `approve*` (`offline_sync_service.dart:122`). Updates/deletes (`income_service.dart:303/316`, `expense_service.dart:199/212`, `transaction_service.dart:417/500/376`) are still direct Firestore writes and fail offline.

## Goals / Non-Goals
**Goals:** (per Q1–Q5) All 6 mutation types for every entity offline-queued; local balance validation against cached + pending deltas (industry standard); coalesce `create+delete→drop` etc.; queued audit + deferred Cloudinary receipt; outbox UX (failed stays visible, tap retry/edit/discard); 7-day lock enforced locally and authoritatively on sync.
**Non-Goals:** Worker CRUD offline, replacing Hive with SQLite/drift (Approach B), relying solely on Firestore persistence (Approach C), multi-device CRDT.

## Architecture
```
Dialog → Provider (optimistic _records/_fullRecords + notify) 
       → Service (queueOperation + cache* → return true) 
       → OfflineCacheService (Hive: pending_operations, income_cache, expenses_cache, transactions_cache, failed_operations)
       → OfflineSyncService (connectivity + 30s timer → _executeOperation runTransaction + increments)
```
No new DB, no `init` reorder. Reuses tombstone `_cancelledOpIds` (`offline_cache_service.dart:426`), reconciling `_refreshTotals` (`income_provider.dart:203`), `_pendingIds`, and `[main]` timeouts.

## Operation Types
Existing 7 + new 7 + 2:
`updateIncome`, `deleteIncome`, `updateExpense`, `deleteExpense`, `updateTransaction`, `deleteTransaction`, `deleteTransfer`, `auditLog`, `uploadReceipt` (deferred). Each: `{opId, type, docId|transferId, payload/delta, receiptPath?, attempts, queuedAt}`. `opId == docId` for income/expense to allow `removePendingOperationByOpId` collapse.

## Queue & Coalesce
`OfflineCacheService.queueOperation` coalesces **before** `box.put`:
- `create(id)+delete(id)` → drop both
- `create(id)+update(id)` → single `create` with final payload
- `update+update` → last `update`
- `update+delete` → `delete`
- `delete+create` → keep both in order
- Transfer keyed by `transferId` (covers `senderDocId`/`receiverDocId`).

## Services & Providers

**Services** — all `update*`/`delete*` become queue-first (`transaction_service.dart:171` pattern):
```dart
await queueOperation({...}); await cache*(optimistic); unawaited(syncNow()); return true;
```
Offline balance check: `projected = getCachedWorker(workerId).currentBalance + sum(pending deltas for worker)` when `!isOnline`; mirrors `if(isOnline) fetch live` (`transaction_service.dart:174`). `_enforceLock` (`transaction_service.dart:571`) also checked locally.

**Providers** — optimistic before await:
- `IncomeProvider.deleteIncome` (`income_provider.dart:371`), `ExpenseProvider.deleteExpense` (`expense_provider.dart:302`), `TransactionProvider.deleteTransaction` (`transaction_provider.dart:630`) etc.: `_records = _records.where(id!=).toList()` + `removeCached*` + `notifyListeners()` + `_refreshTotals`/_persist before service call. Mirrors `add*` optimistic insert (`income_provider.dart:332`, `transaction_provider.dart:577`). `_mergeFirstPage` already guards pending rows.

## Sync, Receipts, Audit & Failures

**Sync** `OfflineSyncService._executeOperation` new cases: `firestore.runTransaction { if(snap.exists) return; set/update/delete }` + `_balanceUpdates` (`transaction_service.dart:583`) for tx, direct for income/expense. Transfer delete: 2 doc deletes + 2 worker increments atomically. `attempts` capped (e.g., 5) → move to `failed_operations` box (new) instead of infinite `remaining` loop (`offline_sync_service.dart:87`).

**Receipts:** `TransactionDialog` (`transaction_dialog.dart:176`) stores `localReceiptPath` in op; sync uploads via `http.MultipartRequest` (`transaction_service.dart:829`) **inside** `_executeOperation` before `txn.set`; upload failure → `remaining.add` retries whole op.

**Audit:** New `auditLog` op type; all dialog call-sites already `unawaited` after fix (`add_income_dialog.dart:96`, `add_expense_dialog.dart:121`); sync executes `collection('audit_logs').add`.

**Failure UX (Q5 A):** Failed ops stay in `_records` with `syncError` flag, banner via `pendingCount/hasSyncErrors` (extend `OfflineIndicator`), actions: Retry (`syncNow`), Edit (re-queues merged), Discard (tombstone). Success path `markDelivered` + `pruneDelivered` unchanged.

## Dialog Close Behavior
- `AddIncomeDialog` / `AddExpenseDialog`: `success = await provider.add*` (queued → true) → `pop + toast` → `unawaited(audit)` — already fixed, kept.
- `TransactionDialog` (`distribution`/`return`/`purchase`): no audit; receipt path deferred; `if(success) pop` works offline (queue-first).
- `TransferDialog` (`transfer_dialog.dart:49`): same.
- Delete/edit confirmations (`worker_transactions_list.dart:167`, `company_income_screen.dart:456`) `await provider.delete*` now queue-first → `success==true` offline → `_reload()` + toast immediately.

## Data Flow Example (offline 5 rapid deletes)
User taps delete 5× while offline → each `provider.delete*` optimistically removes row + tombstones any pending create + queues `delete*` (coalesced). UI shows 0 rows instantly, `totalIncome = server+pending` stays correct. On reconnect, `connectionStatus` (`connectivity_service.dart`) triggers `syncPendingOperations`; 5 `runTransaction` batches commit in enqueue order; 5 `markDelivered`; `replacePendingOperations` clears queue; stream emits 5 deletes; `_mergeFirstPage` reconciles. If one delete hits `isLocked` or `Insufficient balance` authoritatively, it moves to `failed_operations` and UI shows retry banner for that row only.

## Testing
- Unit: `OfflineCacheService` coalesce matrix (create+delete drop, etc.), `TransactionService` local balance `projected` calc.
- Provider: offline `add→delete` coalesce, 5× delete offline all succeed locally, totals reconcile with pending.
- Sync: fake `FirebaseFirestore` + `OfflineSyncService` — 7 new op types, transfer 2-doc atomicity, idempotent `snap.exists` retry, cap→failed box.
- Dialog: widget test `AddIncomeDialog` closes offline without awaiting audit; `TransactionDialog` with image defers upload.
- Integration: airplane-mode create 3 incomes, 2 expenses, 1 purchase with receipt, delete 2 — reconnect → Firestore matches Hive, no `permission-denied` loops.

## Risks
- Coalesce bug → lost update — mitigated by matrix tests.
- Balance double-count if `sync` succeeds but stream lags — mitigated by existing `_refreshTotals` pending delta + `attempts` cap.
- Hive growth — `failed_operations` TTL + `pruneDelivered` 7d.
