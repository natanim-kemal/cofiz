import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import '../../_support/mock_http_client.dart';
import 'package:cofiz/core/services/auth_backend.dart';

void main() {
  group('AuthBackend', () {
    test('requestOtp posts phone+provider and returns verificationId', () async {
      final mock = MockHttpClient();
      mock.onPost('/otp/start', (req) => jsonEncode({
            'verificationId': 'v1',
            'expiresInSeconds': 300,
          }), status: 200);
      final backend = AuthBackend(baseUrl: 'https://relay.example', client: mock);
      final r = await backend.requestOtp(phone: '+251911234567', provider: OtpProvider.telegram);
      expect(r.verificationId, 'v1');
      expect(r.expiresInSeconds, 300);
    });

    test('verifyOtp returns customToken', () async {
      final mock = MockHttpClient();
      mock.onPost('/otp/verify', (req) => jsonEncode({
            'customToken': 'tok',
            'uid': 'abc',
            'isNewUser': false,
          }), status: 200);
      final backend = AuthBackend(baseUrl: 'https://relay.example', client: mock);
      final r = await backend.verifyOtp(
        phone: '+251911234567',
        provider: OtpProvider.telegram,
        verificationId: 'v1',
        code: '123456',
      );
      expect(r.customToken, 'tok');
      expect(r.uid, 'abc');
      expect(r.isNewUser, isFalse);
    });

    test('verifyOtp throws AuthBackendException on 400', () async {
      final mock = MockHttpClient();
      mock.onPost('/otp/verify', (_) => jsonEncode({'error': 'bad_code'}), status: 400);
      final backend = AuthBackend(baseUrl: 'https://relay.example', client: mock);
      expect(
        () => backend.verifyOtp(
          phone: '+251911234567',
          provider: OtpProvider.telegram,
          verificationId: 'v1',
          code: '000000',
        ),
        throwsA(isA<AuthBackendException>()),
      );
    });
  });
}
