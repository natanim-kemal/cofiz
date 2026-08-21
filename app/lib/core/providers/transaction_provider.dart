import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/transaction_model.dart';
import '../services/transaction_service.dart';
import '../services/offline_cache_service.dart';

class TransactionProvider with ChangeNotifier {
  final TransactionService _transactionService;

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

  /// Load worker transactions - bounded live stream (first page) + cursor pages
  void loadWorkerTransactions(String workerId) {
    _currentWorkerId = workerId;
    _workerSub?.cancel();
    _workerTransactions = [];
    _workerLastDoc = null;
    _workerHasMore = false;
    _workerLoadedExtraPages = false;
    _workerTotalCount = 0;
    notifyListeners();

    _workerSub = _transactionService
        .getWorkerTransactionsStream(workerId, limit: _workerPageSize)
        .listen(
      (transactions) {
        _mergeFirstPage(transactions);
        notifyListeners();
      },
      onError: (error) {
        print('Error loading worker transactions: $error');
        _errorMessage = _parseError(error);
        notifyListeners();
      },
    );

    _loadWorkerCount(workerId);
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

    final page = await _transactionService.getWorkerTransactionsPage(
      workerId,
      startAfter: _workerLastDoc,
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
    _workerLoadedExtraPages = true;
    _isLoadingMoreWorker = false;
    notifyListeners();
  }

  /// Merge the live first-page stream into the accumulated list without
  /// dropping previously loaded pages. Newest items from the stream replace
  /// the head; older loaded pages are preserved.
  void _mergeFirstPage(List<MoneyTransaction> freshHead) {
    if (!_workerLoadedExtraPages) {
      // No pages loaded yet - take the stream head directly.
      _workerTransactions = freshHead;
      return;
    }
    // Keep everything beyond the first page; the stream head is the newest.
    final tail = _workerTransactions.length > freshHead.length
        ? _workerTransactions.sublist(freshHead.length)
        : <MoneyTransaction>[];
    _workerTransactions = [...freshHead, ...tail];
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
        _allTransactions = transactions;
        OfflineCacheService()
            .cacheTransactions(transactions)
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

      final docId = await _transactionService.addTransaction(transaction);
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

      final docId2 = await _transactionService.addTransaction(transaction);
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
    String? coffeeType,
    double? weight,
    double? pricePerKg,
    double? commission,
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
      );

      final docId3 = await _transactionService.addTransaction(transaction);
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
      _todayDistributed = totals['distributed'] ?? 0.0;
      _todayReturned = totals['returned'] ?? 0.0;
      _todayPurchased = totals['purchased'] ?? 0.0;
      notifyListeners();
      OfflineCacheService().cacheTodayTotals(totals).catchError((_) {});
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
    // Insert at front of allTransactions (newest first)
    if (!_allTransactions.any((t) => t.id == tx.id)) {
      _allTransactions = [tx, ..._allTransactions];
    }
    // Also insert into workerTransactions if it matches the currently viewed worker
    if (_currentWorkerId != null && tx.workerId == _currentWorkerId) {
      if (!_workerTransactions.any((t) => t.id == tx.id)) {
        _workerTransactions = [tx, ..._workerTransactions];
      }
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

  /// Edit an existing transaction (reverses old balance effect, applies new)
  /// [overrideReason] is required when the transaction is past the
  /// immutability window.
  Future<bool> updateTransaction(
    MoneyTransaction transaction, {
    String? overrideReason,
  }) async {
    try {
      await _transactionService.updateTransaction(transaction,
          overrideReason: overrideReason);
      return true;
    } catch (e) {
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
    try {
      await _transactionService.deleteTransaction(transactionId,
          overrideReason: overrideReason);
      return true;
    } catch (e) {
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
    try {
      await _transactionService.deleteTransfer(transferId,
          overrideReason: overrideReason);
      return true;
    } catch (e) {
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
