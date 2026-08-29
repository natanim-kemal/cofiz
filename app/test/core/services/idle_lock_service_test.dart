import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cofiz/core/providers/lock_state_provider.dart';
import 'package:cofiz/core/services/idle_lock_service.dart';
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
        store[call.arguments['key']] = call.arguments['value'] as String;
        return null;
      case 'delete':
        store.remove(call.arguments['key']);
        return null;
      default:
        return null;
    }
  });
  setUp(() => store.clear());

  test('bump() resets the timer; expiry calls lock()', () async {
    final svc = PinService(storage: const FlutterSecureStorage());
    await svc.setPin('482917');
    final lsp = LockStateProvider(pinService: svc);
    await lsp.initialize();
    expect(lsp.state, PinLockState.unlocked);
    final idle = IdleLockService(
      lockState: lsp,
      duration: const Duration(milliseconds: 60),
    );
    idle.attach();
    idle.bump();
    expect(lsp.state, PinLockState.unlocked);
    await Future.delayed(const Duration(milliseconds: 150));
    expect(lsp.state, PinLockState.locked);
    idle.detach();
  });

  test('bump respects cooldown - does not re-arm during cooldown', () async {
    final svc = PinService(storage: const FlutterSecureStorage());
    await svc.setPin('482917');
    final lsp = LockStateProvider(pinService: svc);
    await lsp.initialize();
    lsp.lock();
    // 3 fails -> cooldown
    for (var i = 0; i < 3; i++) {
      await lsp.attemptUnlock('739204');
    }
    expect(lsp.isInCooldown, isTrue);
    final idle = IdleLockService(lockState: lsp, duration: const Duration(milliseconds: 60));
    idle.bump();
    // bump should be no-op while in cooldown or locked
    expect(lsp.state, PinLockState.locked);
    idle.detach();
  });
}
