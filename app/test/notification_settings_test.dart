import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cofiz/core/providers/settings_provider.dart';
import 'package:cofiz/l10n/app_localizations.dart';
import 'package:cofiz/presentation/screens/settings/notification_settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('SettingsProvider exposes no smsNotifications surface', () {
    final p = SettingsProvider();
    expect(() => (p as dynamic).smsNotifications,
        throwsA(isA<NoSuchMethodError>()));
    expect(() => (p as dynamic).toggleSmsNotifications(true),
        throwsA(isA<NoSuchMethodError>()));
  });

  testWidgets('NotificationSettingsScreen renders only email and push tiles',
      (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>(
        create: (_) => SettingsProvider(),
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
    expect(find.text('SMS Notifications'), findsNothing);
    expect(find.text('Receive text message alerts'), findsNothing);
  });
}
