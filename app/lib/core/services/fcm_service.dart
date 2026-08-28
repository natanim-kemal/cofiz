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
  String? _boundUserId;
  StreamSubscription? _tokenRefreshSubscription;

  String? get currentToken => _currentToken;

  /// Register the background message handler. Cheap and must run as early
  /// as possible so cold-start notification launches are handled.
  void setup() {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  /// Initialize FCM - call this after Firebase.initializeApp()
  Future<void> initialize() async {
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

  DateTime? _lastSaveAt;
  String? _lastSaveUserId;

  Future<void> saveTokenForUser(String userId) async {
    if (_lastSaveUserId == userId &&
        _lastSaveAt != null &&
        DateTime.now().difference(_lastSaveAt!).inSeconds < 5) {
      debugPrint('FCM saveToken deduped for $userId');
      return;
    }
    _boundUserId = userId;
    try {
      await requestPermission();
    } catch (_) {}
    final token = await _messaging.getToken();
    if (token == null) {
      debugPrint('FCM getToken null for $userId');
      return;
    }
    if (_currentToken == token && _lastSaveUserId == userId) {
      debugPrint('FCM token unchanged for $userId');
      _lastSaveAt = DateTime.now();
      return;
    }
    _currentToken = token;
    _lastSaveUserId = userId;
    _lastSaveAt = DateTime.now();
    await _persistToken(userId, token);
  }

  Future<void> _persistToken(String userId, String token) async {
    try {
      await _firestore.collection('users').doc(userId).set({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('FCM token saved for $userId');
    } catch (e) {
      debugPrint('Error saving FCM token: $e');
    }
  }

  /// Remove FCM token for a user (on logout)
  Future<void> removeTokenForUser(String userId) async {
    _boundUserId = null;
    _lastSaveUserId = null;
    _lastSaveAt = null;
    try {
      await _firestore.collection('users').doc(userId).set({
        'fcmToken': FieldValue.delete(),
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('FCM token removed for user: $userId');
    } catch (e) {
      debugPrint('Error removing FCM token: $e');
    }
  }

  /// Update token in Firestore when it rotates - re-save for the bound user.
  Future<void> _updateStoredToken(String newToken) async {
    final uid = _boundUserId;
    if (uid == null) {
      debugPrint('Token refreshed before login; will bind on next auth.');
      return;
    }
    await _persistToken(uid, newToken);
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
