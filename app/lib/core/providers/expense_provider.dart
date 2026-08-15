import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/expense_record_model.dart';
import '../services/expense_service.dart';

class ExpenseProvider extends ChangeNotifier {
  ExpenseProvider({ExpenseService? service})
      : _service = service ?? ExpenseService();

  final ExpenseService _service;

  List<ExpenseRecord> _records = [];
  bool _isLoading = false;
  String? _errorMessage;
  StreamSubscription<List<ExpenseRecord>>? _subscription;

  List<ExpenseRecord> get records => List.unmodifiable(_records);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  double get totalExpenses => sum(_records);
  double get todayExpenses => sumToday(_records);

  void initialize() {
    _subscription ??= _service.getExpensesStream().listen(
      (records) {
        _records = records;
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
  }

  Future<bool> addExpense(ExpenseRecord record) async {
    final id = await _service.addExpense(record);
    if (id == null) {
      _errorMessage = 'Failed to record expense';
      notifyListeners();
      return false;
    }
    return true;
  }

  Future<bool> updateExpense(ExpenseRecord record) async {
    final success = await _service.updateExpense(record);
    if (!success) {
      _errorMessage = 'Failed to update expense';
      notifyListeners();
      return false;
    }
    return true;
  }

  Future<bool> deleteExpense(String id) async {
    final success = await _service.deleteExpense(id);
    if (!success) {
      _errorMessage = 'Failed to delete expense';
      notifyListeners();
      return false;
    }
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
