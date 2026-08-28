import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cofiz/core/providers/settings_provider.dart';
import 'package:cofiz/l10n/app_localizations.dart';
import 'package:cofiz/presentation/screens/settings/notification_settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SettingsProvider exposes no smsNotifications surface', () {
    SharedPreferences.setMockInitialValues({});
    final fake = FakeFirebaseFirestore();
    final p = SettingsProvider(firestore: fake);
    expect(() => (p as dynamic).smsNotifications,
        throwsA(isA<NoSuchMethodError>()));
    expect(() => (p as dynamic).toggleSmsNotifications(true),
        throwsA(isA<NoSuchMethodError>()));
  });

  test('SettingsProvider emailNotifications defaults true and toggles',
      () async {
    SharedPreferences.setMockInitialValues({});
    final fake = FakeFirebaseFirestore();
    final p = SettingsProvider(firestore: fake);
    await pumpEventQueue();
    expect(p.emailNotifications, true);
    await p.toggleEmailNotifications(false);
    expect(p.emailNotifications, false);
  });

  testWidgets(
      'NotificationSettingsScreen renders email and push tiles, '
      'gating the verify tile when email notifications are off',
      (tester) async {
    SharedPreferences.setMockInitialValues({'email_notifications': false});
    final fake = FakeFirebaseFirestore();
    late SettingsProvider settings;
    await tester.runAsync(() async {
      settings = SettingsProvider(firestore: fake);
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: NotificationSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SwitchListTile), findsNWidgets(2));
    expect(find.text('Email Notifications'), findsOneWidget);
    expect(find.text('Push Notifications'), findsOneWidget);
    expect(find.text('Verify email'), findsNothing);
    expect(find.text('SMS Notifications'), findsNothing);
    expect(find.text('Receive text message alerts'), findsNothing);
  });
}
