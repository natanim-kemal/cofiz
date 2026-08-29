import 'package:flutter/foundation.dart';
import '../services/auth_backend.dart';

enum OtpAuthState { unauthenticated, awaitingCode, verifying, authenticated, error }

class PhoneOtpAuthProvider extends ChangeNotifier {
  PhoneOtpAuthProvider({required this.backend});
  final AuthBackend backend;

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
      _state = OtpAuthState.authenticated;
    } on AuthBackendException catch (e) {
      _lastErrorCode = e.errorCode;
      _lastErrorMessage = e.message;
      _state = OtpAuthState.error;
    }
    notifyListeners();
  }

  Future<void> signOut() async {
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
