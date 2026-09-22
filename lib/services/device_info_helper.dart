// Collects device + app metadata sent on login. The backend persists this
// alongside the auth token so the admin dashboard can show which device a
// session belongs to (and force-logout individual devices).
import 'dart:io';
import 'dart:math';

import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceInfoHelper {
  /// Persisted per-install identifier, sent as `device_id`.
  ///
  /// Android's `ANDROID_ID` is deliberately NOT used: `device_info_plus`
  /// dropped it in v4 on privacy grounds, and IMEI and MAC are both blocked
  /// for ordinary apps on modern Android (IMEI needs a privileged permission;
  /// MAC returns a constant `02:00:00:00:00:00`). None of them are obtainable.
  ///
  /// A random id generated once and stored locally gives what the admin
  /// dashboard actually needs — "which install is this session from" — and is
  /// stable across reboots, app updates and logins. It does NOT survive an
  /// uninstall or a "clear data", which is the honest limit of a client-side
  /// identifier without privileged permissions.
  static const String _prefsDeviceIdKey = 'device_install_id';

  static Future<String> _deviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(_prefsDeviceIdKey);
      if (existing != null && existing.isNotEmpty) return existing;

      final rnd = Random.secure();
      final id = List<String>.generate(
        16,
        (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();

      await prefs.setString(_prefsDeviceIdKey, id);
      return id;
    } catch (e) {
      debugPrint('⚠️ device id unavailable: $e');
      return '';
    }
  }

  static Future<String> _appVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return packageInfo.version;
    } catch (_) {
      return '';
    }
  }

  /// Login payload — flat strings, unchanged shape.
  static Future<Map<String, String>> getDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    final appVersion = await _appVersion();
    final deviceId = await _deviceId();

    try {
      if (Platform.isAndroid) {
        final android = await deviceInfo.androidInfo;
        return {
          'device_name': '${android.brand} ${android.model}',
          'os_version': 'Android ${android.version.release}',
          'app_version': appVersion,
          'device_id': deviceId,
        };
      } else if (Platform.isIOS) {
        final ios = await deviceInfo.iosInfo;
        return {
          'device_name': ios.name,
          'os_version': 'iOS ${ios.systemVersion}',
          'app_version': appVersion,
          'device_id': deviceId,
        };
      }
    } catch (e) {
      debugPrint('⚠️ DeviceInfoHelper failed: $e');
    }

    return {
      'device_name': 'Unknown',
      'os_version': 'Unknown',
      'app_version': appVersion,
      'device_id': deviceId,
    };
  }

  /// Richer payload for the `device_info` JSON field on punch-in / punch-out.
  ///
  /// The API has accepted this since day one and `attendance_punches.device_info`
  /// exists in the schema, but nothing ever populated it — every punch stored
  /// null. It answers "which phone made this punch, and was its battery about
  /// to die" when a trail is disputed.
  ///
  /// Every field is best-effort: a punch must never fail because metadata
  /// could not be read.
  static Future<Map<String, dynamic>> getPunchDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    final info = <String, dynamic>{
      'platform': Platform.operatingSystem,
      'app_version': await _appVersion(),
      'device_id': await _deviceId(),
    };

    try {
      if (Platform.isAndroid) {
        final android = await deviceInfo.androidInfo;
        info['manufacturer'] = android.manufacturer;
        info['brand'] = android.brand;
        info['model'] = android.model;
        info['os_version'] = 'Android ${android.version.release}';
        info['sdk_int'] = android.version.sdkInt;
        // False on an emulator — useful when a punch location looks impossible.
        info['is_physical_device'] = android.isPhysicalDevice;
      } else if (Platform.isIOS) {
        final ios = await deviceInfo.iosInfo;
        info['model'] = ios.utsname.machine;
        info['device_name'] = ios.name;
        info['os_version'] = 'iOS ${ios.systemVersion}';
        info['is_physical_device'] = ios.isPhysicalDevice;
      }
    } catch (e) {
      debugPrint('⚠️ getPunchDeviceInfo device lookup failed: $e');
    }

    try {
      info['battery_pct'] = await Battery().batteryLevel;
    } catch (_) {
      // omitted rather than sent as null
    }

    return info;
  }
}
