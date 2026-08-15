import 'package:flutter_test/flutter_test.dart';
import 'package:cofiz/core/models/income_record_model.dart';

void main() {
  group('IncomeKind', () {
    test('name/fromName round trip', () {
      expect(IncomeKind.investment.name, 'investment');
      expect(IncomeKind.sale.name, 'sale');
      expect(IncomeKind.fromName('sale'), IncomeKind.sale);
      expect(IncomeKind.fromName('investment'), IncomeKind.investment);
      expect(IncomeKind.fromName(null), IncomeKind.investment);
      expect(IncomeKind.fromName('unknown'), IncomeKind.investment);
    });
  });

  group('IncomeRecord', () {
    final base = IncomeRecord(
      id: 'r1',
      kind: IncomeKind.investment,
      amount: 500.0,
      createdAt: DateTime(2026, 8, 14, 10, 30),
      createdBy: 'u1',
      createdByName: 'Admin',
      viewerId: 'v1',
      viewerName: 'Alem',
    );

    test('fromFirestore/toFirestore round trip (investment)', () {
      final map = base.toFirestore();
      final parsed = IncomeRecord.fromFirestore(map, 'r1');
      expect(parsed.id, 'r1');
      expect(parsed.kind, IncomeKind.investment);
      expect(parsed.amount, 500.0);
      expect(parsed.viewerId, 'v1');
      expect(parsed.viewerName, 'Alem');
      expect(parsed.saleCategory, isNull);
      expect(parsed.createdAt, DateTime(2026, 8, 14, 10, 30));
    });

    test('fromFirestore/toFirestore round trip (sale)', () {
      final sale = IncomeRecord(
        id: 'r2',
        kind: IncomeKind.sale,
        amount: 500.0,
        createdAt: DateTime(2026, 8, 14, 10, 30),
        createdBy: 'u1',
        createdByName: 'Admin',
        saleCategory: 'Coffee Beans',
      );
      final parsed = IncomeRecord.fromFirestore(sale.toFirestore(), 'r2');
      expect(parsed.kind, IncomeKind.sale);
      expect(parsed.saleCategory, 'Coffee Beans');
      expect(parsed.viewerId, isNull);
    });

    test('toJson/fromJson round trip', () {
      final parsed = IncomeRecord.fromJson(base.toJson());
      expect(parsed.id, 'r1');
      expect(parsed.kind, IncomeKind.investment);
      expect(parsed.amount, 500.0);
      expect(parsed.viewerName, 'Alem');
    });
  });
}
