import 'package:flutter_test/flutter_test.dart';
import 'package:cofiz/core/models/transaction_model.dart';
import 'package:cofiz/core/utils/transaction_balance.dart';

MoneyTransaction purchase({double amount = 1000, double? forgiven, bool isDebt = false}) {
  return MoneyTransaction(
    id: 'p1',
    workerId: 'w1',
    workerName: 'Alice',
    type: 'purchase',
    amount: amount,
    createdAt: DateTime(2026, 8, 29),
    createdBy: 'u1',
    forgivenAmount: forgiven,
    isDebt: isDebt,
  );
}

void main() {
  test('purchase without debt uses full amount key', () {
    final u = transactionBalanceUpdates(purchase(amount: 1000), 1);
    expect(u.containsKey('currentBalance'), isTrue);
    expect(u.containsKey('totalCoffeePurchased'), isTrue);
  });

  test('purchase with forgiven subtracts only covered portion key present', () {
    final u = transactionBalanceUpdates(purchase(amount: 1000, forgiven: 600, isDebt: true), 1);
    expect(u.containsKey('currentBalance'), isTrue);
  });
}
