# Design: Collector-to-Collector Transfers + Dashboard Activity Card Filter

Date: 2026-08-15
Status: Approved (all design sections approved by user)

## Overview

Two related features for the admin dashboard and collector detail screens:

1. **Collector-to-collector transfers** replace the primary "Return" flow. A transfer moves money from one collector to another; it does not directly change the admin/company balance. Each transfer is stored as two linked transaction records (one per side).
2. **Activity card filter** on the admin dashboard: pressing the Money In / Money Out stat filters the latest-transactions feed to that direction only.

## Section 1: Transfer data model & balance

### New transaction type `'transfer'`

A transfer from sender to receiver is stored as **two linked records**:

- **Sender record**
  - `workerId` = sender
  - `type` = `'transfer'`
  - `amount` = X
  - `fromWorkerId` = sender
  - `toWorkerId` = receiver
  - `transferId` = shared UUID linking the pair
  - `transferRole` = `'sender'`
  - `approved` = false
- **Receiver record**
  - `workerId` = receiver
  - `type` = `'transfer'`
  - `amount` = X
  - `fromWorkerId` = sender
  - `toWorkerId` = receiver
  - `transferId` = same shared UUID
  - `transferRole` = `'receiver'`
  - `approved` = false

### MoneyTransaction model additions

New nullable fields: `fromWorkerId`, `toWorkerId`, `transferId`, `transferRole`.
These are absent/null for distribution/return/purchase records.

Read helpers:
- `isTransfer` → `type == 'transfer'`
- `isTransferSender` → transfer and `transferRole == 'sender'`
- `isTransferReceiver` → transfer and `transferRole == 'receiver'`

All `fromFirestore` / `toFirestore` / `fromJson` / `toJson` mappings updated.

### Balance updates

In `TransactionService`:

- `addTransaction`:
  - transfer + sender: `currentBalance −X`
  - transfer + receiver: `currentBalance +X`
  - No change to `totalDistributed`, `totalReturned`, or `totalCoffeePurchased`.
- `_balanceUpdates` (used by update/delete): same transfer handling so reversing a transfer record inverts correctly.
- The balance-validation guard in `addTransaction` / `updateTransaction` / `deleteTransaction` currently checks only `purchase` and `return`. Transfers are validated separately at creation (sender balance) via the new TransferDialog and service-level guard.

### Approval flow

- Both records created with `approved: false`.
- Receiver's collector history shows a **Confirm** button for the incoming transfer.
- Confirming calls a new `approveTransfer(String transferId)` that batch-updates **both** records (by shared `transferId`) to `approved: true`.
- Sender's record shows a pending badge but **no** confirm button.

### Admin per-collector list (worker_transactions_list.dart)

- Transfer records render as orange arrows.
- **Delete** a transfer removes the **whole pair** (batch delete both docs by `transferId`).
- **Edit** is disabled for transfers (no partial-edit path).

## Section 2: Transfer / Return entry flow

### Entry points

Both the Admin Dashboard "Record Transactions" card and the Collector Detail action buttons change:

- The button labeled **"Return"** (icon `remove_circle`) becomes **"Transfer"** (icon `swap_horiz`), warm orange like the other entry buttons.
- Tapping it opens the **collector picker sheet** with a **segmented toggle at the top**: `Transfer | Return`, default **Transfer**, both warm orange.
  - **Dashboard**: reuse the existing `_WorkerPickerSheet` (moved to a shared widget so both screens can use it).
  - **Collector detail screen**: the sender is the viewed worker (fixed — no sender picker); after choosing Transfer, only the receiver is picked, then the TransferDialog opens.

### Transfer mode

1. Pick **sender** collector (list shows current balances).
2. Sheet swaps to pick **receiver** (sender excluded; receiver must be active; sender ≠ receiver).
3. Open a new **TransferDialog** (styled like `TransactionDialog`, not a second-worker variant of it): amount field, notes, amount ≤ sender's `currentBalance` validation, warm-orange confirm.
4. On submit: create the two linked records + both worker balance updates + toasts.

### Return mode (unchanged behavior)

Pick one collector → existing `TransactionDialog(type: 'return')`.

### Collector's own screens

- Receiver: incoming transfer with **Confirm** button (approves both sides via `transferId`).
- Sender: outgoing transfer, pending badge, no confirm.
- Titles: "Money Received" / "Transferred Out".

### Dialog icon colors

Per user note ("keep the return and distribute icons on these modals our main orange color, not red or green"):
- `TransactionDialog.color`: **distribution → warm orange** (currently green), **return → warm orange** (currently red). Purchase stays orange.
- All three entry modals use the main orange `Color(0xFFF0A04B)`.

## Section 3: Activity card filter

On the "Today's Overview" card, each Money In / Money Out stat becomes tappable with a pressed/selected state.

- **Money In pressed** → feed shows only money-in entries: income records (investment + sales), and transactions of type `return` + `purchase`. Left stat gets an orange highlight.
- **Money Out pressed** → feed shows only money-out entries: expense records and transactions of type `distribution`. Right stat highlighted.
- **Pressed again (same side)** → clears filter (both sides unpressed, full feed).
- **Press other side while active** → switches filter.
- **Transfers are excluded from both filters** — only visible in the unfiltered feed.

Implementation:
- Add `enum _FeedFilter { none, in, out }` to `_DashboardScreenState`.
- Pass a filter into the feed. `ActivityFeedList` gains an optional filter param; `_FeedItem` gains a direction (moneyIn / moneyOut / neutral) so filtering is applied centrally.

## Files touched

- `app/lib/core/models/transaction_model.dart` — new transfer fields + helpers.
- `app/lib/core/services/transaction_service.dart` — addTransfer (two records + balances), approveTransfer, delete by pair, balance updates.
- `app/lib/core/providers/transaction_provider.dart` — transferFromCollectorToCollector, approveTransfer, deleteTransfer, updateTransaction/deleteTransaction revalidation.
- `app/lib/presentation/screens/transaction/transaction_dialog.dart` — icon colors warm orange (distribution/return). Transfer uses a new `TransferDialog`, not a variant of this dialog.
- `app/lib/presentation/screens/dashboard/dashboard_screen.dart` — Transfer button, segmented picker, filter state.
- `app/lib/presentation/widgets/activity_feed_list.dart` — transfer rendering (orange arrow, neutral) + filter param.
- `app/lib/presentation/widgets/worker_transactions_list.dart` — transfer rendering, pair delete, no edit.
- `app/lib/presentation/screens/worker_detail/worker_detail_screen.dart` — Transfer button + TransferDialog wiring.
- `app/lib/presentation/screens/worker/widgets/worker_transaction_tile.dart` — transfer rendering (sender/receiver, confirm for receiver).
- `app/lib/presentation/screens/worker/tabs/worker_home_tab.dart` + `worker_history_tab.dart` — approveTransfer wiring.
- `app/lib/l10n/app_en.arb` + `app/lib/l10n/app_am.arb` — new keys (transfer, transferredOut, moneyReceived, chooseSender, chooseReceiver, etc.).