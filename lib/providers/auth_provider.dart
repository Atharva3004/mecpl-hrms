// Authentication Provider with API Integration
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/attendance_session.dart';
import '../models/user_model.dart';
import '../models/role_model.dart';
import '../repositories/geofence_repository.dart';
import '../services/api_service.dart';
import '../services/background_location_service.dart';
import '../services/biometric_service.dart';
import '../services/device_info_helper.dart';
import '../services/notification_service.dart';
import '../services/session_manager.dart';

/// SharedPreferences key names. Kept here so the login / lock screen
/// and provider agree on where biometric session data lives.
const String _kTokenPref = 'auth_token';
const String _kUserPref = 'auth_user_data';
const String _kBiometricEnabledPref = 'auth_biometric_enabled';

class AuthProvider extends ChangeNotifier {
  UserModel? _currentUser;
  bool _isLoading = false;
  bool _isAuthenticated = false;
  String? _token;
  String? errorMessage;

  // Set to true when there's a persisted session + biometric is enabled.
  // main.dart routes to the BiometricLockScreen until unlockWithBiometric()
  // succeeds.
  bool _needsBiometricUnlock = false;

  // Mirrors `_kBiometricEnabledPref` for synchronous reads in UI.
  bool _isBiometricEnabled = false;

  // True during the initial SharedPreferences read on app start, so the UI
  // can show a loader instead of briefly flashing the login screen before
  // the biometric prompt.
  bool _isBootstrapping = true;

  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _isAuthenticated;
  UserRole? get currentRole => _currentUser?.role;
  String? get token => _token;
  bool get needsBiometricUnlock => _needsBiometricUnlock;
  bool get isBiometricEnabled => _isBiometricEnabled;
  bool get isBootstrapping => _isBootstrapping;

  AuthProvider() {
    _bootstrap();
  }

  // Clear error
  void clearError() {
    errorMessage = null;
    notifyListeners();
  }

