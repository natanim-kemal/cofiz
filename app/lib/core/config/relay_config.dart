/// Cloudflare Worker relay that sends FCM pushes without Google billing.
///
/// Deploy workers/fcm-relay (see its README), then paste your worker URL
/// and the RELAY_SECRET here. When [isConfigured] is false the app skips
/// the relay call silently (in-app notifications still work).
class RelayConfig {
  static const String relayUrl =
      'https://cofiz-fcm-relay.kemalnatanim.workers.dev/';
  static const String relaySecret =
      'd152db415c8d4b6ad3e82a81dec0e35de326144411f388a278e8d8b3ed92ff72';

  static bool get isConfigured =>
      relayUrl.isNotEmpty && relaySecret.isNotEmpty;
}
