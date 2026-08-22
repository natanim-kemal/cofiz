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
      expect(provider.scale, 1.0);
      expect(provider.density, DisplayDensity.normal);
      expect(provider.textScaleFactor, 1.0);
      expect(provider.visualDensity, VisualDensity.standard);
    });

    test('very compact via slider', () async {
      final provider = DensityProvider();
      await provider.setScale(0.6);

      expect(provider.scale, 0.6);
      expect(provider.textScaleFactor, 0.6);
      expect(
        provider.visualDensity,
        const VisualDensity(horizontal: -3, vertical: -3),
      );
    });

    test('compact preset scales text down and compacts components', () async {
      final provider = DensityProvider();
      await provider.setScale(0.8);

      expect(provider.scale, 0.8);
      expect(provider.textScaleFactor, 0.8);
      expect(provider.visualDensity, VisualDensity.compact);
    });

    test('large preset scales text up and keeps standard spacing', () async {
      final provider = DensityProvider();
      await provider.setScale(1.2);

      expect(provider.textScaleFactor, greaterThan(1.0));
      expect(provider.visualDensity, VisualDensity.standard);
    });

    test('scale snaps to 0.1 and clamps to 0.6..1.2', () async {
      final provider = DensityProvider();
      await provider.setScale(0.65);
      expect(provider.scale, 0.7);
      await provider.setScale(2.0);
      expect(provider.scale, 1.2);
      await provider.setScale(0.1);
      expect(provider.scale, 0.6);
    });

    test('setScale persists the choice', () async {
      final provider = DensityProvider();
      await provider.setScale(0.9);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('displayDensityScale'), 0.9);
    });

    test('legacy setDensity maps to a scale', () async {
      final provider = DensityProvider();
      await provider.setDensity(DisplayDensity.veryCompact);
      expect(provider.scale, 0.6);
      await provider.setDensity(DisplayDensity.compact);
      expect(provider.scale, 0.8);
    });

    test('choice is restored on a new instance', () async {
      SharedPreferences.setMockInitialValues({'displayDensityScale': 0.8});
      final provider = DensityProvider();
      await Future<void>.delayed(Duration.zero);

      expect(provider.scale, 0.8);
    });

    test('migrates legacy enum string', () async {
      SharedPreferences.setMockInitialValues({'displayDensity': 'compact'});
      final provider = DensityProvider();
      await Future<void>.delayed(Duration.zero);

      expect(provider.scale, 0.8);
    });

    test('unknown stored value falls back to normal', () async {
      SharedPreferences.setMockInitialValues({'displayDensity': 'bogus'});
      final provider = DensityProvider();
      await Future<void>.delayed(Duration.zero);

      expect(provider.density, DisplayDensity.normal);
    });
  });
}
