# Feature: Debt Recording on Purchases

**Date:** 2026-08-29
**Status:** Approved design — ready to plan
**Target codebase:** `app/` (Cofiz Flutter app)
**Co-dependency:** none

## Goal

When an admin records a purchase for a collector and the amount exceeds the collector's balance, allow the admin to toggle **"Record as debt"** so the overage is captured in a separate debt ledger. The collector's `currentBalance` is **not** allowed to go negative — the covered portion is debited normally, the overage is recorded as debt and is independent of the balance.

## Out of scope (v1)

- Auto-deducting debt from future distributions. Tracked as an open item below.
- Collector-initiated debt (only admin can record debt in v1).
- Partial debt payment schedules.
- Interest / late fees.

## User-visible behavior

### Purchase dialog with debt toggle

1. Admin opens "Record purchase" for a collector.
2. Enters an amount and (optionally) coffee type / weight / price-per-kg.
3. The dialog already shows a "Current balance: ETB X" line. Below the amount field, a new row appears **only when** `amount > currentBalance`:
   - A switch labeled **"Record as debt"**.
   - Helper text: "Collector has ETB X; remaining ETB Y will be recorded as debt."
4. Toggle is off by default.
5. If toggle is **off**: existing behavior — the save throws "Insufficient balance. Toggle 'Record as debt' to record the overage separately." and the dialog stays open.
6. If toggle is **on**: the save succeeds. The transaction is recorded as a purchase with:
   - `amount = coveredAmount` (the part actually paid by balance),
   - `forgivenAmount = amount − currentBalance` (the overage),
   - `isDebt = true`,
   - `notes` gains a marker `[Debt: ETB Y]`.
   - The collector's `currentBalance` decreases by `coveredAmount` (so it goes to 0), not by the full `amount`.
7. A toast/in-app message confirms: "Purchase recorded. ETB Y added to debt."

### Collector detail page — Debt button

- On the collector detail page, immediately **to the left of the existing filter row** that sits under the "Transactions" title, add a **"Debt"** button.
- Icon: `Icons.receipt_long`. (Fallback `Icons.account_balance_wallet_outlined` if the design system prefers it.)
- The button shows a small numeric badge with the count of open debts (red dot if any).
- Tapping navigates to `CollectorDebtsScreen`.

### `CollectorDebtsScreen`

- Title: "Debts — <collector name>".
- Header card: total open debt, count of open debts, count of paid debts.
- List of all debts newest first. Each row shows: created date, total amount, covered amount, forgiven amount, status badge, paid date (if paid).
- Admin-only action: "Mark paid" on open debts. Opens a confirm dialog; on confirm, `status = 'paid'`, `paidAt = now`.
- Empty state: "No debts recorded."

### Admin dashboard — "Outstanding debt" tile

- On the admin `DashboardScreen`, the **Today's Overview** card gets a fifth tile: **"Outstanding debt"**, with the total `forgivenAmount` across all collectors today.
- Tap behavior: navigates to a new "All debts" screen (admin only) listing every open debt across all collectors, with the same "Mark paid" action.

### Notifications

- **At-record (in-app + push):** When a debt is created, an entry is added to the `notifications` collection for every admin and every viewer. Title: "Debt recorded". Body: "Collector <name>: ETB <Y> added to debt (purchase ETB <X>)."
- **Daily reminder:** A Cloudflare Worker cron at **09:00 Africa/Addis_Ababa** runs a digest query against `debts` where `status != 'paid'`, groups by collector, and pushes one notification per admin/viewer with their affected collectors and totals. Days with no open debts are skipped.

## Architecture

### 1. `lib/core/models/debt_model.dart` (new)

Fields:
```dart
class Debt {
  final String id;
  final String collectorId;
  final String collectorName;
  final String purchaseId;          // links to transactions.id
  final double totalAmount;        // original intended amount
  final double coveredAmount;      // the part paid by balance
  final double forgivenAmount;     // the overage
  final DebtStatus status;         // open | partial | paid   (partial reserved for v2)
  final DateTime createdAt;
  final DateTime? paidAt;
  final String? notes;
  final String createdBy;          // admin userId
}
```

`toFirestore()` and `fromFirestore()` helpers.

### 2. `lib/core/services/debt_service.dart` (new)

Responsibilities:
- `createDebtFromPurchase(...)` — Firestore `add` to `debts`.
- `markPaid(debtId)` — update `status` and `paidAt`.
- `streamDebtsForCollector(collectorId)` — `where collectorId == ... orderBy createdAt desc`.
- `streamAllOpenDebts()` — `where status == 'open' orderBy createdAt desc`.
- `getOpenDebtsTotal()` — sum of `forgivenAmount` where `status == 'open'`.
- `getOpenDebtsTotalForToday()` — for the dashboard tile.

### 3. `lib/core/providers/debt_provider.dart` (new)

`ChangeNotifier` exposing: `openDebtsByCollector`, `openDebtsTotal`, `todayOpenDebtsTotal`, `openDebtsCountByCollector`. Streams via Firestore and forwards to `NotificationTriggerService` on create.

### 4. `lib/core/models/transaction_model.dart` — add fields

Add optional fields to `MoneyTransaction`:
- `double? forgivenAmount`
- `bool isDebt`

