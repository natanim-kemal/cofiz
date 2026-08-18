# Outbox Reliable Delivery — Design

Date: 2026-08-18
Status: Approved (brainstorming)
Scope: Transactions (`addTransaction` distribution/return/purchase, `addTransfer`, `approve*`) + Income + Expense. Queue-first outbox with idempotent drain, delivered log, timer + reconnect + app-start retry, optimistic cache visibility.
Related code: `app/lib/core/services/offline_sync_service.dart`, `offline_cache_service.dart`, `transaction_service.dart`, `income_service.dart`, `expense_service.dart`, `core/providers/*`, `presentation/widgets/offline_indicator.dart`

## 1. Context

The app currently has a partial "confirmation outbox": `OfflineSyncService` + `OfflineCacheService` (Hive `pending_operations` queue) only for `approveTransaction`/`approveTransfer`/`approveAllForWorker`, and only as an offline fallback (online writes bypass the queue). `OfflineSyncService.queueTransaction` is dead code. Creating transactions (`addTransaction`/`addTransfer`) and income/expense writes go straight to Firestore batches — not durable offline.

Drain confirmation today is implicit: `syncPendingOperations` iterates pending ops, calls `_executeOperation`, drops successes from the queue and keeps failures (`replacePendingOperations`). Confirmation = "write did not throw and queue shrank." Retry is passive: connectivity listener + app start only, no timer, no cap. Approves are safe to retry; creates are not (duplicate doc + double `FieldValue.increment` on worker balance on retry after crash between commit and dequeue).

Goal: wire transactions + income/expense through a proper outbox so they survive offline, with exactly-once-safe drain, positive ack, and retry that the user can reason about.

## 2. Goals / Non-goals

Goals:
- Every transaction/income/expense creation survives offline and is eventually delivered exactly once to Firestore.
- Home/list screens show queued items immediately (optimistic cache).
- Delivery is idempotent across crash/retry; worker balance increments are not double-applied.
- Positive ack: delivered ops are recorded and queue length is the ground truth for pending.
- Retry: timer + reconnect + app start, no retry cap (per approved choice).

Non-goals:
- Workers / areas / settings / categories writes (out of scope).
- Cloud Functions relay, separate Firestore outbox collection, or backend changes.
- Offline receipt upload (Firebase Storage) — queued ops carry the receipt URL if already uploaded; otherwise `receiptUrl` is null and upload is retried when online (future enhancement, not in v1).

## 3. Chosen Approach

Approach A — deterministic client-generated IDs + transactional conditional create.

Each queued op carries a client-generated `opId` (UUID v4) assigned once at queue time and persisted in the op. For transaction/income/expense creates, the Firestore doc ID = `opId`. Drain runs `firestore.runTransaction`: read `collection/{opId}`; if exists → already delivered (no-op); else atomically write the doc(s) and `FieldValue.increment` the worker balance. The transaction doc itself is the idempotency marker. Same pattern for transfers: both docs derive from `opId` (sender `{opId}`, receiver `{opId}_r` or derived), marker = sender doc existence, both docs + two balance updates in one transaction.

Rationale: standard client-side outbox, no extra collections or indexes, works with existing Firestore data model. Alternatives rejected: separate dedupe marker collection (extra read/write), `clientOpId` field + query (needs indexes, slower).

## 4. Architecture

### 4.1 Components

- `OfflineCacheService` (Hive):
  - Existing: `pending_operations` queue (`queueOperation`, `getPendingOperations`, `replacePendingOperations`, `clearPendingOperations`).
  - New: `delivered_operations` box — `{opId, type, deliveredAt}`. Pruned after 7 days. Bounded.
  - Existing caches: `transactions_cache`, `income_cache`, `expenses_cache`, `totals_cache` — reused for optimistic visibility.
- `OfflineSyncService` (singleton):
  - Queue ingestion: `queueOperation` is the single entry point; callers queue first, always.
  - Drain: `syncPendingOperations()` iterates snapshot of pending ops, executes each via `_executeOperation` inside `runTransaction`, collects failures in `remaining`, writes successes to delivered log, rewrites pending queue.
  - Triggers: connectivity listener (existing), `initialize()` on app start, new `Timer.periodic(30s)` while online. Guard `isSyncing` prevents overlap. Public `syncNow()` for immediate flush when online.
  - Test seam: `firestore` getter/setter already exists.
- Services: `TransactionService`, `IncomeService`, `ExpenseService`:
  - Change `addTransaction`/`addTransfer`/`addIncome`/`addExpense`/`addTransfer` to queue-first: generate `opId`, queue full payload (with deterministic docId), write to Hive cache for immediate visibility, then `syncNow()` if online; return `opId` (or derived transferId) immediately.
  - Approve paths already queue-first when offline; change to queue-first always (consistent with outbox).
- Providers: `TransactionProvider`, `IncomeProvider`, `ExpenseProvider`:
  - Keep existing amount>0 guards; call service queue methods; no change to optimistic `_flipApproved` for approves.
  - For creates, providers can trigger cache seeding already present (`OfflineCacheService` caches).
- UI: `OfflineIndicator` already shows `OfflineSyncService().getPendingOperationsCount()` — continues to show pending count. No new screen for delivered log in v1.

### 4.2 Data Flow

