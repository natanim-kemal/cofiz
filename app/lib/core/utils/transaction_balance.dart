import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/transaction_model.dart';

/// Shared with TransactionService and OfflineSyncService — keep in sync.

class TransactionLockedException implements Exception {
  final String message;
  TransactionLockedException(this.message);
  @override
  String toString() => message;
}

Map<String, dynamic> transactionBalanceUpdates(
    MoneyTransaction t, int direction) {
  final mult = direction.toDouble();
  switch (t.type.toLowerCase()) {
    case 'distribution':
      return {
        'currentBalance': FieldValue.increment(t.amount * mult),
        'totalDistributed': FieldValue.increment(t.amount * mult),
      };
    case 'return':
      return {
        'currentBalance': FieldValue.increment(-t.amount * mult),
        'totalReturned': FieldValue.increment(t.amount * mult),
      };
    case 'purchase':
      final covered = t.amount - (t.forgivenAmount ?? 0.0);
      final updates = <String, dynamic>{
        'currentBalance': FieldValue.increment(-covered * mult),
        'totalCoffeePurchased': FieldValue.increment(covered * mult),
      };
      if (t.commissionAmount != null && t.commissionAmount! > 0) {
        updates['totalCommissionEarned'] =
            FieldValue.increment(t.commissionAmount! * mult);
      }
      return updates;
    case 'transfer':
      final effect = t.isTransferSender ? -1.0 : 1.0;
      final updates = <String, dynamic>{
        'currentBalance': FieldValue.increment(t.amount * mult * effect),
      };
      if (t.isTransferSender) {
        updates['totalReturned'] = FieldValue.increment(t.amount * mult);
      } else {
        updates['totalDistributed'] = FieldValue.increment(t.amount * mult);
      }
      return updates;
    default:
      return {};
  }
}

void enforceTransactionLock(
  MoneyTransaction transaction, {
  required String? overrideReason,
  required String action,
}) {
  if (transaction.isLocked &&
      (overrideReason == null || overrideReason.trim().isEmpty)) {
    throw TransactionLockedException(
        'This transaction is locked. Please provide a reason to $action it.');
  }
}