  /// One-shot app-launch bootstrap. Reads the persisted session and decides
  /// the initial route:
  ///   - No persisted token             → login screen (needsBiometricUnlock=false, isAuthenticated=false)
  ///   - Token present, biometric off   → auto-resume the session (isAuthenticated=true)
  ///   - Token present, biometric on    → BiometricLockScreen (needsBiometricUnlock=true)
  /// The transition to `isAuthenticated = true` for the biometric case happens
  /// later via [unlockWithBiometric].
  Future<void> _bootstrap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_kTokenPref);
      final userJson = prefs.getString(_kUserPref);
      _isBiometricEnabled = prefs.getBool(_kBiometricEnabledPref) ?? false;

      if (token == null || userJson == null) {
        // Fresh install / post-logout — straight to login.
        _isAuthenticated = false;
        _currentUser = null;
        _token = null;
        _needsBiometricUnlock = false;
        return;
      }

      // Rehydrate user object for the UI (shell, drawer, etc.).
      UserModel? user;
      try {
        user = UserModel.fromJson(
          json.decode(userJson) as Map<String, dynamic>,
        );
      } catch (_) {
        user = null;
      }

      if (user == null) {
        // Persisted user data is corrupt — force re-login so we don't limp
        // along with bad state.
        await prefs.remove(_kTokenPref);
        await prefs.remove(_kUserPref);
        _isAuthenticated = false;
        _currentUser = null;
        _token = null;
        _needsBiometricUnlock = false;
        return;
      }

      // Pre-flight: ask the backend whether this token is still good. The
      // backend now enforces single-session-per-employee, so a token from a
      // previous device may have been deleted while we were away.
      //   - 200  → continue with biometric/no-biometric branching below.
      //   - 401  → server says the token is gone; clear prefs and bounce
      //            the user to login (don't show snackbar — the user
      //            wasn't doing anything yet).
      //   - throw (network error) → fall back to optimistic resume; the
      //            next real API call will catch a 401 if the token is
      //            actually dead, via SessionManager.
      try {
        final isValid = await ApiService.validateToken(token);
        if (!isValid) {
          await prefs.remove(_kTokenPref);
          await prefs.remove(_kUserPref);
          _isAuthenticated = false;
          _currentUser = null;
          _token = null;
          _needsBiometricUnlock = false;
          errorMessage = 'Your session has expired. Please login again.';
          return;
        }
      } catch (e) {
        debugPrint('⚠️ validate-token failed (offline?): $e — resuming session optimistically');
      }

      if (_isBiometricEnabled) {
        // Keep user/token ready but don't mark authenticated yet — the
        // BiometricLockScreen must succeed first.
        _currentUser = user;
        _token = token;
        _isAuthenticated = false;
        _needsBiometricUnlock = true;
      } else {
        // Biometric not opted in — just resume the session directly.
        _currentUser = user;
        _token = token;
        _isAuthenticated = true;
        _needsBiometricUnlock = false;
      }
    } finally {
      _isBootstrapping = false;
      notifyListeners();
    }
  }

  /// Called by the BiometricLockScreen after the OS prompt returns success.
  /// Flips `_isAuthenticated` to true so main.dart swaps in the MainShell.
  Future<bool> unlockWithBiometric() async {
    if (_token == null || _currentUser == null) {
      // Shouldn't happen — we only show the lock screen when these are set.
      _needsBiometricUnlock = false;
      notifyListeners();
      return false;
    }
    final ok = await BiometricService.instance.authenticate(
      reason: 'Unlock MECPL HRMS',
    );
    if (!ok) return false;
    _isAuthenticated = true;
    _needsBiometricUnlock = false;
    notifyListeners();
    return true;
  }

  /// Lets the user bail out of the biometric prompt and log in with a
  /// password instead. Clears the persisted session so the login screen
  /// comes up clean.
  Future<void> cancelBiometricAndShowLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kTokenPref);
    await prefs.remove(_kUserPref);
    _token = null;
    _currentUser = null;
    _isAuthenticated = false;
    _needsBiometricUnlock = false;
    notifyListeners();
  }

  /// Toggles the biometric-login preference. Asking the user for biometric
  /// consent (the enable prompt) happens in the login screen; this just
  /// persists the result.
  Future<void> setBiometricEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBiometricEnabledPref, enabled);
    _isBiometricEnabled = enabled;
    notifyListeners();
  }

  // Login with Employee Code and Password via API

  Future<bool> login({
    required String empCode,
    required String password,
  }) async {
    _isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      // Backend stores device + app metadata so the admin dashboard can
      // identify and force-logout individual sessions. Failure to gather
      // any of this is non-fatal — we send what we can.
      final device = await DeviceInfoHelper.getDeviceInfo();

      final response = await ApiService.login(
        empCode: empCode,
        password: password,
        deviceName: device['device_name'],
        osVersion: device['os_version'],
        appVersion: device['app_version'],
        // Sent so the backend can target this device via FCM. May be null on
        // first run if `NotificationService.init()` hasn't finished resolving
        // the token yet — in which case the onTokenRefresh listener will
        // back-fill via /update-fcm-token shortly after.
        fcmToken: NotificationService.token,
      );

      if (response.isSuccess && response.data != null) {
        final data = response.data!;

        // Check for API success status if present in response body
        if (data.containsKey('status') && data['status'] == false) {
          errorMessage = data['message'] ?? 'Login failed';
          _isLoading = false;
          notifyListeners();
          return false;
        }

        // Parse User
        final user = ApiService.parseUserFromResponse(data);
        final token = data['token']?.toString();

        if (user != null && token != null) {
          _currentUser = user;
          _token = token;
          _isAuthenticated = true;

          // Clear any stale 401/expiry signal left over from the previous
          // session. Without this, a leftover SessionManager value (e.g. from
          // a background ping or a flushed offline ping that 401'd against the
          // now-revoked old token) could bounce the user straight back to the
          // login screen right after a successful sign-in.
          SessionManager.instance.reset();

          // Save to SharedPreferences. The user blob is persisted so the
          // BiometricLockScreen can rehydrate the shell without a password
          // re-entry on next launch.
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_kTokenPref, token);
          await prefs.setString(_kUserPref, json.encode(user.toJson()));
          final branchId = data['user']?['branch_id'];
          if (branchId != null) {
            await prefs.setInt(
              'branch_id',
              branchId is int
                  ? branchId
                  : int.tryParse(branchId.toString()) ?? 0,
            );
          }

          debugPrint("✅ Login Successful. Token: $token");

          // Hydrate the employee's assigned-branch geofence from `/me/geofence`.
          // Fire-and-forget: login must not fail if this call errors out.
          unawaited(
            GeofenceRepository().refresh(token).then((g) {
              debugPrint(
                g == null
                    ? 'ℹ️ Geofence refresh returned no data'
                    : '📍 Geofence loaded: ${g.branchName} '
                        '(lat=${g.latitude}, lng=${g.longitude}, radius=${g.radiusM}m, enforced=${g.isEnforced})',
              );
            }).catchError((e) {
              debugPrint('⚠️ Geofence refresh failed: $e');
            }),
          );

          _isLoading = false;
          notifyListeners();
          return true;
        } else {
          errorMessage = 'Invalid response from server';
        }
      } else {
        errorMessage = response.error ?? 'Login failed';
      }
    } catch (e) {
      errorMessage = 'Something went wrong: $e';
      debugPrint("❌ Login Error: $e");
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  // Quick login with role (for demo/testing - can be removed in production)
  Future<void> loginWithRole(UserRole role) async {
    _isLoading = true;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 800));

    _currentUser = UserModel.demoUsers.firstWhere(
      (u) => u.role == role,
      orElse: () => UserModel.demoUsers.last,
    );
    _isAuthenticated = true;
    _isLoading = false;
    notifyListeners();
  }

  // Logout
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    // Best-effort server-side logout — deletes the token row in the backend
    // so it can't be reused. Swallowed on failure (offline) since we're
    // about to clear local state anyway.
    final tokenForServer = _token;
    if (tokenForServer != null && tokenForServer.isNotEmpty) {
      await ApiService.logoutApi(tokenForServer);
    }

    await _clearLocalSession(clearBiometricPref: true);

    errorMessage = null;
    _isLoading = false;
    notifyListeners();
  }

  /// Called by main.dart when SessionManager fires (any 401 from a real API
  /// call). Skips the server logout — the token is already gone server-side
  /// — and surfaces a reason the login screen can display.
  Future<void> forceLogout({String? reason}) async {
    if (!_isAuthenticated && !_needsBiometricUnlock && _token == null) {
      // Already logged out — nothing to do.
      return;
    }
    await _clearLocalSession(clearBiometricPref: true);
    errorMessage = reason;
    notifyListeners();
  }

  Future<void> _clearLocalSession({required bool clearBiometricPref}) async {
    // Drop the cached geofence so the next user (or re-login) fetches fresh.
    await GeofenceRepository().clear();

    // Attendance is per-employee and these caches are not. On a shared device
    // the next person to log in would otherwise see the previous employee's
    // punch times, selfies and location trail until the first server sync —
    // and the OS would keep waking us to ping a session that isn't theirs.
    await BackgroundLocationService.clearAllOnLogout();
    await AttendanceSession.clear();

    // Clear persisted session. Biometric preference is cleared so the user
    // is re-prompted after the next successful login.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kTokenPref);
    await prefs.remove(_kUserPref);
    // Cached punch records (times, coordinates, selfie paths) — same key the
    // AttendanceProvider writes.
    await prefs.remove('attendance_local_punch_records_v1');
    if (clearBiometricPref) {
      await prefs.remove(_kBiometricEnabledPref);
      _isBiometricEnabled = false;
    }

    _currentUser = null;
    _token = null;
    _isAuthenticated = false;
    _needsBiometricUnlock = false;
  }

  // Check if current user has permission
  bool hasPermission(String permission) {
    if (_currentUser == null) return false;

    switch (permission) {
      case 'view_all_employees':
        return _currentUser!.role.canViewAllEmployees;
      case 'manage_payroll':
        return _currentUser!.role.canManagePayroll;
      case 'approve_leaves':
        return _currentUser!.role.canApproveLeaves;
      case 'view_reports':
        return _currentUser!.role.canViewReports;
      case 'manage_settings':
        return _currentUser!.role.canManageSettings;
      default:
        return false;
    }
  }

  // Check access level
  bool hasAccessLevel(int requiredLevel) {
    if (_currentUser == null) return false;
    return _currentUser!.role.accessLevel >= requiredLevel;
  }
}
