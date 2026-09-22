import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  static const String _pushNotificationsKey = 'push_notifications';
  static const String _emailNotificationsKey = 'email_notifications';
  static const String _attendanceRemindersKey = 'attendance_reminders';
  static const String _biometricLoginKey = 'biometric_login';

  bool _pushNotifications = true;
  bool _emailNotifications = true;
  bool _attendanceReminders = false;
  bool _biometricLogin = true;

  bool get pushNotifications => _pushNotifications;
  bool get emailNotifications => _emailNotifications;
  bool get attendanceReminders => _attendanceReminders;
  bool get biometricLogin => _biometricLogin;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _pushNotifications = prefs.getBool(_pushNotificationsKey) ?? true;
    _emailNotifications = prefs.getBool(_emailNotificationsKey) ?? true;
    _attendanceReminders = prefs.getBool(_attendanceRemindersKey) ?? false;
    _biometricLogin = prefs.getBool(_biometricLoginKey) ?? true;
    notifyListeners();
  }

  Future<void> togglePushNotifications(bool value) async {
    _pushNotifications = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pushNotificationsKey, value);
    notifyListeners();
  }

  Future<void> toggleEmailNotifications(bool value) async {
    _emailNotifications = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_emailNotificationsKey, value);
    notifyListeners();
  }

  Future<void> toggleAttendanceReminders(bool value) async {
    _attendanceReminders = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_attendanceRemindersKey, value);
    notifyListeners();
  }

  Future<void> toggleBiometricLogin(bool value) async {
    _biometricLogin = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricLoginKey, value);
    notifyListeners();
  }
}
