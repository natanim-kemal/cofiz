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

  bool get hasMoreRecords => _hasMore;
  bool get isLoadingMore => _isLoadingMore;
  int get totalRecordCount => _totalCount;

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

  Future<void> loadMore() async {
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
    if (!_loadedExtraPages) {
      _records = freshHead;
      return;
    }
    final tail = _records.length > freshHead.length
        ? _records.sublist(freshHead.length)
        : <ExpenseRecord>[];
    _records = [...freshHead, ...tail];
  }

  Future<void> _refreshTotals() async {
    _seedTotalsFromCache();

    final totalExpenses = await _service.getExpensesTotal();
    final todayExpenses = await _service.getExpensesTodayTotal();
    final count = await _service.getExpensesCount();

    // Only overwrite fields that actually succeeded; keep last-known values
    // otherwise so a failed query (e.g. index still building) never zeros
    // the dashboard.
    var anyFailed = false;
    if (totalExpenses != null) {
      _totalExpenses = totalExpenses;
    } else {
      anyFailed = true;
    }
    if (todayExpenses != null) {
      _todayExpenses = todayExpenses;
    } else {
      anyFailed = true;
    }
    if (count != null) {
      _totalCount = count;
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
    notifyListeners();
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
    final success = await _service.deleteExpense(id);
    if (!success) {
      _errorMessage = 'Failed to delete expense';
      notifyListeners();
      return false;
    }
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