With defaults of `null` and `false` so existing code paths are unaffected.

### 5. `lib/core/utils/transaction_balance.dart` — adjust purchase branch

```dart
case 'purchase':
  final covered = t.amount - (t.forgivenAmount ?? 0);
  final updates = <String, dynamic>{
    'currentBalance': FieldValue.increment(-covered * mult),
    'totalCoffeePurchased': FieldValue.increment(covered * mult),
  };
  ...
```

`totalCoffeePurchased` records the **covered** portion (what was actually paid for from cash). The forgiven portion is captured in the `debts` collection, not in the worker counters.

### 6. `lib/core/providers/worker_provider.dart` `applyTransactionDelta` — same adjustment

Mirror the new formula. Keep the existing `dist < 0 ? 0 : dist` etc. clamps for now (cumulative counters should never go negative, only `currentBalance` can).

### 7. Purchase dialog (`lib/presentation/screens/transaction/dialogs/...`)

- Compute `overage = amount − collector.balance` reactively.
- Show toggle when `overage > 0`.
- On save with toggle on, pass `forgivenAmount = overage` to `TransactionProvider.recordPurchase(...)`.

### 8. `TransactionProvider.recordPurchase` — pass through

Add an optional `forgivenAmount` param. When non-null and > 0, set on the `MoneyTransaction` and also call `DebtService.createDebtFromPurchase(...)` after the transaction commit.

### 9. Collector detail page (`lib/presentation/screens/worker_detail/worker_detail_screen.dart`)

- New `IconButton` to the left of the existing filter row, labeled "Debt", with badge.
- Tapping pushes `CollectorDebtsScreen` for `worker.id`.

### 10. `lib/presentation/screens/transaction/collector_debts_screen.dart` (new)

As described above.

### 11. Admin dashboard tile (`lib/presentation/screens/dashboard/dashboard_screen.dart`)

- 5th tile "Outstanding debt" with today's total.
- Tapping navigates to `lib/presentation/screens/transaction/all_debts_screen.dart` (new).

### 12. Notification integration

- New `NotificationType.debtRecorded` in `notification_model.dart`.
- `DebtService.createDebtFromPurchase` calls `NotificationTriggerService.notifyDebtRecorded(...)`, which is a new method modeled on the existing `_notifyAllAdmins` + `_notifyAllViewers` helpers.

### 13. Cloudflare Worker — daily cron

- New file `workers/fcm-relay/src/cron/debt-reminder.ts`.
- New route binding on the worker: `scheduled().cron('0 6 * * *')` (06:00 UTC = 09:00 Africa/Addis_Ababa, no DST in Ethiopia).
- Logic: query Firestore `debts` where `status != 'paid'`; for each admin/viewer user, build a digest message and call the existing FCM relay path. If the digest is empty, skip.

## Data model

| Collection | Doc | Fields |
|---|---|---|
| Firestore `debts` | auto id | `collectorId`, `collectorName`, `purchaseId`, `totalAmount`, `coveredAmount`, `forgivenAmount`, `status`, `createdAt`, `paidAt?`, `notes?`, `createdBy` |
| Firestore `transactions` | (existing) | adds `forgivenAmount?`, `isDebt` (default false) |
| Firestore `workers` | (existing) | **unchanged** — balance never goes negative |

Indexes needed:
- `debts` composite: `collectorId ASC, status ASC, createdAt DESC`
- `debts` composite: `status ASC, createdAt DESC` (for the admin all-debts screen and the cron query)

## Security considerations

- Only admins can mark a debt paid (`markPaid` is gated on `AuthProvider.role == 'admin'` in `DebtService` and enforced again in the screen).
- Only admins see the admin all-debts screen.
- Collectors see their own debt list (read-only).
- The collector detail page's Debt button is visible to all roles but the contents respect role.

## Error handling

| Failure | UX |
|---|---|
| Toggle on, save fails mid-transaction | Transaction rolls back; debt not created; toast "Could not record debt" |
| Mark-paid network failure | Retry button inline; "Saved locally" if queued offline |
| Daily cron FCM failure | Log + retry; we accept that some reminder days may be missed in the early rollout |

## Testing

- **Unit:** `DebtModel` round-trip; `transaction_balance.dart` math with `forgivenAmount`.
- **Widget:** Purchase dialog with toggle visible/hidden; `CollectorDebtsScreen` empty + populated.
- **Integration:** Recording a debt end-to-end, with `TransactionProvider` and `DebtService` mocks.
- **Manual:** Real Firestore emulator, end-to-end debt → mark paid → notification.
- **Worker:** cron test with a fake date (use `wrangler dev --test-scheduled` or invoke the handler manually with a mock env).

## Open items (deferred)

1. **Auto-deduct from distributions.** When a `distribution` is recorded for a collector with open debt, automatically reduce `forgivenAmount` of the oldest open debt by the distribution amount, and flip status to `paid` when it reaches 0. To be designed later.
2. **Partial payments.** `DebtStatus.partial` is reserved in the model but not exposed in v1.
3. **Debt reminders in Amharic.** Native-speaker review for the notification copy.
4. **Dashboard tile behavior when offline.** Cached value from `shared_preferences` keyed on the last `todayOpenDebtsTotal`.
