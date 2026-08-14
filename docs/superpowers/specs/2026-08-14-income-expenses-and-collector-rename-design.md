# Design: Income, Expenses & Collector Rename

**Date:** 2026-08-14
**Status:** Approved in design review

## Overview

Eleven requested changes to the Cofiz app:

1. Rename "Worker/workers" → "Collector/collectors" (user-visible text only)
2. Add a new source of income called **Investment** with two kinds: viewer investments (visible to the viewer, non-repudiation) and manual sales recorded by the admin
3. The home card's **Total** slot becomes **Investment**, navigating to a Company Income page
4. The **Active** stat stays, navigates to the Collectors page, label becomes "Collectors"
5. Remove the two big stat cards from the Collectors page; show the collector count beside the filter chips (tracks selected filter)
6. Remove green background containers from money amounts everywhere (keep red low-balance text)
7. **Expenses** replaces **Perf** on the home card; performance indicators wiped app-wide; tapping Expenses shows the Expenses page
8. Sales stat on the home card unchanged
9. Net balance includes the new additions; Today's Activity card reflects it
10. Replace the "Active Workers" section at the bottom of the home screen with Latest Transactions
11. Light-mode background lightened slightly

## Data model

### New Firestore collections

**`income_records`** (auto ID) — one doc per income event:

| Field | Type | Notes |
|-------|------|-------|
| `kind` | string | `investment` \| `sale` |
| `amount` | double | |
| `description` | string? | optional note |
| `createdAt` | number (ms) | epoch millis |
| `createdBy` | string | user uid who recorded it |
| `createdByName` | string | display name of recorder |
| `viewerId` | string? | investment-only: → `users` doc |
| `viewerName` | string? | investment-only: display name |
| `saleCategory` | string? | sale-only |

**`expenses`** (auto ID) — one doc per expense:

| Field | Type | Notes |
|-------|------|-------|
| `amount` | double | |
| `expenseCategory` | string | |
| `description` | string? | optional note |
| `createdAt` | number (ms) | |
| `createdBy` | string | |
| `createdByName` | string | |

### Settings docs (mirror `settings/areas` pattern)

- `settings/saleCategories` → `{ categories: [...], createdAt?, updatedAt? }`
- `settings/expenseCategories` → `{ categories: [...], createdAt?, updatedAt? }`

Seed lists:
- Sale categories: `Coffee Beans`, `Processed Coffee`, `Equipment`, `Byproducts`, `Other`
- Expense categories: `Purchased Goods`, `Salary`, `Wages`, `Maintenance`, `Food`, `Transport`, `Rent`, `Other`

Seeding happens at app startup (`main()`) like `AreaService.initializeDefaultAreas()`.

## Services & providers

- **`IncomeService`**: CRUD on `income_records`; category get/add/rename/remove on `settings/saleCategories`
- **`IncomeProvider`** (ChangeNotifier): all-time income total, today's income (split investment/sale), income record list, streaming from Firestore
- **`ExpenseService`**: CRUD on `expenses`; category get/add/rename/remove on `settings/expenseCategories`
- **`ExpenseProvider`** (ChangeNotifier): all-time expense total, today's expenses, expense record list
- Dashboard latest feed: merged stream of `transactions` + `income_records` + `expenses`, newest first
- Both providers registered in `main.dart` `MultiProvider`

## Dashboard & home screen

### Top stats card (4 tappable slots, role-aware)

| Slot | Value | Tap → |
|------|-------|-------|
| Investment (was Total) | Total income all-time (investments + sales) | Company Income (admin) / My Investments (viewer) |
| Collectors (was Active) | Active collectors count | Collectors page (tab 1) |
| Expenses (was Perf) | Total expenses all-time | Expenses page |
| Sales | Today's coffee purchases (unchanged) | — |

### Today's Activity card (two-column income/outflow)

- Left (money in, today): Returned, Purchased, Investment Income, Manual Sales
- Right (money out, today): Distributed, Expenses
- Net Balance pinned at bottom: `(Returned + Purchased + Investment Income + Manual Sales) − (Distributed + Expenses)`

### Bottom section

"Active Workers" removed → **"Latest Transactions"**: merged newest-first feed showing type, collector/party, amount, time; tap opens related record. Empty state if none.

### Viewer entry point

"My Investments" button on the viewer dashboard header, visible only for `UserRole.viewer`, opens `MyInvestmentsScreen`.

### Performance rating removed

`Perf` stat, rating stars in collector items, avg performance displays — removed everywhere. The `performanceRating` data field stays in Firestore untouched.

## Collectors page

- Remove the two big `StatsCard`s (Total + Active) from `worker_list_screen.dart`
- Filter row: `[All] [Active] [Busy] [Offline]` chips + count text right-aligned at the same vertical level
- Count tracks the selected filter: All → total, Active → active count, Busy → busy count, Offline → offline count
- Count sized proportionally to the chips (same height, medium-weight), vertically centered
- Rest of the page unchanged (search bar, list, FAB)

## Global polish

### Worker → Collector rename (user-visible text only)

- Update English + Amharic localizations (all `worker/workers` strings → `collector/collectors`)
- `UserRole.worker.displayName` → "Collector"
- Display mapping: stored role value `'Worker'` renders as "Collector" in collector list items, detail, dashboard (data values unchanged)
- Worker-side screens (worker dashboard/tabs) get the same label treatment
- Internal code identifiers, Firestore collection names, enum values, stored data values unchanged

### Green money backgrounds removed

- Collector list items, dashboard balance badges, worker detail, transaction/purchase/return dialogs: money amounts become plain default text, no background pill
- Low balance keeps red text (background removed), warning cue retained
- Non-money greens (status chips, success icons, chart legend, action buttons) untouched

### Background

- Light-mode `AppColors.backgroundLight` lightened from `#F5F5F7` toward white, still darker than the pure-white cards (e.g. `#FAFAFB`)
- Dark mode unchanged

## New screens & navigation

**Company Income** (admin, from Investment card): total income all-time; two sections with sub-totals (Viewer Investments, Manual Sales), each listing records newest-first; FAB → add-record dialog (kind = Investment/Sale; investment picks viewer + amount + note; sale picks category + amount + note); category management entry.

**Expenses** (admin, from Expenses card): total expenses all-time; records newest-first (category, amount, description, date); FAB → add expense dialog; category management entry.

**My Investments** (viewer entry + admin review): viewers see their own investments (total + records); admins see all. Read-only, no FAB.

**Category management screens** mirror the Areas screen pattern (list, add, rename, delete).

### Navigation

```
Investment card ──admin──▶ Company Income ──▶ add record / manage sale categories
Investment card ──viewer─▶ My Investments
Collectors stat  ────────▶ Collectors page (tab)
Expenses card   ─────────▶ Expenses ──▶ add expense / manage expense categories
My Investments button    ─▶ My Investments (viewer dashboard only)
```

## Viewer non-repudiation

`MyInvestmentsScreen` queries `income_records` where `viewerId == logged-in uid`. Records are served to the investor themselves, so they cannot be silently altered without the viewer noticing.

## Out of scope

- Firestore security rules (none exist in the repo; app posture unchanged)
- Offline sync for new records (existing offline sync is a stub)
- Data migration for stored `Worker`/role values (rename is display-only)
- Reports screen rework (only rename/perf-wipe text touches)