Queue path (always):
1. Caller (provider/service) generates `opId` (UUID).
2. Build op: `{opId, type, payload: {deterministicDocId, fields}, queuedAt, attempts: 0}`.
3. `OfflineCacheService.queueOperation(op)` — durable Hive write.
4. Optimistic cache write: insert into `transactions_cache`/`income_cache`/`expenses_cache` keyed by deterministic docId.
5. If `ConnectivityService.isOnline`, call `OfflineSyncService.syncNow()` (debounced by `isSyncing`).

Drain path:
1. Trigger (connectivity true / app start / timer tick) → `syncPendingOperations()`.
2. Snapshot `pending = getPendingOperations()`, `remaining = []`, `delivered = []`.
3. For each `op` in pending:
   - `runTransaction`: read `doc(opId)`; if exists → success (already delivered); else write doc(s) + increments.
   - On success: push to `delivered` (write to delivered box with `deliveredAt`).
   - On throw: push to `remaining` (increment `attempts` for observability), `debugPrint`.
4. `replacePendingOperations(remaining)` + prune delivered log >7 days.
5. `debugPrint` summary; streams naturally pick up new docs.

### 4.3 Op Types & Payloads

- `createTransaction` — payload: `{opId, docId: opId, workerId, workerName, type, amount, notes, receiptUrl, createdAt, createdBy, coffeeType/weight/pricePerKg/commission}`. Drain: single doc conditional create + worker balance increment in one transaction.
- `createTransfer` — payload: `{opId, senderDocId: opId, receiverDocId: opId_r, transferId, from*, to*, amount, notes, createdAt, createdBy}`. Drain: two doc conditional creates (marker = sender) + two balance increments in one transaction.
- `createIncome` / `createExpense` — payload: `{opId, docId: opId, fields}`. Drain: single doc conditional create.
- `approveTransaction` / `approveTransfer` / `approveAll` — existing payload shapes + `opId`; drain: plain updates/batches (idempotent).

Backward compat: existing pending approve ops lack `opId`; drain treats them as before (no conditional check, plain `_executeOperation` path). New ops always have `opId`.

### 4.4 Idempotency Detail

For creates, the Firestore transaction reads the deterministic doc by `opId`. Existence check is inside the transaction, so two concurrent drains (not possible today due to `isSyncing`, but safe anyway) cannot double-apply. `FieldValue.increment` only executes when the doc did not exist. Retry after crash between commit and dequeue finds the doc already exists → no-op, still acked and dequeued.

### 4.5 Error Handling

- Firestore `FirebaseException` (permission-denied, unavailable, etc.) → thrown and kept in `remaining` for retry. With no cap, permanent failures retry forever on each trigger — `debugPrint` each attempt for observability. This matches the approved choice; a future cap/circuit-breaker is deferred.
- Queue write failure (Hive) → propagate to caller; provider surfaces `errorMessage`.
- Balance validation: services keep live-Firestore balance check when online; offline the check is skipped (same as today). Document the caveat that a queued distribution may exceed actual balance when eventually applied.

### 4.6 Confirmation / Observability

- Positive ack = entry in `delivered_operations` + removal from pending queue. Ground truth for "is it delivered" is delivered log + doc existence; inferring from queue shrink alone is no longer needed.
- UI: pending count from `getPendingOperationsCount()` (already shown as "Offline • N pending"). Delivered count available via `getDeliveredCount()` if needed; no dedicated screen in v1.

### 4.7 Testing

- `OfflineSyncService` with `FakeFirebaseFirestore` + Hive temp dir:
  - Queue create while offline → drain → doc exists, balance incremented once, queue empty, delivered log has entry.
  - Second drain is no-op (doc exists).
  - Crash simulation: write then keep in queue → drain again → single increment.
  - Transfer atomic: two docs + two balances.
  - Timer/reconnect/app-start triggers covered.
- Service/provider contract tests: `addTransaction`/`addTransfer`/`addIncome`/`addExpense` no longer call `batch.commit` directly when routed via outbox; verify queue + cache write.
- Existing approve tests updated to queue-first-always.

### 4.8 Rollout & Migrations

- No Firestore migration. Hive boxes auto-created on `initialize()`.
- Existing pending approve ops drain as before.

## 5. File Changes (planned)

- `app/lib/core/services/offline_cache_service.dart` — delivered box, prune, pending schema with `opId/queuedAt/attempts`.
- `app/lib/core/services/offline_sync_service.dart` — timer + `syncNow`, idempotent `_executeOperation` via `runTransaction`, delivered log, pruning, dead-code `queueTransaction` removed or repurposed.
- `app/lib/core/services/transaction_service.dart` — queue-first for `addTransaction`/`addTransfer`/`approve*`, deterministic IDs, cache write.
- `app/lib/core/services/income_service.dart`, `expense_service.dart` + `core/providers/income_provider.dart`, `expense_provider.dart`, `transaction_provider.dart` — queue-first wiring + optimistic cache where needed.
- Tests: `test/offline_sync_service_test.dart`, `test/transaction_service_test.dart`, new `test/income_outbox_test.dart` style.

## 6. Open Questions (resolved)

- Scope: transactions + income/expense (confirmed).
- Retry: timer (30s) + reconnect + app start, no cap (confirmed).
- Ack: idempotent conditional create + delivered log (confirmed).
- Visibility: show pending items immediately via Hive cache (confirmed).
