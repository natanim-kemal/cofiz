import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/notification_model.dart';

/// Service for triggering automated notifications based on app events
class NotificationTriggerService {
  final FirebaseFirestore _firestore;

  NotificationTriggerService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  // Thresholds for notifications
  static const double lowBalanceThreshold = 500.0;
  static const double largePurchaseThreshold = 10000.0;

  /// Send notification to a specific user
  Future<void> _sendNotification({
    required String targetUserId,
    required String title,
    required String body,
    required NotificationType type,
    String? senderName,
    String? senderId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await _firestore.collection('notifications').add({
        'targetUserId': targetUserId,
        'title': title,
        'body': body,
        'type': type.name,
        'isRead': false,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'senderName': senderName ?? 'System',
        'senderId': senderId,
        'metadata': metadata,
      });
      debugPrint('Notification sent: $title to $targetUserId');
      await _maybeQueueEmail(
        targetUserId: targetUserId,
        title: title,
        body: body,
      );
    } catch (e) {
      debugPrint('Error sending notification: $e');
    }
  }

  /// Queue an email for the target user via the Trigger Email extension,
  /// but only when the user has verified their address AND opted in to
  /// email notifications (users/{uid}.emailNotificationsEnabled, synced
  /// from SettingsProvider). Push delivery is unaffected.
  Future<void> _maybeQueueEmail({
    required String targetUserId,
    required String title,
    required String body,
  }) async {
    try {
      final userDoc =
          await _firestore.collection('users').doc(targetUserId).get();
      final data = userDoc.data();
      if (data == null) return;
      final verified = data['emailVerified'] == true;
      final optedIn = data['emailNotificationsEnabled'] == true;
      if (!verified || !optedIn) return;

      final email = data['email'];
      if (email is! String || email.isEmpty) return;

      await _firestore.collection('mail').add({
        'to': email,
        'template': {
          'name': 'notification',
          'data': {'title': title, 'body': body},
        },
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
      debugPrint('Email queued: $title to $email');
    } catch (e) {
      debugPrint('Error queueing notification email: $e');
    }
  }

  /// Notify worker when money is distributed to them
  Future<void> notifyMoneyDistributed({
    required String workerId,
    required String workerUserId,
    required String workerName,
    required double amount,
    String? adminName,
  }) async {
    await _sendNotification(
      targetUserId: workerUserId,
      title: 'Money Received',
      body:
          'You received ETB ${amount.toStringAsFixed(0)} from ${adminName ?? 'Admin'}',
      type: NotificationType.moneyDistributed,
      senderName: adminName ?? 'Admin',
      metadata: {
        'workerId': workerId,
        'amount': amount,
      },
    );
  }

  /// Check and notify admins if worker balance drops below threshold after
  /// a purchase. Admin echo removed — bells are ping-only (collector/viewer
  /// → admin via PingService). Kept as no-op for backward compat.
  Future<void> checkLowBalance({
    required String workerId,
    required String workerUserId,
    required String workerName,
    required double newBalance,
  }) async {
    // no-op: admin echo removed — bells are ping-only.
    // Intentionally does not create notifications or mail.
    return;
  }

  /// Notify worker when they earn commission
  Future<void> notifyCommissionEarned({
    required String workerUserId,
    required String workerName,
    required double commission,
    required double totalCommission,
  }) async {
    await _sendNotification(
      targetUserId: workerUserId,
      title: 'Commission Earned!',
      body:
          'You earned ETB ${commission.toStringAsFixed(0)} commission. Total: ETB ${totalCommission.toStringAsFixed(0)}',
      type: NotificationType.commissionEarned,
      metadata: {
        'commission': commission,
        'totalCommission': totalCommission,
      },
    );
  }

  /// Notify admins about a large purchase. Admin echo removed — ping-only.
  Future<void> checkLargePurchase({
    required String workerId,
    required String workerName,
    required double amount,
    String? coffeeType,
    double? weight,
  }) async {
    // no-op: admin echo removed — bells are ping-only.
    return;
  }

  /// Notify all admin users
  Future<void> _notifyAllAdmins({
    required String title,
    required String body,
    required NotificationType type,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      // Get all admin users
      final adminSnapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'admin')
          .get();

      for (var doc in adminSnapshot.docs) {
        await _sendNotification(
          targetUserId: doc.id,
          title: title,
          body: body,
          type: type,
          senderName: 'System',
          metadata: metadata,
        );
      }
    } catch (e) {
      debugPrint('Error notifying admins: $e');
    }
  }

  /// Notify all viewers (read-only users)
  Future<void> _notifyAllViewers({
    required String title,
    required String body,
    required NotificationType type,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final viewerSnapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'viewer')
          .get();

      for (var doc in viewerSnapshot.docs) {
        await _sendNotification(
          targetUserId: doc.id,
          title: title,
          body: body,
          type: type,
          senderName: 'System',
          metadata: metadata,
        );
      }
    } catch (e) {
      debugPrint('Error notifying viewers: $e');
    }
  }
}
