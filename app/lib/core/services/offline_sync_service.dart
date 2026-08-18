import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'connectivity_service.dart';
import 'offline_cache_service.dart';

class OfflineSyncService {
  static final OfflineSyncService _instance = OfflineSyncService._internal();
  factory OfflineSyncService() => _instance;
  OfflineSyncService._internal();

  final ConnectivityService _connectivity = ConnectivityService();
  final OfflineCacheService _cache = OfflineCacheService();

  FirebaseFirestore? _firestore;

  /// Production uses FirebaseFirestore.instance; tests inject a fake.
  FirebaseFirestore get firestore => _firestore ??= FirebaseFirestore.instance;

  @visibleForTesting
  set firestore(FirebaseFirestore value) => _firestore = value;

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  Timer? _periodicTimer;

  Future<void> initialize() async {
    await _cache.initialize();
    await _connectivity.initialize();

    // Listen for connectivity changes
    _connectivity.connectionStatus.listen((isOnline) {
      if (isOnline && !_isSyncing) {
        syncPendingOperations();
      }
    });

    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_connectivity.isOnline && !_isSyncing) syncPendingOperations();
    });
  }

  void dispose() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  Future<void> syncNow() async {
    if (_connectivity.isOnline && !_isSyncing) {
      await syncPendingOperations();
    }
  }

  Future<void> syncPendingOperations() async {
    if (_isSyncing) return;

    _isSyncing = true;
    debugPrint('📡 Starting sync of pending operations...');

    try {
      final pendingOps = _cache.getPendingOperations();
      debugPrint('📡 Found ${pendingOps.length} pending operations');

      final remaining = <Map<String, dynamic>>[];
      for (final operation in pendingOps) {
        try {
          await _executeOperation(operation);
          debugPrint('✅ Synced operation: ${operation['type']}');
          final opId = operation['opId'] as String?;
          final type = operation['type'] as String? ?? 'unknown';
          if (opId != null) {
            await _cache.markDelivered(opId, type);
          }
        } catch (e) {
          debugPrint('❌ Failed to sync operation: $e');
          final updated = Map<String, dynamic>.from(operation);
          updated['attempts'] = ((operation['attempts'] as int?) ?? 0) + 1;
          remaining.add(updated);
        }
      }

      await _cache.replacePendingOperations(remaining);
      await _cache.pruneDelivered();
      debugPrint('📡 Sync completed!');
    } catch (e) {
      debugPrint('❌ Sync failed: $e');
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _executeOperation(Map<String, dynamic> operation) async {
    final type = operation['type'] as String;
    switch (type) {
      case 'approveTransaction':
        await firestore
            .collection('transactions')
            .doc(operation['transactionId'] as String)
            .update({'approved': true});
        break;
      case 'approveTransfer':
        final snapshot = await firestore
            .collection('transactions')
            .where('transferId', isEqualTo: operation['transferId'] as String)
            .get();
        final batch = firestore.batch();
        for (final doc in snapshot.docs) {
          batch.update(doc.reference, {'approved': true});
        }
        await batch.commit();
        break;
      case 'approveAll':
        final snapshot = await firestore
            .collection('transactions')
            .where('workerId', isEqualTo: operation['workerId'] as String)
            .where('approved', isEqualTo: false)
            .get();
        final batch = firestore.batch();
        for (final doc in snapshot.docs) {
          batch.update(doc.reference, {'approved': true});
        }
        await batch.commit();
        break;
      case 'createTransaction':
        {
          final docId = operation['docId'] as String;
          final workerId = operation['workerId'] as String;
          final txType = operation['transactionType'] as String;
          final amount = (operation['amount'] as num).toDouble();
          await firestore.runTransaction((txn) async {
            final ref = firestore.collection('transactions').doc(docId);
            final snap = await txn.get(ref);
            if (snap.exists) return;
            txn.set(ref, {
              'workerId': workerId,
              'workerName': operation['workerName'],
              'type': txType,
              'amount': amount,
              'notes': operation['notes'],
              'receiptUrl': operation['receiptUrl'],
              'createdAt': operation['createdAt'],
              'createdBy': operation['createdBy'],
              'approved': false,
              if (operation['coffeeType'] != null)
                'coffeeType': operation['coffeeType'],
              if (operation['coffeeWeight'] != null)
                'coffeeWeight': operation['coffeeWeight'],
              if (operation['pricePerKg'] != null)
                'pricePerKg': operation['pricePerKg'],
              if (operation['commissionAmount'] != null)
                'commissionAmount': operation['commissionAmount'],
            });
            final workerRef = firestore.collection('workers').doc(workerId);
            if (txType == 'distribution') {
              txn.update(workerRef, {
                'currentBalance': FieldValue.increment(amount),
                'totalDistributed': FieldValue.increment(amount),
              });
            } else if (txType == 'return') {
              txn.update(workerRef, {
                'currentBalance': FieldValue.increment(-amount),
                'totalReturned': FieldValue.increment(amount),
              });
            } else if (txType == 'purchase') {
              final Map<String, dynamic> updates = {
                'currentBalance': FieldValue.increment(-amount),
                'totalCoffeePurchased': FieldValue.increment(amount),
              };
              final commission =
                  (operation['commissionAmount'] as num?)?.toDouble();
              if (commission != null && commission > 0) {
                updates['totalCommissionEarned'] =
                    FieldValue.increment(commission);
              }
              txn.update(workerRef, updates);
            }
          });
        }
        break;
      case 'createTransfer':
        {
          final opId = operation['opId'] as String? ??
              operation['transferId'] as String? ??
              '';
          final transferId = operation['transferId'] as String? ?? opId;
          final senderDocId = operation['senderDocId'] as String? ??
              operation['docId'] as String? ??
              opId;
          final receiverDocId =
              operation['receiverDocId'] as String? ?? '${senderDocId}_r';
          final fromWorkerId = operation['fromWorkerId'] as String;
          final fromWorkerName = operation['fromWorkerName'] as String?;
          final toWorkerId = operation['toWorkerId'] as String;
          final toWorkerName = operation['toWorkerName'] as String?;
          final amount = (operation['amount'] as num).toDouble();
          final createdAt = operation['createdAt'];
          final createdBy = operation['createdBy'] as String?;
          final notes = operation['notes'] as String?;

          await firestore.runTransaction((txn) async {
            final senderRef =
                firestore.collection('transactions').doc(senderDocId);
            final snap = await txn.get(senderRef);
            if (snap.exists) return;

            final receiverRef =
                firestore.collection('transactions').doc(receiverDocId);

            final base = {
              'type': 'transfer',
              'amount': amount,
              'transferId': transferId,
              'createdAt': createdAt,
              'createdBy': createdBy,
              'notes': notes,
              'approved': false,
            };

            txn.set(senderRef, {
              ...base,
              'workerId': fromWorkerId,
              'workerName': fromWorkerName,
              'fromWorkerId': fromWorkerId,
              'toWorkerId': toWorkerId,
              'fromWorkerName': fromWorkerName,
              'toWorkerName': toWorkerName,
              'transferRole': 'sender',
            });

            txn.set(receiverRef, {
              ...base,
              'workerId': toWorkerId,
              'workerName': toWorkerName,
              'fromWorkerId': fromWorkerId,
              'toWorkerId': toWorkerId,
              'fromWorkerName': fromWorkerName,
              'toWorkerName': toWorkerName,
              'transferRole': 'receiver',
            });

            final fromRef = firestore.collection('workers').doc(fromWorkerId);
            final toRef = firestore.collection('workers').doc(toWorkerId);
            txn.update(
                fromRef, {'currentBalance': FieldValue.increment(-amount)});
            txn.update(toRef, {'currentBalance': FieldValue.increment(amount)});
          });
        }
        break;
      case 'createIncome':
        {
          final docId =
              (operation['docId'] as String?) ?? (operation['opId'] as String);
          final Map<String, dynamic> data;
          if (operation['payload'] != null) {
            data = Map<String, dynamic>.from(operation['payload'] as Map);
          } else {
            data = {
              if (operation['kind'] != null) 'kind': operation['kind'],
              if (operation['amount'] != null) 'amount': operation['amount'],
              if (operation['description'] != null)
                'description': operation['description'],
              if (operation['createdAt'] != null)
                'createdAt': operation['createdAt'],
              if (operation['createdBy'] != null)
                'createdBy': operation['createdBy'],
              if (operation['createdByName'] != null)
                'createdByName': operation['createdByName'],
              if (operation['viewerId'] != null)
                'viewerId': operation['viewerId'],
              if (operation['viewerName'] != null)
                'viewerName': operation['viewerName'],
              if (operation['saleCategory'] != null)
                'saleCategory': operation['saleCategory'],
            };
          }
          await firestore.runTransaction((txn) async {
            final ref = firestore.collection('income_records').doc(docId);
            final snap = await txn.get(ref);
            if (snap.exists) return;
            txn.set(ref, data);
          });
        }
        break;
      case 'createExpense':
        {
          final docId =
              (operation['docId'] as String?) ?? (operation['opId'] as String);
          final Map<String, dynamic> data;
          if (operation['payload'] != null) {
            data = Map<String, dynamic>.from(operation['payload'] as Map);
          } else {
            data = {
              if (operation['amount'] != null) 'amount': operation['amount'],
              if (operation['expenseCategory'] != null)
                'expenseCategory': operation['expenseCategory'],
              if (operation['description'] != null)
                'description': operation['description'],
              if (operation['createdAt'] != null)
                'createdAt': operation['createdAt'],
              if (operation['createdBy'] != null)
                'createdBy': operation['createdBy'],
              if (operation['createdByName'] != null)
                'createdByName': operation['createdByName'],
            };
          }
          await firestore.runTransaction((txn) async {
            final ref = firestore.collection('expenses').doc(docId);
            final snap = await txn.get(ref);
            if (snap.exists) return;
            txn.set(ref, data);
          });
        }
        break;
      default:
        throw UnsupportedError('Unknown operation type: $type');
    }
  }

  Future<void> queueTransaction({
    required String type,
    required String workerId,
    required String workerName,
    required double amount,
    required String createdBy,
    String? notes,
    String? receiptUrl,
  }) async {
    await _cache.queueOperation({
      'type': type,
      'workerId': workerId,
      'workerName': workerName,
      'amount': amount,
      'createdBy': createdBy,
      'notes': notes,
      'receiptUrl': receiptUrl,
      'timestamp': DateTime.now().toIso8601String(),
    });

    debugPrint('📥 Queued $type transaction for offline sync');
  }

  int getPendingOperationsCount() {
    return _cache.getPendingOperations().length;
  }

  Future<void> clearSyncQueue() async {
    await _cache.clearPendingOperations();
  }
}
