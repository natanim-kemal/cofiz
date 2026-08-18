import 'package:flutter/foundation.dart';
import 'connectivity_service.dart';
import 'offline_cache_service.dart';

class OfflineSyncService {
  static final OfflineSyncService _instance = OfflineSyncService._internal();
  factory OfflineSyncService() => _instance;
  OfflineSyncService._internal();

  final ConnectivityService _connectivity = ConnectivityService();
  final OfflineCacheService _cache = OfflineCacheService();

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
    // This would need to be injected with providers
    // For now, we'll just log it
    debugPrint('Executing: ${operation['type']}');

    // In a real implementation, you would:
    // - Get the appropriate provider
    // - Call the service method with the cached data
    // - Handle success/failure

    throw UnimplementedError('Sync execution needs provider injection');
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
