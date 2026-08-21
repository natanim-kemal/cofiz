import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cofiz/core/providers/density_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('DensityProvider', () {
    test('defaults to normal density', () {
      final provider = DensityProvider();
      expect(provider.density, DisplayDensity.normal);
      expect(provider.textScaleFactor, 1.0);
      expect(provider.visualDensity, VisualDensity.standard);
    });

    test('very compact preset is the densest', () {
      final provider = DensityProvider();
      provider.setDensity(DisplayDensity.veryCompact);

      expect(provider.textScaleFactor, lessThan(0.9));
      expect(
        provider.visualDensity,
        const VisualDensity(horizontal: -3, vertical: -3),
      );
    });

    test('compact preset scales text down and compacts components', () {
      final provider = DensityProvider();
      provider.setDensity(DisplayDensity.compact);

      expect(provider.density, DisplayDensity.compact);
      expect(provider.textScaleFactor, lessThan(1.0));
      expect(provider.visualDensity, VisualDensity.compact);
    });

    test('large preset scales text up and keeps standard spacing', () {
      final provider = DensityProvider();
      provider.setDensity(DisplayDensity.large);

      expect(provider.textScaleFactor, greaterThan(1.0));
      expect(provider.visualDensity, VisualDensity.standard);
    });

    test('setDensity persists the choice', () async {
      final provider = DensityProvider();
      await provider.setDensity(DisplayDensity.compact);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('displayDensity'), 'compact');
    });

    test('choice is restored on a new instance', () async {
      SharedPreferences.setMockInitialValues({'displayDensity': 'compact'});
      final provider = DensityProvider();
      // _load is async fire-and-forget in the constructor.
      await Future<void>.delayed(Duration.zero);

      expect(provider.density, DisplayDensity.compact);
    });

    test('unknown stored value falls back to normal', () async {
      SharedPreferences.setMockInitialValues({'displayDensity': 'bogus'});
      final provider = DensityProvider();
      await Future<void>.delayed(Duration.zero);

      expect(provider.density, DisplayDensity.normal);
    });
  });
}
