# Offline Confirmation Caching Design

Date: 2026-08-18
Status: Approved (Approach A)

## Problem

When a collector confirms (approves) a transaction entry while offline, the
current `TransactionService` methods do a plain Firestore write
(`update({approved: true})`). Offline, that write either hangs indefinitely
(the known offline hang issue) or fails, so the admin never reliably learns
that the collector confirmed the entry.

Only confirmations are in scope. Collectors no longer create transaction
entries — that logic lives on the admin side, and the collector-side entry
files (`record_purchase_dialog.dart`, `record_return_dialog.dart`,
`worker_action_button.dart`) have already been removed as dead code.

## Goals

1. When the collector confirms a transaction while offline, the confirmation
   is cached locally and replayed to Firestore when connectivity returns.
2. The collector sees the entry as confirmed immediately (optimistic UI),
   even while offline.
3. The admin reliably sees the confirmation once synced.

## Non-goals

- Caching creation of new transaction entries by collectors (admin-side only).
- Deduplicating duplicate offline confirmations (writes are idempotent).
- Changing the admin-side confirmation/approval UI.

## Approach

Reuse the existing pending-operations queue in `OfflineCacheService`, implement
the stub executor in `OfflineSyncService`, add connectivity checks to the
`TransactionService` approve methods, and add optimistic local state in
`TransactionProvider`.

## Architecture

### 1. `OfflineSyncService._executeOperation` (implement the stub)

Currently throws `UnimplementedError`. Implement execution for the three
approval op types by writing to Firestore directly via
`FirebaseFirestore.instance`:

- `approveTransaction`: `{type, transactionId}` → update that doc to
  `{approved: true}`.
- `approveTransfer`: `{type, transferId}` → query `transactions` where
  `transferId` equals, batch-update all docs to `{approved: true}`.
- `approveAll`: `{type, workerId}` → query `transactions` where `workerId`
  equals and `approved == false`, batch-update them to `{approved: true}`.

On failure the operation stays queued (existing behavior) and is retried on
the next connectivity change or app start. Sync trigger is the existing
`connectionStatus` listener in `initialize()`.

### 2. `TransactionService` approve methods (queue when offline)

Each of the three approve methods checks connectivity first:

- Online → existing direct Firestore write.
- Offline → `OfflineCacheService().queueOperation(...)` and return normally
  (no throw), so the provider reports success and the UI shows the confirm
  toast.

Queued op payloads:

- `approveTransaction(id)` → `{type: 'approveTransaction', transactionId: id}`
- `approveTransfer(transferId)` → `{type: 'approveTransfer', transferId}`
- `approveAllForWorker(workerId)` → `{type: 'approveAll', workerId}`

### 3. `TransactionProvider` optimistic local state

After a successful approve (online or queued), flip `approved = true` on the
matching entries in `_workerTransactions` and `notifyListeners()`:

- single: the entry with that `transactionId`
- transfer: both records sharing that `transferId`
- all: every unapproved entry for that worker

The live Firestore stream reconciles the same data once back online.

### 4. `ConnectivityService` shared instance

Already a private singleton with `isOnline`; expose a public getter for the
shared instance and ensure it is initialized once in `main.dart` before the
approve methods use it.

## Data flow

```
Collector taps Confirm
        │
        ▼
TransactionProvider.approveX(...)
        │
        ▼
TransactionService.approveX(...)
        │
   ┌────┴─────┐
 online    offline
   │          │
   ▼          ▼
 Firestore  queueOperation()  ──► OfflineSyncService.syncPendingOperations()
   │                                   │ (on connectivity restore)
   ▼                                   ▼
 provider flips approved=true    _executeOperation → Firestore update
   │                                   │
   ▼                                   ▼
 notifyListeners()                removePendingOperation(i)
   │
   ▼
 entry shows confirmed immediately
```

## Error handling

- Queued ops never throw at enqueue time; the optimistic flip/toast already
  happened. Failures only surface during sync, where a failed op stays queued
  and is retried later.
- `approveAll` replay semantics match today's online behavior (approve all
  unapproved for the worker). Idempotent.
- Duplicate offline confirms produce duplicate queued ops; writes are
  idempotent (`approved: true` on an already-approved doc is a no-op), so no
  dedup is needed.
- The offline-indicator widget already reads `ConnectivityService` /
  `OfflineSyncService`; no changes needed there.

## Files touched

- `app/lib/core/services/offline_sync_service.dart` — implement
  `_executeOperation`; add Firestore dependency.
- `app/lib/core/services/transaction_service.dart` — connectivity check +
  queue in the three approve methods.
- `app/lib/core/providers/transaction_provider.dart` — optimistic local
  `approved` flips.
- `app/lib/core/services/connectivity_service.dart` — expose shared instance
  getter.
- `app/lib/main.dart` — initialize connectivity before approve paths run.

## Testing

- Unit: `OfflineSyncService._executeOperation` for each op type.
- Unit: `TransactionService` approve methods queue ops when offline and skip
  the Firestore write.
- Widget: home tab confirm button flips entry to confirmed offline without
  network.
- Verification gate: `dart format`, `flutter analyze --no-pub` (0 errors),
  `flutter test` (existing 27 must still pass).