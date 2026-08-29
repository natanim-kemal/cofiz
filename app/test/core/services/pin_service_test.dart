import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
      case 'readAll':
        return Map<String, String>.from(store);
      case 'deleteAll':
        store.clear();
        return null;
      default:
        return null;
    }
  });

  setUp(() => store.clear());

  group('PinService', () {
    test('hasPin returns false when no pin set', () async {
      final s = PinService(storage: const FlutterSecureStorage());
      expect(await s.hasPin(), isFalse);
    });

    test('verifyPin returns true after setPin', () async {
      final s = PinService(storage: const FlutterSecureStorage());
      await s.setPin('482917');
      expect(await s.verifyPin('482917'), isTrue);
      expect(await s.verifyPin('739204'), isFalse);
    });

    test('changePin replaces the pin', () async {
      final s = PinService(storage: const FlutterSecureStorage());
      await s.setPin('482917');
      await s.changePin(oldPin: '482917', newPin: '739204');
      expect(await s.verifyPin('482917'), isFalse);
      expect(await s.verifyPin('739204'), isTrue);
    });

    test('clearPin removes the pin', () async {
      final s = PinService(storage: const FlutterSecureStorage());
      await s.setPin('482917');
      await s.clearPin();
      expect(await s.hasPin(), isFalse);
    });

    test('setPin throws on invalid length', () async {
      final s = PinService(storage: const FlutterSecureStorage());
      expect(() => s.setPin('12345'), throwsA(isA<ArgumentError>()));
      expect(() => s.setPin('1234567'), throwsA(isA<ArgumentError>()));
      expect(() => s.setPin('12345a'), throwsA(isA<ArgumentError>()));
    });

    test('setPin throws on weak PIN', () async {
      final s = PinService(storage: const FlutterSecureStorage());
      expect(() => s.setPin('000000'), throwsA(isA<ArgumentError>()));
      expect(() => s.setPin('123456'), throwsA(isA<ArgumentError>()));
      expect(() => s.setPin('111111'), throwsA(isA<ArgumentError>()));
    });

    test('verifyPin is per-uid isolated when uid provided', () async {
      final s = PinService(storage: const FlutterSecureStorage());
      await s.setPin('482917', uid: 'userA');
      await s.setPin('739204', uid: 'userB');
      expect(await s.verifyPin('482917', uid: 'userA'), isTrue);
      expect(await s.verifyPin('739204', uid: 'userB'), isTrue);
      expect(await s.verifyPin('739204', uid: 'userA'), isFalse);
    });
  });
}
