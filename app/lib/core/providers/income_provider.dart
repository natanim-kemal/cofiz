import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/income_record_model.dart';
import '../services/income_service.dart';

class IncomeProvider extends ChangeNotifier {
  IncomeProvider({IncomeService? service})
      : _service = service ?? IncomeService();

  final IncomeService _service;

  List<IncomeRecord> _records = [];
  bool _isLoading = false;
  String? _errorMessage;
  StreamSubscription<List<IncomeRecord>>? _subscription;

  List<IncomeRecord> get records => List.unmodifiable(_records);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  List<IncomeRecord> get investments =>
      _records.where((r) => r.kind == IncomeKind.investment).toList();

  List<IncomeRecord> get sales =>
      _records.where((r) => r.kind == IncomeKind.sale).toList();

  double get totalIncome => sum(_records);
  double get totalInvestments => sum(investments);
  double get totalSales => sum(sales);

  double get todayInvestmentIncome => sumToday(investments);
  double get todayManualSales => sumToday(sales);
  double get todayIncome => todayInvestmentIncome + todayManualSales;

  void initialize() {
    _subscription ??= _service.getIncomeStream().listen(
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

  Future<bool> addIncome(IncomeRecord record) async {
    final id = await _service.addIncome(record);
    if (id == null) {
      _errorMessage = 'Failed to record income';
      notifyListeners();
      return false;
    }
    return true;
  }

  Future<bool> updateIncome(IncomeRecord record) async {
    final success = await _service.updateIncome(record);
    if (!success) {
      _errorMessage = 'Failed to update income';
      notifyListeners();
      return false;
    }
    return true;
  }

  Future<bool> deleteIncome(String id) async {
    final success = await _service.deleteIncome(id);
    if (!success) {
      _errorMessage = 'Failed to delete income';
      notifyListeners();
      return false;
    }
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
