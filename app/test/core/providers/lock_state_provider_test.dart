import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cofiz/core/providers/lock_state_provider.dart';
import 'package:cofiz/core/services/pin_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final Map<String, String> store = {};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    switch (call.method) {
      case 'read':
        return store[call.arguments['key']];
      case 'write':
        store[call.arguments['key']] = call.arguments['value'];
        return null;
      case 'delete':
        store.remove(call.arguments['key']);
        return null;
      default:
        return null;
    }
  });

  setUp(() => store.clear());

  group('LockStateProvider', () {
    test('initialize sets awaitingFirstSetup if no PIN', () async {
      final p = LockStateProvider(pinService: PinService(storage: const FlutterSecureStorage()));
      await p.initialize();
      expect(p.state, PinLockState.awaitingFirstSetup);
    });

    test('lock moves to locked and attemptUnlock with right PIN unlocks', () async {
      final svc = PinService(storage: const FlutterSecureStorage());
      await svc.setPin('482917');
      final p = LockStateProvider(pinService: svc);
      await p.initialize();
      p.lock();
      expect(p.state, PinLockState.locked);
      final ok = await p.attemptUnlock('482917');
      expect(ok, isTrue);
      expect(p.state, PinLockState.unlocked);
    });

    test('cooldown after 3 wrong attempts', () async {
      final svc = PinService(storage: const FlutterSecureStorage());
      await svc.setPin('482917');
      final p = LockStateProvider(pinService: svc);
      await p.initialize();
      p.lock();
      for (var i = 0; i < 3; i++) {
        await p.attemptUnlock('739204');
      }
      expect(p.failedAttempts, 3);
      expect(p.isInCooldown, isTrue);
    });

    test('5 wrong attempts triggers force sign-out', () async {
      final svc = PinService(storage: const FlutterSecureStorage());
      await svc.setPin('482917');
      final p = LockStateProvider(pinService: svc);
      await p.initialize();
      p.lock();
      for (var i = 0; i < 5; i++) {
        // clear cooldown between attempts to allow 5 real tries
        if (p.isInCooldown) p.clearCooldown();
        await p.attemptUnlock('739204');
      }
      expect(p.failedAttempts, 5);
      expect(p.shouldForceSignOut, isTrue);
    });
  });
}
