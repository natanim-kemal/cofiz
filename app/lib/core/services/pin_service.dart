import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _kBaseKey = 'pin_lock_v1';
const _kIterations = 100000;
const _kPinLength = 6;
const _kSaltBytes = 16;

/// Top-10 weakest 6-digit PINs + trivial sequences — blocked.
const _weakPins = <String>{
  '000000',
  '111111',
  '222222',
  '333333',
  '444444',
  '555555',
  '666666',
  '777777',
  '888888',
  '999999',
  '123456',
  '654321',
  '012345',
  '543210',
};

class PinService {
  PinService({FlutterSecureStorage? storage, FirebaseAuth? auth})
      : _storage = storage ?? const FlutterSecureStorage(),
        _auth = auth;

  final FlutterSecureStorage _storage;
  final FirebaseAuth? _auth;

  String _keyForUid(String? uid) =>
      uid == null || uid.isEmpty ? _kBaseKey : '${_kBaseKey}::$uid';

  /// Resolves current uid (if Firebase available) — falls back to global key.
  String _currentKey() {
    try {
      final uid = (_auth ?? FirebaseAuth.instance).currentUser?.uid;
      return _keyForUid(uid);
    } catch (_) {
      return _kBaseKey;
    }
  }

  /// Explicit uid variants for tests / per-user callers.
  String keyForTest(String? uid) => _keyForUid(uid);

  Future<bool> hasPin({String? uid}) async {
    final k = uid != null ? _keyForUid(uid) : _currentKey();
    final v = await _storage.read(key: k);
    return v != null && v.isNotEmpty;
  }

  Future<void> setPin(String pin, {String? uid}) {
    _validate(pin);
    return _write(pin, uid: uid);
  }

  Future<bool> verifyPin(String pin, {String? uid}) async {
    _validate(pin);
    final k = uid != null ? _keyForUid(uid) : _currentKey();
    final stored = await _storage.read(key: k);
    if (stored == null) return false;
    final data = jsonDecode(stored) as Map<String, dynamic>;
    final salt = base64Decode(data['salt'] as String);
    final expected = base64Decode(data['hash'] as String);
    final iters = (data['iterations'] as int?) ?? _kIterations;
    // Offload CPU-heavy PBKDF2 to isolate.
    final actual = await Isolate.run(() => _pbkdf2Sync(pin, salt, expected.length, iters));
    return _constantTimeEquals(actual, expected);
  }

  Future<void> changePin({required String oldPin, required String newPin, String? uid}) async {
    if (!await verifyPin(oldPin, uid: uid)) {
      throw StateError('Old PIN does not match');
    }
    _validate(newPin);
    await _write(newPin, uid: uid);
  }

  Future<void> clearPin({String? uid}) {
    final k = uid != null ? _keyForUid(uid) : _currentKey();
    return _storage.delete(key: k);
  }

  /// Clears *all* pin keys (global + per-uid) — used on sign-out to avoid leftover.
  Future<void> clearAll() async {
    // Best-effort: delete global + current uid's key.
    await _storage.delete(key: _kBaseKey);
    final uid = await _currentUid();
    if (uid != null) await _storage.delete(key: _keyForUid(uid));
  }

  Future<String?> _currentUid() async {
    try {
      return (_auth ?? FirebaseAuth.instance).currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  void _validate(String pin) {
    if (pin.length != _kPinLength || !RegExp(r'^\d{6}$').hasMatch(pin)) {
      throw ArgumentError('PIN must be exactly 6 digits');
    }
    if (_weakPins.contains(pin)) {
      throw ArgumentError('PIN is too weak — choose a less predictable 6-digit code');
    }
  }

  Future<void> _write(String pin, {String? uid}) async {
    final k = uid != null ? _keyForUid(uid) : _currentKey();
    final salt = _randomBytes(_kSaltBytes);
    final hash = await Isolate.run(() => _pbkdf2Sync(pin, salt, 32, _kIterations));
    final payload = jsonEncode({
      'salt': base64Encode(salt),
      'hash': base64Encode(hash),
      'iterations': _kIterations,
      'length': _kPinLength,
    });
    await _storage.write(key: k, value: payload);
  }

  List<int> _randomBytes(int n) {
    final rng = Random.secure();
    return List<int>.generate(n, (_) => rng.nextInt(256));
  }

  bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

/// Top-level for Isolate.run — must be static / top-level.
List<int> _pbkdf2Sync(String pin, List<int> salt, int outLen, int iterations) {
  final hmac = Hmac(sha256, utf8.encode(pin));
  final blocks = (outLen / 32).ceil();
  final out = <int>[];
  for (var i = 1; i <= blocks; i++) {
    final block = _pbkdf2BlockSync(hmac, salt, i, iterations);
    out.addAll(block);
  }
  return out.sublist(0, outLen);
}

List<int> _pbkdf2BlockSync(Hmac hmac, List<int> salt, int i, int iterations) {
  final seed = [...salt, ...[i >> 24 & 0xff, i >> 16 & 0xff, i >> 8 & 0xff, i & 0xff]];
  var u = hmac.convert(seed).bytes;
  final result = List<int>.from(u);
  for (var round = 1; round < iterations; round++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < result.length; j++) {
      result[j] = result[j] ^ u[j];
    }
  }
  return result;
}
