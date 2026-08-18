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

  Future<void> initialize() async {
    await _cache.initialize();
    await _connectivity.initialize();

    // Listen for connectivity changes
    _connectivity.connectionStatus.listen((isOnline) {
      if (isOnline && !_isSyncing) {
        syncPendingOperations();
      }
    });
  }

  Future<void> syncPendingOperations() async {
    if (_isSyncing) return;

    _isSyncing = true;
    debugPrint('📡 Starting sync of pending operations...');

    try {
      final pendingOps = _cache.getPendingOperations();
      debugPrint('📡 Found ${pendingOps.length} pending operations');

      for (int i = 0; i < pendingOps.length; i++) {
        final operation = pendingOps[i];

        try {
          await _executeOperation(operation);
          await _cache.removePendingOperation(i);
          debugPrint('✅ Synced operation: ${operation['type']}');
        } catch (e) {
          debugPrint('❌ Failed to sync operation: $e');
          // Keep in queue for next sync attempt
        }
      }

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
