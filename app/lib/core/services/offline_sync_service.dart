import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/cloudinary_config.dart';
import '../models/transaction_model.dart';
import '../utils/receipt_image_utils.dart';
import '../utils/transaction_balance.dart' as tb;
import '../utils/transaction_balance.dart' show TransactionLockedException;
import 'connectivity_service.dart';
import 'offline_cache_service.dart';

// shared with TransactionService — keep in sync (delegates to transaction_balance.dart)
typedef OfflineSyncLockedException = TransactionLockedException;

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
    debugPrint('[Sync] initialize: opening caches...');
    await _cache.initialize();
    debugPrint('[Sync] initialize: caches open');
    await _connectivity.initialize();
    debugPrint('[Sync] initialize: connectivity ready');

    // Listen for connectivity changes
    _connectivity.connectionStatus.listen((isOnline) {
      debugPrint('[Sync] connectivity changed isOnline=$isOnline');
      if (isOnline && !_isSyncing) {
        syncPendingOperations();
      }
    });

    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_connectivity.isOnline && !_isSyncing) syncPendingOperations();
    });
  }

  /// Cancels the periodic retry timer. Call on app shutdown / test teardown.
  void dispose() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  Future<void> syncNow() async {
    if (_connectivity.isOnline && !_isSyncing) {
      await syncPendingOperations();
    } else {
      debugPrint(
          '[Sync] syncNow skipped: online=${_connectivity.isOnline} isSyncing=$_isSyncing');
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
          final updated = Map<String, dynamic>.from(operation);
          updated['attempts'] = ((operation['attempts'] as int?) ?? 0) + 1;
          debugPrint(
              '❌ Failed to sync operation: ${operation['type']} attempt ${updated['attempts']}: $e');
          if ((updated['attempts'] as int) >= 5) {
            await _cache.markFailed(updated, e.toString());
          } else {
            remaining.add(updated);
          }
        }
      }

      // Merge ops queued while syncing to avoid lost-update race (snapshot -> replace overwrites).
      final snapshotIds = <String>{
        for (final op in pendingOps)
          if (op['opId'] is String) op['opId'] as String
      };
      final current = _cache.getPendingOperations();
      final newDuringSync = current.where((op) {
        final id = op['opId'] as String?;
        if (id != null) return !snapshotIds.contains(id);
        // Fallback for legacy ops without opId: consider new if no equal snapshot op.
        return !pendingOps.any((s) =>
            s['type'] == op['type'] &&
            s['transactionId'] == op['transactionId'] &&
            s['transferId'] == op['transferId'] &&
            s['workerId'] == op['workerId']);
      }).toList();
      await _cache.replacePendingOperations([...remaining, ...newDuringSync]);
      await _cache.pruneDelivered();
      debugPrint('📡 Sync completed!');
    } catch (e) {
      debugPrint('❌ Sync failed: $e');
    } finally {
      _isSyncing = false;
    }
  }

  Future<String?> _uploadReceipt(String filePath) async {
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
      throw 'Failed to upload receipt image (${response.statusCode})';
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final secureUrl = json['secure_url'] as String?;
    return secureUrl;
  }

  // shared with TransactionService — keep in sync
  void _enforceLock(
    MoneyTransaction transaction, {
    required String? overrideReason,
    required String action,
  }) =>
      tb.enforceTransactionLock(transaction,
          overrideReason: overrideReason, action: action);

  // shared with TransactionService — keep in sync
  Map<String, dynamic> _balanceUpdates(MoneyTransaction t, int direction) =>
      tb.transactionBalanceUpdates(t, direction);

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
          String? receiptUrl = operation['receiptUrl'] as String?;
          final localReceiptPath = operation['localReceiptPath'] as String?;
          if (localReceiptPath != null && localReceiptPath.isNotEmpty) {
            final uploaded = await _uploadReceipt(localReceiptPath);
            if (uploaded != null) {
              receiptUrl = uploaded;
            }
            // if upload returns null (file missing/compress fail) defer — keep receiptUrl as-is (no crash)
          }
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
              'receiptUrl': receiptUrl,
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
            final lastActiveAt = operation['createdAt'] as int? ??
                DateTime.now().millisecondsSinceEpoch;
            if (txType == 'distribution') {
              txn.update(workerRef, {
                'currentBalance': FieldValue.increment(amount),
                'totalDistributed': FieldValue.increment(amount),
                'lastActiveAt': lastActiveAt,
              });
            } else if (txType == 'return') {
              txn.update(workerRef, {
                'currentBalance': FieldValue.increment(-amount),
                'totalReturned': FieldValue.increment(amount),
                'lastActiveAt': lastActiveAt,
              });
            } else if (txType == 'purchase') {
              final Map<String, dynamic> updates = {
                'currentBalance': FieldValue.increment(-amount),
                'totalCoffeePurchased': FieldValue.increment(amount),
                'lastActiveAt': lastActiveAt,
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
              'transferTotalsBackfilled': true,
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
            txn.update(fromRef, {
              'currentBalance': FieldValue.increment(-amount),
              'totalReturned': FieldValue.increment(amount),
            });
            txn.update(toRef, {
              'currentBalance': FieldValue.increment(amount),
              'totalDistributed': FieldValue.increment(amount),
            });
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
      case 'updateIncome':
        {
          final docId = operation['docId'] as String;
          final data = Map<String, dynamic>.from(operation['payload'] as Map);
          await firestore.runTransaction((txn) async {
            final ref = firestore.collection('income_records').doc(docId);
            final snap = await txn.get(ref);
            if (!snap.exists) return;
            txn.update(ref, data);
          });
          break;
        }
      case 'deleteIncome':
        {
          final docId = operation['docId'] as String;
          await firestore.runTransaction((txn) async {
            final ref = firestore.collection('income_records').doc(docId);
            final snap = await txn.get(ref);
            if (!snap.exists) return;
            txn.delete(ref);
          });
          break;
        }
      case 'updateExpense':
        {
          final docId = operation['docId'] as String;
          final data = Map<String, dynamic>.from(operation['payload'] as Map);
          await firestore.runTransaction((txn) async {
            final ref = firestore.collection('expenses').doc(docId);
            final snap = await txn.get(ref);
            if (!snap.exists) return;
            txn.update(ref, data);
          });
          break;
        }
      case 'deleteExpense':
        {
          final docId = operation['docId'] as String;
          await firestore.runTransaction((txn) async {
            final ref = firestore.collection('expenses').doc(docId);
            final snap = await txn.get(ref);
            if (!snap.exists) return;
            txn.delete(ref);
          });
          break;
        }
      case 'updateTransaction':
        {
          final docId = operation['docId'] as String;
          final overrideReason = operation['overrideReason'] as String?;
          final payload =
              Map<String, dynamic>.from(operation['payload'] as Map);
          await firestore.runTransaction((txn) async {
            final ref = firestore.collection('transactions').doc(docId);
            final snap = await txn.get(ref);
            if (!snap.exists) return;
            final oldTx = MoneyTransaction.fromFirestore(
                Map<String, dynamic>.from(snap.data() as Map), docId);
            _enforceLock(oldTx, overrideReason: overrideReason, action: 'edit');
            if (oldTx.isTransfer ||
                payload['type']?.toString().toLowerCase() == 'transfer') {
              throw 'Transfers cannot be edited.';
            }
            final newTx = MoneyTransaction.fromFirestore(payload, docId);
            final oldWorkerRef =
                firestore.collection('workers').doc(oldTx.workerId);
            final newWorkerRef =
                firestore.collection('workers').doc(newTx.workerId);
            if (oldTx.workerId == newTx.workerId) {
              final oldUpdates = _balanceUpdates(oldTx, -1);
              if (oldUpdates.isNotEmpty) txn.update(oldWorkerRef, oldUpdates);
              final newUpdates = _balanceUpdates(newTx, 1);
              if (newUpdates.isNotEmpty) txn.update(newWorkerRef, newUpdates);
            } else {
              final oldUpdates = _balanceUpdates(oldTx, -1);
              if (oldUpdates.isNotEmpty) txn.update(oldWorkerRef, oldUpdates);
              final newUpdates = _balanceUpdates(newTx, 1);
              if (newUpdates.isNotEmpty) txn.update(newWorkerRef, newUpdates);
            }
            txn.update(ref, payload);
          });
          break;
        }
      case 'deleteTransaction':
        {
          final docId = operation['docId'] as String;
          final overrideReason = operation['overrideReason'] as String?;
          await firestore.runTransaction((txn) async {
            final ref = firestore.collection('transactions').doc(docId);
            final snap = await txn.get(ref);
            if (!snap.exists) return;
            final tx = MoneyTransaction.fromFirestore(
                Map<String, dynamic>.from(snap.data() as Map), docId);
            if (tx.isTransfer) {
              throw 'Use transfer delete for transfers.';
            }
            _enforceLock(tx, overrideReason: overrideReason, action: 'delete');
            final workerRef = firestore.collection('workers').doc(tx.workerId);
            final updates = _balanceUpdates(tx, -1);
            if (updates.isNotEmpty) txn.update(workerRef, updates);
            txn.delete(ref);
          });
          break;
        }
      case 'deleteTransfer':
        {
          final transferId = (operation['transferId'] as String?) ??
              (operation['opId'] as String);
          final overrideReason = operation['overrideReason'] as String?;
          final senderDocId = operation['senderDocId'] as String?;
          final receiverDocId = operation['receiverDocId'] as String?;
          // Prefer explicit docIds if present (stored at queue time), else fallback to query
          // Firestore transactions require all reads before writes — collect snaps first.
          if (senderDocId != null || receiverDocId != null) {
            final docIds = <String>[
              if (senderDocId != null) senderDocId,
              if (receiverDocId != null) receiverDocId,
            ];
            await firestore.runTransaction((txn) async {
              final snaps = <DocumentSnapshot<Map<String, dynamic>>>[];
              for (final docId in docIds) {
                final snap = await txn
                    .get(firestore.collection('transactions').doc(docId));
                snaps.add(snap as DocumentSnapshot<Map<String, dynamic>>);
              }
              for (final snap in snaps) {
                if (!snap.exists) continue;
                final tx = MoneyTransaction.fromFirestore(
                    Map<String, dynamic>.from(snap.data() as Map), snap.id);
                _enforceLock(tx,
                    overrideReason: overrideReason, action: 'delete');
                final workerRef =
                    firestore.collection('workers').doc(tx.workerId);
                final updates = _balanceUpdates(tx, -1);
                if (updates.isNotEmpty) txn.update(workerRef, updates);
                txn.delete(snap.reference);
              }
            });
            // Also handle any additional docs matching transferId that weren't in explicit list (safety)
            final snapshot = await firestore
                .collection('transactions')
                .where('transferId', isEqualTo: transferId)
                .get();
            final remaining =
                snapshot.docs.where((d) => !docIds.contains(d.id)).toList();
            if (remaining.isNotEmpty) {
              await firestore.runTransaction((txn) async {
                final snaps = <DocumentSnapshot<Map<String, dynamic>>>[];
                for (final doc in remaining) {
                  final snap = await txn
                      .get(firestore.collection('transactions').doc(doc.id));
                  snaps.add(snap as DocumentSnapshot<Map<String, dynamic>>);
                }
                for (final snap in snaps) {
                  if (!snap.exists) continue;
                  final tx = MoneyTransaction.fromFirestore(
                      Map<String, dynamic>.from(snap.data() as Map), snap.id);
                  _enforceLock(tx,
                      overrideReason: overrideReason, action: 'delete');
                  final workerRef =
                      firestore.collection('workers').doc(tx.workerId);
                  final updates = _balanceUpdates(tx, -1);
                  if (updates.isNotEmpty) txn.update(workerRef, updates);
                  txn.delete(snap.reference);
                }
              });
            }
            break;
          }
          final snapshot = await firestore
              .collection('transactions')
              .where('transferId', isEqualTo: transferId)
              .get();
          if (snapshot.docs.isEmpty) return;
          await firestore.runTransaction((txn) async {
            final snaps = <DocumentSnapshot<Map<String, dynamic>>>[];
            for (final doc in snapshot.docs) {
              final snap = await txn
                  .get(firestore.collection('transactions').doc(doc.id));
              snaps.add(snap as DocumentSnapshot<Map<String, dynamic>>);
            }
            for (final snap in snaps) {
              if (!snap.exists) continue;
              final tx = MoneyTransaction.fromFirestore(
                  Map<String, dynamic>.from(snap.data() as Map), snap.id);
              _enforceLock(tx,
                  overrideReason: overrideReason, action: 'delete');
              final workerRef =
                  firestore.collection('workers').doc(tx.workerId);
              final updates = _balanceUpdates(tx, -1);
              if (updates.isNotEmpty) txn.update(workerRef, updates);
              txn.delete(snap.reference);
            }
          });
          break;
        }
      case 'auditLog':
        {
          final data = Map<String, dynamic>.from(operation['payload'] as Map);
          await firestore.collection('audit_logs').add(data);
          break;
        }
      default:
        throw UnsupportedError('Unknown operation type: $type');
    }
  }

  int getPendingOperationsCount() {
    return _cache.getPendingOperations().length;
  }

  Future<void> clearSyncQueue() async {
    await _cache.clearPendingOperations();
  }
}
