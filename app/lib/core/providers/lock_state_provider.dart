import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/pin_service.dart';

enum PinLockState { unlocked, locked, awaitingFirstSetup }

class LockStateProvider extends ChangeNotifier {
  LockStateProvider({required this.pinService, this.maxFailedAttempts = 5});
  final PinService pinService;
  final int maxFailedAttempts;

  PinLockState _state = PinLockState.unlocked;
  int _failedAttempts = 0;
  DateTime? _cooldownUntil;

  PinLockState get state => _state;
  int get failedAttempts => _failedAttempts;
  DateTime? get cooldownUntil => _cooldownUntil;
  bool get isInCooldown => _cooldownUntil != null && DateTime.now().isBefore(_cooldownUntil!);
  Duration? get cooldownRemaining =>
      isInCooldown ? _cooldownUntil!.difference(DateTime.now()) : null;
  bool get shouldForceSignOut => _failedAttempts >= maxFailedAttempts;

  Future<void> initialize({String? uid}) async {
    if (!await pinService.hasPin(uid: uid)) {
      _state = PinLockState.awaitingFirstSetup;
    } else {
      _state = PinLockState.unlocked;
    }
    notifyListeners();
  }

  void lock() {
    _state = PinLockState.locked;
    _failedAttempts = 0;
    _cooldownUntil = null;
    notifyListeners();
  }

  Future<bool> attemptUnlock(String pin, {String? uid}) async {
    if (isInCooldown) return false;
    final ok = await pinService.verifyPin(pin, uid: uid);
    if (ok) {
      _state = PinLockState.unlocked;
      _failedAttempts = 0;
      _cooldownUntil = null;
    } else {
      _failedAttempts += 1;
      // Exponential cooldown: 10s after 3rd, 30s after 4th, force sign-out at 5.
      if (_failedAttempts == 3) {
        _cooldownUntil = DateTime.now().add(const Duration(seconds: 10));
      } else if (_failedAttempts == 4) {
        _cooldownUntil = DateTime.now().add(const Duration(seconds: 30));
      }
    }
    notifyListeners();
    return ok;
  }

  Future<void> reset({String? uid}) async {
    await pinService.clearPin(uid: uid);
    _state = PinLockState.awaitingFirstSetup;
    _failedAttempts = 0;
    _cooldownUntil = null;
    notifyListeners();
  }

  void clearCooldown() {
    _cooldownUntil = null;
    notifyListeners();
  }

  /// Unlock via biometric — trusted path, clears cooldown and unlocks.
  void unlockWithBiometric() {
    _state = PinLockState.unlocked;
    _failedAttempts = 0;
    _cooldownUntil = null;
    notifyListeners();
  }
}
