import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/worker_model.dart';
import '../models/transaction_model.dart';
import '../models/income_record_model.dart';
import '../models/expense_record_model.dart';

/// Local persistence layer (Hive).
///
/// Storage layout:
/// - Collection caches (workers/transactions/income/expenses) store one
///   document per Hive key (the doc id), so partial reads/writes stay cheap.
/// - A legacy single-key snapshot from older app versions is migrated to
///   per-id keys on first read or write.
/// - [metaBoxName] stores per-dataset `fetchedAt` timestamps used to detect
///   staleness.
class OfflineCacheService {
  static final OfflineCacheService _instance = OfflineCacheService._internal();
  factory OfflineCacheService() => _instance;
  OfflineCacheService._internal();

  static const String _workersBox = 'workers_cache';
  static const String _transactionsBox = 'transactions_cache';
  static const String _workerTxsBox = 'worker_transactions_cache';
  static const String pendingBoxName = 'pending_operations';
  static const String _deliveredBox = 'delivered_operations';
  static const String failedBoxName = 'failed_operations';
  static const String _incomeBox = 'income_cache';
  static const String _expensesBox = 'expenses_cache';
  static const String _totalsBox = 'totals_cache';
  static const String metaBoxName = 'cache_meta';

  /// Legacy single-key snapshots written by older versions of this service.
  static const String _legacyWorkersKey = 'all_workers';
  static const String _legacyTransactionsKey = 'all_transactions';
  static const String _legacyIncomeKey = 'all_income';
  static const String _legacyExpensesKey = 'all_expenses';

  /// Keys with this prefix in the workers box are single cached profiles and
  /// must survive collection-wide replacements.
  static const String _profilePrefix = 'profile_';

  /// Keys in the worker-transactions box are `wt_<workerId>:<txId>`.
  static const String _wtPrefix = 'wt_';

  static const String _fetchedAtPrefix = 'fetchedAt_';

  /// Dataset names used with [getFetchedAt] / [isStale].
  static const String dsWorkers = 'workers';
  static const String dsTransactions = 'transactions';
  static const String dsIncome = 'income';
  static const String dsExpenses = 'expenses';
  static const String dsIncomeTotals = 'income_totals';
  static const String dsExpenseTotals = 'expense_totals';
  static const String dsTodayTotals = 'today_totals';
  static const String dsWorkerProfile = 'worker_profile';
  static const String dsWorkerTransactions = 'worker_transactions';

  /// Records older than this are evicted on write, bounding the cache
  /// regardless of how much history the backend accumulates.
  static const Duration retentionWindow = Duration(days: 365);

  static DateTime get _cutoff => DateTime.now().subtract(retentionWindow);

  Future<void> initialize({String? path}) async {
    if (path != null) {
      Hive.init(path);
    } else {
      await Hive.initFlutter();
    }

    await Hive.openBox(_workersBox);
    await Hive.openBox(_transactionsBox);
    await Hive.openBox(_workerTxsBox);
    await Hive.openBox(pendingBoxName);
    await Hive.openBox(_deliveredBox);
    await Hive.openBox(failedBoxName);
    await Hive.openBox(_incomeBox);
    await Hive.openBox(_expensesBox);
    await Hive.openBox(_totalsBox);
    await Hive.openBox(metaBoxName);
  }

  // ---------------------------------------------------------------------------
  // Generic per-document helpers
  // ---------------------------------------------------------------------------

  /// Migrates a legacy single-key snapshot to per-id entries. Returns the
  /// legacy map if one was found (and starts the write-back), else null.
  ///
  /// The putAll is issued BEFORE the delete: Hive serializes writes per box
  /// in call order, so a crash mid-migration leaves either both applied or
  /// only the putAll - never a deleted snapshot without its replacement.
  /// Worst case the migration re-runs idempotently on next launch.
  Map<String, dynamic>? _takeLegacySnapshot(
    Box box,
    String legacyKey,
  ) {
    final legacy = box.get(legacyKey);
    if (legacy is! Map) return null;
    final snapshot = <String, dynamic>{
      for (final e in legacy.entries) e.key.toString(): e.value,
    };
    box.putAll(snapshot);
    box.delete(legacyKey);
    return snapshot;
  }

