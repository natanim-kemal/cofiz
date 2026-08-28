import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cofiz/core/providers/settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsProvider nightly nudge', () {
    late FakeFirebaseFirestore fake;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      fake = FakeFirebaseFirestore();
    });

    test('defaults: adminReminderTime 20:00, reminderEnabled true', () async {
      final provider = SettingsProvider(firestore: fake);
      // allow async load to settle
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(provider.adminReminderTime, '20:00');
      expect(provider.reminderEnabled, isTrue);
    });

    test('setAdminReminderTime round-trip to SharedPreferences and Firestore', () async {
      final provider = SettingsProvider(firestore: fake);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await provider.setAdminReminderTime('09:30');
      expect(provider.adminReminderTime, '09:30');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('admin_reminder_time'), '09:30');

      final doc = await fake.collection('settings').doc('app').get();
      expect(doc.data()?['adminReminderTime'], '09:30');
    });

    test('setReminderEnabled round-trip', () async {
      final provider = SettingsProvider(firestore: fake);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await provider.setReminderEnabled(false);
      expect(provider.reminderEnabled, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('reminder_enabled'), isFalse);
      final doc = await fake.collection('settings').doc('app').get();
      expect(doc.data()?['reminderEnabled'], isFalse);

      await provider.setReminderEnabled(true);
      expect(provider.reminderEnabled, isTrue);
      final doc2 = await fake.collection('settings').doc('app').get();
      expect(doc2.data()?['reminderEnabled'], isTrue);
    });

    test('setViewerCheckInEnabled round-trip', () async {
      final provider = SettingsProvider(firestore: fake);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await provider.setViewerCheckInEnabled(true);
      expect(provider.viewerCheckInEnabled, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('viewer_check_in_enabled'), isTrue);
      final doc = await fake.collection('settings').doc('app').get();
      expect(doc.data()?['viewerCheckInEnabled'], isTrue);

      await provider.setViewerCheckInEnabled(false);
      expect(provider.viewerCheckInEnabled, isFalse);
    });

    test('invalid time throws ArgumentError', () async {
      final provider = SettingsProvider(firestore: fake);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(() => provider.setAdminReminderTime('25:00'), throwsA(isA<ArgumentError>()));
      expect(() => provider.setAdminReminderTime('9:30'), throwsA(isA<ArgumentError>()));
      expect(() => provider.setAdminReminderTime('ab:cd'), throwsA(isA<ArgumentError>()));
      // original value unchanged
      expect(provider.adminReminderTime, '20:00');
    });

    test('load from Firestore overrides prefs', () async {
      // seed Firestore before provider creation
      await fake.collection('settings').doc('app').set({
        'adminReminderTime': '21:15',
        'reminderEnabled': false,
        'viewerCheckInEnabled': true,
      });
      // prefs has different values
      SharedPreferences.setMockInitialValues({
        'admin_reminder_time': '10:00',
        'reminder_enabled': true,
        'viewer_check_in_enabled': false,
      });
      final provider = SettingsProvider(firestore: fake);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(provider.adminReminderTime, '21:15');
      expect(provider.reminderEnabled, isFalse);
      expect(provider.viewerCheckInEnabled, isTrue);
      // prefs should be synced
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('admin_reminder_time'), '21:15');
      expect(prefs.getBool('reminder_enabled'), isFalse);
      expect(prefs.getBool('viewer_check_in_enabled'), isTrue);
    });

    test('adminReminderTime getter parses to HH:mm', () async {
      final provider = SettingsProvider(firestore: fake);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await provider.setAdminReminderTime('07:05');
      expect(provider.adminReminderTime, '07:05');
      final parts = provider.adminReminderTime.split(':');
      expect(parts.length, 2);
      expect(int.parse(parts[0]), 7);
      expect(int.parse(parts[1]), 5);
    });
  });
}
