import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/cloudinary_config.dart';
import '../config/relay_config.dart';
import '../models/transaction_model.dart';
import '../utils/receipt_image_utils.dart';
import '../utils/transaction_balance.dart' as tb;
import '../utils/transaction_balance.dart' show TransactionLockedException;
import 'connectivity_service.dart';
import 'notification_trigger_service.dart';
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
      // Failed ops (attempts>=5) are retried with a fresh budget on every
      // sync pass; user-discarded ops are excluded via tombstones.
      await _cache.requeueFailedOperations();
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
      await _cache.replacePendingOperations(
          mergeRemainingWithCurrent(remaining, current, snapshotIds));
      await _cache.pruneDelivered();
      debugPrint('📡 Sync completed!');
    } catch (e) {
      debugPrint('❌ Sync failed: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Merges the ops that survived this sync pass ([remaining]) with the live
  /// box contents ([current], which may hold coalesced edits queued while the
  /// sync was in flight). For an opId present in both, the CURRENT entry wins
  /// whenever it differs from the remaining copy — the user's newer coalesced
  /// edit must not be clobbered by the stale pre-sync payload. Entries only in
  /// [current] are appended only when [snapshotIds] never saw their opId:
  /// snapshot ops that are no longer remaining were either delivered or moved
  /// to the failed box and must not be resurrected. Bookkeeping fields
  /// ('attempts') are ignored when comparing.
  @visibleForTesting
  static List<Map<String, dynamic>> mergeRemainingWithCurrent(
    List<Map<String, dynamic>> remaining,
    List<Map<String, dynamic>> current, [
    Set<String> snapshotIds = const {},
  ]) {
    final merged = [...remaining];
    for (final cur in current) {
      final id = cur['opId'] as String?;
      final idx = id == null ? -1 : merged.indexWhere((r) => r['opId'] == id);
      if (idx == -1) {
        if (!snapshotIds.contains(id)) merged.add(cur);
        continue;
      }
      if (!_sameOperation(merged[idx], cur)) merged[idx] = cur;
    }
    return merged;
  }

  /// Equality ignoring the 'attempts' bookkeeping field; payloads compared
  /// deep so a coalesced payload change is always detected.
  static bool _sameOperation(Map<String, dynamic> a, Map<String, dynamic> b) {
    bool deepEq(Object? x, Object? y) {
      if (x is Map && y is Map) {
        final mx = Map<String, dynamic>.from(x);
        final my = Map<String, dynamic>.from(y);
        if (mx.length != my.length) return false;
        for (final k in mx.keys) {
          if (!my.containsKey(k)) return false;
          if (!deepEq(mx[k], my[k])) return false;
        }
        return true;
      }
      return x == y;
    }

    final keysA = a.keys.where((k) => k != 'attempts').toSet();
    final keysB = b.keys.where((k) => k != 'attempts').toSet();
    if (keysA.length != keysB.length) return false;
    for (final k in keysA) {
      if (!keysB.contains(k)) return false;
      if (!deepEq(a[k], b[k])) return false;
    }
    return true;
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
            if (uploaded == null) {
              // Missing/corrupt receipt file: throw so the op stays queued
              // and retries instead of committing a transaction whose
              // receipt is silently lost forever.
              throw 'Receipt unavailable for $docId (compress/upload returned null)';
            }
            receiptUrl = uploaded;
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
          // Post-commit side effects (queue-first refactor orphaned the
          // old in-process trigger): fire best-effort, never fail the op.
          _fireTransactionNotifications(
            workerId: workerId,
            txType: txType,
            amount: amount,
            commissionAmount:
                (operation['commissionAmount'] as num?)?.toDouble(),
            coffeeType: operation['coffeeType'] as String?,
            coffeeWeight: (operation['coffeeWeight'] as num?)?.toDouble(),
          );
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
          // Receipt captured offline for an edit: upload before commit; a
          // null result throws so the op stays queued and retries rather
          // than losing the newly attached receipt.
          final localReceiptPath = operation['localReceiptPath'] as String?;
          String? uploadedReceiptUrl;
          if (localReceiptPath != null && localReceiptPath.isNotEmpty) {
            final uploaded = await _uploadReceipt(localReceiptPath);
            if (uploaded == null) {
              throw 'Receipt unavailable for $docId (compress/upload returned null)';
            }
            uploadedReceiptUrl = uploaded;
          }
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
            txn.update(ref, {
              ...payload,
              if (uploadedReceiptUrl != null) 'receiptUrl': uploadedReceiptUrl,
            });
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
            // Authoritative sufficiency recheck: deleting a distribution
            // removes money from the worker; never drive currentBalance
            // below zero even if the balance shifted since queue-time.
            if (tx.type.toLowerCase() == 'distribution') {
              final workerSnap = await txn
                  .get(firestore.collection('workers').doc(tx.workerId));
              final balance =
                  ((workerSnap.data()?['currentBalance'] as num?) ?? 0)
                      .toDouble();
              if (tx.amount > balance) {
                throw 'Insufficient balance. Available: ETB ${balance.toStringAsFixed(2)}, Required: ETB ${tx.amount.toStringAsFixed(2)}';
              }
            }
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

  /// Best-effort post-commit notifications for a synced createTransaction.
  /// Never throws - notification failures must not fail the (already
  /// committed) sync operation.
  void _fireTransactionNotifications({
    required String workerId,
    required String txType,
    required double amount,
    double? commissionAmount,
    String? coffeeType,
    double? coffeeWeight,
  }) {
    unawaited(() async {
      try {
        final workerDoc =
            await firestore.collection('workers').doc(workerId).get();
        if (!workerDoc.exists) {
          debugPrint('[Relay] worker doc not found: $workerId');
          return;
        }
        final data = workerDoc.data() ?? <String, dynamic>{};
        final workerUserId = data['userId'] as String?;
        if (workerUserId == null || workerUserId.isEmpty) {
          debugPrint('[Relay] worker $workerId has no userId linked');
          return;
        }
        final workerName = (data['name'] as String?) ?? 'Collector';
        final newBalance = ((data['currentBalance'] as num?) ?? 0).toDouble();
        final totalCommission =
            ((data['totalCommissionEarned'] as num?) ?? 0).toDouble();

        switch (txType.toLowerCase()) {
          case 'distribution':
            await NotificationTriggerService().notifyMoneyDistributed(
              workerId: workerId,
              workerUserId: workerUserId,
              workerName: workerName,
              amount: amount,
              adminName: null,
            );
            await _pushViaRelay(
              targetUserId: workerUserId,
              title: 'Money Received',
              body: 'You received ETB ${amount.toStringAsFixed(0)} from Admin',
              type: 'moneyDistributed',
            );
            break;
          case 'purchase':
            await NotificationTriggerService().checkLowBalance(
              workerId: workerId,
              workerUserId: workerUserId,
              workerName: workerName,
              newBalance: newBalance,
            );
            if (newBalance < NotificationTriggerService.lowBalanceThreshold &&
                newBalance >= 0) {
              await _pushViaRelay(
                targetUserId: workerUserId,
                title: 'Low Balance',
                body:
                    'Your balance is low (ETB ${newBalance.toStringAsFixed(0)}).',
                type: 'lowBalance',
              );
            }
            if ((commissionAmount ?? 0) > 0) {
              await NotificationTriggerService().notifyCommissionEarned(
                workerUserId: workerUserId,
                workerName: workerName,
                commission: commissionAmount!,
                totalCommission: totalCommission,
              );
              await _pushViaRelay(
                targetUserId: workerUserId,
                title: 'Commission Earned!',
                body:
                    'You earned ETB ${commissionAmount!.toStringAsFixed(0)} commission.',
                type: 'commissionEarned',
              );
            }
            await NotificationTriggerService().checkLargePurchase(
              workerId: workerId,
              workerName: workerName,
              amount: amount,
              coffeeType: coffeeType,
              weight: coffeeWeight,
            );
            if (amount >= NotificationTriggerService.largePurchaseThreshold) {
              await _pushViaRelay(
                targetUserId: workerUserId,
                title: 'Large Purchase',
                body:
                    'Purchased ETB ${amount.toStringAsFixed(0)}${coffeeType != null ? " ($coffeeType)" : ""}',
                type: 'purchaseRecorded',
              );
            }
            break;
        }
      } catch (e) {
        debugPrint('[Sync] post-commit notification failed: $e');
      }
    }());
  }

  static final http.Client _relayHttpClient = http.Client();

  /// Best-effort push through the Cloudflare relay (free FCM path, no
  /// Google billing). Silent no-op when the relay isn't configured.
  /// Prefers Firestore-sourced config; falls back to dart-define.
  Future<void> _pushViaRelay({
    required String targetUserId,
    required String title,
    required String body,
    required String type,
  }) async {
    try {
      await RelayConfig.ensureInitialized(firestore: firestore);
    } catch (_) {}
    if (!RelayConfig.isConfigured) {
      debugPrint('[Relay] SKIPPED - not configured. '
          'Set settings/app relayUrl/relaySecret or build with --dart-define=RELAY_URL=... --dart-define=RELAY_SECRET=...');
      return;
    }
    try {
      final res = await _relayHttpClient.post(
        Uri.parse(RelayConfig.relayUrl),
        headers: {
          'Content-Type': 'application/json',
          'X-Relay-Secret': RelayConfig.relaySecret,
        },
        body: jsonEncode({
          'targetUserId': targetUserId,
          'title': title,
          'body': body,
          'type': type,
        }),
      );
      debugPrint(
          '[Relay] $type -> $targetUserId: ${res.statusCode} ${res.body}');
    } catch (e) {
      debugPrint('[Relay] push failed: $e');
    }
  }

  int getPendingOperationsCount() {
    return _cache.getPendingOperations().length;
  }

  Future<void> clearSyncQueue() async {
    await _cache.clearPendingOperations();
  }
}
