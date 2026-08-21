import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide display density presets. Lets any device reproduce a compact
/// (dense) or large look regardless of its logical width and OS font scale.
enum DisplayDensity { veryCompact, compact, normal, large }

class DensityProvider extends ChangeNotifier {
  static const String _prefKey = 'displayDensity';

  DisplayDensity _density = DisplayDensity.normal;

  DisplayDensity get density => _density;

  /// Multiplier applied on top of the system text scaler.
  double get textScaleFactor => switch (_density) {
        DisplayDensity.veryCompact => 0.8,
        DisplayDensity.compact => 0.9,
        DisplayDensity.normal => 1.0,
        DisplayDensity.large => 1.1,
      };

  /// Material density for buttons, chips, list tiles, etc. Large keeps
  /// standard spacing - the bigger text scale already opens the layout up.
  VisualDensity get visualDensity => switch (_density) {
        DisplayDensity.veryCompact =>
          const VisualDensity(horizontal: -3, vertical: -3),
        DisplayDensity.compact => VisualDensity.compact,
        DisplayDensity.normal => VisualDensity.standard,
        DisplayDensity.large => VisualDensity.standard,
      };

  DensityProvider() {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_prefKey);
      if (stored != null) {
        _density = DisplayDensity.values
            .firstWhere((d) => d.name == stored, orElse: () => _density);
        notifyListeners();
      }
    } catch (_) {
      // Pref read failure is non-fatal: keep the default.
    }
  }

  Future<void> setDensity(DisplayDensity density) async {
    if (density == _density) return;
    _density = density;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, density.name);
    } catch (_) {
      // Persist failure is non-fatal: the choice lives until restart.
    }
  }
}
