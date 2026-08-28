import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/notification_service.dart';

class SettingsProvider with ChangeNotifier {
  final FirebaseFirestore _firestore;

  bool _emailNotifications = true;
  bool _pushNotifications = true;
  Locale _locale = const Locale('en');

  // Business Settings
  String _companyName = 'Stitch Plc';
  String _companyAddress = 'Addis Ababa, Ethiopia';
  String _companyPhone = '+251 911 223344';
  double _distributionLimit = 5000.0;

  // Nightly nudge settings — persisted to SharedPreferences + Firestore settings/app
  String _adminReminderTime = '20:00';
  bool _reminderEnabled = true;
  bool _viewerCheckInEnabled = false;

  bool get emailNotifications => _emailNotifications;
  bool get pushNotifications => _pushNotifications;
  Locale get locale => _locale;

  // Business Getters
  String get companyName => _companyName;
  String get companyAddress => _companyAddress;
  String get companyPhone => _companyPhone;
  double get distributionLimit => _distributionLimit;

  // Nightly nudge getters
  String get adminReminderTime => _adminReminderTime;
  bool get reminderEnabled => _reminderEnabled;
  bool get viewerCheckInEnabled => _viewerCheckInEnabled;

  /// Validates HH:mm (00:00 - 23:59)
  static bool isValidReminderTime(String value) =>
      RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(value);

  SettingsProvider({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _emailNotifications = prefs.getBool('email_notifications') ?? true;
    _pushNotifications = prefs.getBool('push_notifications') ?? true;
    final languageCode = prefs.getString('language_code');
    if (languageCode != null) {
      _locale = Locale(languageCode);
    }

    // Load Business Settings
    _companyName = prefs.getString('company_name') ?? 'YT Plc';
    _companyAddress =
        prefs.getString('company_address') ?? 'Addis Ababa, Ethiopia';
    _companyPhone = prefs.getString('company_phone') ?? '+251 911 223344';
    _distributionLimit = prefs.getDouble('distribution_limit') ?? 5000.0;

    // Load nightly nudge from SharedPreferences
    _adminReminderTime = prefs.getString('admin_reminder_time') ?? '20:00';
    if (!isValidReminderTime(_adminReminderTime)) _adminReminderTime = '20:00';
    _reminderEnabled = prefs.getBool('reminder_enabled') ?? true;
    _viewerCheckInEnabled = prefs.getBool('viewer_check_in_enabled') ?? false;

    // Overlay Firestore settings/app (authoritative for time + toggles)
    try {
      final doc = await _firestore
          .collection('settings')
          .doc('app')
          .get()
          .timeout(const Duration(seconds: 2));
      if (doc.exists) {
        final data = doc.data();
        if (data != null) {
          final firestoreTime = data['adminReminderTime'];
          if (firestoreTime is String && isValidReminderTime(firestoreTime)) {
            _adminReminderTime = firestoreTime;
            await prefs.setString('admin_reminder_time', firestoreTime);
          }
          if (data['reminderEnabled'] is bool) {
            _reminderEnabled = data['reminderEnabled'] as bool;
            await prefs.setBool('reminder_enabled', _reminderEnabled);
          }
          if (data['viewerCheckInEnabled'] is bool) {
            _viewerCheckInEnabled = data['viewerCheckInEnabled'] as bool;
            await prefs.setBool('viewer_check_in_enabled', _viewerCheckInEnabled);
          }
        }
      }
    } catch (_) {
      // Best-effort: keep local prefs.
    }

    notifyListeners();
  }

  Future<void> toggleEmailNotifications(bool value, {String? uid}) async {
    _emailNotifications = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('email_notifications', value);

    // Sync the opt-in so verified-gated email delivery can respect it.
    if (uid != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set({'emailNotificationsEnabled': value}, SetOptions(merge: true));
      } catch (_) {
        // Best-effort: local preference already saved.
      }
    }
  }

  Future<void> togglePushNotifications(bool value) async {
    _pushNotifications = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('push_notifications', value);

    if (value) {
      await NotificationService().requestPermissions();
      // Schedule daily reminder at 6 PM
      await NotificationService().scheduleDailyNotification(
        id: 999,
        title: 'Daily Summary',
        body: 'Don\'t forget to check today\'s transactions.',
        time: const TimeOfDay(hour: 18, minute: 0),
      );
    } else {
      await NotificationService().cancelAll();
    }
  }

  Future<void> updateCompanyInfo({
    required String name,
    required String address,
    required String phone,
  }) async {
    _companyName = name;
    _companyAddress = address;
    _companyPhone = phone;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('company_name', name);
    await prefs.setString('company_address', address);
    await prefs.setString('company_phone', phone);
  }

  Future<void> updateDistributionLimit(double limit) async {
    _distributionLimit = limit;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('distribution_limit', limit);
  }

  Future<void> setLocale(Locale locale) async {
    if (_locale == locale) return;
    _locale = locale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language_code', locale.languageCode);
  }

  Future<void> setAdminReminderTime(String time) async {
    if (!isValidReminderTime(time)) {
      throw ArgumentError('Invalid time format, expected HH:mm got: $time');
    }
    if (_adminReminderTime == time) return;
    _adminReminderTime = time;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('admin_reminder_time', time);
    try {
      await _firestore.collection('settings').doc('app').set(
        {'adminReminderTime': time},
        SetOptions(merge: true),
      );
    } catch (_) {
      // Best-effort Firestore sync.
    }
  }

  Future<void> setReminderEnabled(bool value) async {
    if (_reminderEnabled == value) return;
    _reminderEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('reminder_enabled', value);
    try {
      await _firestore.collection('settings').doc('app').set(
        {'reminderEnabled': value},
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  Future<void> setViewerCheckInEnabled(bool value) async {
    if (_viewerCheckInEnabled == value) return;
    _viewerCheckInEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('viewer_check_in_enabled', value);
    try {
      await _firestore.collection('settings').doc('app').set(
        {'viewerCheckInEnabled': value},
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  /// Parses adminReminderTime to TimeOfDay.
  TimeOfDay get adminReminderTimeOfDay {
    final parts = _adminReminderTime.split(':');
    final h = int.tryParse(parts[0]) ?? 20;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    return TimeOfDay(hour: h, minute: m);
  }
}
