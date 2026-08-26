/// Cloudflare Worker relay that sends FCM pushes without Google billing.
///
/// Deploy workers/fcm-relay (see its README), then paste your worker URL
/// and the RELAY_SECRET here. When [isConfigured] is false the app skips
/// the relay call silently (in-app notifications still work).
class RelayConfig {
  static const String relayUrl = '';
  static const String relaySecret = '';

  static bool get isConfigured =>
      relayUrl.isNotEmpty && relaySecret.isNotEmpty;
}
