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

  // Guards concurrent _refreshTotals() runs: only the latest invocation may
  // write results, so a slow stale refresh can never clobber fresh totals
  // (the "total went up then reverted" bug).
  int _totalsGeneration = 0;

  // True once totals hold real session data (computed or seeded). Replaces
  // the old "all zeros means cold start" heuristic, which misfired after an
  // optimistic delete zeroed every total and re-seeded stale cache values.
  bool _totalsHaveData = false;

  // Optimistic record ids (queued ops not yet confirmed by the server
  // stream). Protected from being dropped by _mergeFirstPage.
  final Set<String> _pendingIds = {};

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
        // A full first page implies more may exist - enable Load More.
        // (The cursor itself is bootstrapped lazily in loadMore.)
        if (!_loadedExtraPages) _hasMore = records.length >= _pageSize;
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

    // The live stream cannot expose a DocumentSnapshot cursor. When no
    // cursor exists yet (first loadMore after the stream-only init), fetch
    // a fresh first page to establish it; known ids are filtered below.
    var startAfter = _lastDoc;
    if (startAfter == null && _records.isNotEmpty) {
      final bootstrap = await _service.getIncomePage(pageSize: _pageSize);
      startAfter = bootstrap.lastDoc;
      if (startAfter == null) {
        _hasMore = false;
        _isLoadingMore = false;
        notifyListeners();
        return;
      }
    }

    final page = await _service.getIncomePage(
      startAfter: startAfter,
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

    // Optimistic records the server hasn't confirmed yet stay visible;
    // otherwise a snapshot taken before the sync commit wipes them (they
    // reappear on the next emission - the "row flashed away" bug).
    final freshIds = freshHead.map((r) => r.id).toSet();
    final stillPending = _records
        .where((r) => _pendingIds.contains(r.id) && !freshIds.contains(r.id))
        .toList();
    for (final id in freshIds) {
      if (_pendingIds.remove(id)) {
        // Confirmed by the server: reconcile totals so the pending delta
        // added by the last refresh is dropped exactly once.
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
          : <IncomeRecord>[];
      _records = [...freshHead, ...tail];
      return;
    }

    final merged = <IncomeRecord>[...stillPending, ...freshHead]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (!_loadedExtraPages) {
      _records = merged;
      return;
    }
    final tailIds = merged.map((r) => r.id).toSet();
    final tail = _records.where((r) => !tailIds.contains(r.id)).toList();
    _records = [...merged, ...tail];
  }

  Future<void> _refreshTotals() async {
    final generation = ++_totalsGeneration;
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

    // A newer refresh started while this one was in flight - discard these
    // (stale) results instead of overwriting the newer values.
    if (generation != _totalsGeneration) return;

    // Reconcile: a server aggregate taken BEFORE the queued create commits
    // is stale by exactly the pending records' amounts. Add them back so a
    // successful-but-stale response can never pull the total down (the
    // visible "total bumped then reverted" bug).
    final pendingById = {
      for (final r in _records)
        if (_pendingIds.contains(r.id)) r.id: r,
      for (final r in _fullRecords)
        if (_pendingIds.contains(r.id)) r.id: r,
    };
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    double pendingTotal = 0;
    double pendingSales = 0;
    double pendingInvestments = 0;
    double pendingToday = 0;
    double pendingTodaySales = 0;
    double pendingTodayInvestments = 0;
    for (final r in pendingById.values) {
      pendingTotal += r.amount;
      final isToday = r.createdAt.isAfter(dayStart);
      if (r.kind == IncomeKind.investment) {
        pendingInvestments += r.amount;
        if (isToday) pendingTodayInvestments += r.amount;
      } else {
        pendingSales += r.amount;
        if (isToday) pendingTodaySales += r.amount;
      }
      if (isToday) pendingToday += r.amount;
    }
    debugPrint(
        '[Income] refresh gen=$generation serverTotal=$incomeTotal pending=${pendingById.length} ($pendingTotal)');

    // Only overwrite fields that actually succeeded; keep last-known values
    // otherwise so a failed query (e.g. index still building) never zeros
    // the dashboard.
    var anyFailed = false;
    if (incomeTotal != null) {
      _totalIncome = incomeTotal + pendingTotal;
    } else {
      anyFailed = true;
    }
    if (salesTotal != null) {
      _totalSales = salesTotal + pendingSales;
    } else {
      anyFailed = true;
    }
    if (investmentsTotal != null) {
      _totalInvestments = investmentsTotal + pendingInvestments;
    } else {
      anyFailed = true;
    }
    if (todayIncome != null) {
      _todayIncome = todayIncome + pendingToday;
    } else {
      anyFailed = true;
    }
    if (todaySales != null) {
      _todaySales = todaySales + pendingTodaySales;
    } else {
      anyFailed = true;
    }
    if (todayInvestments != null) {
      _todayInvestments = todayInvestments + pendingTodayInvestments;
    } else {
      anyFailed = true;
    }
    if (count != null) {
      _totalCount = count + pendingById.length;
    } else {
      anyFailed = true;
    }
    _totalsHaveData = true;

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
      // Seed only before the session has any total data (cold start).
      // Mid-session seeding would flash stale cached totals over fresher
      // in-memory values - the visible "total reverted" symptom.
      if (_totalsHaveData) return;
      final cached = OfflineCacheService().getCachedIncomeTotals();
      if (cached == null) return;
      _totalIncome = cached['totalIncome'] ?? 0.0;
      _totalSales = cached['totalSales'] ?? 0.0;
      _totalInvestments = cached['totalInvestments'] ?? 0.0;
      _todayIncome = cached['todayIncome'] ?? 0.0;
      _todaySales = cached['todaySales'] ?? 0.0;
      _todayInvestments = cached['todayInvestments'] ?? 0.0;
      _totalCount = (cached['totalCount'] ?? 0).toInt();
      _totalsHaveData = true;
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
    debugPrint('[Income] addIncome queued id=$id amount=${record.amount}');
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
    // Optimistically reflect the new record in totals so the UI never
    // depends on aggregate-query timing. The next successful
    // _refreshTotals reconciles with server truth.
    _totalIncome += optimistic.amount;
    if (optimistic.kind == IncomeKind.investment) {
      _totalInvestments += optimistic.amount;
      _todayInvestments += optimistic.amount;
    } else {
      _totalSales += optimistic.amount;
      _todaySales += optimistic.amount;
    }
    _todayIncome += optimistic.amount;
    _totalCount += 1;
    // Optimistic mutations establish live session data: later refreshes
    // must never seed stale cache values over them.
    _totalsHaveData = true;
    _pendingIds.add(id);
    notifyListeners();
    // Bump the generation so the in-flight (stale) refresh triggered before
    // this add cannot clobber these values when it completes.
    _totalsGeneration++;
    _refreshTotals();
    return true;
  }

  Future<bool> updateIncome(IncomeRecord record) async {
    final idx = _records.indexWhere((r) => r.id == record.id);
    final old = idx >= 0 ? _records[idx] : null;
    final fullIdx = _fullRecords.indexWhere((r) => r.id == record.id);
    final oldFull = fullIdx >= 0 ? _fullRecords[fullIdx] : null;

    // Optimistic replace BEFORE awaiting the service: offline edits must
    // show up instantly; the service queues the op and returns true.
    _records = [for (final r in _records) r.id == record.id ? record : r];
    _fullRecords = [
      for (final r in _fullRecords) r.id == record.id ? record : r,
    ];
    notifyListeners();

    final success = await _service.updateIncome(record);
    if (!success) {
      // Rollback the optimistic replace (queue failure path).
      if (old != null) {
        _records = [
          for (final r in _records) r.id == old.id ? old : r,
        ];
      }
      if (oldFull != null) {
        _fullRecords = [
          for (final r in _fullRecords) r.id == oldFull.id ? oldFull : r,
        ];
      }
      _errorMessage = 'Failed to update income';
      notifyListeners();
      return false;
    }
    _refreshTotals();
    return true;
  }

  Future<bool> deleteIncome(String id) async {
    // If the record's create op hasn't synced yet, cancelling the queued
    // op is essential: a server delete of a not-yet-existing doc is a
    // no-op, and the queued create would resurrect the record afterwards
    // (total income going UP after a delete).
    await OfflineCacheService().removePendingOperationByOpId(id);
    _pendingIds.remove(id);

    // Optimistic removal BEFORE the service call: offline deletes must
    // drop the row instantly, and if the record never reached the server
    // (pending create) no stream emission will ever arrive to remove it.
    final removed = <String, IncomeRecord>{};
    for (final r in [..._records, ..._fullRecords]) {
      if (r.id != id || removed.containsKey(r.id)) continue;
      removed[r.id] = r;
    }
    _records = _records.where((r) => r.id != id).toList();
    _fullRecords = _fullRecords.where((r) => r.id != id).toList();
    // Bump the generation BEFORE mutating totals so any in-flight refresh
    // cannot clobber these values while we await the service call below.
    _totalsGeneration++;
    _totalsHaveData = true;
    // Optimistically decrement totals by kind; next refresh reconciles
    // with server truth. Today totals only move for records created today —
    // deleting an old record must not corrupt them.
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    for (final r in removed.values) {
      _totalIncome -= r.amount;
      final isToday = r.createdAt.isAfter(dayStart);
      if (r.kind == IncomeKind.investment) {
        _totalInvestments -= r.amount;
        if (isToday) _todayInvestments -= r.amount;
      } else {
        _totalSales -= r.amount;
        if (isToday) _todaySales -= r.amount;
      }
      if (isToday) _todayIncome -= r.amount;
      _totalCount -= 1;
    }
    debugPrint(
        '[Income] deleteIncome id=$id remaining records=${_records.length} total=$_totalIncome');
    notifyListeners();

    final success = await _service.deleteIncome(id);
    debugPrint('[Income] deleteIncome id=$id serverSuccess=$success');
    if (!success) {
      // Keep removed state (already tombstoned) — outbox will retry.
      return false;
    }
    try {
      await OfflineCacheService().removeCachedIncome(id);
    } catch (_) {
      // Cache write failure is non-fatal: next cache sync reconciles.
    }
    _totalsGeneration++;
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
