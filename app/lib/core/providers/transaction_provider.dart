import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/transaction_model.dart';
import '../services/transaction_service.dart';
import '../services/offline_cache_service.dart';

class TransactionProvider with ChangeNotifier {
  final TransactionService _transactionService;

  /// Wired at app composition (main.dart) so optimistic creates/deletes can
  /// also move the worker Balance Card. Signature: (tx, +1 create | -1 reverse).
  void Function(MoneyTransaction transaction, int direction)?
      onTransactionApplied;

  TransactionProvider({TransactionService? transactionService})
      : _transactionService = transactionService ?? TransactionService();

  static const int _workerPageSize = 20;

  List<MoneyTransaction> _allTransactions = [];
  List<MoneyTransaction> _workerTransactions = [];
  bool _isLoading = false;
  String? _errorMessage;

  // Worker transactions cursor pagination state
  DocumentSnapshot<Map<String, dynamic>>? _workerLastDoc;
  bool _workerHasMore = false;
  bool _isLoadingMoreWorker = false;
  bool _workerLoadedExtraPages = false;
  StreamSubscription<List<MoneyTransaction>>? _workerSub;
  int _workerTotalCount = 0;
  String? _currentWorkerId;

  final Set<String> _pendingTxIds = {};

  bool isPending(String id) => _pendingTxIds.contains(id);

  // Today's totals
  double _todayDistributed = 0.0;
  double _todayReturned = 0.0;
  double _todayPurchased = 0.0;

  List<MoneyTransaction> get allTransactions => _allTransactions;
  List<MoneyTransaction> get workerTransactions => _workerTransactions;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  bool get hasMoreWorkerTransactions => _workerHasMore;
  bool get isLoadingMoreWorkerTransactions => _isLoadingMoreWorker;
  int get workerTransactionTotalCount => _workerTotalCount;

  double get todayDistributed => _todayDistributed;
  double get todayReturned => _todayReturned;
  double get todayPurchased => _todayPurchased;
  double get todayNet => _todayDistributed - _todayReturned - _todayPurchased;

  /// Load worker transactions - bounded live stream (first page) + cursor pages.
  /// Seeds from the local Hive cache first so cold start or offline shows
  /// data immediately instead of a blank list.
  void loadWorkerTransactions(String workerId) {
    _currentWorkerId = workerId;
    _workerSub?.cancel();
    _workerLastDoc = null;
    _workerHasMore = false;
    _workerLoadedExtraPages = false;
    _workerTotalCount = 0;

    // Seed from cache (newest first). Cache failure is non-fatal: fall
    // through to the live stream with an empty list, like before.
    try {
      final cached =
          OfflineCacheService().getCachedWorkerTransactions(workerId);
      if (cached.isNotEmpty) {
        cached.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _workerTransactions = cached;
      } else {
        _workerTransactions = [];
      }
    } catch (_) {
      _workerTransactions = [];
    }
    notifyListeners();

    try {
      _workerSub = _transactionService
          .getWorkerTransactionsStream(workerId, limit: _workerPageSize)
          .listen(
        (transactions) {
          if (_currentWorkerId != workerId) return;
          _mergeFirstPage(transactions);
          // Full first page implies more may exist - enable Load More.
          if (!_workerLoadedExtraPages) {
            _workerHasMore = transactions.length >= _workerPageSize;
          }
          notifyListeners();
          _persistWorkerCache(workerId);
        },
        onError: (error) {
          print('Error loading worker transactions: $error');
          _errorMessage = _parseError(error);
          notifyListeners();
        },
      );

      _loadWorkerCount(workerId);
    } catch (_) {
      // Firestore unreachable (e.g. offline cold start): cached data stays.
    }
  }

  /// Persist the currently accumulated worker transactions so the next cold
  /// start can seed from them. Fire-and-forget; failures are non-fatal.
  void _persistWorkerCache(String workerId) {
    OfflineCacheService()
        .cacheWorkerTransactions(workerId, _workerTransactions)
        .catchError((_) {});
  }

  /// Test seam: seed the in-memory worker transaction list directly.
  @visibleForTesting
  void debugSetWorkerTransactions(List<MoneyTransaction> transactions) {
    _workerTransactions = List.of(transactions);
  }

