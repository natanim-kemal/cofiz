import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:cofiz/core/providers/phone_otp_auth_provider.dart';
import 'package:cofiz/core/services/auth_backend.dart';
import 'package:cofiz/l10n/app_localizations.dart';
import 'package:cofiz/presentation/screens/auth/phone_login_screen.dart';
import '../../../_support/mock_http_client.dart';

void main() {
  testWidgets('PhoneLoginScreen shows Send Code button and provider toggle', (tester) async {
    final mock = MockHttpClient();
    mock.onPost('/otp/start', (_) => {'verificationId': 'v1', 'expiresInSeconds': 300});
    final provider = PhoneOtpAuthProvider(
      backend: AuthBackend(baseUrl: 'https://x', client: mock),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChangeNotifierProvider.value(
          value: provider,
          child: const PhoneLoginScreen(),
        ),
      ),
    );
    expect(find.text('Telegram'), findsOneWidget);
    expect(find.text('WhatsApp'), findsOneWidget);
    expect(find.byKey(const Key('sendCodeButton')), findsOneWidget);
  });
}
