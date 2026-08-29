import 'package:flutter/foundation.dart';
import '../services/auth_backend.dart';
import '../services/auth_backend_firebase.dart';

enum OtpAuthState {
  unauthenticated,
  awaitingCode,
  verifying,
  authenticated,
  error,
  awaitingTelegramReturn,
}

class PhoneOtpAuthProvider extends ChangeNotifier {
  PhoneOtpAuthProvider({required this.backend, AuthBackendFirebase? firebaseAuth})
      : _firebaseAuth = firebaseAuth;
  final AuthBackend backend;
  final AuthBackendFirebase? _firebaseAuth;

  OtpAuthState _state = OtpAuthState.unauthenticated;
  String? _phone;
  OtpProvider? _provider;
  String? _verificationId;
  String? _uid;
  String? _lastErrorCode;
  String? _lastErrorMessage;

  OtpAuthState get state => _state;
  String? get phone => _phone;
  OtpProvider? get provider => _provider;
  String? get verificationId => _verificationId;
  String? get uid => _uid;
  bool get isAuthenticated => _state == OtpAuthState.authenticated;
  String? get lastErrorCode => _lastErrorCode;
  String? get lastErrorMessage => _lastErrorMessage;

  Future<void> requestOtp({required String phone, required OtpProvider provider}) async {
    _phone = phone;
    _provider = provider;
    _state = OtpAuthState.unauthenticated;
    notifyListeners();
    try {
      final r = await backend.requestOtp(phone: phone, provider: provider);
      _verificationId = r.verificationId;
      _state = OtpAuthState.awaitingCode;
    } on AuthBackendException catch (e) {
      _lastErrorCode = e.errorCode;
      _lastErrorMessage = e.message;
      _state = OtpAuthState.error;
    }
    notifyListeners();
  }

  Future<void> verifyOtp({required String code}) async {
    if (_phone == null || _provider == null || _verificationId == null) {
      _state = OtpAuthState.error;
      _lastErrorMessage = 'No verification in progress';
      notifyListeners();
      return;
    }
    _state = OtpAuthState.verifying;
    notifyListeners();
    try {
      final r = await backend.verifyOtp(
        phone: _phone!,
        provider: _provider!,
        verificationId: _verificationId!,
        code: code,
      );
      _uid = r.uid;
      // Exchange the custom token for a real Firebase session.
      if (_firebaseAuth != null) {
        try {
          await _firebaseAuth.signInWithCustomToken(r.customToken);
        } catch (e) {
          _lastErrorCode = 'firebase_signin_failed';
          _lastErrorMessage = e.toString();
          _state = OtpAuthState.error;
          notifyListeners();
          return;
        }
      }
      _state = OtpAuthState.authenticated;
    } on AuthBackendException catch (e) {
      _lastErrorCode = e.errorCode;
      _lastErrorMessage = e.message;
      _state = OtpAuthState.error;
    }
    notifyListeners();
  }

  /// Telegram Login Widget one-tap sign-in.
  /// [fields] are the query parameters Telegram posts to the deep link
  /// (`cofiz://auth/telegram?...`): id, first_name, last_name, username,
  /// photo_url, auth_date, hash.
  Future<void> completeTelegramLogin({required Map<String, String> fields}) async {
    _state = OtpAuthState.verifying;
    _lastErrorCode = null;
    _lastErrorMessage = null;
    notifyListeners();
    try {
      final r = await backend.authTelegram(fields);
      _uid = r.uid;
      if (_firebaseAuth != null) {
        try {
          await _firebaseAuth.signInWithCustomToken(r.customToken);
        } catch (e) {
          _lastErrorCode = 'firebase_signin_failed';
          _lastErrorMessage = e.toString();
          _state = OtpAuthState.error;
          notifyListeners();
          return;
        }
      }
      _state = OtpAuthState.authenticated;
    } on AuthBackendException catch (e) {
      _lastErrorCode = e.errorCode;
      _lastErrorMessage = e.message;
      _state = OtpAuthState.error;
    }
    notifyListeners();
  }

  Future<void> signOut() async {
    final fb = _firebaseAuth;
    if (fb != null) {
      try {
        await fb.signOut();
      } catch (_) {
        // Best-effort: even if Firebase signOut throws, we still clear local state.
      }
    }
    _state = OtpAuthState.unauthenticated;
    _phone = null;
    _provider = null;
    _verificationId = null;
    _uid = null;
    _lastErrorCode = null;
    _lastErrorMessage = null;
    notifyListeners();
  }
}
