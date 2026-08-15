import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/audit_log_model.dart';

class AuditService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'audit_logs';

  /// Log an action
  Future<void> log({
    required String userId,
    required String userName,
    required AuditAction action,
    String? targetId,
    String? targetName,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final log = AuditLog(
        id: '',
        userId: userId,
        userName: userName,
        action: action,
        targetId: targetId,
        targetName: targetName,
        metadata: metadata,
        timestamp: DateTime.now(),
      );

      await _firestore.collection(_collection).add(log.toFirestore());
    } catch (e) {
      // Silent fail - don't let audit logging break the app
      print('Audit log failed: $e');
    }
  }

  /// Get audit logs with pagination
  Stream<List<AuditLog>> getLogsStream({int limit = 50}) {
    return _firestore
        .collection(_collection)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => AuditLog.fromFirestore(doc.data(), doc.id))
            .toList());
  }

  /// Get logs for specific user
  Stream<List<AuditLog>> getUserLogsStream(String userId, {int limit = 50}) {
    return _firestore
        .collection(_collection)
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => AuditLog.fromFirestore(doc.data(), doc.id))
            .toList());
  }

  /// Get logs for specific action
  Stream<List<AuditLog>> getActionLogsStream(AuditAction action,
      {int limit = 50}) {
    return _firestore
        .collection(_collection)
        .where('action', isEqualTo: action.name)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => AuditLog.fromFirestore(doc.data(), doc.id))
            .toList());
  }

  /// Delete old logs (cleanup)
  Future<void> deleteOldLogs(DateTime before) async {
    try {
      final snapshot = await _firestore
          .collection(_collection)
          .where('timestamp', isLessThan: before.millisecondsSinceEpoch)
          .get();

      final batch = _firestore.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      print('Failed to delete old logs: $e');
    }
  }
}
