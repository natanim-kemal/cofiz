import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/transaction_model.dart';
import '../models/worker_model.dart';
import '../config/cloudinary_config.dart';
import '../utils/receipt_image_utils.dart';
import '../utils/transaction_balance.dart' as tb;
import '../utils/transaction_balance.dart' show TransactionLockedException;
export '../utils/transaction_balance.dart' show TransactionLockedException;
import 'connectivity_service.dart';
import 'notification_trigger_service.dart';
import 'offline_cache_service.dart';
import 'offline_sync_service.dart';

/// A single page of transactions from a cursor-paginated query.
class TransactionPage {
  final List<MoneyTransaction> items;
  final DocumentSnapshot<Map<String, dynamic>>? lastDoc;
  final bool hasMore;

  TransactionPage({
    required this.items,
    required this.lastDoc,
    required this.hasMore,
  });
}

// TransactionLockedException is shared with OfflineSyncService — see transaction_balance.dart
class TransactionService {
  final FirebaseFirestore _firestore;

  TransactionService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;
  late final NotificationTriggerService _notificationService =
      NotificationTriggerService();
  static const String _transactionsCollection = 'transactions';

  /// Get transactions for a specific worker
  /// [limit] bounds the real-time stream to the newest items.
  Stream<List<MoneyTransaction>> getWorkerTransactionsStream(
    String workerId, {
    int limit = 20,
  }) {
    return _firestore
        .collection(_transactionsCollection)
        .where('workerId', isEqualTo: workerId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return MoneyTransaction.fromFirestore(doc.data(), doc.id);
      }).toList();
    });
  }

  /// Fetch a page of worker transactions (newest first) via cursor.
  Future<TransactionPage> getWorkerTransactionsPage(
    String workerId, {
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int pageSize = 20,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _firestore
          .collection(_transactionsCollection)
          .where('workerId', isEqualTo: workerId)
          .orderBy('createdAt', descending: true)
          .limit(pageSize);
      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }
      final snapshot = await query.get();
      final transactions = snapshot.docs
          .map((doc) => MoneyTransaction.fromFirestore(doc.data(), doc.id))
          .toList();
      return TransactionPage(
        items: transactions,
        lastDoc: snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
        hasMore: snapshot.docs.length == pageSize,
      );
    } catch (e) {
      print('Error fetching worker transactions page: $e');
      return TransactionPage(items: const [], lastDoc: null, hasMore: false);
    }
  }

  /// Fetch all transactions for a worker on a specific calendar day (local time).
  /// Used by the date filter on the worker detail page so that old dates can be
  /// viewed without paginating through the full history.
  Future<List<MoneyTransaction>> getWorkerTransactionsForDay(
    String workerId,
    DateTime day,
  ) async {
    final startOfDay = DateTime(day.year, day.month, day.day);
    final startTimestamp = startOfDay.millisecondsSinceEpoch;
    final endTimestamp =
        startOfDay.add(const Duration(days: 1)).millisecondsSinceEpoch;

    try {
      final snapshot = await _firestore
          .collection(_transactionsCollection)
          .where('workerId', isEqualTo: workerId)
          .where('createdAt', isGreaterThanOrEqualTo: startTimestamp)
          .where('createdAt', isLessThan: endTimestamp)
          .orderBy('createdAt', descending: true)
          .get();
      return snapshot.docs
          .map((doc) => MoneyTransaction.fromFirestore(doc.data(), doc.id))
          .toList();
    } catch (e) {
      return const [];
    }
  }

  /// Total count of transactions for a worker (server-side count).
  Future<int> getWorkerTransactionCount(String workerId) async {
    try {
      final snap = await _firestore
          .collection(_transactionsCollection)
          .where('workerId', isEqualTo: workerId)
          .count()
          .get();
      return snap.count ?? 0;
    } catch (e) {
      print('Error counting worker transactions: $e');
      return 0;
    }
  }

  /// Get all transactions
  Stream<List<MoneyTransaction>> getAllTransactionsStream() {
    return _firestore
        .collection(_transactionsCollection)
        .snapshots()
        .map((snapshot) {
      final transactions = snapshot.docs.map((doc) {
        return MoneyTransaction.fromFirestore(doc.data(), doc.id);
      }).toList();

      // Sort by date (newest first)
      transactions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return transactions;
    });
  }

  /// Get all transactions (One-time fetch)
  Future<List<MoneyTransaction>> getAllTransactions() async {
    try {
      final snapshot = await _firestore
          .collection(_transactionsCollection)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => MoneyTransaction.fromFirestore(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('Error fetching all transactions: $e');
      return [];
    }
  }

  /// Add transaction and update worker balance (queue-first)
  Future<String?> addTransaction(MoneyTransaction transaction) async {
    if (transaction.amount <= 0) throw 'Amount must be greater than 0';
    if (ConnectivityService().isOnline &&
        (transaction.type.toLowerCase() == 'purchase' ||
            transaction.type.toLowerCase() == 'return')) {
      final workerDoc = await _firestore
          .collection('workers')
          .doc(transaction.workerId)
          .get();

      if (!workerDoc.exists) {
        throw 'Collector not found';
      }

      final currentBalance =
          (workerDoc.data()?['currentBalance'] ?? 0.0).toDouble();

      if (transaction.amount > currentBalance) {
        throw 'Insufficient balance. Available: ETB ${currentBalance.toStringAsFixed(2)}, Required: ETB ${transaction.amount.toStringAsFixed(2)}';
      }
    } else if (!ConnectivityService().isOnline &&
        (transaction.type.toLowerCase() == 'purchase' ||
            transaction.type.toLowerCase() == 'return')) {
      final projected = _projectedBalance(transaction.workerId);
      if (projected != null && transaction.amount > projected) {
        throw 'Insufficient balance. Available: ETB ${projected.toStringAsFixed(2)}, Required: ETB ${transaction.amount.toStringAsFixed(2)}';
      }
    }
    final opId = const Uuid().v4();
    final docId = opId;
    await OfflineCacheService().queueOperation({
      'opId': opId,
      'type': 'createTransaction',
      'docId': docId,
      'workerId': transaction.workerId,
      'workerName': transaction.workerName,
      'transactionType': transaction.type,
      'amount': transaction.amount,
      'notes': transaction.notes,
      'receiptUrl': transaction.receiptUrl,
      'createdAt': transaction.createdAt.millisecondsSinceEpoch,
      'createdBy': transaction.createdBy,
      'coffeeType': transaction.coffeeType,
      'coffeeWeight': transaction.coffeeWeight,
      'pricePerKg': transaction.pricePerKg,
      'commissionAmount': transaction.commissionAmount,
      'queuedAt': DateTime.now().toIso8601String(),
      'attempts': 0,
    });
    // optimistic cache
    final cached = OfflineCacheService().getCachedTransactions() ?? [];
    final optimistic = MoneyTransaction(
      id: docId,
      workerId: transaction.workerId,
      workerName: transaction.workerName,
      type: transaction.type,
      amount: transaction.amount,
      notes: transaction.notes,
      receiptUrl: transaction.receiptUrl,
      createdAt: transaction.createdAt,
      createdBy: transaction.createdBy,
      approved: transaction.approved,
      coffeeType: transaction.coffeeType,
      coffeeWeight: transaction.coffeeWeight,
      pricePerKg: transaction.pricePerKg,
      commissionAmount: transaction.commissionAmount,
      fromWorkerId: transaction.fromWorkerId,
      toWorkerId: transaction.toWorkerId,
      fromWorkerName: transaction.fromWorkerName,
      toWorkerName: transaction.toWorkerName,
      transferId: transaction.transferId,
      transferRole: transaction.transferRole,
    );
    await OfflineCacheService().cacheTransactions([...cached, optimistic]);
    unawaited(OfflineSyncService().syncNow());
    return docId;
  }

  /// Record a collector-to-collector transfer: two linked records + balances (queue-first).
  Future<String?> addTransfer({
    required String fromWorkerId,
    required String fromWorkerName,
    required String toWorkerId,
    required String toWorkerName,
    required double amount,
    required String createdBy,
    String? notes,
  }) async {
    if (amount <= 0) {
      throw 'Amount must be greater than 0';
    }

    if (ConnectivityService().isOnline) {
      final senderDoc =
          await _firestore.collection('workers').doc(fromWorkerId).get();
      if (!senderDoc.exists) {
        throw 'Collector not found';
      }
      final senderBalance =
          (senderDoc.data()?['currentBalance'] ?? 0.0).toDouble();
      if (amount > senderBalance) {
        throw 'Insufficient balance. Available: ETB ${senderBalance.toStringAsFixed(2)}, Required: ETB ${amount.toStringAsFixed(2)}';
      }
    } else {
      final projected = _projectedBalance(fromWorkerId);
      if (projected != null && amount > projected) {
        throw 'Insufficient balance. Available: ETB ${projected.toStringAsFixed(2)}, Required: ETB ${amount.toStringAsFixed(2)}';
      }
    }

    final opId = const Uuid().v4();
    final transferId = opId;
    final senderDocId = opId;
    final receiverDocId = '${opId}_r';
    final now = DateTime.now();

    await OfflineCacheService().queueOperation({
      'opId': opId,
      'type': 'createTransfer',
      'transferId': transferId,
      'senderDocId': senderDocId,
      'receiverDocId': receiverDocId,
      'fromWorkerId': fromWorkerId,
      'fromWorkerName': fromWorkerName,
      'toWorkerId': toWorkerId,
      'toWorkerName': toWorkerName,
      'amount': amount,
      'createdAt': now.millisecondsSinceEpoch,
      'createdBy': createdBy,
      'notes': notes,
      'queuedAt': DateTime.now().toIso8601String(),
      'attempts': 0,
    });

    // optimistic cache: two MoneyTransactions
    final cached = OfflineCacheService().getCachedTransactions() ?? [];
    final senderTx = MoneyTransaction(
      id: senderDocId,
      workerId: fromWorkerId,
      workerName: fromWorkerName,
      type: 'transfer',
      amount: amount,
      notes: notes,
      createdAt: now,
      createdBy: createdBy,
      approved: false,
      fromWorkerId: fromWorkerId,
      toWorkerId: toWorkerId,
      fromWorkerName: fromWorkerName,
      toWorkerName: toWorkerName,
      transferId: transferId,
      transferRole: 'sender',
    );
    final receiverTx = MoneyTransaction(
      id: receiverDocId,
      workerId: toWorkerId,
      workerName: toWorkerName,
      type: 'transfer',
      amount: amount,
      notes: notes,
      createdAt: now,
      createdBy: createdBy,
      approved: false,
      fromWorkerId: fromWorkerId,
      toWorkerId: toWorkerId,
      fromWorkerName: fromWorkerName,
      toWorkerName: toWorkerName,
      transferId: transferId,
      transferRole: 'receiver',
    );
    await OfflineCacheService()
        .cacheTransactions([...cached, senderTx, receiverTx]);
    unawaited(OfflineSyncService().syncNow());
    return transferId;
  }

  /// Approve a single transaction entry (queue-first-always)
  Future<void> approveTransaction(String transactionId) async {
    await OfflineCacheService().queueOperation({
      'opId': const Uuid().v4(),
      'type': 'approveTransaction',
      'transactionId': transactionId,
      'queuedAt': DateTime.now().toIso8601String(),
      'attempts': 0,
    });
    unawaited(OfflineSyncService().syncNow());
  }

  /// Batch approve all pending transactions for a worker (queue-first-always)
  Future<void> approveAllForWorker(String workerId) async {
    await OfflineCacheService().queueOperation({
      'opId': const Uuid().v4(),
      'type': 'approveAll',
      'workerId': workerId,
      'queuedAt': DateTime.now().toIso8601String(),
      'attempts': 0,
    });
    unawaited(OfflineSyncService().syncNow());
  }

  /// Approve both records of a transfer by shared transferId (queue-first-always)
  Future<void> approveTransfer(String transferId) async {
    await OfflineCacheService().queueOperation({
      'opId': const Uuid().v4(),
      'type': 'approveTransfer',
      'transferId': transferId,
      'queuedAt': DateTime.now().toIso8601String(),
      'attempts': 0,
    });
    unawaited(OfflineSyncService().syncNow());
  }

  /// Delete both records of a transfer by shared transferId, reversing balances.
  /// If the transfer is past the immutability window, [overrideReason] must be
  /// provided by an admin.
  Future<void> deleteTransfer(
    String transferId, {
    String? overrideReason,
  }) async {
    final cached = OfflineCacheService().getCachedTransactions();
    if (cached != null) {
      final matches = cached.where((t) => t.transferId == transferId).toList();
      for (final tx in matches) {
        _enforceLock(tx, overrideReason: overrideReason, action: 'delete');
      }
    }
    await OfflineCacheService().queueOperation({
      'opId': transferId,
      'type': 'deleteTransfer',
      'transferId': transferId,
      'overrideReason': overrideReason,
      'attempts': 0,
      'queuedAt': DateTime.now().toIso8601String(),
    });
    final cachedList = OfflineCacheService().getCachedTransactions() ?? [];
    await OfflineCacheService().cacheTransactions(
        cachedList.where((t) => t.transferId != transferId).toList());
    unawaited(OfflineSyncService().syncNow());
  }

  /// Edit an existing transaction, reversing the old balance effect and applying the new one
  /// If the transaction is past the immutability window, [overrideReason] must be
  /// provided by an admin.
  Future<void> updateTransaction(
    MoneyTransaction transaction, {
    String? overrideReason,
  }) async {
    final cached = OfflineCacheService().getCachedTransactions();
    MoneyTransaction? old;
    if (cached != null) {
      try {
        old = cached.firstWhere((t) => t.id == transaction.id);
      } catch (_) {}
    }
    if (old != null) {
      _enforceLock(old, overrideReason: overrideReason, action: 'edit');
      if (old.isTransfer || transaction.isTransfer) {
        throw 'Transfers cannot be edited.';
      }
    } else if (transaction.isTransfer) {
      throw 'Transfers cannot be edited.';
    }
    if (!ConnectivityService().isOnline) {
      if (transaction.type.toLowerCase() == 'purchase' ||
          transaction.type.toLowerCase() == 'return') {
        final projected = _projectedBalance(transaction.workerId);
        if (projected != null) {
          double available = projected;
          if (old != null && old.workerId == transaction.workerId) {
            available -= _numericBalanceDelta(old, 1);
          }
          if (transaction.amount > available) {
            throw 'Insufficient balance. Available: ETB ${available.toStringAsFixed(2)}, Required: ETB ${transaction.amount.toStringAsFixed(2)}';
          }
        }
      }
    } else {
      // online: still enforce balance using projected (cached + pending) as fallback if worker doc unavailable
      if (transaction.type.toLowerCase() == 'purchase' ||
          transaction.type.toLowerCase() == 'return') {
        // try live check via firestore if online; if fails fallback to projected
        try {
          final workerDoc = await _firestore
              .collection('workers')
              .doc(transaction.workerId)
              .get();
          if (workerDoc.exists && old != null) {
            final currentBalance =
                (workerDoc.data()?['currentBalance'] ?? 0.0).toDouble();
            final oldDirection =
                old.type.toLowerCase() == 'distribution' ? 1.0 : -1.0;
            final projectedBalance =
                currentBalance + oldDirection * old.amount - transaction.amount;
            if (projectedBalance < 0) {
              throw 'Insufficient balance. Available: ETB ${projectedBalance.toStringAsFixed(2)}, Required: ETB ${transaction.amount.toStringAsFixed(2)}';
            }
          }
        } catch (e) {
          if (e is String && e.contains('Insufficient')) rethrow;
        }
      }
    }
    await OfflineCacheService().queueOperation({
      'opId': transaction.id,
      'type': 'updateTransaction',
      'docId': transaction.id,
      'payload': transaction.toFirestore(),
      'overrideReason': overrideReason,
      'attempts': 0,
      'queuedAt': DateTime.now().toIso8601String(),
    });
    final cachedList = OfflineCacheService().getCachedTransactions() ?? [];
    await OfflineCacheService().cacheTransactions([
      for (final t in cachedList)
        if (t.id != transaction.id) t,
      transaction,
    ]);
    unawaited(OfflineSyncService().syncNow());
  }

  /// Delete an existing transaction, reversing its balance effect
  /// If the transaction is past the immutability window, [overrideReason] must be
  /// provided by an admin.
  Future<void> deleteTransaction(
    String transactionId, {
    String? overrideReason,
  }) async {
    final cached = OfflineCacheService().getCachedTransactions();
    MoneyTransaction? tx;
    if (cached != null) {
      try {
        tx = cached.firstWhere((t) => t.id == transactionId);
      } catch (_) {}
    }
    if (tx != null) {
      _enforceLock(tx, overrideReason: overrideReason, action: 'delete');
      if (tx.isTransfer) {
        throw 'Use transfer delete for transfers.';
      }
      if (tx.type.toLowerCase() == 'distribution' &&
          !ConnectivityService().isOnline) {
        final projected = _projectedBalance(tx.workerId);
        if (projected != null && tx.amount > projected) {
          throw 'Insufficient balance. Available: ETB ${projected.toStringAsFixed(2)}, Required: ETB ${tx.amount.toStringAsFixed(2)}';
        }
      }
    }
    await OfflineCacheService().queueOperation({
      'opId': transactionId,
      'type': 'deleteTransaction',
      'docId': transactionId,
      'overrideReason': overrideReason,
      'attempts': 0,
      'queuedAt': DateTime.now().toIso8601String(),
    });
    final cachedList = OfflineCacheService().getCachedTransactions() ?? [];
    await OfflineCacheService().cacheTransactions(
        cachedList.where((t) => t.id != transactionId).toList());
    unawaited(OfflineSyncService().syncNow());
  }

  /// Throws if the transaction is past the immutability window and no admin
  // shared with OfflineSyncService — keep in sync (delegates to transaction_balance.dart)
  void _enforceLock(
    MoneyTransaction transaction, {
    required String? overrideReason,
    required String action,
  }) =>
      tb.enforceTransactionLock(transaction,
          overrideReason: overrideReason, action: action);

  // shared with OfflineSyncService — keep in sync
  Map<String, dynamic> _balanceUpdates(MoneyTransaction t, int direction) =>
      tb.transactionBalanceUpdates(t, direction);

  double _numericBalanceDelta(MoneyTransaction t, int direction) {
    final mult = direction.toDouble();
    switch (t.type.toLowerCase()) {
      case 'distribution':
        return t.amount * mult;
      case 'return':
        return -t.amount * mult;
      case 'purchase':
        return -t.amount * mult;
      case 'transfer':
        final eff = t.isTransferSender ? -1.0 : 1.0;
        return t.amount * mult * eff;
      default:
        return 0;
    }
  }

  /// Cached worker balance + pending op deltas, or null when the worker has no
  /// cached baseline (local validation impossible — sync enforces authoritatively).
  double? _projectedBalance(String workerId) {
    double base = 0;
    Worker? w =
        OfflineCacheService().getCachedWorkerProfile(expectedId: workerId);
    if (w == null) {
      final workers = OfflineCacheService().getCachedWorkers();
      if (workers != null) {
        for (final worker in workers) {
          if (worker.id == workerId) {
            w = worker;
            break;
          }
        }
      }
    }
    if (w == null) return null;
    base = w.currentBalance;
    final pending = OfflineCacheService().getPendingOperations();
    final cachedTxs = OfflineCacheService().getCachedTransactions() ?? [];
    final txMap = {for (final t in cachedTxs) t.id: t};
    for (final op in pending) {
      final type = op['type'] as String? ?? '';
      try {
        if (type == 'createTransaction') {
          if (op['workerId'] != workerId) continue;
          final mt = MoneyTransaction(
            id: op['docId'] as String? ?? op['opId'] as String,
            workerId: op['workerId'] as String,
            workerName: op['workerName'] as String? ?? '',
            type: op['transactionType'] as String? ?? 'distribution',
            amount: (op['amount'] as num).toDouble(),
            createdAt: op['createdAt'] != null
                ? DateTime.fromMillisecondsSinceEpoch(op['createdAt'] as int)
                : DateTime.now(),
            createdBy: op['createdBy'] as String? ?? '',
            commissionAmount: (op['commissionAmount'] as num?)?.toDouble(),
            transferId: op['transferId'] as String?,
            transferRole: op['transferRole'] as String?,
          );
          base += _numericBalanceDelta(mt, 1);
        } else if (type == 'deleteTransaction') {
          final docId = op['docId'] as String?;
          final tx = txMap[docId];
          if (tx == null || tx.workerId != workerId) continue;
          base += _numericBalanceDelta(tx, -1);
        } else if (type == 'updateTransaction') {
          final docId = op['docId'] as String?;
          final old = txMap[docId];
          final payload = op['payload'] as Map<String, dynamic>?;
          if (payload == null) continue;
          MoneyTransaction newTx;
          try {
            newTx = MoneyTransaction.fromFirestore(
                Map<String, dynamic>.from(payload), docId!);
          } catch (_) {
            continue;
          }
          if (old != null && old.workerId == workerId)
            base += _numericBalanceDelta(old, -1);
          if (newTx.workerId == workerId)
            base += _numericBalanceDelta(newTx, 1);
          if (old == null && newTx.workerId == workerId) {
            // if old not in cache, only new matters (handled)
          }
        } else if (type == 'createTransfer') {
          final amt = (op['amount'] as num?)?.toDouble() ?? 0;
          if (op['fromWorkerId'] == workerId) base -= amt;
          if (op['toWorkerId'] == workerId) base += amt;
        } else if (type == 'deleteTransfer') {
          final tid = op['transferId'] as String? ?? op['opId'] as String?;
          if (tid == null) continue;
          for (final t in cachedTxs.where((t) => t.transferId == tid)) {
            if (t.workerId != workerId) continue;
            base += _numericBalanceDelta(t, -1);
          }
        }
      } catch (_) {}
    }
    return base;
  }

  /// Trigger notifications based on transaction type
  Future<void> _triggerTransactionNotifications({
    required MoneyTransaction transaction,
    required double balanceChange,
  }) async {
    try {
      // Get worker data to check userId and new balance
      final workerDoc = await _firestore
          .collection('workers')
          .doc(transaction.workerId)
          .get();

      if (!workerDoc.exists) return;

      final workerData = workerDoc.data()!;
      final workerUserId = workerData['userId'] as String?;
      final workerName = workerData['name'] as String? ?? 'Collector';
      final newBalance = (workerData['currentBalance'] ?? 0.0).toDouble();
      final totalCommission =
          (workerData['totalCommissionEarned'] ?? 0.0).toDouble();

      // Only send notifications if worker has a user account
      if (workerUserId == null || workerUserId.isEmpty) return;

      switch (transaction.type.toLowerCase()) {
        case 'distribution':
          // Notify worker they received money
          await _notificationService.notifyMoneyDistributed(
            workerId: transaction.workerId,
            workerUserId: workerUserId,
            workerName: workerName,
            amount: transaction.amount,
            adminName: null,
          );
          break;

        case 'purchase':
          // Check for low balance
          await _notificationService.checkLowBalance(
            workerId: transaction.workerId,
            workerUserId: workerUserId,
            workerName: workerName,
            newBalance: newBalance,
          );

          // Notify commission earned
          if (transaction.commissionAmount != null &&
              transaction.commissionAmount! > 0) {
            await _notificationService.notifyCommissionEarned(
              workerUserId: workerUserId,
              workerName: workerName,
              commission: transaction.commissionAmount!,
              totalCommission: totalCommission,
            );
          }

          // Check for large purchase (notify admins)
          await _notificationService.checkLargePurchase(
            workerId: transaction.workerId,
            workerName: workerName,
            amount: transaction.amount,
            coffeeType: transaction.coffeeType,
            weight: transaction.coffeeWeight,
          );
          break;

        case 'return':
          // Could add notification for returns if needed
          break;
      }
    } catch (e) {
      // Don't fail the transaction if notification fails
      print('Error triggering notifications: $e');
    }
  }

  /// Get recent transactions (limit)
  Future<List<MoneyTransaction>> getRecentTransactions({int limit = 10}) async {
    try {
      final snapshot = await _firestore
          .collection(_transactionsCollection)
          .limit(limit)
          .get();

      final transactions = snapshot.docs
          .map((doc) => MoneyTransaction.fromFirestore(doc.data(), doc.id))
          .toList();

      transactions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return transactions;
    } catch (e) {
      print('Error getting recent transactions: $e');
      return [];
    }
  }

  /// Get worker transactions (limit)
  Future<List<MoneyTransaction>> getWorkerTransactions(
    String workerId, {
    int limit = 50,
  }) async {
    try {
      final snapshot = await _firestore
          .collection(_transactionsCollection)
          .where('workerId', isEqualTo: workerId)
          .limit(limit)
          .get();

      final transactions = snapshot.docs
          .map((doc) => MoneyTransaction.fromFirestore(doc.data(), doc.id))
          .toList();

      transactions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return transactions;
    } catch (e) {
      print('Error getting worker transactions: $e');
      return [];
    }
  }

  /// Get transactions by type
  Future<List<MoneyTransaction>> getTransactionsByType(String type) async {
    try {
      final snapshot = await _firestore
          .collection(_transactionsCollection)
          .where('type', isEqualTo: type)
          .get();

      final transactions = snapshot.docs
          .map((doc) => MoneyTransaction.fromFirestore(doc.data(), doc.id))
          .toList();

      transactions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return transactions;
    } catch (e) {
      print('Error getting transactions by type: $e');
      return [];
    }
  }

  /// Calculate total for today
  Future<Map<String, double>> getTodayTotals() async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final startTimestamp = startOfDay.millisecondsSinceEpoch;

      final snapshot = await _firestore
          .collection(_transactionsCollection)
          .where('createdAt', isGreaterThanOrEqualTo: startTimestamp)
          .get();

      double totalDistributed = 0;
      double totalReturned = 0;
      double totalPurchased = 0;

      for (var doc in snapshot.docs) {
        final transaction = MoneyTransaction.fromFirestore(doc.data(), doc.id);
        switch (transaction.type.toLowerCase()) {
          case 'distribution':
            totalDistributed += transaction.amount;
            break;
          case 'return':
            totalReturned += transaction.amount;
            break;
          case 'purchase':
            totalPurchased += transaction.amount;
            break;
        }
      }

      return {
        'distributed': totalDistributed,
        'returned': totalReturned,
        'purchased': totalPurchased,
      };
    } catch (e) {
      print('Error getting today totals: $e');
      return {
        'distributed': 0.0,
        'returned': 0.0,
        'purchased': 0.0,
      };
    }
  }

  /// Handle Firestore exceptions with user-friendly messages
  String _handleFirestoreError(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
        return 'Database access denied. Please check your permissions.';
      case 'unavailable':
        return 'Database is currently unavailable. Please check your internet connection.';
      case 'not-found':
        return 'Transaction not found in database.';
      case 'already-exists':
        return 'This transaction already exists.';
      default:
        return 'Database error: ${e.message ?? 'Unknown error'}';
    }
  }

  Future<String?> uploadReceipt(String filePath) async {
    try {
      final compressedBytes = await ReceiptImageUtils.compress(filePath);
      if (compressedBytes == null || compressedBytes.isEmpty) return null;

      final request = http.MultipartRequest(
        'POST',
        Uri.parse(CloudinaryConfig.uploadEndpoint),
      )
        ..fields['upload_preset'] = CloudinaryConfig.uploadPreset
        ..fields['folder'] = CloudinaryConfig.folder
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          compressedBytes,
          filename: 'receipt_${DateTime.now().millisecondsSinceEpoch}.jpg',
        ));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode != 200) {
        print(
          'Cloudinary upload failed (${response.statusCode}): ${response.body}',
        );
        throw 'Failed to upload receipt image';
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final secureUrl = json['secure_url'] as String?;
      return secureUrl;
    } catch (e) {
      print('Error uploading receipt: $e');
      throw 'Failed to upload receipt image';
    }
  }
}
