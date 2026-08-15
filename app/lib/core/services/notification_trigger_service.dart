import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/notification_model.dart';

/// Service for triggering automated notifications based on app events
class NotificationTriggerService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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
    } catch (e) {
      debugPrint('Error sending notification: $e');
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
      title: '💰 Money Received',
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

  /// Check and notify if worker balance is low after a purchase
  Future<void> checkLowBalance({
    required String workerId,
    required String workerUserId,
    required String workerName,
    required double newBalance,
  }) async {
    if (newBalance < lowBalanceThreshold && newBalance >= 0) {
      // Notify the worker
      await _sendNotification(
        targetUserId: workerUserId,
        title: '⚠️ Low Balance Alert',
        body:
            'Your balance is low (ETB ${newBalance.toStringAsFixed(0)}). Please return funds soon.',
        type: NotificationType.lowBalance,
        metadata: {
          'workerId': workerId,
          'balance': newBalance,
        },
      );

      // Also notify all admins
      await _notifyAllAdmins(
        title: '⚠️ Low Balance: $workerName',
        body:
            '$workerName has low balance (ETB ${newBalance.toStringAsFixed(0)})',
        type: NotificationType.lowBalance,
        metadata: {
          'workerId': workerId,
          'workerName': workerName,
          'balance': newBalance,
        },
      );
    }
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
      title: '🎉 Commission Earned!',
      body:
          'You earned ETB ${commission.toStringAsFixed(0)} commission. Total: ETB ${totalCommission.toStringAsFixed(0)}',
      type: NotificationType.commissionEarned,
      metadata: {
        'commission': commission,
        'totalCommission': totalCommission,
      },
    );
  }

  /// Notify admins about a large purchase
  Future<void> checkLargePurchase({
    required String workerId,
    required String workerName,
    required double amount,
    String? coffeeType,
    double? weight,
  }) async {
    if (amount >= largePurchaseThreshold) {
      await _notifyAllAdmins(
        title: '📦 Large Purchase: $workerName',
        body:
            '$workerName purchased ETB ${amount.toStringAsFixed(0)} ${coffeeType != null ? "($coffeeType)" : ""} - ${weight?.toStringAsFixed(1) ?? ""} Kg',
        type: NotificationType.purchaseRecorded,
        metadata: {
          'workerId': workerId,
          'workerName': workerName,
          'amount': amount,
          'coffeeType': coffeeType,
          'weight': weight,
        },
      );
    }
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
