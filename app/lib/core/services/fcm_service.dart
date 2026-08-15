import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'notification_service.dart';

/// Background message handler - must be top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Handling background message: ${message.messageId}');
}

class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _currentToken;
  StreamSubscription? _tokenRefreshSubscription;

  String? get currentToken => _currentToken;

  /// Initialize FCM - call this after Firebase.initializeApp()
  Future<void> initialize() async {
    // Set up background message handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Request permission
    await requestPermission();

    // Get initial token
    _currentToken = await _messaging.getToken();
    debugPrint('FCM Token: $_currentToken');

    // Listen for token refresh
    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen((newToken) {
      debugPrint('FCM Token refreshed: $newToken');
      _currentToken = newToken;
      // If user is logged in, update their token
      _updateStoredToken(newToken);
    });

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle notification taps when app is in background/terminated
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Check if app was opened from a terminated state via notification
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }
  }

  /// Request notification permission
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    final isAuthorized =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;

    debugPrint('FCM Permission: ${settings.authorizationStatus}');
    return isAuthorized;
  }

  /// Save FCM token for a user
  Future<void> saveTokenForUser(String userId) async {
    if (_currentToken == null) {
      _currentToken = await _messaging.getToken();
    }

    if (_currentToken != null) {
      try {
        await _firestore.collection('users').doc(userId).update({
          'fcmToken': _currentToken,
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        });
        debugPrint('FCM token saved for user: $userId');
      } catch (e) {
        debugPrint('Error saving FCM token: $e');
      }
    }
  }

  /// Remove FCM token for a user (on logout)
  Future<void> removeTokenForUser(String userId) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'fcmToken': FieldValue.delete(),
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      });
      debugPrint('FCM token removed for user: $userId');
    } catch (e) {
      debugPrint('Error removing FCM token: $e');
    }
  }

  /// Update token in Firestore when it refreshes
  Future<void> _updateStoredToken(String newToken) async {
    // This would need the current user ID - we'll handle this in AuthProvider
    debugPrint(
        'Token refresh detected. Update will happen on next auth check.');
  }

  /// Handle foreground messages - show local notification
  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('Foreground message received: ${message.notification?.title}');

    final notification = message.notification;
    if (notification != null) {
      // Show local notification using NotificationService
      NotificationService().showNotification(
        id: message.hashCode,
        title: notification.title ?? 'New Notification',
        body: notification.body ?? '',
        payload: message.data['notificationId'],
      );
    }
  }

  /// Handle notification tap
  void _handleNotificationTap(RemoteMessage message) {
    debugPrint('Notification tapped: ${message.data}');
    // Navigate to notifications screen or specific content
    // This would typically use a navigation service or global key
  }

  /// Dispose resources
  void dispose() {
    _tokenRefreshSubscription?.cancel();
  }
}
