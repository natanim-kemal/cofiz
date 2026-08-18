import 'package:hive_flutter/hive_flutter.dart';
import '../models/worker_model.dart';
import '../models/transaction_model.dart';
import '../models/income_record_model.dart';
import '../models/expense_record_model.dart';

class OfflineCacheService {
  static final OfflineCacheService _instance = OfflineCacheService._internal();
  factory OfflineCacheService() => _instance;
  OfflineCacheService._internal();

  static const String _workersBox = 'workers_cache';
  static const String _transactionsBox = 'transactions_cache';
  static const String _pendingBox = 'pending_operations';
  static const String _deliveredBox = 'delivered_operations';
  static const String _incomeBox = 'income_cache';
  static const String _expensesBox = 'expenses_cache';
  static const String _totalsBox = 'totals_cache';

  /// Records older than this are evicted on write, bounding the cache
  /// regardless of how much history the backend accumulates.
  static const Duration _retentionWindow = Duration(days: 365);

  static DateTime get _cutoff => DateTime.now().subtract(_retentionWindow);

  Future<void> initialize({String? path}) async {
    if (path != null) {
      Hive.init(path);
    } else {
      await Hive.initFlutter();
    }

    await Hive.openBox(_workersBox);
    await Hive.openBox(_transactionsBox);
    await Hive.openBox(_pendingBox);
    await Hive.openBox(_deliveredBox);
    await Hive.openBox(_incomeBox);
    await Hive.openBox(_expensesBox);
    await Hive.openBox(_totalsBox);
  }

  // Workers cache
  Future<void> cacheWorkers(List<Worker> workers) async {
    final box = Hive.box(_workersBox);
    final workersMap = {for (var w in workers) w.id: w.toJson()};
    await box.put('all_workers', workersMap);
  }

  List<Worker>? getCachedWorkers() {
    final box = Hive.box(_workersBox);
    final cached = box.get('all_workers') as Map<dynamic, dynamic>?;
    if (cached == null) return null;

    return cached.values
        .map((json) => Worker.fromJson(Map<String, dynamic>.from(json as Map)))
        .toList();
  }

  // Transactions cache (kept within the retention window)
  Future<void> cacheTransactions(List<MoneyTransaction> transactions) async {
    final box = Hive.box(_transactionsBox);
    final cutoff = _cutoff;
    final transactionsMap = {
      for (final t in transactions)
        if (t.createdAt.isAfter(cutoff)) t.id: t.toJson(),
    };
    await box.put('all_transactions', transactionsMap);
  }

  List<MoneyTransaction>? getCachedTransactions() {
    final box = Hive.box(_transactionsBox);
    final cached = box.get('all_transactions') as Map<dynamic, dynamic>?;
    if (cached == null) return null;

    return cached.values
        .map((json) =>
            MoneyTransaction.fromJson(Map<String, dynamic>.from(json as Map)))
        .toList();
  }

  // Income cache (kept within the retention window)
  Future<void> cacheIncome(List<IncomeRecord> records) async {
    final box = Hive.box(_incomeBox);
    final cutoff = _cutoff;
    final recordsMap = {
      for (final r in records)
        if (r.createdAt.isAfter(cutoff)) r.id: r.toJson(),
    };
    await box.put('all_income', recordsMap);
  }

  List<IncomeRecord>? getCachedIncome() {
    final box = Hive.box(_incomeBox);
    final cached = box.get('all_income') as Map<dynamic, dynamic>?;
    if (cached == null) return null;

    return cached.values
        .map((json) =>
            IncomeRecord.fromJson(Map<String, dynamic>.from(json as Map)))
        .toList();
  }

  // Expenses cache (kept within the retention window)
  Future<void> cacheExpenses(List<ExpenseRecord> records) async {
    final box = Hive.box(_expensesBox);
    final cutoff = _cutoff;
    final recordsMap = {
      for (final r in records)
        if (r.createdAt.isAfter(cutoff)) r.id: r.toJson(),
    };
    await box.put('all_expenses', recordsMap);
  }

  List<ExpenseRecord>? getCachedExpenses() {
    final box = Hive.box(_expensesBox);
    final cached = box.get('all_expenses') as Map<dynamic, dynamic>?;
    if (cached == null) return null;

    return cached.values
        .map((json) =>
            ExpenseRecord.fromJson(Map<String, dynamic>.from(json as Map)))
        .toList();
  }

  // Income totals cache (last-known server-side aggregates)
  Future<void> cacheIncomeTotals(Map<String, double> totals) async {
    await Hive.box(_totalsBox).put('income_totals', totals);
  }

  Map<String, double>? getCachedIncomeTotals() {
    final box = Hive.box(_totalsBox);
    final cached = box.get('income_totals') as Map<dynamic, dynamic>?;
    if (cached == null) return null;
    return cached.map((k, v) => MapEntry(k as String, (v as num).toDouble()));
  }

  // Expenses totals cache (last-known server-side aggregates)
  Future<void> cacheExpenseTotals(Map<String, double> totals) async {
    await Hive.box(_totalsBox).put('expense_totals', totals);
  }

  Map<String, double>? getCachedExpenseTotals() {
    final box = Hive.box(_totalsBox);
    final cached = box.get('expense_totals') as Map<dynamic, dynamic>?;
    if (cached == null) return null;
    return cached.map((k, v) => MapEntry(k as String, (v as num).toDouble()));
  }

  // Today totals cache (transactions)
  Future<void> cacheTodayTotals(Map<String, double> totals) async {
    await Hive.box(_totalsBox).put('today_totals', totals);
  }

  Map<String, double>? getCachedTodayTotals() {
    final box = Hive.box(_totalsBox);
    final cached = box.get('today_totals') as Map<dynamic, dynamic>?;
    if (cached == null) return null;
    return cached.map((k, v) => MapEntry(k as String, (v as num).toDouble()));
  }

  // Pending operations queue
  Future<void> queueOperation(Map<String, dynamic> operation) async {
    final box = Hive.box(_pendingBox);
    final pending = box.get('queue', defaultValue: <Map>[]) as List;
    pending.add(operation);
    await box.put('queue', pending);
  }

  List<Map<String, dynamic>> getPendingOperations() {
    final box = Hive.box(_pendingBox);
    final pending = box.get('queue', defaultValue: <Map>[]) as List;
    return pending.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> clearPendingOperations() async {
    final box = Hive.box(_pendingBox);
    await box.put('queue', <Map>[]);
  }

  Future<void> removePendingOperation(int index) async {
    final box = Hive.box(_pendingBox);
    final pending = box.get('queue', defaultValue: <Map>[]) as List;
    if (index < pending.length) {
      pending.removeAt(index);
      await box.put('queue', pending);
    }
  }

  Future<void> replacePendingOperations(
      List<Map<String, dynamic>> operations) async {
    final box = Hive.box(_pendingBox);
    await box.put('queue', operations);
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

  // Clear all cache
  Future<void> clearAllCache() async {
    await Hive.box(_workersBox).clear();
    await Hive.box(_transactionsBox).clear();
    await Hive.box(_incomeBox).clear();
    await Hive.box(_expensesBox).clear();
    await Hive.box(_pendingBox).clear();
    await Hive.box(_deliveredBox).clear();
    await Hive.box(_totalsBox).clear();
  }
}
