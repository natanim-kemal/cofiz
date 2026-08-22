import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/expense_record_model.dart';
import '../services/expense_service.dart';
import '../services/offline_cache_service.dart';

class ExpenseProvider extends ChangeNotifier {
  ExpenseProvider({ExpenseService? service})
      : _service = service ?? ExpenseService();

  final ExpenseService _service;

  static const int _pageSize = 20;

  List<ExpenseRecord> _records = [];
  bool _isLoading = false;
  String? _errorMessage;

  // Cursor pagination state
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _hasMore = false;
  bool _isLoadingMore = false;
  bool _loadedExtraPages = false;
  StreamSubscription<List<ExpenseRecord>>? _subscription;

  // Day-filter state: when non-null, _records holds that day's full list.
  DateTime? _activeDay;
  int _loadGeneration = 0;

  // Guards concurrent _refreshTotals() runs: only the latest invocation may
  // write results (prevents stale refresh clobbering fresh totals).
  int _totalsGeneration = 0;

  // Optimistic record ids (queued ops not yet confirmed by the server
  // stream). Protected from being dropped by _mergeFirstPage.
  final Set<String> _pendingIds = {};

  // Full dataset (used by reports/export, loaded on demand)
  List<ExpenseRecord> _fullRecords = [];

  // Server-side aggregate totals
  double _totalExpenses = 0.0;
  double _todayExpenses = 0.0;
  int _totalCount = 0;

  List<ExpenseRecord> get records => List.unmodifiable(_records);
  List<ExpenseRecord> get fullRecords => List.unmodifiable(_fullRecords);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  bool get hasMoreRecords => _hasMore && _activeDay == null;
  bool get isLoadingMore => _isLoadingMore;
  int get totalRecordCount => _totalCount;
  DateTime? get activeDay => _activeDay;

  double get totalExpenses => _totalExpenses;
  double get todayExpenses => _todayExpenses;

