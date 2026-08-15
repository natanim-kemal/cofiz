import 'package:hive_flutter/hive_flutter.dart';
import '../models/worker_model.dart';
import '../models/transaction_model.dart';

class OfflineCacheService {
  static final OfflineCacheService _instance = OfflineCacheService._internal();
  factory OfflineCacheService() => _instance;
  OfflineCacheService._internal();

  static const String _workersBox = 'workers_cache';
  static const String _transactionsBox = 'transactions_cache';
  static const String _pendingBox = 'pending_operations';

  Future<void> initialize() async {
    await Hive.initFlutter();

    // Open boxes
    await Hive.openBox(_workersBox);
    await Hive.openBox(_transactionsBox);
    await Hive.openBox(_pendingBox);
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

  // Transactions cache
  Future<void> cacheTransactions(List<MoneyTransaction> transactions) async {
    final box = Hive.box(_transactionsBox);
    final transactionsMap = {for (var t in transactions) t.id: t.toJson()};
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

  // Clear all cache
  Future<void> clearAllCache() async {
    await Hive.box(_workersBox).clear();
    await Hive.box(_transactionsBox).clear();
    await Hive.box(_pendingBox).clear();
  }
}
