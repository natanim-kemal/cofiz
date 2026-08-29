import 'package:flutter_test/flutter_test.dart';
import 'package:cofiz/core/providers/phone_otp_auth_provider.dart';
import 'package:cofiz/core/services/auth_backend.dart';
import '../../_support/mock_http_client.dart';

void main() {
  group('PhoneOtpAuthProvider', () {
    test('requestOtp transitions to awaitingCode on success', () async {
      final mock = MockHttpClient();
      mock.onPost('/otp/start', (_) => {'verificationId': 'v1', 'expiresInSeconds': 300});
      final p = PhoneOtpAuthProvider(
        backend: AuthBackend(baseUrl: 'https://x', client: mock),
      );
      await p.requestOtp(phone: '+251911234567', provider: OtpProvider.telegram);
      expect(p.state, OtpAuthState.awaitingCode);
      expect(p.verificationId, 'v1');
      expect(p.phone, '+251911234567');
    });

    test('verifyOtp transitions to authenticated on success', () async {
      final mock = MockHttpClient();
      mock.onPost('/otp/start', (_) => {'verificationId': 'v1', 'expiresInSeconds': 300});
      mock.onPost('/otp/verify', (_) => {'customToken': 'tok', 'uid': 'abc', 'isNewUser': true});
      final p = PhoneOtpAuthProvider(
        backend: AuthBackend(baseUrl: 'https://x', client: mock),
      );
      await p.requestOtp(phone: '+251911234567', provider: OtpProvider.telegram);
      await p.verifyOtp(code: '123456');
      expect(p.state, OtpAuthState.authenticated);
      expect(p.uid, 'abc');
    });

    test('verifyOtp moves to error on 400', () async {
      final mock = MockHttpClient();
      mock.onPost('/otp/start', (_) => {'verificationId': 'v1', 'expiresInSeconds': 300});
      mock.onPost('/otp/verify', (_) => {'error': 'bad_code', 'message': 'Wrong code'}, status: 400);
      final p = PhoneOtpAuthProvider(
        backend: AuthBackend(baseUrl: 'https://x', client: mock),
      );
      await p.requestOtp(phone: '+251911234567', provider: OtpProvider.telegram);
      await p.verifyOtp(code: '000000');
      expect(p.state, OtpAuthState.error);
    });

    test('signOut resets state', () async {
      final mock = MockHttpClient();
      mock.onPost('/otp/start', (_) => {'verificationId': 'v1', 'expiresInSeconds': 300});
      mock.onPost('/otp/verify', (_) => {'customToken': 'tok', 'uid': 'abc', 'isNewUser': false});
      final p = PhoneOtpAuthProvider(
        backend: AuthBackend(baseUrl: 'https://x', client: mock),
      );
      await p.requestOtp(phone: '+251911234567', provider: OtpProvider.telegram);
      await p.verifyOtp(code: '123456');
      await p.signOut();
      expect(p.state, OtpAuthState.unauthenticated);
      expect(p.uid, isNull);
    });
  });
}