  /// Load a specific calendar day of a worker's transactions from the server.
  /// Replaces the live first-page stream while a date filter is active.
  Future<void> loadWorkerTransactionsForDay(
    String workerId,
    DateTime day,
  ) async {
    _currentWorkerId = workerId;
    _workerSub?.cancel();
    _workerSub = null;
    _workerTransactions = [];
    _workerLastDoc = null;
    _workerHasMore = false;
    _workerLoadedExtraPages = false;
    _workerTotalCount = 0;
    notifyListeners();

    final items = await _transactionService.getWorkerTransactionsForDay(
      workerId,
      day,
    );
    if (_currentWorkerId != workerId) return;
    _workerTransactions = items;
    _workerTotalCount = items.length;
    notifyListeners();
  }

  /// Load the next page of worker transactions from the backend cursor.
  Future<void> loadMoreWorkerTransactions(String workerId) async {
    if (_isLoadingMoreWorker || !_workerHasMore) return;
    _isLoadingMoreWorker = true;
    notifyListeners();

    // Bootstrap the cursor when the stream-only init left it unset.
    var startAfter = _workerLastDoc;
    if (startAfter == null && _workerTransactions.isNotEmpty) {
      final bootstrap = await _transactionService.getWorkerTransactionsPage(
        workerId,
        pageSize: _workerPageSize,
      );
      startAfter = bootstrap.lastDoc;
      if (startAfter == null) {
        _workerHasMore = false;
        _isLoadingMoreWorker = false;
        notifyListeners();
        return;
      }
    }

    final page = await _transactionService.getWorkerTransactionsPage(
      workerId,
      startAfter: startAfter,
      pageSize: _workerPageSize,
    );

    if (page.items.isEmpty) {
      _workerHasMore = false;
      _isLoadingMoreWorker = false;
      notifyListeners();
      return;
    }

    final knownIds = _workerTransactions.map((t) => t.id).toSet();
    _workerTransactions = [
      ..._workerTransactions,
      ...page.items.where((t) => !knownIds.contains(t.id)),
    ];
    _workerLastDoc = page.lastDoc;
    _workerHasMore = page.hasMore;
    if (_currentWorkerId != null) {
      _persistWorkerCache(_currentWorkerId!);
    }
    _workerLoadedExtraPages = true;
    _isLoadingMoreWorker = false;
    notifyListeners();
  }

  void _mergeFirstPage(List<MoneyTransaction> freshHead) {
    final freshIds = freshHead.map((t) => t.id).toSet();
    final stillPending = _workerTransactions
        .where((t) => _pendingTxIds.contains(t.id) && !freshIds.contains(t.id))
        .toList();
    for (final id in freshIds) {
      _pendingTxIds.remove(id);
    }
    if (!_workerLoadedExtraPages) {
      if (stillPending.isEmpty) {
        _workerTransactions = freshHead;
        return;
      }
      final merged = [...stillPending, ...freshHead]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _workerTransactions = merged;
      return;
    }
    final tailIds = {...freshHead.map((t) => t.id), ...stillPending.map((t) => t.id)};
    final tail = _workerTransactions.where((t) => !tailIds.contains(t.id)).toList();
    if (stillPending.isEmpty) {
      _workerTransactions = [...freshHead, ...tail];
    } else {
      final merged = [...stillPending, ...freshHead]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _workerTransactions = [...merged, ...tail];
    }
  }

  Future<void> _loadWorkerCount(String workerId) async {
    final count = await _transactionService.getWorkerTransactionCount(workerId);
    _workerTotalCount = count;
    notifyListeners();
  }

  /// Load all transactions - seed from cache instantly, then refresh live.
  void loadAllTransactions() {
    final cached = OfflineCacheService().getCachedTransactions();
    if (cached != null) {
      _allTransactions = cached;
      notifyListeners();
    }

    _transactionService.getAllTransactionsStream().listen(
      (transactions) {
        final freshIds = transactions.map((t) => t.id).toSet();
        final stillPending = _allTransactions
            .where((t) => _pendingTxIds.contains(t.id) && !freshIds.contains(t.id))
            .toList();
        for (final id in freshIds) {
          _pendingTxIds.remove(id);
        }
        if (stillPending.isEmpty) {
          _allTransactions = transactions;
        } else {
          _allTransactions = [...stillPending, ...transactions]
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        }
        OfflineCacheService()
            .cacheTransactions(_allTransactions)
            .catchError((_) {});
        notifyListeners();
      },
      onError: (error) {
        print('Error loading all transactions: $error');
        _errorMessage = _parseError(error);
        notifyListeners();
      },
    );
  }

