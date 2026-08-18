# Stale-While-Revalidate Cache for Main Transactions

Date: 2026-08-17
Status: Approved

## Problem

First paint of the reports screen (and dashboard) is slow because the "main
transactions" lists are loaded via unbounded, full-collection queries:

- `TransactionService.getAllTransactionsStream()` streams the entire
  `transactions` collection.
- `IncomeProvider.loadFullRecords()` calls `getAllIncome()` (full fetch).
- `ExpenseProvider.loadFullRecords()` calls `getAllExpenses()` (full fetch).

On a cold Firestore cache, first paint blocks on network + serialize work.

## Approach (Approved: A)

Wire the existing, currently-unused Hive cache (`OfflineCacheService`) as a
**stale-while-revalidate** layer:

1. On load, seed the in-memory list from the Hive cache immediately and
   `notifyListeners()` so the UI paints instantly with the last-known data.
2. Then subscribe to the live Firestore stream; on each emission, update state
   and write the fresh list back to the cache.
3. Clear the cache on sign-out so one user's data never leaks to the next on a
   shared device.

## Components

### OfflineCacheService (extend)
- Add `cacheIncome(List<IncomeRecord>)` / `getCachedIncome()`.
- Add `cacheExpenses(List<ExpenseRecord>)` / `getCachedExpenses()`.
- Reuse existing box pattern (`transactions_cache`, plus new `income_cache` and
  `expenses_cache` boxes). Open the new boxes in `initialize()`.
- Models already expose `toJson()` / `fromJson()` — verified for
  `IncomeRecord`, `ExpenseRecord`, and `MoneyTransaction`.

### TransactionProvider
- `loadAllTransactions()`: before subscribing to the stream, read
  `getCachedTransactions()`; if non-null, set `_allTransactions` and
  `notifyListeners()`. On each stream emission, set state then fire-and-forget
  `cacheTransactions(list)`.

### IncomeProvider / ExpenseProvider
- `loadFullRecords()`: read cached records first, paint, then fetch fresh via
  existing `getAllIncome()` / `getAllExpenses()` and cache the result.

### AuthProvider
- In `signOut()` (both success and error paths, where user data is cleared),
  call `OfflineCacheService().clearAllCache()` to prevent cross-user leakage.

## Data Flow

```
Cold start / relaunch
  Provider.loadX()
    ├─ read Hive cache  ──► paint instantly (stale data)
    └─ subscribe Firestore stream ──► fresh data ──► notify + write cache
```

## Error Handling

- Cache read failures are non-fatal: fall through to the network path with an
  empty seed. Hive getters return null on missing/empty boxes.
- Stream errors behave as today (surface `_errorMessage`).

## Testing

- Existing test suite (15 tests) must stay green.
- Cache round-trip is covered implicitly by existing model JSON tests plus the
  app's provider tests; no new fixtures required.
- Verify gate: `dart format`, `flutter analyze --no-pub` (0 errors),
  `flutter test` (15/15).

## Out of Scope

- Bounding the reports queries / cursor pagination for reports (Approach C).
- UI-thread optimization of `_getFilteredEntries` list building.