import 'package:cloud_functions/cloud_functions.dart';

class EmailVerificationService {
  FirebaseFunctions get _fns => FirebaseFunctions.instance;

  Future<void> requestCode(String email) async {
    await _fns.httpsCallable('requestEmailVerification').call({'email': email});
  }

  Future<bool> verifyCode(String code) async {
    final res =
        await _fns.httpsCallable('verifyEmailCode').call({'code': code});
    return (res.data as Map)['verified'] == true;
  }
}
