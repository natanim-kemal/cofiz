class RelayConfig {
  static const String relayUrl = String.fromEnvironment('RELAY_URL');
  static const String relaySecret = String.fromEnvironment('RELAY_SECRET');

  static bool get isConfigured =>
      relayUrl.isNotEmpty && relaySecret.isNotEmpty;
}
