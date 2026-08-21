import 'package:flutter_test/flutter_test.dart';
import 'package:cofiz/core/models/transaction_model.dart';

MoneyTransaction base({String type = 'distribution', bool approved = true}) {
  return MoneyTransaction(
    id: 'id1',
    workerId: 'w1',
    workerName: 'A',
    type: type,
    amount: 100,
    createdAt: DateTime(2026, 8, 15),
    createdBy: 'admin',
    approved: approved,
  );
}

void main() {
  test('fromFirestore reads transfer fields', () {
    final t = MoneyTransaction.fromFirestore({
      'workerId': 'w2',
      'workerName': 'B',
      'type': 'transfer',
      'amount': 50.0,
      'createdAt': DateTime(2026, 8, 15).millisecondsSinceEpoch,
      'createdBy': 'admin',
      'fromWorkerId': 'w1',
      'toWorkerId': 'w2',
      'transferId': 't-1',
      'transferRole': 'receiver',
    }, 'id2');
    expect(t.fromWorkerId, 'w1');
    expect(t.toWorkerId, 'w2');
    expect(t.transferId, 't-1');
    expect(t.transferRole, 'receiver');
    expect(t.isTransfer, isTrue);
    expect(t.isTransferReceiver, isTrue);
    expect(t.isTransferSender, isFalse);
  });

  test('toFirestore round-trips transfer fields', () {
    final t = MoneyTransaction(
      id: 'id1',
      workerId: 'w1',
      workerName: 'A',
      type: 'transfer',
      amount: 50,
      createdAt: DateTime(2026, 8, 15),
      createdBy: 'admin',
      fromWorkerId: 'w1',
      toWorkerId: 'w2',
      transferId: 't-1',
      transferRole: 'sender',
    );
    final map = t.toFirestore();
    expect(map['fromWorkerId'], 'w1');
    expect(map['toWorkerId'], 'w2');
    expect(map['transferId'], 't-1');
    expect(map['transferRole'], 'sender');
  });

  test('non-transfer helpers are false', () {
    expect(base().isTransfer, isFalse);
    expect(base().isTransferSender, isFalse);
    expect(base().isTransferReceiver, isFalse);
  });

  test('copyWith overrides approved', () {
    final t = base(approved: false);
    final updated = t.copyWith(approved: true);
    expect(updated.approved, isTrue);
    expect(updated.id, t.id);
    expect(updated.amount, t.amount);
  });
}
