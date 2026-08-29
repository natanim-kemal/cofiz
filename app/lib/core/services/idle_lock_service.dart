import 'dart:async';
import 'package:flutter/widgets.dart' hide LockState;
import '../providers/lock_state_provider.dart';

/// Watches for inactivity and app backgrounding to lock the app.
///
/// Use via `IdleLockService` singleton-ish: create in `StitchWorkerApp` and
/// call `attach()` in `initState`, `detach()` in `dispose`.
/// Interaction is reported via `onUserInteraction()` — wire it with a
/// top-level `Listener` + `NotificationListener` in the app's builder.
class IdleLockService with WidgetsBindingObserver {
  IdleLockService({required this.lockState, Duration? duration})
      : duration = duration ?? const Duration(minutes: 2) {
    assert(duration == null || duration > Duration.zero);
  }

  final LockStateProvider lockState;
  final Duration duration;

  Timer? _timer;
  bool _attached = false;

  void attach() {
    if (_attached) return;
    WidgetsBinding.instance.addObserver(this);
    _attached = true;
    bump();
  }

  void detach() {
    if (!_attached) return;
    WidgetsBinding.instance.removeObserver(this);
    _attached = false;
    _timer?.cancel();
  }

  void bump() {
    // Don't arm timer if locked or awaiting setup, and respect cooldown.
    if (lockState.state != PinLockState.unlocked) return;
    if (lockState.isInCooldown) return;
    _timer?.cancel();
    _timer = Timer(duration, () {
      if (lockState.state == PinLockState.unlocked) {
        lockState.lock();
      }
    });
  }

  void onUserInteraction() => bump();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      if (lockState.state == PinLockState.unlocked) {
        lockState.lock();
      }
      _timer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      bump();
    }
  }
}
