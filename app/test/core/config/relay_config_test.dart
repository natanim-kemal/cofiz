import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

void main() {
  test('relay config uses dart-define, no hardcoded secrets', () {
    final content = File('lib/core/config/relay_config.dart').readAsStringSync();
    expect(content.contains('String.fromEnvironment'), isTrue);
    expect(content.contains(RegExp(r'https?://')), isFalse);
    expect(content.contains(RegExp(r'[0-9a-f]{32}')), isFalse);
  });

  test('sync executor wires _pushViaRelay for all 4 event types', () {
    final content =
        File('lib/core/services/offline_sync_service.dart').readAsStringSync();
    expect(content.contains('_pushViaRelay'), isTrue);
    expect(content.contains("'Money Received'"), isTrue);
    expect(content.contains("'Low Balance'"), isTrue);
    expect(content.contains("'Commission Earned!'"), isTrue);
    expect(content.contains("'Large Purchase'"), isTrue);
    expect(content.contains('isConfigured'), isTrue);
  });

  test('relay worker has auth gate + FCM + Firestore', () {
    final content =
        File('../workers/fcm-relay/src/index.js').readAsStringSync();
    expect(content.contains('X-Relay-Secret'), isTrue);
    expect(content.contains('fcm.googleapis.com'), isTrue);
    expect(content.contains('firestore.googleapis.com'), isTrue);
  });
}
