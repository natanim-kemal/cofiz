import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cofiz/core/services/email_verification_service.dart';
import 'package:cofiz/l10n/app_localizations.dart';
import 'package:cofiz/presentation/widgets/verification_dialog.dart';

class FakeEmailVerificationService extends EmailVerificationService {
  String correctCode = '123456';
  int verifyCalls = 0;
  int requestCalls = 0;
  String? lastRequestedEmail;
  bool throwExpired = false;

  @override
  Future<bool> verifyCode(String code) async {
    verifyCalls++;
    if (throwExpired) throw Exception('expired');
    return code == correctCode;
  }

  @override
  Future<void> requestCode(String email) async {
    requestCalls++;
    lastRequestedEmail = email;
  }
}

Widget wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

void main() {
  group('VerifyEmailTile', () {
    testWidgets('shows badge directly when already verified', (tester) async {
      await tester.pumpWidget(wrap(VerifyEmailTile(
        email: 'a@b.com',
        verified: true,
        onVerify: () async => true,
      )));

      expect(find.text('Verified'), findsOneWidget);
      expect(find.text('Verify email'), findsNothing);
      expect(find.byIcon(Icons.verified), findsOneWidget);
    });

    testWidgets(
        'renders verify button and flips to badge after successful verify',
        (tester) async {
      var calls = 0;
      await tester.pumpWidget(wrap(VerifyEmailTile(
        email: 'a@b.com',
        verified: false,
        onVerify: () async {
          calls++;
          return true;
        },
      )));

      expect(find.text('Verify email'), findsOneWidget);
      expect(find.text('a@b.com'), findsOneWidget);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Verify'));
      await tester.pumpAndSettle();

      expect(calls, 1);
      expect(find.text('Verified'), findsOneWidget);
      expect(find.text('Verify email'), findsNothing);
    });

    testWidgets('stays unverified when onVerify returns false', (tester) async {
      var calls = 0;
      await tester.pumpWidget(wrap(VerifyEmailTile(
        email: 'a@b.com',
        verified: false,
        onVerify: () async {
          calls++;
          return false;
        },
      )));

      await tester.tap(find.widgetWithText(ElevatedButton, 'Verify'));
      await tester.pumpAndSettle();

      expect(calls, 1);
      expect(find.text('Verify email'), findsOneWidget);
    });
  });

  group('VerificationDialog', () {
    testWidgets('renders 6 code fields, resend and verify controls',
        (tester) async {
      final fake = FakeEmailVerificationService();
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: VerificationDialog(email: 'a@b.com', service: fake),
        ),
      ));
      await tester.pump();

      expect(find.byType(TextField), findsNWidgets(6));
      expect(find.text('Resend code'), findsOneWidget);
      expect(find.text('Verify'), findsOneWidget);
      expect(find.text('a@b.com'), findsOneWidget);
      expect(find.text('10:00'), findsOneWidget);
      expect(find.text('5 attempts remaining'), findsOneWidget);
    });

    testWidgets('countdown ticks down', (tester) async {
      final fake = FakeEmailVerificationService();
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: VerificationDialog(email: 'a@b.com', service: fake),
        ),
      ));
      await tester.pump();

      expect(find.text('10:00'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('09:59'), findsOneWidget);
    });

    testWidgets('pops with true when code is correct', (tester) async {
      bool? result;
      final fake = FakeEmailVerificationService();
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showDialog<bool>(
                    context: context,
                    builder: (_) =>
                        VerificationDialog(email: 'a@b.com', service: fake),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      for (var i = 0; i < 6; i++) {
        await tester.enterText(
            find.byType(TextField).at(i), fake.correctCode[i]);
      }

      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();

      expect(fake.verifyCalls, 1);
      expect(find.byType(TextField), findsNothing);
      expect(result, isTrue);
    });

    testWidgets('keeps dialog open and decrements attempts on wrong code',
        (tester) async {
      final fake = FakeEmailVerificationService();
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) =>
                      VerificationDialog(email: 'a@b.com', service: fake),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      for (var i = 0; i < 6; i++) {
        await tester.enterText(find.byType(TextField).at(i), '0');
      }

      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();

      expect(fake.verifyCalls, 1);
      expect(find.byType(TextField), findsNWidgets(6));
      expect(find.text('4 attempts remaining'), findsOneWidget);
    });

    testWidgets('resend resets countdown and attempts', (tester) async {
      final fake = FakeEmailVerificationService();
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: VerificationDialog(email: 'a@b.com', service: fake),
        ),
      ));
      await tester.pump();

      await tester.pump(const Duration(minutes: 10));

      await tester.tap(find.text('Resend code'));
      await tester.pumpAndSettle();

      expect(fake.requestCalls, 1);
      expect(fake.lastRequestedEmail, 'a@b.com');
      expect(find.text('10:00'), findsOneWidget);
      expect(find.text('5 attempts remaining'), findsOneWidget);
    });
  });
}
