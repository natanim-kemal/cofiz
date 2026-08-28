import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class RelayConfig {
  // Compile-time fallback (dart-define) — kept for backward compat.
  static const String _envRelayUrl = String.fromEnvironment('RELAY_URL');
  static const String _envRelaySecret = String.fromEnvironment('RELAY_SECRET');

  static String _relayUrl = _envRelayUrl;
  static String _relaySecret = _envRelaySecret;
  static bool _initialized = false;

  /// Synchronous accessors — reflect the latest cached value.
  /// Prefer ensuring [init] has been awaited at app startup.
  static String get relayUrl => _relayUrl;
  static String get relaySecret => _relaySecret;

  static bool get isConfigured => relayUrl.isNotEmpty && relaySecret.isNotEmpty;

  /// Fetches relayUrl/relaySecret from Firestore `settings/app` at runtime.
  /// Falls back to dart-define values if Firestore is unavailable or fields
  /// are absent. Idempotent — subsequent calls are no-ops unless [force] is true.
  static Future<void> init({
    FirebaseFirestore? firestore,
    bool force = false,
  }) async {
    if (_initialized && !force) return;
    try {
      final fs = firestore ?? FirebaseFirestore.instance;
      final doc = await fs
          .collection('settings')
          .doc('app')
          .get()
          .timeout(const Duration(seconds: 2));
      if (doc.exists) {
        final data = doc.data();
        if (data != null) {
          final url = data['relayUrl'];
          final secret = data['relaySecret'];
          if (url is String && url.isNotEmpty) _relayUrl = url;
          if (secret is String && secret.isNotEmpty) _relaySecret = secret;
          debugPrint(
              '[RelayConfig] loaded from Firestore: url=${_relayUrl.isNotEmpty ? "set" : "empty"} secret=${_relaySecret.isNotEmpty ? "set" : "empty"}');
        }
      } else {
        debugPrint('[RelayConfig] settings/app not found — using env fallback');
      }
    } catch (e) {
      debugPrint(
          '[RelayConfig] Firestore fetch failed, using env fallback: $e');
    }
    _initialized = true;
  }

  /// Ensures [init] has run once; call before relying on Firestore-sourced values.
  static Future<void> ensureInitialized({FirebaseFirestore? firestore}) async {
    if (!_initialized) await init(firestore: firestore);
  }

  @visibleForTesting
  static void setForTest({String? url, String? secret}) {
    if (url != null) _relayUrl = url;
    if (secret != null) _relaySecret = secret;
    _initialized = true;
  }

  @visibleForTesting
  static void resetForTest() {
    _relayUrl = _envRelayUrl;
    _relaySecret = _envRelaySecret;
    _initialized = false;
  }

  @visibleForTesting
  static bool get isInitialized => _initialized;
}
