import 'package:flutter_test/flutter_test.dart';
import 'package:cofiz/core/utils/phone_utils.dart';

void main() {
  group('isValidE164', () {
    test('accepts +251911234567', () {
      expect(isValidE164('+251911234567'), isTrue);
    });
    test('rejects missing plus', () {
      expect(isValidE164('251911234567'), isFalse);
    });
    test('rejects too short', () {
      expect(isValidE164('+1234'), isFalse);
    });
    test('rejects letters', () {
      expect(isValidE164('+25191abc4567'), isFalse);
    });
  });

  group('normalizeE164', () {
    test('adds +251 to 0911234567', () {
      expect(normalizeE164('0911234567', defaultRegion: 'ET'), '+251911234567');
    });
    test('keeps existing +', () {
      expect(normalizeE164('+251911234567'), '+251911234567');
    });
  });

  group('sha256Hex', () {
    test('matches known vector for "abc"', () {
      expect(sha256Hex('abc'),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });
  });
}
