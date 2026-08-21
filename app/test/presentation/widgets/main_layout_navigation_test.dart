import 'package:flutter_test/flutter_test.dart';
import 'package:cofiz/main.dart';

void main() {
  group('shouldAnimateTabSwitch', () {
    test('adjacent tabs animate', () {
      expect(shouldAnimateTabSwitch(0, 1), isTrue);
      expect(shouldAnimateTabSwitch(1, 0), isTrue);
      expect(shouldAnimateTabSwitch(2, 3), isTrue);
      expect(shouldAnimateTabSwitch(3, 2), isTrue);
    });

    test('non-adjacent tabs jump instead of scrolling across pages', () {
      expect(shouldAnimateTabSwitch(0, 2), isFalse);
      expect(shouldAnimateTabSwitch(0, 3), isFalse);
      expect(shouldAnimateTabSwitch(1, 3), isFalse);
      expect(shouldAnimateTabSwitch(3, 0), isFalse);
      expect(shouldAnimateTabSwitch(2, 0), isFalse);
    });

    test('same index does not animate', () {
      expect(shouldAnimateTabSwitch(2, 2), isFalse);
    });
  });
}