  /// Replaces a box's contents with [entries] keyed by document id,
  /// migrating a legacy snapshot if present and removing keys that are no
  /// longer part of the set. Keys starting with [preservePrefix] are kept.
  Future<void> _replaceEntries(
    Box box,
    Map<String, dynamic> entries,
    String legacyKey, {
    String? preservePrefix,
  }) async {
    _takeLegacySnapshot(box, legacyKey);
    final staleKeys = box.keys.whereType<String>().where((k) {
      if (entries.containsKey(k)) return false;
      if (preservePrefix != null && k.startsWith(preservePrefix)) return false;
      return true;
    }).toList();
    await box.putAll(entries);
    for (final k in staleKeys) {
      await box.delete(k);
    }
  }

  List<T>? _readEntries<T>(
    Box box,
    T Function(Map<String, dynamic>) fromJson,
    String legacyKey, {
    String? excludePrefix,
  }) {
    var source = _takeLegacySnapshot(box, legacyKey);
    if (source == null) {
      source = <String, dynamic>{};
      for (final k in box.keys.whereType<String>()) {
        if (excludePrefix != null && k.startsWith(excludePrefix)) continue;
        final v = box.get(k);
        if (v is Map) {
          source[k] = v;
        }
      }
    }
    // Empty means "never cached" (null), distinct from an explicitly cached
    // empty collection. A box holding only excluded keys (e.g. worker
    // profiles alongside the workers collection) still counts as never
    // cached for this dataset.
    if (source.isEmpty) return null;
    return source.values
        .map((v) => fromJson(Map<String, dynamic>.from(v as Map)))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Fetched-at metadata / staleness
  // ---------------------------------------------------------------------------

  Future<void> markFetched(String dataset) async {
    await Hive.box(metaBoxName).put(
        '$_fetchedAtPrefix$dataset', DateTime.now().millisecondsSinceEpoch);
  }

  DateTime? getFetchedAt(String dataset) {
    final v = Hive.box(metaBoxName).get('$_fetchedAtPrefix$dataset') as int?;
    if (v == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(v);
  }

  /// True when the dataset has never been fetched or its last fetch is older
  /// than [maxAge].
  bool isStale(
    String dataset, {
    Duration maxAge = const Duration(minutes: 5),
  }) {
    final t = getFetchedAt(dataset);
    if (t == null) return true;
    return DateTime.now().difference(t) > maxAge;
  }

  /// Most recent fetch time across [datasets], or null when none was ever
  /// fetched. Used by UI (e.g. the offline banner) to report the age of
  /// whatever data is actually on screen.
  DateTime? newestFetchedAt(Iterable<String> datasets) {
    DateTime? newest;
    for (final d in datasets) {
      final t = getFetchedAt(d);
      if (t != null && (newest == null || t.isAfter(newest))) newest = t;
    }
    return newest;
  }

  /// Per-worker dataset name for [getFetchedAt]/[isStale] - worker fetch
  /// times must never share one global timestamp.
  static String workerTxDataset(String workerId) =>
      '$dsWorkerTransactions:$workerId';

  // ---------------------------------------------------------------------------
  // Workers cache
  // ---------------------------------------------------------------------------

  Future<void> cacheWorkers(List<Worker> workers) async {
    await _replaceEntries(
      Hive.box(_workersBox),
      {for (var w in workers) w.id: w.toJson()},
      _legacyWorkersKey,
      preservePrefix: _profilePrefix,
    );
    await markFetched(dsWorkers);
  }

  List<Worker>? getCachedWorkers() => _readEntries<Worker>(
        Hive.box(_workersBox),
        Worker.fromJson,
        _legacyWorkersKey,
        excludePrefix: _profilePrefix,
      );

  /// Caches a single worker profile (used by the collector app for instant
  /// cold start). Keyed by id so multiple accounts on one device coexist.
  Future<void> cacheWorkerProfile(Worker worker) async {
    await Hive.box(_workersBox)
        .put('$_profilePrefix${worker.id}', worker.toJson());
    await markFetched(dsWorkerProfile);
  }

  /// Returns the cached profile for [expectedId], or - only when exactly one
  /// profile is stored - the profile itself when [expectedId] is null.
  /// Multiple stored profiles with a null [expectedId] is ambiguous on a
  /// multi-account device, so null is returned rather than an arbitrary
  /// account's data. Returns null when absent/mismatched.
  Worker? getCachedWorkerProfile({String? expectedId}) {
    final box = Hive.box(_workersBox);
    Worker? parse(Object? raw) {
      if (raw is! Map) return null;
      try {
        return Worker.fromJson(Map<String, dynamic>.from(raw));
      } catch (_) {
        return null;
      }
    }

    if (expectedId != null) {
      final direct = parse(box.get('$_profilePrefix$expectedId'));
      if (direct != null) return direct;
    }
    Worker? single;
    for (final k in box.keys.whereType<String>()) {
      if (!k.startsWith(_profilePrefix)) continue;
      final w = parse(box.get(k));
      if (w == null) continue;
      if (expectedId == null) {
        if (single != null) return null; // ambiguous: >1 profile
        single = w;
      } else if (w.id == expectedId) {
        return w;
      }
    }
    return single;
  }

  // ---------------------------------------------------------------------------
  // Transactions cache
  // ---------------------------------------------------------------------------

  Future<void> cacheTransactions(List<MoneyTransaction> transactions) async {
    final cutoff = _cutoff;
    await _replaceEntries(
      Hive.box(_transactionsBox),
      {
        for (final t in transactions)
          if (t.createdAt.isAfter(cutoff)) t.id: t.toJson(),
      },
      _legacyTransactionsKey,
    );
    await markFetched(dsTransactions);
  }

  List<MoneyTransaction>? getCachedTransactions() =>
      _readEntries<MoneyTransaction>(
        Hive.box(_transactionsBox),
        MoneyTransaction.fromJson,
        _legacyTransactionsKey,
      );

  // ---------------------------------------------------------------------------
  // Per-worker transactions cache (collector device cold start)
  // ---------------------------------------------------------------------------

  /// Replaces the cached set for [workerId] with [transactions].
  Future<void> cacheWorkerTransactions(
    String workerId,
    List<MoneyTransaction> transactions,
  ) async {
    final box = Hive.box(_workerTxsBox);
    final keyPrefix = '$_wtPrefix$workerId:';
    final staleKeys = box.keys
        .whereType<String>()
        .where((k) => k.startsWith(keyPrefix))
        .toList();
    for (final k in staleKeys) {
      await box.delete(k);
    }
    final cutoff = _cutoff;
    await box.putAll({
      for (final t in transactions)
        if (t.createdAt.isAfter(cutoff)) '$keyPrefix${t.id}': t.toJson(),
    });
    await markFetched(workerTxDataset(workerId));
  }

  /// Cached transactions for [workerId], unordered. Empty list when none —
  /// callers seed the UI directly and sort as needed.
  List<MoneyTransaction> getCachedWorkerTransactions(String workerId) {
    final box = Hive.box(_workerTxsBox);
    final keyPrefix = '$_wtPrefix$workerId:';
    final result = <MoneyTransaction>[];
    for (final k in box.keys.whereType<String>()) {
      if (!k.startsWith(keyPrefix)) continue;
      final v = box.get(k);
      if (v is! Map) continue;
      try {
        result.add(MoneyTransaction.fromJson(Map<String, dynamic>.from(v)));
      } catch (_) {
        // Skip corrupt entries rather than failing the whole read.
      }
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Income cache
  // ---------------------------------------------------------------------------

  Future<void> cacheIncome(List<IncomeRecord> records) async {
    final cutoff = _cutoff;
    await _replaceEntries(
      Hive.box(_incomeBox),
      {
        for (final r in records)
          if (r.createdAt.isAfter(cutoff)) r.id: r.toJson(),
      },
      _legacyIncomeKey,
    );
    await markFetched(dsIncome);
  }

  List<IncomeRecord>? getCachedIncome() => _readEntries<IncomeRecord>(
        Hive.box(_incomeBox),
        IncomeRecord.fromJson,
        _legacyIncomeKey,
      );

  /// Drops one record from the income cache (called on local delete so a
  /// deleted record cannot resurface from the cache after a restart).
  Future<void> removeCachedIncome(String id) async {
    final cached = getCachedIncome();
    if (cached == null) return;
    final kept = cached.where((r) => r.id != id).toList();
    if (kept.length == cached.length) return;
    debugPrint(
        '[Cache] removeCachedIncome id=$id cache ${cached.length}->${kept.length}');
    await cacheIncome(kept);
  }

  // ---------------------------------------------------------------------------
  // Expenses cache
  // ---------------------------------------------------------------------------

  Future<void> cacheExpenses(List<ExpenseRecord> records) async {
    final cutoff = _cutoff;
    await _replaceEntries(
      Hive.box(_expensesBox),
      {
        for (final r in records)
          if (r.createdAt.isAfter(cutoff)) r.id: r.toJson(),
      },
      _legacyExpensesKey,
    );
    await markFetched(dsExpenses);
  }

  List<ExpenseRecord>? getCachedExpenses() => _readEntries<ExpenseRecord>(
        Hive.box(_expensesBox),
        ExpenseRecord.fromJson,
        _legacyExpensesKey,
      );

  /// Drops one record from the expense cache (see [removeCachedIncome]).
  Future<void> removeCachedExpense(String id) async {
    final cached = getCachedExpenses();
    if (cached == null) return;
    final kept = cached.where((r) => r.id != id).toList();
    if (kept.length == cached.length) return;
    debugPrint(
        '[Cache] removeCachedExpense id=$id cache ${cached.length}->${kept.length}');
    await cacheExpenses(kept);
  }

  // ---------------------------------------------------------------------------
  // Totals caches
  // ---------------------------------------------------------------------------

  Future<void> cacheIncomeTotals(Map<String, double> totals) async {
    await Hive.box(_totalsBox).put('income_totals', totals);
    await markFetched(dsIncomeTotals);
  }

  Map<String, double>? getCachedIncomeTotals() {
    final box = Hive.box(_totalsBox);
    final cached = box.get('income_totals') as Map<dynamic, dynamic>?;
    if (cached == null) return null;
    return cached.map((k, v) => MapEntry(k as String, (v as num).toDouble()));
  }

  Future<void> cacheExpenseTotals(Map<String, double> totals) async {
    await Hive.box(_totalsBox).put('expense_totals', totals);
    await markFetched(dsExpenseTotals);
  }

  Map<String, double>? getCachedExpenseTotals() {
    final box = Hive.box(_totalsBox);
    final cached = box.get('expense_totals') as Map<dynamic, dynamic>?;
    if (cached == null) return null;
    return cached.map((k, v) => MapEntry(k as String, (v as num).toDouble()));
  }

  Future<void> cacheTodayTotals(Map<String, double> totals) async {
    await Hive.box(_totalsBox).put('today_totals', totals);
    await markFetched(dsTodayTotals);
  }

  Map<String, double>? getCachedTodayTotals() {
    final box = Hive.box(_totalsBox);
    final cached = box.get('today_totals') as Map<dynamic, dynamic>?;
    if (cached == null) return null;
    return cached.map((k, v) => MapEntry(k as String, (v as num).toDouble()));
  }

  // ---------------------------------------------------------------------------
  // Pending operations queue
  // ---------------------------------------------------------------------------

  /// opIds explicitly cancelled while an in-flight sync still holds them in
  /// its snapshot. [replacePendingOperations] filters these out so a failed
  /// sync's merge-back cannot resurrect an operation the user deleted
  /// mid-flight. Kept for the process lifetime (op ids are fresh UUIDs, so
  /// a legitimate re-queue can never collide with a tombstone).
  final Set<String> _cancelledOpIds = {};

  Future<void> queueOperation(Map<String, dynamic> operation) async {
    assert(operation.containsKey('opId'),
        'queueOperation requires opId for idempotent drain');
    _cancelledOpIds.remove(operation['opId']);
    final box = Hive.box(pendingBoxName);
    final pending = box.get('queue', defaultValue: <Map>[]) as List;
    debugPrint(
        '[Cache] queueOperation opId=${operation['opId']} type=${operation['type']} before=${pending.length}');

    // Coalesce with existing queued op sharing the same logical key.
    // Transfer ops may use transferId alias, so fallback to transferId.
    final opId = operation['opId'] as String;
    final newType = (operation['type'] as String?) ?? '';
    final newTransferId = operation['transferId'] as String?;
    bool matches(Map m) {
      if (m['opId'] == opId) return true;
      if (m['transferId'] == opId) return true;
      if (newTransferId != null && m['transferId'] == newTransferId) {
        return true;
      }
      return false;
    }

    final matchingIdxs = <int>[
      for (var i = 0; i < pending.length; i++)
        if (matches(pending[i] as Map)) i,
    ];

    // A delete supersedes every queued variant of the key: drop them all
    // (covers create+delete AND delete+create+delete without leaving a
    // stale earlier entry for a later coalesce to mistakenly match).
    if (newType.startsWith('delete') && matchingIdxs.isNotEmpty) {
      for (final idx in matchingIdxs.reversed) {
        final removed = Map<String, dynamic>.from(pending.removeAt(idx) as Map);
        final tid = removed['transferId'] as String?;
        if (tid != null) _cancelledOpIds.add(tid);
      }
      _cancelledOpIds.add(opId);
      if (newTransferId != null) _cancelledOpIds.add(newTransferId);
      await box.put('queue', pending);
      debugPrint(
          '[Cache] coalesce delete-removes-all opId=$opId count=${matchingIdxs.length}');
      return;
    }

    // Coalesce with the NEWEST matching entry (last), never an older one -
    // after a delete+create pair the create is the live state.
    final existingIdx = matchingIdxs.isEmpty ? -1 : matchingIdxs.last;
    if (existingIdx != -1) {
      final existing = Map<String, dynamic>.from(pending[existingIdx] as Map);
      final existingType = (existing['type'] as String?) ?? '';

      bool isCreate(String t) => t.startsWith('create');
      bool isUpdate(String t) => t.startsWith('update');
      bool isDelete(String t) => t.startsWith('delete');

      final existingIsCreate = isCreate(existingType);
      final existingIsUpdate = isUpdate(existingType);
      final existingIsDelete = isDelete(existingType);
      final newIsCreate = isCreate(newType);
      final newIsUpdate = isUpdate(newType);
      // Deletes were already handled (remove-all) above; only create/update
      // merges reach here.

      // 1. create + update -> merge into create
      if (existingIsCreate && newIsUpdate) {
        final merged = <String, dynamic>{};
        if (existing['payload'] is Map) {
          merged.addAll(Map<String, dynamic>.from(existing['payload'] as Map));
        }
        if (operation['payload'] is Map) {
          merged.addAll(Map<String, dynamic>.from(operation['payload'] as Map));
        }
        if (merged.isNotEmpty) existing['payload'] = merged;
        pending[existingIdx] = existing;
        await box.put('queue', pending);
        debugPrint('[Cache] coalesce create+update merge opId=$opId');
        return;
      }

      // 3. update + update -> last (merged payload)
      if (existingIsUpdate && newIsUpdate) {
        final merged = <String, dynamic>{};
        if (existing['payload'] is Map) {
          merged.addAll(Map<String, dynamic>.from(existing['payload'] as Map));
        }
        if (operation['payload'] is Map) {
          merged.addAll(Map<String, dynamic>.from(operation['payload'] as Map));
        }
        final updated = Map<String, dynamic>.from(operation);
        if (merged.isNotEmpty) updated['payload'] = merged;
        pending[existingIdx] = updated;
        await box.put('queue', pending);
        debugPrint('[Cache] coalesce update+update last opId=$opId');
        return;
      }

      // 4. update + delete -> delete (unreachable for deletes: the
      // remove-all block above already consumed them; kept for safety)
      if (existingIsUpdate && newType.startsWith('delete')) {
        pending[existingIdx] = Map<String, dynamic>.from(operation);
        await box.put('queue', pending);
        debugPrint('[Cache] coalesce update+delete -> delete opId=$opId');
        return;
      }

      // 5. delete + create -> keep both in order (fall through to add)
      if (existingIsDelete && newIsCreate) {
        // fall through
      } else {
        // default: replace existing with newest (create+create, delete+delete, etc.)
        pending[existingIdx] = Map<String, dynamic>.from(operation);
        await box.put('queue', pending);
        debugPrint(
            '[Cache] coalesce replace opId=$opId $existingType -> $newType');
        return;
      }
    }

    pending.add(operation);
    await box.put('queue', pending);
    debugPrint('[Cache] queueOperation done now=${pending.length}');
  }

  List<Map<String, dynamic>> getPendingOperations() {
    final box = Hive.box(pendingBoxName);
    final pending = box.get('queue', defaultValue: <Map>[]) as List;
    return pending.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> clearPendingOperations() async {
    _cancelledOpIds.clear();
    final box = Hive.box(pendingBoxName);
    await box.put('queue', <Map>[]);
  }

  Future<void> removePendingOperation(int index) async {
    final box = Hive.box(pendingBoxName);
    final pending = box.get('queue', defaultValue: <Map>[]) as List;
    if (index < pending.length) {
      pending.removeAt(index);
      await box.put('queue', pending);
    }
  }

  Future<void> replacePendingOperations(
      List<Map<String, dynamic>> operations) async {
    // Drop operations the user cancelled while this batch was in flight.
    // The tombstones stay in _cancelledOpIds - an earlier sync cycle can
    // still merge them back after this write.
    final effective = operations
        .where((op) => !_cancelledOpIds.contains(op['opId']))
        .toList();
    if (operations.length != effective.length) {
      debugPrint(
          '[Cache] replacePendingOperations dropped ${operations.length - effective.length} cancelled op(s)');
    }
    final box = Hive.box(pendingBoxName);
    await box.put('queue', effective);
  }

  /// Removes every queued operation whose opId equals [opId]. Returns how
  /// many were removed. Used to cancel a queued create when the record is
  /// deleted before its sync commits (prevents post-delete resurrection).
  Future<int> removePendingOperationByOpId(String opId) async {
    _cancelledOpIds.add(opId);
    final pending = getPendingOperations();
    final kept = pending.where((op) => op['opId'] != opId).toList();
    final removed = pending.length - kept.length;
    debugPrint(
        '[Cache] removePendingOperationByOpId opId=$opId removed=$removed now=${kept.length}');
    if (removed > 0) {
      await replacePendingOperations(kept);
    }
    return removed;
  }

  Future<void> markDelivered(String opId, String type) async {
    final box = Hive.box(_deliveredBox);
    await box.put(opId, {
      'opId': opId,
      'type': type,
      'deliveredAt': DateTime.now().millisecondsSinceEpoch
    });
  }

  List<Map<String, dynamic>> getDeliveredOperations() {
    final box = Hive.box(_deliveredBox);
    return box.values.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  int getDeliveredCount() => Hive.box(_deliveredBox).length;

  Future<void> pruneDelivered({Duration ttl = const Duration(days: 7)}) async {
    final box = Hive.box(_deliveredBox);
    final cutoff = DateTime.now().subtract(ttl).millisecondsSinceEpoch;
    final toDelete = <dynamic>[];
    for (final k in box.keys) {
      final v = Map<String, dynamic>.from(box.get(k) as Map);
      if ((v['deliveredAt'] as int) < cutoff) toDelete.add(k);
    }
    for (final k in toDelete) {
      await box.delete(k);
    }
  }

  Future<void> clearDelivered() async => Hive.box(_deliveredBox).clear();

  // ---------------------------------------------------------------------------
  // Failed operations box
  // ---------------------------------------------------------------------------

  List<Map<String, dynamic>> getFailedOperations() {
    if (!Hive.isBoxOpen(failedBoxName)) return [];
    final box = Hive.box(failedBoxName);
    final failed = box.get('queue', defaultValue: <Map>[]) as List;
    return failed.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> markFailed(Map<String, dynamic> operation, String reason) async {
    final box = Hive.box(failedBoxName);
    final failed = box.get('queue', defaultValue: <Map>[]) as List;
    final entry = Map<String, dynamic>.from(operation);
    entry['failedReason'] = reason;
    entry['failedAt'] = DateTime.now().toIso8601String();
    failed.add(entry);
    await box.put('queue', failed);
    debugPrint('[Cache] markFailed opId=${operation['opId']} reason=$reason');
  }

  /// Moves every failed operation back onto the pending queue (appended
  /// after existing pending ops) so the next sync retries it with a fresh
  /// attempt budget. [failedReason]/[failedAt] bookkeeping is stripped and
  /// attempts reset to 0. Ops the user discarded (tombstoned) stay out.
  /// The failed box is cleared afterwards, so a successful requeue+sync
  /// removes the op from both boxes.
  Future<void> requeueFailedOperations() async {
    if (!Hive.isBoxOpen(failedBoxName)) return;
    final failedBox = Hive.box(failedBoxName);
    final failed = failedBox.get('queue', defaultValue: <Map>[]) as List;
    if (failed.isEmpty) return;
    final pendingBox = Hive.box(pendingBoxName);
    final pending = pendingBox.get('queue', defaultValue: <Map>[]) as List;
    var requeued = 0;
    for (final e in failed) {
      final op = Map<String, dynamic>.from(e as Map);
      final opId = op['opId'] as String?;
      if (opId != null && _cancelledOpIds.contains(opId)) continue;
      op
        ..remove('failedReason')
        ..remove('failedAt');
      op['attempts'] = 0;
      pending.add(op);
      requeued++;
    }
    await pendingBox.put('queue', pending);
    await failedBox.put('queue', <Map>[]);
    debugPrint('[Cache] requeueFailedOperations requeued=$requeued');
  }

  Future<void> discardFailed(String opId) async {
    if (!Hive.isBoxOpen(failedBoxName)) return;
    final box = Hive.box(failedBoxName);
    final failed = box.get('queue', defaultValue: <Map>[]) as List;
    Map<String, dynamic>? discarded;
    final kept = failed.where((e) {
      final m = e as Map;
      if (m['opId'] != opId) return true;
      discarded = Map<String, dynamic>.from(m);
      return false;
    }).toList();
    await box.put('queue', kept);
    // Tombstone the op so an in-flight sync's merge-back can never
    // resurrect what the user just discarded.
    _cancelledOpIds.add(opId);
    debugPrint('[Cache] discardFailed opId=$opId kept=${kept.length}');
    if (discarded == null) return;
    await _evictOptimisticCopy(discarded!);
  }

  /// A failed create has no server document behind it - only its optimistic
  /// cache copy. Evict that copy so it cannot resurface after a restart.
  /// Failed deletes are left alone on purpose: the server doc still exists
  /// and the stream will restore the cached row.
  Future<void> _evictOptimisticCopy(Map<String, dynamic> op) async {
    final type = (op['type'] as String?) ?? '';
    switch (type) {
      case 'createIncome':
        final docId = op['docId'] as String?;
        if (docId != null) await removeCachedIncome(docId);
      case 'createExpense':
        final docId = op['docId'] as String?;
        if (docId != null) await removeCachedExpense(docId);
      case 'createTransaction':
      case 'createTransfer':
        final docId = op['docId'] as String?;
        final transferId = op['transferId'] as String? ?? op['opId'] as String?;
        await removeCachedTransaction(docId ?? transferId ?? '');
    }
  }

  Future<void> clearFailed() async {
    if (Hive.isBoxOpen(failedBoxName)) {
      await Hive.box(failedBoxName).clear();
    }
  }

  // ---------------------------------------------------------------------------
  // Transaction cache helpers (remove by id / transferId)
  // ---------------------------------------------------------------------------

  Future<void> removeCachedTransaction(String id) async {
    final cached = getCachedTransactions();
    if (cached == null) return;
    final kept = cached.where((t) => t.id != id && t.transferId != id).toList();
    if (kept.length == cached.length) return;
    debugPrint(
        '[Cache] removeCachedTransaction id=$id cache ${cached.length}->${kept.length}');
    await cacheTransactions(kept);
  }

  // Clear all cache. When [keepOutbox] is true (sign-out), the pending and
  // failed queues survive so offline mutations can still sync under the
  // next session instead of being silently destroyed.
  Future<void> clearAllCache({bool keepOutbox = false}) async {
    _cancelledOpIds.clear();
    await Hive.box(_workersBox).clear();
    await Hive.box(_transactionsBox).clear();
    await Hive.box(_workerTxsBox).clear();
    await Hive.box(_incomeBox).clear();
    await Hive.box(_expensesBox).clear();
    if (!keepOutbox) {
      await Hive.box(pendingBoxName).clear();
      await Hive.box(_deliveredBox).clear();
      if (Hive.isBoxOpen(failedBoxName)) {
        await Hive.box(failedBoxName).clear();
      }
    }
    await Hive.box(_totalsBox).clear();
    await Hive.box(metaBoxName).clear();
  }
}
