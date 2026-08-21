import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/income_record_model.dart';
import '../services/income_service.dart';
import '../services/offline_cache_service.dart';

class IncomeProvider extends ChangeNotifier {
  IncomeProvider({IncomeService? service})
      : _service = service ?? IncomeService();

  final IncomeService _service;

  static const int _pageSize = 20;

  List<IncomeRecord> _records = [];
  bool _isLoading = false;
  String? _errorMessage;

  // Cursor pagination state
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _hasMore = false;
  bool _isLoadingMore = false;
  bool _loadedExtraPages = false;
  StreamSubscription<List<IncomeRecord>>? _subscription;

  // Day-filter state: when non-null, _records holds that day's full list.
  DateTime? _activeDay;
  int _loadGeneration = 0;

  // Full dataset (used by reports/export, loaded on demand)
  List<IncomeRecord> _fullRecords = [];

  // Server-side aggregate totals
  double _totalIncome = 0.0;
  double _totalSales = 0.0;
  double _totalInvestments = 0.0;
  double _todayIncome = 0.0;
  double _todaySales = 0.0;
  double _todayInvestments = 0.0;
  int _totalCount = 0;

  List<IncomeRecord> get records => List.unmodifiable(_records);
  List<IncomeRecord> get fullRecords => List.unmodifiable(_fullRecords);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  bool get hasMoreRecords => _hasMore && _activeDay == null;
  bool get isLoadingMore => _isLoadingMore;
  int get totalRecordCount => _totalCount;
  DateTime? get activeDay => _activeDay;

  List<IncomeRecord> get investments =>
      _records.where((r) => r.kind == IncomeKind.investment).toList();

  List<IncomeRecord> get sales =>
      _records.where((r) => r.kind == IncomeKind.sale).toList();

  double get totalIncome => _totalIncome;
  double get totalInvestments => _totalInvestments;
  double get totalSales => _totalSales;

  double get todayInvestmentIncome => _todayInvestments;
  double get todayManualSales => _todaySales;
  double get todayIncome => _todayIncome;

  /// Initialize paginated list + aggregate totals.
  void initialize() {
    if (_subscription != null) return;
    _subscription = _service.getIncomePageStream(limit: _pageSize).listen(
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

  /// Load all income records for a specific calendar day from the server.
  /// Replaces the live first-page stream while a date filter is active.
  Future<void> loadIncomesForDay(DateTime day) async {
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

    final items = await _service.getIncomeForDay(day);
    if (generation != _loadGeneration) return;
    _records = items;
    _totalCount = items.length;
    _isLoading = false;
    notifyListeners();
  }

  /// Load the next page from the backend cursor.
  Future<void> loadMore() async {
    if (_activeDay != null) return;
    if (_isLoadingMore || !_hasMore) return;
    _isLoadingMore = true;
    notifyListeners();

    final page = await _service.getIncomePage(
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

  void _mergeFirstPage(List<IncomeRecord> freshHead) {
    if (_activeDay != null) return;
    if (!_loadedExtraPages) {
      _records = freshHead;
      return;
    }
    final tail = _records.length > freshHead.length
        ? _records.sublist(freshHead.length)
        : <IncomeRecord>[];
    _records = [...freshHead, ...tail];
  }

  Future<void> _refreshTotals() async {
    _seedTotalsFromCache();

    final incomeTotal = await _service.getIncomeTotal();
    final salesTotal = await _service.getIncomeTotalByKind(IncomeKind.sale);
    final investmentsTotal =
        await _service.getIncomeTotalByKind(IncomeKind.investment);
    final todayIncome = await _service.getIncomeTodayTotal();
    final todaySales =
        await _service.getIncomeTodayTotalByKind(IncomeKind.sale);
    final todayInvestments =
        await _service.getIncomeTodayTotalByKind(IncomeKind.investment);
    final count = await _service.getIncomeCount();

    // Only overwrite fields that actually succeeded; keep last-known values
    // otherwise so a failed query (e.g. index still building) never zeros
    // the dashboard.
    var anyFailed = false;
    if (incomeTotal != null) {
      _totalIncome = incomeTotal;
    } else {
      anyFailed = true;
    }
    if (salesTotal != null) {
      _totalSales = salesTotal;
    } else {
      anyFailed = true;
    }
    if (investmentsTotal != null) {
      _totalInvestments = investmentsTotal;
    } else {
      anyFailed = true;
    }
    if (todayIncome != null) {
      _todayIncome = todayIncome;
    } else {
      anyFailed = true;
    }
    if (todaySales != null) {
      _todaySales = todaySales;
    } else {
      anyFailed = true;
    }
    if (todayInvestments != null) {
      _todayInvestments = todayInvestments;
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
      await OfflineCacheService().cacheIncomeTotals({
        'totalIncome': _totalIncome,
        'totalSales': _totalSales,
        'totalInvestments': _totalInvestments,
        'todayIncome': _todayIncome,
        'todaySales': _todaySales,
        'todayInvestments': _todayInvestments,
        'totalCount': _totalCount.toDouble(),
      });
    } catch (_) {
      // Cache write failure is non-fatal: totals still shown from network.
    }
  }

  void _seedTotalsFromCache() {
    try {
      final cached = OfflineCacheService().getCachedIncomeTotals();
      if (cached == null) return;
      _totalIncome = cached['totalIncome'] ?? 0.0;
      _totalSales = cached['totalSales'] ?? 0.0;
      _totalInvestments = cached['totalInvestments'] ?? 0.0;
      _todayIncome = cached['todayIncome'] ?? 0.0;
      _todaySales = cached['todaySales'] ?? 0.0;
      _todayInvestments = cached['todayInvestments'] ?? 0.0;
      _totalCount = (cached['totalCount'] ?? 0).toInt();
      notifyListeners();
    } catch (_) {
      // Cache read failure is non-fatal: fall through to network path.
    }
  }

  /// Load the complete dataset (used by reports/export screens).
  Future<void> loadFullRecords() async {
    try {
      final cached = OfflineCacheService().getCachedIncome();
      if (cached != null) {
        _fullRecords = cached;
        notifyListeners();
      }
    } catch (_) {
      // Cache read failure is non-fatal: fall through to network path.
    }

    final records = await _service.getAllIncome();
    _fullRecords = records;
    try {
      await OfflineCacheService().cacheIncome(records);
    } catch (_) {
      // Cache write failure is non-fatal: still notify with fresh data.
    }
    notifyListeners();
  }

  Future<bool> addIncome(IncomeRecord record) async {
    final id = await _service.addIncome(record);
    if (id == null) {
      _errorMessage = 'Failed to record income';
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

  Future<bool> updateIncome(IncomeRecord record) async {
    final success = await _service.updateIncome(record);
    if (!success) {
      _errorMessage = 'Failed to update income';
      notifyListeners();
      return false;
    }
    _refreshTotals();
    return true;
  }

  Future<bool> deleteIncome(String id) async {
    final success = await _service.deleteIncome(id);
    if (!success) {
      _errorMessage = 'Failed to delete income';
      notifyListeners();
      return false;
    }
    _refreshTotals();
    return true;
  }

  static double sum(Iterable<IncomeRecord> records) =>
      records.fold(0.0, (total, r) => total + r.amount);

  static double sumToday(Iterable<IncomeRecord> records, {DateTime? now}) {
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