  void initialize() {
    if (_subscription != null) return;
    _subscription = _service.getExpensesPageStream(limit: _pageSize).listen(
      (records) {
        _mergeFirstPage(records);
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
    _refreshTotals();
  }

  /// Restore the live first-page stream after a day filter is cleared.
  void restoreStream() {
    _subscription?.cancel();
    _subscription = null;
    _activeDay = null;
    _loadGeneration++;
    _records = [];
    _lastDoc = null;
    _hasMore = false;
    _isLoadingMore = false;
    _loadedExtraPages = false;
    _isLoading = true;
    notifyListeners();
    initialize();
  }

  /// Load all expense records for a specific calendar day from the server.
  /// Replaces the live first-page stream while a date filter is active.
  Future<void> loadExpensesForDay(DateTime day) async {
    final generation = ++_loadGeneration;
    _subscription?.cancel();
    _subscription = null;
    _activeDay = day;
    _records = [];
    _lastDoc = null;
    _hasMore = false;
    _isLoadingMore = false;
    _loadedExtraPages = false;
    _isLoading = true;
    notifyListeners();

    final items = await _service.getExpensesForDay(day);
    if (generation != _loadGeneration) return;
    _records = items;
    _totalCount = items.length;
    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (_activeDay != null) return;
    if (_isLoadingMore || !_hasMore) return;
    _isLoadingMore = true;
    notifyListeners();

    final page = await _service.getExpensesPage(
      startAfter: _lastDoc,
      pageSize: _pageSize,
    );

    if (page.items.isEmpty) {
      _hasMore = false;
      _isLoadingMore = false;
      notifyListeners();
      return;
    }

    final knownIds = _records.map((r) => r.id).toSet();
    _records = [
      ..._records,
      ...page.items.where((r) => !knownIds.contains(r.id)),
    ];
    _lastDoc = page.lastDoc;
    _hasMore = page.hasMore;
    _loadedExtraPages = true;
    _isLoadingMore = false;
    notifyListeners();
  }

  void _mergeFirstPage(List<ExpenseRecord> freshHead) {
    if (_activeDay != null) return;

    // Optimistic records the server hasn't confirmed yet stay visible.
    final freshIds = freshHead.map((r) => r.id).toSet();
    final stillPending = _records
        .where((r) =>
            _pendingIds.contains(r.id) && !freshIds.contains(r.id))
        .toList();
    for (final id in freshIds) {
      if (_pendingIds.remove(id)) {
        unawaited(_refreshTotals());
      }
    }
    if (stillPending.isEmpty) {
      if (!_loadedExtraPages) {
        _records = freshHead;
        return;
      }
      final tail = _records.length > freshHead.length
          ? _records.sublist(freshHead.length)
          : <ExpenseRecord>[];
      _records = [...freshHead, ...tail];
      return;
    }

    final merged = <ExpenseRecord>[...stillPending, ...freshHead]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (!_loadedExtraPages) {
      _records = merged;
      return;
    }
    final tailIds = merged.map((r) => r.id).toSet();
    final tail =
        _records.where((r) => !tailIds.contains(r.id)).toList();
    _records = [...merged, ...tail];
  }

  Future<void> _refreshTotals() async {
    final generation = ++_totalsGeneration;
    _seedTotalsFromCache();

    final totalExpenses = await _service.getExpensesTotal();
    final todayExpenses = await _service.getExpensesTodayTotal();
    final count = await _service.getExpensesCount();

    // A newer refresh started while this one was in flight - discard.
    if (generation != _totalsGeneration) return;

    // Reconcile: a successful-but-stale aggregate (taken before the queued
    // create committed) would otherwise drag the total back down; add the
    // still-pending amounts back onto server truth.
    final pendingById = {
      for (final r in _records)
        if (_pendingIds.contains(r.id)) r.id: r,
      for (final r in _fullRecords)
        if (_pendingIds.contains(r.id)) r.id: r,
    };
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    double pendingTotal = 0;
    double pendingToday = 0;
    for (final r in pendingById.values) {
      pendingTotal += r.amount;
      if (r.createdAt.isAfter(dayStart)) pendingToday += r.amount;
    }
    debugPrint(
        '[Expense] refresh gen=$generation serverTotal=$totalExpenses pending=${pendingById.length} ($pendingTotal)');

    // Only overwrite fields that actually succeeded; keep last-known values
    // otherwise so a failed query (e.g. index still building) never zeros
    // the dashboard.
    var anyFailed = false;
    if (totalExpenses != null) {
      _totalExpenses = totalExpenses + pendingTotal;
    } else {
      anyFailed = true;
    }
    if (todayExpenses != null) {
      _todayExpenses = todayExpenses + pendingToday;
    } else {
      anyFailed = true;
    }
    if (count != null) {
      _totalCount = count + pendingById.length;
    } else {
      anyFailed = true;
    }

    notifyListeners();

    if (anyFailed) return;

    try {
      await OfflineCacheService().cacheExpenseTotals({
        'totalExpenses': _totalExpenses,
        'todayExpenses': _todayExpenses,
        'totalCount': _totalCount.toDouble(),
      });
    } catch (_) {
      // Cache write failure is non-fatal: totals still shown from network.
    }
  }

  void _seedTotalsFromCache() {
    try {
      // Seed only on cold start; mid-session seeding flashes stale values.
      if (_totalExpenses != 0.0 || _totalCount > 0) return;
      final cached = OfflineCacheService().getCachedExpenseTotals();
      if (cached == null) return;
      _totalExpenses = cached['totalExpenses'] ?? 0.0;
      _todayExpenses = cached['todayExpenses'] ?? 0.0;
      _totalCount = (cached['totalCount'] ?? 0).toInt();
      notifyListeners();
    } catch (_) {
      // Cache read failure is non-fatal: fall through to network path.
    }
  }

  /// Load the complete dataset (used by reports/export screens).
  Future<void> loadFullRecords() async {
    try {
      final cached = OfflineCacheService().getCachedExpenses();
      if (cached != null) {
        _fullRecords = cached;
        notifyListeners();
      }
    } catch (_) {
      // Cache read failure is non-fatal: fall through to network path.
    }

    final records = await _service.getAllExpenses();
    _fullRecords = records;
    try {
      await OfflineCacheService().cacheExpenses(records);
    } catch (_) {
      // Cache write failure is non-fatal: still notify with fresh data.
    }
    notifyListeners();
  }

  Future<bool> addExpense(ExpenseRecord record) async {
    final id = await _service.addExpense(record);
    debugPrint('[Expense] addExpense queued id=$id amount=${record.amount}');
    if (id == null) {
      _errorMessage = 'Failed to record expense';
      notifyListeners();
      return false;
    }
    final optimistic = record.copyWith(id: id);
    if (!_records.any((r) => r.id == id)) {
      _records = [optimistic, ..._records];
    }
    if (!_fullRecords.any((r) => r.id == id)) {
      _fullRecords = [optimistic, ..._fullRecords];
    }
    // Optimistic totals bump; next successful refresh reconciles.
    _totalExpenses += optimistic.amount;
    _todayExpenses += optimistic.amount;
    _totalCount += 1;
    _pendingIds.add(id);
    notifyListeners();
    _totalsGeneration++;
    _refreshTotals();
    return true;
  }

  Future<bool> updateExpense(ExpenseRecord record) async {
    final success = await _service.updateExpense(record);
    if (!success) {
      _errorMessage = 'Failed to update expense';
      notifyListeners();
      return false;
    }
    _refreshTotals();
    return true;
  }

  Future<bool> deleteExpense(String id) async {
    // Cancel a still-queued create so the record cannot resurrect after
    // the delete (server delete of a not-yet-synced doc is a no-op).
    await OfflineCacheService().removePendingOperationByOpId(id);
    _pendingIds.remove(id);

    final success = await _service.deleteExpense(id);
    debugPrint('[Expense] deleteExpense id=$id serverSuccess=$success');
    if (!success) {
      _errorMessage = 'Failed to delete expense';
      notifyListeners();
      return false;
    }
    // Optimistic totals decrement; next refresh reconciles.
    final removedIds = <String>{};
    for (final r in [..._records, ..._fullRecords]) {
      if (r.id != id || !removedIds.add(r.id)) continue;
      _totalExpenses -= r.amount;
    }
    // Remove from live lists + cache immediately (same rationale as the
    // income provider: no stream emission may ever arrive to drop the row).
    _records = _records.where((r) => r.id != id).toList();
    _fullRecords = _fullRecords.where((r) => r.id != id).toList();
    try {
      await OfflineCacheService().removeCachedExpense(id);
    } catch (_) {
      // Cache write failure is non-fatal: next cache sync reconciles.
    }
    debugPrint(
        '[Expense] deleteExpense id=$id remaining records=${_records.length} total=$_totalExpenses');
    notifyListeners();
    _totalsGeneration++;
    _refreshTotals();
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
