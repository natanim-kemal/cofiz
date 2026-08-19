import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';

class SettingsProvider with ChangeNotifier {
  bool _emailNotifications = true;
  bool _pushNotifications = true;
  Locale _locale = const Locale('en');

  // Business Settings
  String _companyName = 'Stitch Plc';
  String _companyAddress = 'Addis Ababa, Ethiopia';
  String _companyPhone = '+251 911 223344';
  double _distributionLimit = 5000.0;

  bool get emailNotifications => _emailNotifications;
  bool get pushNotifications => _pushNotifications;
  Locale get locale => _locale;

  // Business Getters
  String get companyName => _companyName;
  String get companyAddress => _companyAddress;
  String get companyPhone => _companyPhone;
  double get distributionLimit => _distributionLimit;

  SettingsProvider() {
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

    notifyListeners();
  }

  Future<void> toggleEmailNotifications(bool value) async {
    _emailNotifications = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('email_notifications', value);
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
}
