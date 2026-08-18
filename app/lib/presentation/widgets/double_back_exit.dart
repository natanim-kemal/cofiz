import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/app_localizations.dart';
import 'app_toast.dart';

/// Wraps a root screen and intercepts the system back gesture so the user
/// must tap back twice (within a short window) to actually leave the app.
class DoubleBackExit extends StatefulWidget {
  final Widget child;

  /// Clock source; injected for tests to control the exit window.
  final DateTime Function()? now;

  const DoubleBackExit({super.key, required this.child, this.now});

  @override
  State<DoubleBackExit> createState() => _DoubleBackExitState();
}

class _DoubleBackExitState extends State<DoubleBackExit> {
  static const Duration _exitWindow = Duration(seconds: 2);
  DateTime? _lastBackPressed;

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: widget.child,
    );
  }

  Future<void> _handleBack() async {
    final now = _now();
    final last = _lastBackPressed;
    _lastBackPressed = now;

    if (last != null && now.difference(last) <= _exitWindow) {
      await SystemNavigator.pop();
      return;
    }

    AppToast.show(
      AppLocalizations.of(context)?.tapAgainToExit ?? 'Tap back again to exit',
    );
  }
}
