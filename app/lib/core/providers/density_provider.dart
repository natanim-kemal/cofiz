import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide display density. Backed by a continuous scale persisted in
/// SharedPreferences so a Slider can offer fine-grained control (0.6–1.2).
/// Older installs stored an enum string under the same key — that is
/// migrated automatically.
enum DisplayDensity { veryCompact, compact, normal, large }

class DensityProvider extends ChangeNotifier {
  static const String _prefKey = 'displayDensity';
  static const String _scaleKey = 'displayDensityScale';
  static const double minScale = 0.6;
  static const double maxScale = 1.2;

  double _scale = 1.0;

  double get scale => _scale;
  double get textScaleFactor => _scale;

  /// Kept for backwards-compat callers that still read the enum. Maps the
  /// continuous scale to the nearest legacy bucket.
  DisplayDensity get density {
    if (_scale <= 0.65) return DisplayDensity.veryCompact;
    if (_scale <= 0.85) return DisplayDensity.compact;
    if (_scale <= 1.05) return DisplayDensity.normal;
    return DisplayDensity.large;
  }

  VisualDensity get visualDensity {
    if (_scale <= 0.7) return const VisualDensity(horizontal: -3, vertical: -3);
    if (_scale <= 0.85) return VisualDensity.compact;
    return VisualDensity.standard;
  }

  DensityProvider() {
    _load();
  }

  double _snap(double v) => double.parse(v.toStringAsFixed(1));

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(_scaleKey)) {
        final s = prefs.getDouble(_scaleKey);
        if (s != null) {
          _scale = _snap(s.clamp(minScale, maxScale));
          notifyListeners();
          return;
        }
      }
      // Migrate legacy enum string if present.
      final stored = prefs.getString(_prefKey);
      if (stored != null) {
        _scale = switch (stored) {
          'veryCompact' => 0.6,
          'compact' => 0.8,
          'large' => 1.1,
          _ => 1.0,
        };
        // Persist in the new format.
        await prefs.setDouble(_scaleKey, _scale);
        notifyListeners();
      }
    } catch (_) {
      // Pref read failure is non-fatal: keep the default.
    }
  }

  Future<void> setScale(double value) async {
    final snapped = _snap(value.clamp(minScale, maxScale));
    if (snapped == _scale) return;
    _scale = snapped;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_scaleKey, _scale);
    } catch (_) {
      // Persist failure is non-fatal: the choice lives until restart.
    }
  }

  /// Legacy setter — maps the preset to its scale. Kept so older call
  /// sites and tests keep compiling.
  Future<void> setDensity(DisplayDensity density) async {
    final v = switch (density) {
      DisplayDensity.veryCompact => 0.6,
      DisplayDensity.compact => 0.8,
      DisplayDensity.normal => 1.0,
      DisplayDensity.large => 1.1,
    };
    await setScale(v);
  }
}
