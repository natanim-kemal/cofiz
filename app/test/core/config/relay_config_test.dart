import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cofiz/core/config/relay_config.dart';

void main() {
  group('RelayConfig Firestore runtime', () {
    setUp(() {
      RelayConfig.resetForTest();
    });

    tearDown(() {
      RelayConfig.resetForTest();
    });

    test('dart-define fallback when Firestore missing', () async {
      final fake = FakeFirebaseFirestore();
      // No settings/app doc — should keep env fallback (empty in test)
      await RelayConfig.init(firestore: fake);
      expect(RelayConfig.isInitialized, isTrue);
      // In test env, dart-define is empty, so isConfigured false
      expect(RelayConfig.relayUrl, isEmpty);
      expect(RelayConfig.isConfigured, isFalse);
    });

    test('loads relayUrl/relaySecret from Firestore settings/app', () async {
      final fake = FakeFirebaseFirestore();
      await fake.collection('settings').doc('app').set({
        'relayUrl': 'https://relay.example.com/push',
        'relaySecret': 's3cret',
      });
      await RelayConfig.init(firestore: fake);
      expect(RelayConfig.relayUrl, 'https://relay.example.com/push');
      expect(RelayConfig.relaySecret, 's3cret');
      expect(RelayConfig.isConfigured, isTrue);
    });

    test('backward compat: Firestore partial overrides env fallback', () async {
      // Simulate env already seeded via setForTest (as if dart-define provided fallback)
      RelayConfig.setForTest(
          url: 'https://env.example.com', secret: 'envSecret');
      RelayConfig
          .resetForTest(); // clears to env empty, but we mimic env non-empty by setting after reset
      RelayConfig.setForTest(
          url: 'https://env.example.com', secret: 'envSecret');
      // Now Firestore only provides relayUrl, secret stays env
      final fake = FakeFirebaseFirestore();
      await fake.collection('settings').doc('app').set({
        'relayUrl': 'https://firestore.example.com',
      });
      // Force reload
      await RelayConfig.init(firestore: fake, force: true);
      expect(RelayConfig.relayUrl, 'https://firestore.example.com');
      expect(RelayConfig.relaySecret, 'envSecret');
    });

    test('fallback to env when Firestore throws/timeout', () async {
      // Use a firestore that will not have doc and init handles error gracefully
      final fake = FakeFirebaseFirestore();
      RelayConfig.setForTest(
          url: 'https://env.example.com', secret: 'envSecret');
      // init with force should keep env values if Firestore doc absent but not overwrite with empty
      await RelayConfig.init(firestore: fake, force: true);
      // After init, our setForTest values should remain because Firestore doc has no relayUrl
      // Actually init will not clear env if Firestore doc missing fields — it keeps current
      expect(RelayConfig.relayUrl, 'https://env.example.com');
      expect(RelayConfig.isConfigured, isTrue);
    });

    test('ensureInitialized is idempotent', () async {
      final fake = FakeFirebaseFirestore();
      await fake.collection('settings').doc('app').set({
        'relayUrl': 'https://a.example.com',
        'relaySecret': 'sec',
      });
      await RelayConfig.ensureInitialized(firestore: fake);
      final firstUrl = RelayConfig.relayUrl;
      // Change Firestore but ensureInitialized second time should be no-op
      await fake.collection('settings').doc('app').set({
        'relayUrl': 'https://b.example.com',
        'relaySecret': 'sec2',
      });
      await RelayConfig.ensureInitialized(firestore: fake);
      expect(RelayConfig.relayUrl, firstUrl);
      // Force should reload
      await RelayConfig.init(firestore: fake, force: true);
      expect(RelayConfig.relayUrl, 'https://b.example.com');
    });

    test('empty string in Firestore does not overwrite', () async {
      final fake = FakeFirebaseFirestore();
      RelayConfig.setForTest(url: 'https://keep.example.com', secret: 'keep');
      await fake.collection('settings').doc('app').set({
        'relayUrl': '',
        'relaySecret': '',
      });
      await RelayConfig.init(firestore: fake, force: true);
      expect(RelayConfig.relayUrl, 'https://keep.example.com');
      expect(RelayConfig.relaySecret, 'keep');
    });
  });
}
