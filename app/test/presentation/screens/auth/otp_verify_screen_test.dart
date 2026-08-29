import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:cofiz/core/providers/phone_otp_auth_provider.dart';
import 'package:cofiz/core/services/auth_backend.dart';
import 'package:cofiz/l10n/app_localizations.dart';
import 'package:cofiz/presentation/screens/auth/otp_verify_screen.dart';
import '../../../_support/mock_http_client.dart';

void main() {
  testWidgets('OtpVerifyScreen shows 6 inputs', (tester) async {
    final mock = MockHttpClient();
    mock.onPost('/otp/start', (_) => {'verificationId': 'v1', 'expiresInSeconds': 300});
    final p = PhoneOtpAuthProvider(
      backend: AuthBackend(baseUrl: 'https://x', client: mock),
    );
    await p.requestOtp(phone: '+251911234567', provider: OtpProvider.telegram);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChangeNotifierProvider.value(
          value: p,
          child: const OtpVerifyScreen(),
        ),
      ),
    );
    expect(find.byKey(const Key('codeDigit0')), findsOneWidget);
    expect(find.byKey(const Key('codeDigit5')), findsOneWidget);
  });
}
