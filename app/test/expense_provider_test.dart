import 'package:flutter_test/flutter_test.dart';
import 'package:cofiz/core/models/expense_record_model.dart';
import 'package:cofiz/core/providers/expense_provider.dart';

void main() {
  ExpenseRecord rec(double amount, DateTime createdAt) {
    return ExpenseRecord(
      id: '',
      amount: amount,
      expenseCategory: 'Rent',
      createdAt: createdAt,
      createdBy: 'u',
      createdByName: 'Admin',
    );
  }

  group('ExpenseProvider statics', () {
    test('sum totals amounts', () {
      final records = [
        rec(100, DateTime(2026, 8, 1)),
        rec(50, DateTime(2026, 8, 2)),
      ];
      expect(ExpenseProvider.sum(records), 150.0);
    });

    test('sumToday only counts today', () {
      final now = DateTime(2026, 8, 14, 12, 0);
      final records = [
        rec(100, DateTime(2026, 8, 14, 8, 0)),
        rec(40, DateTime(2026, 8, 13, 23, 0)),
      ];
      expect(ExpenseProvider.sumToday(records, now: now), 100.0);
    });
  });
}
