import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/relay_config.dart';
import '../models/user_model.dart';

class PingService {
  final FirebaseFirestore _firestore;
  final http.Client _httpClient;
  final String? _relayUrlOverride;
  final String? _relaySecretOverride;

  PingService({
    FirebaseFirestore? firestore,
    http.Client? httpClient,
    String? relayUrl,
    String? relaySecret,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _httpClient = httpClient ?? http.Client(),
        _relayUrlOverride = relayUrl,
        _relaySecretOverride = relaySecret;

  /// Fans out a ping from collector/viewer to all admins.
  ///
  /// Throws [ArgumentError] if note > 120 chars.
  /// Throws [StateError] if sender pinged within last 120 seconds.
  Future<void> pingAdmin({
    required String note,
    required String senderId,
    required String senderName,
    required UserRole senderRole,
  }) async {
    if (note.length > 120) {
      throw ArgumentError('note too long: ${note.length} > 120');
    }

    // Cooldown check via users/{uid}.lastPingAt
    final senderDoc = await _firestore.collection('users').doc(senderId).get();
    final data = senderDoc.data();
    if (data != null && data.containsKey('lastPingAt')) {
      final raw = data['lastPingAt'];
      final lastAtMs = _parseLastPingAt(raw);
      if (lastAtMs != null) {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        if (nowMs - lastAtMs < 120000) {
          throw StateError('cooldown: ping within 120s');
        }
      }
    }

    // Query admins
    final adminSnap = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'admin')
        .get();

    final type = senderRole == UserRole.viewer
        ? 'pingViewerToAdmin'
        : 'pingCollectorToAdmin';
    final title = 'Ping from $senderName (${senderRole.name})';
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // Batch write notifications
    if (adminSnap.docs.isNotEmpty) {
      final batch = _firestore.batch();
      for (final doc in adminSnap.docs) {
        final ref = _firestore.collection('notifications').doc();
        batch.set(ref, {
          'targetUserId': doc.id,
          'title': title,
          'body': note,
          'type': type,
          'isRead': false,
          'createdAt': nowMs,
          'senderId': senderId,
          'senderRole': senderRole.name,
          'senderName': senderName,
          'metadata': {'note': note},
        });
      }
      await batch.commit();
    }

    // Relay push per admin (best-effort) — ensure Firestore-sourced config is loaded
    String relayUrl = _relayUrlOverride ?? RelayConfig.relayUrl;
    String relaySecret = _relaySecretOverride ?? RelayConfig.relaySecret;
    if (_relayUrlOverride == null || _relaySecretOverride == null) {
      try {
        await RelayConfig.ensureInitialized(firestore: _firestore);
        relayUrl = _relayUrlOverride ?? RelayConfig.relayUrl;
        relaySecret = _relaySecretOverride ?? RelayConfig.relaySecret;
      } catch (_) {}
    }
    final isConfigured = relayUrl.isNotEmpty && relaySecret.isNotEmpty;
    if (isConfigured) {
      for (final doc in adminSnap.docs) {
        await _pushViaRelay(
          targetUserId: doc.id,
          title: title,
          body: note,
          type: type,
          relayUrl: relayUrl,
          relaySecret: relaySecret,
        );
      }
    } else {
      debugPrint('[Ping] relay not configured — skipping push');
    }

    // Update cooldown marker
    await _firestore.collection('users').doc(senderId).set(
      {'lastPingAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  int? _parseLastPingAt(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is double) return raw.toInt();
    if (raw is num) return raw.toInt();
    // Firestore Timestamp
    try {
      final ms = (raw as dynamic).millisecondsSinceEpoch;
      if (ms is int) return ms;
      if (ms is num) return ms.toInt();
    } catch (_) {}
    try {
      final date = (raw as dynamic).toDate() as DateTime;
      return date.millisecondsSinceEpoch;
    } catch (_) {}
    if (raw is DateTime) return raw.millisecondsSinceEpoch;
    if (raw is String) {
      final parsed = int.tryParse(raw);
      if (parsed != null) return parsed;
    }
    return null;
  }

  Future<void> _pushViaRelay({
    required String targetUserId,
    required String title,
    required String body,
    required String type,
    required String relayUrl,
    required String relaySecret,
  }) async {
    try {
      final res = await _httpClient.post(
        Uri.parse(relayUrl),
        headers: {
          'Content-Type': 'application/json',
          'X-Relay-Secret': relaySecret,
        },
        body: jsonEncode({
          'targetUserId': targetUserId,
          'title': title,
          'body': body,
          'type': type,
        }),
      );
      debugPrint('[Ping][Relay] $type -> $targetUserId: ${res.statusCode}');
    } catch (e) {
      debugPrint('[Ping][Relay] push failed: $e');
    }
  }
}
