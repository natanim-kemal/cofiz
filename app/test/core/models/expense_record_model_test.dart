import 'package:flutter_test/flutter_test.dart';
import 'package:cofiz/core/models/expense_record_model.dart';

void main() {
  group('ExpenseRecord', () {
    final base = ExpenseRecord(
      id: 'e1',
      amount: 1200.0,
      expenseCategory: 'Rent',
      createdAt: DateTime(2026, 8, 14, 9, 0),
      createdBy: 'u1',
      createdByName: 'Admin',
    );

    test('fromFirestore/toFirestore round trip', () {
      final parsed = ExpenseRecord.fromFirestore(base.toFirestore(), 'e1');
      expect(parsed.id, 'e1');
      expect(parsed.amount, 1200.0);
      expect(parsed.expenseCategory, 'Rent');
      expect(parsed.description, isNull);
      expect(parsed.createdAt, DateTime(2026, 8, 14, 9, 0));
    });

    test('defaults category when missing', () {
      final map = base.copyWith(expenseCategory: 'x').toFirestore()
        ..remove('expenseCategory');
      final parsed = ExpenseRecord.fromFirestore(map, 'e2');
      expect(parsed.expenseCategory, 'Other');
    });

    test('toJson/fromJson round trip', () {
      final parsed = ExpenseRecord.fromJson(base.toJson());
      expect(parsed.id, 'e1');
      expect(parsed.amount, 1200.0);
      expect(parsed.createdByName, 'Admin');
    });
  });
}