  /// Get all transactions as a Future (for export)
  Future<List<MoneyTransaction>> getAllTransactionsFuture() async {
    return await _transactionService.getAllTransactions();
  }

  /// Add distribution transaction
  Future<bool> distributeMoneyToWorker({
    required String workerId,
    required String workerName,
    required double amount,
    required String createdBy,
    String? notes,
    String? receiptUrl,
    String? localReceiptPath,
  }) async {
    if (amount <= 0) {
      _errorMessage = 'Amount must be greater than 0';
      notifyListeners();
      return false;
    }

    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final transaction = MoneyTransaction(
        id: '',
        workerId: workerId,
        workerName: workerName,
        type: 'distribution',
        amount: amount,
        notes: notes,
        receiptUrl: receiptUrl,
        createdAt: DateTime.now(),
        createdBy: createdBy,
        approved: false,
      );

      final docId = await _transactionService.addTransaction(transaction,
          localReceiptPath: localReceiptPath);
      if (docId != null) {
        _optimisticInsert(MoneyTransaction(
          id: docId,
          workerId: transaction.workerId,
          workerName: transaction.workerName,
          type: transaction.type,
          amount: transaction.amount,
          notes: transaction.notes,
          receiptUrl: transaction.receiptUrl,
          createdAt: transaction.createdAt,
          createdBy: transaction.createdBy,
          approved: transaction.approved,
          coffeeType: transaction.coffeeType,
          coffeeWeight: transaction.coffeeWeight,
          pricePerKg: transaction.pricePerKg,
          commissionAmount: transaction.commissionAmount,
          fromWorkerId: transaction.fromWorkerId,
          toWorkerId: transaction.toWorkerId,
          fromWorkerName: transaction.fromWorkerName,
          toWorkerName: transaction.toWorkerName,
          transferId: transaction.transferId,
          transferRole: transaction.transferRole,
        ));
      }

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

  /// Add return transaction
  Future<bool> returnMoneyFromWorker({
    required String workerId,
    required String workerName,
    required double amount,
    required String createdBy,
    String? notes,
    String? receiptUrl,
    String? localReceiptPath,
  }) async {
    if (amount <= 0) {
      _errorMessage = 'Amount must be greater than 0';
      notifyListeners();
      return false;
    }

    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final transaction = MoneyTransaction(
        id: '',
        workerId: workerId,
        workerName: workerName,
        type: 'return',
        amount: amount,
        notes: notes,
        receiptUrl: receiptUrl,
        createdAt: DateTime.now(),
        createdBy: createdBy,
        approved: false,
      );

      final docId2 = await _transactionService.addTransaction(transaction,
          localReceiptPath: localReceiptPath);
      if (docId2 != null) {
        _optimisticInsert(MoneyTransaction(
          id: docId2,
          workerId: transaction.workerId,
          workerName: transaction.workerName,
          type: transaction.type,
          amount: transaction.amount,
          notes: transaction.notes,
          receiptUrl: transaction.receiptUrl,
          createdAt: transaction.createdAt,
          createdBy: transaction.createdBy,
          approved: transaction.approved,
          coffeeType: transaction.coffeeType,
          coffeeWeight: transaction.coffeeWeight,
          pricePerKg: transaction.pricePerKg,
          commissionAmount: transaction.commissionAmount,
        ));
      }

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

  /// Add purchase transaction
  Future<bool> recordCoffeePurchase({
    required String workerId,
    required String workerName,
    required double amount,
    required String createdBy,
    String? notes,
    String? receiptUrl,
    String? localReceiptPath,
    String? coffeeType,
    double? weight,
    double? pricePerKg,
    double? commission,
    double? forgivenAmount,
  }) async {
    if (amount <= 0) {
      _errorMessage = 'Amount must be greater than 0';
      notifyListeners();
      return false;
    }

    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final transaction = MoneyTransaction(
        id: '',
        workerId: workerId,
        workerName: workerName,
        type: 'purchase',
        amount: amount,
        notes: notes,
        receiptUrl: receiptUrl,
        createdAt: DateTime.now(),
        createdBy: createdBy,
        approved: false,
        coffeeType: coffeeType,
        coffeeWeight: weight,
        pricePerKg: pricePerKg,
        commissionAmount: commission,
        forgivenAmount: forgivenAmount,
        isDebt: (forgivenAmount ?? 0) > 0,
      );

      final docId3 = await _transactionService.addTransaction(transaction,
          localReceiptPath: localReceiptPath);
      if (docId3 != null) {
        _optimisticInsert(MoneyTransaction(
          id: docId3,
          workerId: transaction.workerId,
          workerName: transaction.workerName,
          type: transaction.type,
          amount: transaction.amount,
          notes: transaction.notes,
          receiptUrl: transaction.receiptUrl,
          createdAt: transaction.createdAt,
          createdBy: transaction.createdBy,
          approved: transaction.approved,
          coffeeType: transaction.coffeeType,
          coffeeWeight: transaction.coffeeWeight,
          pricePerKg: transaction.pricePerKg,
          commissionAmount: transaction.commissionAmount,
          forgivenAmount: transaction.forgivenAmount,
          isDebt: transaction.isDebt,
        ));
      }

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

  /// Record a collector-to-collector transfer
  Future<bool> transferFromCollectorToCollector({
    required String fromWorkerId,
    required String fromWorkerName,
    required String toWorkerId,
    required String toWorkerName,
    required double amount,
    required String createdBy,
    String? notes,
  }) async {
    if (amount <= 0) {
      _errorMessage = 'Amount must be greater than 0';
      notifyListeners();
      return false;
    }

    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final transferId = await _transactionService.addTransfer(
        fromWorkerId: fromWorkerId,
        fromWorkerName: fromWorkerName,
        toWorkerId: toWorkerId,
        toWorkerName: toWorkerName,
        amount: amount,
        createdBy: createdBy,
        notes: notes,
      );

      if (transferId != null) {
        final now = DateTime.now();
        final senderTx = MoneyTransaction(
          id: transferId,
          workerId: fromWorkerId,
          workerName: fromWorkerName,
          type: 'transfer',
          amount: amount,
          notes: notes,
          createdAt: now,
          createdBy: createdBy,
          approved: false,
          fromWorkerId: fromWorkerId,
          toWorkerId: toWorkerId,
          fromWorkerName: fromWorkerName,
          toWorkerName: toWorkerName,
          transferId: transferId,
          transferRole: 'sender',
        );
        final receiverTx = MoneyTransaction(
          id: '${transferId}_r',
          workerId: toWorkerId,
          workerName: toWorkerName,
          type: 'transfer',
          amount: amount,
          notes: notes,
          createdAt: now,
          createdBy: createdBy,
          approved: false,
          fromWorkerId: fromWorkerId,
          toWorkerId: toWorkerId,
          fromWorkerName: fromWorkerName,
          toWorkerName: toWorkerName,
          transferId: transferId,
          transferRole: 'receiver',
        );
        _optimisticInsert(senderTx);
        _optimisticInsert(receiverTx);
      }

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

  /// Pending offline deltas for today's activity: queued creates that the
  /// server aggregates cannot see yet (write not committed). Mirrors the
  /// income/expense `_refreshTotals` reconcile so Cash In / Cash Out never
  /// revert while ops are pending.
  (double, double, double) _pendingTodayDeltas() {
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    double distributed = 0;
    double returned = 0;
    double purchased = 0;
    for (final op in OfflineCacheService().getPendingOperations()) {
      final type = op['type'] as String? ?? '';
      if (type != 'createTransaction') continue;
      if (op['workerId'] != null && op['workerId'] == '') continue;
      final createdAtMs = op['createdAt'] as int?;
      final isToday = createdAtMs != null &&
          DateTime.fromMillisecondsSinceEpoch(createdAtMs).isAfter(dayStart);
      if (!isToday) continue;
      final amount = ((op['amount'] as num?) ?? 0).toDouble();
      switch ((op['transactionType'] as String? ?? '').toLowerCase()) {
        case 'distribution':
          distributed += amount;
          break;
        case 'return':
          returned += amount;
          break;
        case 'purchase':
          purchased += amount;
          break;
      }
    }
    return (distributed, returned, purchased);
  }

  /// Load today's totals
  Future<void> loadTodayTotals() async {
    try {
      final cached = OfflineCacheService().getCachedTodayTotals();
      if (cached != null) {
        _todayDistributed = cached['distributed'] ?? 0.0;
        _todayReturned = cached['returned'] ?? 0.0;
        _todayPurchased = cached['purchased'] ?? 0.0;
        notifyListeners();
      }
    } catch (_) {
      // Cache read failure is non-fatal: fall through to network path.
    }

    try {
      final totals = await _transactionService.getTodayTotals();
      // Reconcile with still-pending offline creates so a successful-but-
      // stale aggregate can't drag today's activity back down.
      final (pendingDist, pendingRet, pendingPurch) = _pendingTodayDeltas();
      _todayDistributed = (totals['distributed'] ?? 0.0) + pendingDist;
      _todayReturned = (totals['returned'] ?? 0.0) + pendingRet;
      _todayPurchased = (totals['purchased'] ?? 0.0) + pendingPurch;
      notifyListeners();
      OfflineCacheService().cacheTodayTotals({
        'distributed': _todayDistributed,
        'returned': _todayReturned,
        'purchased': _todayPurchased,
      }).catchError((_) {});
    } catch (e) {
      print('Error loading today totals: $e');
    }
  }

  /// Approve a single transaction entry
  Future<bool> approveTransaction(String transactionId) async {
    try {
      await _transactionService.approveTransaction(transactionId);
      _flipApproved((t) => t.id == transactionId);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Batch approve all pending transactions for a worker
  Future<bool> approveAllForWorker(String workerId) async {
    try {
      await _transactionService.approveAllForWorker(workerId);
      _flipApproved((t) => t.workerId == workerId && !t.approved);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Approve both sides of a transfer
  Future<bool> approveTransfer(String transferId) async {
    try {
      await _transactionService.approveTransfer(transferId);
      _flipApproved((t) => t.transferId == transferId);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  void _optimisticInsert(MoneyTransaction tx) {
    if (!_allTransactions.any((t) => t.id == tx.id)) {
      _allTransactions = [tx, ..._allTransactions];
    }
    if (!_workerTransactions.any((t) => t.id == tx.id)) {
      _workerTransactions = [tx, ..._workerTransactions];
    }
    _pendingTxIds.add(tx.id);
    if (tx.isTransfer && tx.transferId != null) {
      _pendingTxIds.add(tx.transferId!);
      _pendingTxIds.add('${tx.transferId}_r');
    }
    onTransactionApplied?.call(tx, 1);
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    if (tx.createdAt.isAfter(dayStart)) {
      switch (tx.type.toLowerCase()) {
        case 'distribution':
          _todayDistributed += tx.amount;
          break;
        case 'return':
          _todayReturned += tx.amount;
          break;
        case 'purchase':
          _todayPurchased += tx.amount;
          break;
      }
      notifyListeners();
    }
    notifyListeners();
  }

  /// Optimistically mark matching in-memory entries as approved so the UI
  /// reflects the confirmation immediately. The live stream reconciles once
  /// back online.
  void _flipApproved(bool Function(MoneyTransaction) matches) {
    var changed = false;
    final updated = <MoneyTransaction>[];
    for (final t in _workerTransactions) {
      if (matches(t) && !t.approved) {
        updated.add(t.copyWith(approved: true));
        changed = true;
      } else {
        updated.add(t);
      }
    }
    _workerTransactions = updated;
    if (changed) notifyListeners();
  }

  /// Optimistically replace a matching in-memory entry so the UI reflects
  /// the edit immediately. The live stream reconciles once back online.
  void _optimisticReplace(MoneyTransaction tx) {
    var changed = false;
    if (_allTransactions.any((t) => t.id == tx.id)) {
      _allTransactions = [
        for (final t in _allTransactions)
          if (t.id == tx.id) tx else t,
      ];
      changed = true;
    }
    if (_workerTransactions.any((t) => t.id == tx.id)) {
      _workerTransactions = [
        for (final t in _workerTransactions)
          if (t.id == tx.id) tx else t,
      ];
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Optimistically remove matching in-memory entries so the UI reflects the
  /// delete immediately. The live stream reconciles once back online.
  void _optimisticRemove(bool Function(MoneyTransaction) matches) {
    final toRemove = _allTransactions.where(matches).toList();
    for (final t in toRemove) {
      _pendingTxIds.remove(t.id);
      if (t.transferId != null) _pendingTxIds.remove(t.transferId!);
    }
    final newAll = _allTransactions.where((t) => !matches(t)).toList();
    final newWorker = _workerTransactions.where((t) => !matches(t)).toList();
    final changed = newAll.length != _allTransactions.length ||
        newWorker.length != _workerTransactions.length;
    _allTransactions = newAll;
    _workerTransactions = newWorker;
    if (changed) notifyListeners();
  }

  /// Edit an existing transaction (reverses old balance effect, applies new)
  /// [overrideReason] is required when the transaction is past the
  /// immutability window.
  Future<bool> updateTransaction(
    MoneyTransaction transaction, {
    String? overrideReason,
    String? localReceiptPath,
  }) async {
    final allSnap = _allTransactions;
    final workerSnap = _workerTransactions;
    final oldTx = _workerTransactions.firstWhere(
      (t) => t.id == transaction.id,
      orElse: () => _allTransactions.firstWhere(
        (t) => t.id == transaction.id,
        orElse: () => transaction,
      ),
    );
    try {
      // Reverse the OLD effect, then apply the NEW one.
      onTransactionApplied?.call(oldTx, -1);
      onTransactionApplied?.call(transaction, 1);
      _optimisticReplace(transaction);
      await _transactionService.updateTransaction(transaction,
          overrideReason: overrideReason, localReceiptPath: localReceiptPath);
      return true;
    } catch (e) {
      onTransactionApplied?.call(transaction, -1);
      onTransactionApplied?.call(oldTx, 1);
      _allTransactions = allSnap;
      _workerTransactions = workerSnap;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Delete a transaction (reverses its balance effect)
  /// [overrideReason] is required when the transaction is past the
  /// immutability window.
  Future<bool> deleteTransaction(
    String transactionId, {
    String? overrideReason,
  }) async {
    final allSnap = _allTransactions;
    final workerSnap = _workerTransactions;
    final removedTx = () {
      try {
        return _allTransactions.firstWhere((t) => t.id == transactionId);
      } catch (_) {
        return null;
      }
    }();
    try {
      if (removedTx != null) onTransactionApplied?.call(removedTx, -1);
      _optimisticRemove((t) => t.id == transactionId);
      await _transactionService.deleteTransaction(transactionId,
          overrideReason: overrideReason);
      return true;
    } catch (e) {
      if (removedTx != null) onTransactionApplied?.call(removedTx, 1);
      _allTransactions = allSnap;
      _workerTransactions = workerSnap;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Delete both records of a transfer
  /// [overrideReason] is required when the transfer is past the
  /// immutability window.
  Future<bool> deleteTransfer(
    String transferId, {
    String? overrideReason,
  }) async {
    final allSnap = _allTransactions;
    final workerSnap = _workerTransactions;
    final removedLegs =
        _allTransactions.where((t) => t.transferId == transferId).toList();
    try {
      for (final leg in removedLegs) {
        onTransactionApplied?.call(leg, -1);
      }
      _optimisticRemove((t) =>
          t.transferId == transferId ||
          t.id == transferId ||
          t.id == '${transferId}_r');
      await _transactionService.deleteTransfer(transferId,
          overrideReason: overrideReason);
      return true;
    } catch (e) {
      for (final leg in removedLegs.reversed) {
        onTransactionApplied?.call(leg, 1);
      }
      _allTransactions = allSnap;
      _workerTransactions = workerSnap;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Clear error
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Parse error message
  String _parseError(dynamic error) {
    String errorStr = error.toString();
    if (errorStr.contains('permission-denied') ||
        errorStr.contains('PERMISSION_DENIED')) {
      return 'Database access denied. Please check permissions.';
    } else if (errorStr.contains('unavailable')) {
      return 'Database unavailable. Check your connection.';
    }
    return 'Failed to load transactions.';
  }

  /// Upload receipt
  Future<String?> uploadReceipt(String filePath) async {
    try {
      _isLoading = true;
      notifyListeners();
      final url = await _transactionService.uploadReceipt(filePath);
      _isLoading = false;
      notifyListeners();
      return url;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }
}
