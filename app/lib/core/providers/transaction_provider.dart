import 'package:flutter/foundation.dart';
import '../models/transaction_model.dart';
import '../services/transaction_service.dart';

class TransactionProvider with ChangeNotifier {
  final TransactionService _transactionService = TransactionService();

  List<MoneyTransaction> _allTransactions = [];
  List<MoneyTransaction> _workerTransactions = [];
  bool _isLoading = false;
  String? _errorMessage;

  // Today's totals
  double _todayDistributed = 0.0;
  double _todayReturned = 0.0;
  double _todayPurchased = 0.0;

  List<MoneyTransaction> get allTransactions => _allTransactions;
  List<MoneyTransaction> get workerTransactions => _workerTransactions;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  double get todayDistributed => _todayDistributed;
  double get todayReturned => _todayReturned;
  double get todayPurchased => _todayPurchased;
  double get todayNet => _todayDistributed - _todayReturned - _todayPurchased;

  /// Load worker transactions
  void loadWorkerTransactions(String workerId) {
    _transactionService.getWorkerTransactionsStream(workerId).listen(
      (transactions) {
        _workerTransactions = transactions;
        notifyListeners();
      },
      onError: (error) {
        print('Error loading worker transactions: $error');
        _errorMessage = _parseError(error);
        notifyListeners();
      },
    );
  }

  /// Load all transactions
  void loadAllTransactions() {
    _transactionService.getAllTransactionsStream().listen(
      (transactions) {
        _allTransactions = transactions;
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

      await _transactionService.addTransaction(transaction);

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

      await _transactionService.addTransaction(transaction);

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

      await _transactionService.addTransaction(transaction);

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
      final totals = await _transactionService.getTodayTotals();
      _todayDistributed = totals['distributed'] ?? 0.0;
      _todayReturned = totals['returned'] ?? 0.0;
      _todayPurchased = totals['purchased'] ?? 0.0;
      notifyListeners();
    } catch (e) {
      print('Error loading today totals: $e');
    }
  }

  /// Approve a single transaction entry
  Future<bool> approveTransaction(String transactionId) async {
    try {
      await _transactionService.approveTransaction(transactionId);
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
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Edit an existing transaction (reverses old balance effect, applies new)
  Future<bool> updateTransaction(MoneyTransaction transaction) async {
    try {
      await _transactionService.updateTransaction(transaction);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Delete a transaction (reverses its balance effect)
  Future<bool> deleteTransaction(String transactionId) async {
    try {
      await _transactionService.deleteTransaction(transactionId);
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
