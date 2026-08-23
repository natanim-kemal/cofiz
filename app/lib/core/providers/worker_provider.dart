import 'package:flutter/foundation.dart';
import '../models/worker_model.dart';
import '../models/transaction_model.dart';
import '../services/worker_service.dart';
import '../services/notification_service.dart';
import '../services/offline_cache_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WorkerProvider with ChangeNotifier {
  final WorkerService _workerService;

  WorkerProvider({WorkerService? service})
      : _workerService = service ?? WorkerService() {
    _seedWorkersFromCache();
    _initializeWorkers();
  }

  List<Worker> _workers = [];
  List<Worker> _filteredWorkers = [];
  bool _isLoading = false;
  String? _errorMessage;
  String _searchQuery = '';
  String _statusFilter = 'all'; // 'all', 'active', 'busy', 'offline'
  final Map<String, double> _previousBalances = {};

  // Statistics
  int _totalWorkers = 0;
  int _activeToday = 0;
  double _totalRevenue = 0.0;

  List<Worker> get workers => _filteredWorkers;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String get searchQuery => _searchQuery;
  String get statusFilter => _statusFilter;

  int get totalWorkers => _totalWorkers;
  int get activeToday => _activeToday;
  double get totalRevenue => _totalRevenue;

  void _seedWorkersFromCache() {
    try {
      final cached = OfflineCacheService().getCachedWorkers();
      if (cached != null) {
        _workers = cached;
        _applyFilters();
        _updateStatistics();
        notifyListeners();
      }
    } catch (_) {
      // Cache read failure is non-fatal: fall through to network stream.
    }
  }

  /// Initialize workers stream
  void _initializeWorkers() {
    _isLoading = true;
    notifyListeners();

    _workerService.getWorkersStream().listen(
      (workersList) {
        OfflineCacheService().cacheWorkers(workersList).catchError((_) {});
        _checkLowBalances(workersList);
        _workers = workersList;
        _applyFilters();
        _updateStatistics();
        _isLoading = false;
        _errorMessage = null;
        notifyListeners();
      },
      onError: (error) {
        print('Worker stream error: $error');
        // Parse error for user-friendly message
        String friendlyMessage = 'Unable to load collectors.';

        if (error.toString().contains('permission-denied') ||
            error.toString().contains('PERMISSION_DENIED')) {
          friendlyMessage =
              'Database access denied. Please enable Firestore in your Firebase project.';
        } else if (error.toString().contains('unavailable')) {
          friendlyMessage =
              'Database is unavailable. Please check your internet connection.';
        } else if (error.toString().contains('unauthenticated')) {
          friendlyMessage = 'Authentication required. Please sign in again.';
        }

        _errorMessage = friendlyMessage;
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  /// Apply search and filter
  void _applyFilters() {
    _filteredWorkers = _workers.where((worker) {
      // Search filter
      final matchesSearch = _searchQuery.isEmpty ||
          worker.name.toLowerCase().contains(_searchQuery.toLowerCase());

      // Status filter
      final matchesStatus = _statusFilter == 'all' ||
          worker.status.toLowerCase() == _statusFilter.toLowerCase();

      return matchesSearch && matchesStatus;
    }).toList();
  }

  /// Update statistics
  void _updateStatistics() {
    _totalWorkers = _workers.length;
    _activeToday = _workers.where((w) => w.status == 'active').length;
    _totalRevenue = _workers.fold<double>(
      0.0,
      (sum, worker) => sum + worker.totalCoffeePurchased,
    );
  }

  /// Set search query
  void setSearchQuery(String query) {
    _searchQuery = query;
    _applyFilters();
    notifyListeners();
  }

  /// Set status filter
  void setStatusFilter(String status) {
    _statusFilter = status;
    _applyFilters();
    notifyListeners();
  }

  /// Clear filters
  void clearFilters() {
    _searchQuery = '';
    _statusFilter = 'all';
    _applyFilters();
    notifyListeners();
  }

  /// Cached profile for [id] (sync, from Hive). Non-null means the UI can
  /// render instantly without waiting on the network.
  Worker? getCachedWorkerById(String id) =>
      OfflineCacheService().getCachedWorkerProfile(expectedId: id);

  /// Get worker by ID. Network-first: a fresh fetch updates the Hive profile
  /// cache; when the network fails, falls back to the cached profile so the
  /// collector app still works offline.
  Future<Worker?> getWorkerById(String id) async {
    try {
      final fresh = await _workerService.getWorkerById(id);
      if (fresh != null) {
        await OfflineCacheService().cacheWorkerProfile(fresh);
        return fresh;
      }
    } catch (_) {
      // Network/Firestore unavailable - fall through to cached profile.
    }
    return OfflineCacheService().getCachedWorkerProfile(expectedId: id);
  }

  /// Find worker in local list by ID (sync, ignores filters)
  Worker? findById(String id) {
    try {
      return _workers.firstWhere((w) => w.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Optimistically apply a transaction's balance effect to the matching
  /// worker so the detail-page Balance Card moves instantly offline.
  /// [direction] is +1 for create, -1 for reversal (delete/old-effect).
  /// Mirrors `_balanceUpdates` semantics — keep in sync.
  void applyTransactionDelta(MoneyTransaction t, int direction) {
    final idx = _workers.indexWhere((w) => w.id == t.workerId);
    if (idx == -1) return;
    final w = _workers[idx];
    final m = direction.toDouble();
    double balance = w.currentBalance;
    double dist = w.totalDistributed;
    double ret = w.totalReturned;
    double purch = w.totalCoffeePurchased;
    double comm = w.totalCommissionEarned;
    switch (t.type.toLowerCase()) {
      case 'distribution':
        balance += t.amount * m;
        dist += t.amount * m;
        break;
      case 'return':
        balance -= t.amount * m;
        ret += t.amount * m;
        break;
      case 'purchase':
        balance -= t.amount * m;
        purch += t.amount * m;
        if ((t.commissionAmount ?? 0) > 0) comm += t.commissionAmount! * m;
        break;
      case 'transfer':
        final eff = t.isTransferSender ? -1.0 : 1.0;
        balance += t.amount * m * eff;
        if (t.isTransferSender) {
          ret += t.amount * m;
        } else {
          dist += t.amount * m;
        }
        break;
    }
    _workers[idx] = w.copyWith(
      currentBalance: balance,
      totalDistributed: dist < 0 ? 0 : dist,
      totalReturned: ret < 0 ? 0 : ret,
      totalCoffeePurchased: purch < 0 ? 0 : purch,
      totalCommissionEarned: comm < 0 ? 0 : comm,
    );
    notifyListeners();
    // Persist so a restart keeps the optimistic figures until sync.
    OfflineCacheService().cacheWorkers(_workers).catchError((_) {});
  }

  /// Add new worker (returns ID on success, null on failure)
  Future<String?> addWorker(Worker worker) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final newId = await _workerService.addWorker(worker);

      _isLoading = false;
      notifyListeners();
      return newId;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  /// Update worker
  Future<bool> updateWorker(String id, Worker worker) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      await _workerService.updateWorker(id, worker);

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Delete worker
  Future<bool> deleteWorker(String id) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      await _workerService.deleteWorker(id);

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Update worker status
  Future<bool> updateWorkerStatus(String id, String status) async {
    try {
      await _workerService.updateWorkerStatus(id, status);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Refresh data
  Future<void> refresh() async {
    _initializeWorkers();
  }

  void _checkLowBalances(List<Worker> newWorkers) async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('push_notifications') ?? true;
    if (!enabled) return;

    for (var worker in newWorkers) {
      if (_previousBalances.containsKey(worker.id)) {
        final double prev = _previousBalances[worker.id]!;
        // Trigger if dropped below 500 and was previously >= 500
        if (prev >= 500 && worker.currentBalance < 500 && worker.isActive) {
          NotificationService().showNotification(
            id: worker.id.hashCode,
            title: 'Low Balance Alert',
            body:
                '${worker.name} is running low on funds (${worker.currentBalance.toStringAsFixed(0)}).',
          );
        }
      }
      _previousBalances[worker.id] = worker.currentBalance;
    }
  }
}
