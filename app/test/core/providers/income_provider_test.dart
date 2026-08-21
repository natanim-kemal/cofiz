import 'package:flutter_test/flutter_test.dart';
import 'package:cofiz/core/models/income_record_model.dart';
import 'package:cofiz/core/providers/income_provider.dart';

void main() {
  IncomeRecord rec(IncomeKind kind, double amount, DateTime createdAt) {
    return IncomeRecord(
      id: '',
      kind: kind,
      amount: amount,
      createdAt: createdAt,
      createdBy: 'u',
      createdByName: 'Admin',
    );
  }

  group('IncomeProvider statics', () {
    test('sum totals amounts', () {
      final records = [
        rec(IncomeKind.investment, 100, DateTime(2026, 8, 1)),
        rec(IncomeKind.sale, 50, DateTime(2026, 8, 2)),
      ];
      expect(IncomeProvider.sum(records), 150.0);
    });

    test('sumToday only counts today', () {
      final now = DateTime(2026, 8, 14, 12, 0);
      final records = [
        rec(IncomeKind.investment, 100, DateTime(2026, 8, 14, 8, 0)),
        rec(IncomeKind.investment, 40, DateTime(2026, 8, 13, 23, 0)),
        rec(IncomeKind.sale, 60, DateTime(2026, 8, 14, 23, 30)),
      ];
      expect(IncomeProvider.sumToday(records, now: now), 160.0);
    });
  });
}
